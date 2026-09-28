#!/usr/bin/env bash
# THROWAWAY: QuantEcon/actions#143 spike.
#
# Asserts that the canary's CI chain (pdflatex, jupyter, html with the PDF and
# notebooks staged) produced every output it should, and that each one was
# written by THIS job: the job deletes the restored _build/{html,latex,jupyter}
# and touches $RUNNER_TEMP/spike-143/before-builds before the first build, so
# nothing restored from the cache can satisfy these checks.
#
# usage: assert-build.sh
# env:   LABEL, PDF_PATH, NB_PATH, HTML_PATH (the three build-path outputs)
# out:   ok=true (only when every check passed), html_pages, html_list_sha
set -uo pipefail

LABEL=${LABEL:-build}
MARKER="${RUNNER_TEMP:-/tmp}/spike-143/before-builds"
S=${GITHUB_STEP_SUMMARY:-/dev/stdout}
FAILS=0
CHECKS=0
bad() { echo "::error title=build outputs ($LABEL)::$*"; FAILS=$((FAILS + 1)); }
chk() { CHECKS=$((CHECKS + 1)); }
fresh() { [ -n "$(find "$1" -newer "$MARKER" 2>/dev/null)" ]; }

[ -f "$MARKER" ] || bad "no $MARKER: the clear-outputs step did not run, so freshness cannot be shown"

# The documents that must exist, read from the toc itself so the list cannot
# go stale; a parse that finds too few entries is itself a failure.
ROOT=$(sed -n 's/^root:[[:space:]]*\([A-Za-z0-9_-]*\).*/\1/p' lectures/_toc.yml)
mapfile -t DOCS < <(sed -n 's/^[[:space:]]*-[[:space:]]*file:[[:space:]]*\([A-Za-z0-9_-]*\).*/\1/p' lectures/_toc.yml)
[ -n "$ROOT" ] || bad "no root: in lectures/_toc.yml"
[ "${#DOCS[@]}" -ge 5 ] || bad "parsed only ${#DOCS[@]} '- file:' entries from lectures/_toc.yml (expected at least 5)"
# Notebooks are required for the five canary lectures; each must be in the toc.
NB_DOCS=(geom_series short_path lln_clt solow linear_equations)
for d in "${NB_DOCS[@]}"; do
  printf '%s\n' "${DOCS[@]}" | grep -qx "$d" || bad "$d is not in lectures/_toc.yml any more; update NB_DOCS in this script"
done
PDF_NAME=$(sed -n 's/^[[:space:]]*targetname:[[:space:]]*\([A-Za-z0-9_.-]*\)\.tex.*/\1/p' lectures/_config.yml)
[ -n "$PDF_NAME" ] || bad "no latex targetname in lectures/_config.yml"

# 1. The build-path outputs, exactly as build-lectures computes them with
#    output-dir '.'.
chk; [ "${PDF_PATH:-}" = "./_build/latex" ] || bad "pdflatex build-path output is [${PDF_PATH:-}], expected [./_build/latex]"
chk; [ "${NB_PATH:-}" = "./_build/jupyter" ] || bad "jupyter build-path output is [${NB_PATH:-}], expected [./_build/jupyter]"
chk; [ "${HTML_PATH:-}" = "./_build/html" ] || bad "html build-path output is [${HTML_PATH:-}], expected [./_build/html]"
H=${HTML_PATH:-./_build/html}
L=${PDF_PATH:-./_build/latex}
N=${NB_PATH:-./_build/jupyter}

# 2. HTML: the root and every toc document, each written by this job.
for d in "$ROOT" "${DOCS[@]}"; do
  f="$H/$d.html"
  chk
  if [ ! -s "$f" ]; then bad "missing or empty: $f"; continue; fi
  grep -qi '<html' "$f" || bad "$f is not an HTML page"
  fresh "$f" || bad "$f predates this job's builds (restored, not built)"
