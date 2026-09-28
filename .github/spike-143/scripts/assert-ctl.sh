#!/usr/bin/env bash
# THROWAWAY: QuantEcon/actions#143 spike. Q2 positive control, part 2.
#
# The one-line-ungated copies were invoked with continue-on-error and the same
# dummy token as the real actions. Each must have:
#   - outcome failure (the deploy step ran and the dummy token failed it);
#   - an empty deploy-url;
#   - created exactly one new CLI install dir that holds a working CLI, which
#     shows the copy got past its install step, so the failure came from the
#     deploy step (detect-changes and the comment are still pull_request-only
#     in the copy, and the skip notification needs skip=true).
#
# env: PN_OUTCOME PN_DEPLOY_URL PN_BEFORE, PC_OUTCOME PC_DEPLOY_URL PC_BEFORE
# out: ok=true only when every check passed
set -uo pipefail

S=${GITHUB_STEP_SUMMARY:-/dev/stdout}
FAILS=0
bad() { echo "::error title=Q2 positive control::$*"; FAILS=$((FAILS + 1)); }
{
  echo "### Q2 positive control (deploy step's event clause removed, dummy token)"
  echo "| provider | outcome | deploy-url | install dirs before → after | reading |"
  echo "|---|---|---|---|---|"
} >> "$S"

for P in netlify cloudflare; do
  case "$P" in
    netlify)    O=${PN_OUTCOME:-}; U=${PN_DEPLOY_URL:-}; B=${PN_BEFORE:-}; BIN=netlify ;;
    cloudflare) O=${PC_OUTCOME:-}; U=${PC_DEPLOY_URL:-}; B=${PC_BEFORE:-}; BIN=wrangler ;;
  esac
  before=$FAILS
  [ "$O" = "failure" ] || bad "preview-$P-ctl outcome is [$O], expected [failure]: with the event clause removed the deploy step should have run and failed on the dummy token"
  [ -z "$U" ] || bad "preview-$P-ctl produced deploy-url [$U] with a dummy token"
  after=$(find "${RUNNER_TEMP:?}" -maxdepth 1 -name "preview-$P.*" -type d | wc -l)
  if [ -z "$B" ] || [ "$after" -ne $((B + 1)) ]; then
    bad "preview-$P install dirs went from [$B] to [$after], expected one more: the control never reached its install step"
  else
    newest=$(ls -1dt "$RUNNER_TEMP"/preview-"$P".* | head -n 1)
    [ -x "$newest/node_modules/.bin/$BIN" ] || bad "the control's install dir $newest has no $BIN: it failed in install, not in deploy"
  fi
  if [ "$FAILS" -eq "$before" ]; then reading="deploy step reachable; fails on a dummy token"; else reading="**FAIL**"; fi
  echo "| $P | $O | \`${U:-<empty>}\` | ${B:-?} → $after | $reading |" >> "$S"
done

if [ "$FAILS" -gt 0 ]; then
  echo "::error title=Q2 positive control::$FAILS check(s) failed"
  exit 1
fi
echo "ok=true" >> "$GITHUB_OUTPUT"
