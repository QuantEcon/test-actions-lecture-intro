#!/usr/bin/env bash
# THROWAWAY: QuantEcon/actions#143 spike.
#
# Asserts build-jupyter-cache's outputs and artifacts for a builders: html run.
# Deliberately NOT cache-saved: it reads 'true' even when the save lost a key
# race to another job of the same run (both bjc jobs, and the q1 jobs' post
# hooks, save build-<env>--<run_id>), and that race is expected here.
#
# usage: assert-bjc.sh LABEL
# env:   BUILD_SUCCESS HTML_STATUS JUPYTER_STATUS PDFLATEX_STATUS CACHE_KEY
#        EXPECTED_KEY ISSUE_URL
# out:   ok=true only when every check passed
set -uo pipefail

LABEL=${1:?label}
S=${GITHUB_STEP_SUMMARY:-/dev/stdout}
FAILS=0
bad() { echo "::error title=build-jupyter-cache ($LABEL)::$*"; FAILS=$((FAILS + 1)); }

[ "${BUILD_SUCCESS:-}" = "true" ] || bad "build-success is [${BUILD_SUCCESS:-}], expected [true]"
[ "${HTML_STATUS:-}" = "success" ] || bad "html-status is [${HTML_STATUS:-}], expected [success]"
[ "${JUPYTER_STATUS:-}" = "skipped" ] || bad "jupyter-status is [${JUPYTER_STATUS:-}], expected [skipped]"
[ "${PDFLATEX_STATUS:-}" = "skipped" ] || bad "pdflatex-status is [${PDFLATEX_STATUS:-}], expected [skipped]"
[ -n "${EXPECTED_KEY:-}" ] && [ "${CACHE_KEY:-}" = "$EXPECTED_KEY" ] || bad "cache-key is [${CACHE_KEY:-}], expected [${EXPECTED_KEY:-}]"
[ -z "${ISSUE_URL:-}" ] || bad "a failure issue was filed ($ISSUE_URL) although create-issue-on-failure is 'false'"

ROOT=$(sed -n 's/^root:[[:space:]]*\([A-Za-z0-9_-]*\).*/\1/p' lectures/_toc.yml)
mapfile -t DOCS < <(sed -n 's/^[[:space:]]*-[[:space:]]*file:[[:space:]]*\([A-Za-z0-9_-]*\).*/\1/p' lectures/_toc.yml)
[ "${#DOCS[@]}" -ge 5 ] || bad "parsed only ${#DOCS[@]} toc entries"
for d in index "$ROOT" "${DOCS[@]}"; do
  [ -s "_build/html/$d.html" ] || bad "missing or empty: _build/html/$d.html"
done
[ -f _build/.jupyter_cache/global.db ] || bad "the execution cache (_build/.jupyter_cache/global.db) was not populated"

{
  echo "### build-jupyter-cache: $LABEL"
  echo "| output | value |"
  echo "|---|---|"
  echo "| build-success | ${BUILD_SUCCESS:-} |"
  echo "| html / jupyter / pdflatex | ${HTML_STATUS:-} / ${JUPYTER_STATUS:-} / ${PDFLATEX_STATUS:-} |"
  echo "| cache-key | \`${CACHE_KEY:-}\` |"
  echo "| failures | $FAILS |"
} >> "$S"

if [ "$FAILS" -gt 0 ]; then
  echo "::error title=build-jupyter-cache ($LABEL)::$FAILS check(s) failed"
  exit 1
fi
echo "ok=true" >> "$GITHUB_OUTPUT"