done
# index.html is not a page for this book: the root doc is intro, so
# sphinx-external-toc's ensure_index_file writes a one-line meta-refresh
# (<meta http-equiv="Refresh" content="0; url=intro.html" />, 58 bytes) when
# the html outdir has none. The job removed _build/html, so it must be there,
# fresh, and redirect to the root document (or be a real page, should the
# book ever gain an index doc).
f="$H/index.html"
chk
if [ ! -s "$f" ]; then
  bad "missing or empty: $f"
else
  if ! grep -qi '<html' "$f"; then
    { grep -qi 'http-equiv="Refresh"' "$f" && grep -qF "url=$ROOT.html" "$f"; } \
      || bad "$f is neither an HTML page nor a redirect to $ROOT.html: [$(head -c 200 "$f")]"
  fi
  fresh "$f" || bad "$f predates this job's builds (restored, not built)"
fi

# 3. PDF built and staged into the HTML tree (html-copy-pdf).
pdf="$L/$PDF_NAME.pdf"
chk
if [ -s "$pdf" ]; then
  [ "$(head -c 5 "$pdf")" = "%PDF-" ] || bad "$pdf does not start with %PDF-"
  [ "$(wc -c < "$pdf")" -gt 20000 ] || bad "$pdf is only $(wc -c < "$pdf") bytes"
  fresh "$pdf" || bad "$pdf predates this job's builds"
  chk; cmp -s "$pdf" "$H/_pdf/$PDF_NAME.pdf" || bad "the PDF was not staged into $H/_pdf/ (html-copy-pdf)"
else
  bad "missing or empty: $pdf"
fi

# 4. Notebooks built and staged into the HTML tree (html-copy-notebooks).
for d in "${NB_DOCS[@]}"; do
  nb="$N/$d.ipynb"
  chk
  if [ ! -s "$nb" ]; then bad "missing or empty: $nb"; continue; fi
  python3 - "$nb" <<'PY' || bad "$nb is not a notebook with cells"
import json, sys
nb = json.load(open(sys.argv[1]))
sys.exit(0 if nb.get("nbformat") and nb.get("cells") else 1)
PY
  fresh "$nb" || bad "$nb predates this job's builds"
  chk; cmp -s "$nb" "$H/_notebooks/$d.ipynb" || bad "$d.ipynb was not staged into $H/_notebooks/ (html-copy-notebooks)"
done

# Page-set fingerprint, for the local-vs-remote comparison in the evidence job.
PAGES=$(find "$H" -name '*.html' -printf '%P\n' 2>/dev/null | LC_ALL=C sort)
NPAGES=$(printf '%s\n' "$PAGES" | grep -c . || true)
LIST_SHA=$(printf '%s\n' "$PAGES" | sha256sum | cut -c1-16)
echo "html_pages=$NPAGES" >> "$GITHUB_OUTPUT"
echo "html_list_sha=$LIST_SHA" >> "$GITHUB_OUTPUT"

{
  echo "### Build outputs: $LABEL"
  echo "| check | result |"
  echo "|---|---|"
  echo "| checks run | $CHECKS |"
  echo "| failures | $FAILS |"
  echo "| html pages | $NPAGES (list sha256 \`$LIST_SHA\`) |"
  echo "| toc documents checked | $ROOT ${DOCS[*]} |"
  echo "| PDF | \`$pdf\` $( [ -s "$pdf" ] && wc -c < "$pdf") bytes, staged: $(cmp -s "$pdf" "$H/_pdf/$PDF_NAME.pdf" && echo yes || echo NO) |"
  echo "| notebooks staged | $(find "$H/_notebooks" -name '*.ipynb' 2>/dev/null | wc -l) |"
} >> "$S"

if [ "$FAILS" -gt 0 ]; then
  echo "::error title=build outputs ($LABEL)::$FAILS of $CHECKS checks failed"
  exit 1
fi
echo "ok=true" >> "$GITHUB_OUTPUT"
echo "All $CHECKS build-output checks passed for $LABEL"
