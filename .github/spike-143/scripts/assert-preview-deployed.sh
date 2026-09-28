#!/usr/bin/env bash
# THROWAWAY: QuantEcon/actions#143 spike. The draft-PR run.
#
# Asserts one LOCAL preview action really deployed THIS run's build on
# pull_request, from inside a container:
#   - the step concluded success and deploy-url is the pr-<N> alias;
#   - changed-files contains the spike's marker lecture. Only the
#     detect-changes step, which runs
#     bash "$GITHUB_ACTION_PATH/../scripts/detect-changed-lectures.sh", can set
#     it, so this proves the ../scripts sibling resolved through a local path
#     in a container. Other entries are recorded, not failed: the script diffs
#     base..head two-dot, so lecture commits that land on main after the branch
#     was cut show up as extra 'M' entries (rebase the branch to clear them);
#   - the alias serves this run's marker file (written into the site just
#     before the deploy), so the content is from this run, not a stale alias;
#   - a built lecture page, after redirects (Cloudflare Pages answers
#     /x.html with a 308 to /x), answers 200 with that lecture's <title>. The
#     title check matters because Cloudflare Pages serves /index.html with a
#     200 for unknown paths when a site has no 404.html.
#
# usage: assert-preview-deployed.sh PROVIDER     (netlify | cloudflare)
# env:   OUTCOME DEPLOY_URL CHANGED_FILES PR EXPECTED_CHANGED MARKER_FILE
# out:   ok=true only when every check passed
set -uo pipefail

P=${1:?provider}
S=${GITHUB_STEP_SUMMARY:-/dev/stdout}
FAILS=0
bad() { echo "::error title=PR preview ($P)::$*"; FAILS=$((FAILS + 1)); }

[[ "${PR:-}" =~ ^[0-9]+$ ]] || bad "PR number [${PR:-}] is not a number"
case "$P" in
  netlify)    RE="^https://pr-${PR}--[a-z0-9-]+\.netlify\.app$" ;;
  cloudflare) RE="^https://pr-${PR}\.qe-preview-canary\.pages\.dev$" ;;
  *) echo "::error::unknown provider $P"; exit 2 ;;
esac

[ "${OUTCOME:-}" = "success" ] || bad "preview-$P step outcome is [${OUTCOME:-}], expected [success]"
U=${DEPLOY_URL:-}
[[ "$U" =~ $RE ]] || bad "deploy-url [$U] does not match $RE"
EXTRA=""
if grep -qxF -- "${EXPECTED_CHANGED:?}" <<<"${CHANGED_FILES:-}"; then
  EXTRA=$(grep -vxF -- "$EXPECTED_CHANGED" <<<"${CHANGED_FILES:-}" | paste -sd' ' - || true)
  if [ -n "$EXTRA" ]; then
    echo "::warning title=PR preview ($P)::changed-files also lists [$EXTRA]: main has lecture commits the branch lacks (two-dot diff). Not a Q1 failure; rebase the branch onto main to clear it"
  fi
else
  bad "changed-files is [${CHANGED_FILES:-}], which does not contain [$EXPECTED_CHANGED]. Either detect-changes (\$GITHUB_ACTION_PATH/../scripts/detect-changed-lectures.sh) did not run, or its git diff failed silently; the evidence job's 'detect-changed-lectures.sh ran' row tells the two apart"
fi

want=$(cat "${MARKER_FILE:?}" 2>/dev/null || true)
[ -n "$want" ] || bad "no local marker at $MARKER_FILE to compare against"
got=""
code=""
eff=""
if [ -n "$U" ] && [ -n "$want" ]; then
  # An alias can take a little while to point at a new deployment.
  for i in $(seq 1 18); do
    got=$(curl -fsSL --max-time 20 "$U/spike-143-marker.txt?try=$i" 2>/dev/null || true)
    [ "$got" = "$want" ] && break
    sleep 10
  done
  [ "$got" = "$want" ] || bad "$U/spike-143-marker.txt serves [$got], expected this run's [$want]"
  page="${RUNNER_TEMP:-/tmp}/spike-143-$P-geom_series.html"
  read -r code eff < <(curl -sSL -o "$page" -w '%{http_code} %{url_effective}\n' --max-time 30 "$U/geom_series.html" 2>/dev/null || echo "000 none")
  if [ "$code" != "200" ]; then
    bad "$U/geom_series.html answered HTTP [$code] after redirects (ended at [$eff])"
  elif ! grep -qiE '<title>[^<]*Geometric Series for Elementary Economics' "$page"; then
    bad "$U/geom_series.html (ended at [$eff]) answered 200 but is not the geom_series lecture (no matching <title>): a fallback page, not the built lecture"
  fi
fi

{
  echo "### PR preview via ./actions-repo/preview-$P"
  echo "| check | value |"
  echo "|---|---|"
  echo "| outcome | ${OUTCOME:-} |"
  echo "| deploy-url | ${U:-<empty>} |"
  echo "| changed-files | \`$(paste -sd' ' - <<<"${CHANGED_FILES:-<empty>}")\` (must contain \`$EXPECTED_CHANGED\`; extra: \`${EXTRA:-none}\`) |"
  echo "| marker served | $( [ -n "$want" ] && [ "$got" = "$want" ] && echo yes || echo NO) |"
  echo "| geom_series.html | HTTP ${code:-n/a}, ended at ${eff:-n/a} |"
  echo "| failures | $FAILS |"
} >> "$S"

if [ "$FAILS" -gt 0 ]; then
  echo "::error title=PR preview ($P)::$FAILS check(s) failed"
  exit 1
fi
echo "ok=true" >> "$GITHUB_OUTPUT"
