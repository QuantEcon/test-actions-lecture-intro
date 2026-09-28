#!/usr/bin/env bash
# THROWAWAY: QuantEcon/actions#143 spike. Q2 on a push/dispatch run.
#
# Asserts the "vacuous green" facts for one preview-netlify and one
# preview-cloudflare invocation on a non-pull_request event:
#   - the step concluded success;
#   - deploy-url, changed-files (and Cloudflare's deployment-url) are empty.
#     The deploy step can only succeed after writing a non-empty deploy-url,
#     so success + empty means the deploy step was skipped, not run;
#   - the CLI install DID run, through $GITHUB_ACTION_PATH: exactly
#     EXPECT_DIRS install dirs exist under $RUNNER_TEMP, the newest holds the
#     pinned CLI, and its package.json is byte-identical to the one beside the
#     action (so the copy really came from the action directory).
#
# usage: assert-preview-skipped.sh LABEL
# env:   EVENT, EXPECT_DIRS, ACTIONS_SRC (dir holding preview-*/package.json),
#        PN_OUTCOME PN_DEPLOY_URL PN_CHANGED, PC_OUTCOME PC_DEPLOY_URL
#        PC_DEPLOYMENT_URL PC_CHANGED
# out:   ok=true only when every check passed
set -uo pipefail

LABEL=${1:?label}
S=${GITHUB_STEP_SUMMARY:-/dev/stdout}
FAILS=0
bad() { echo "::error title=Q2 vacuous green ($LABEL)::$*"; FAILS=$((FAILS + 1)); }

[ "${EVENT:-}" != "pull_request" ] || bad "this assertion is for non-pull_request events; it ran on pull_request"

{
  echo "### Q2 on $EVENT: $LABEL"
  echo "| provider | step outcome | deploy-url | changed-files | CLI installed from \$GITHUB_ACTION_PATH | reading |"
  echo "|---|---|---|---|---|---|"
} >> "$S"

for P in netlify cloudflare; do
  case "$P" in
    netlify)    O=${PN_OUTCOME:-}; U=${PN_DEPLOY_URL:-}; C=${PN_CHANGED:-}; D2=""; PKG=netlify-cli; BIN=netlify ;;
    cloudflare) O=${PC_OUTCOME:-}; U=${PC_DEPLOY_URL:-}; C=${PC_CHANGED:-}; D2=${PC_DEPLOYMENT_URL:-}; PKG=wrangler; BIN=wrangler ;;
  esac
  before=$FAILS
  [ "$O" = "success" ] || bad "preview-$P step outcome is [$O], expected [success]"
  [ -z "$U" ] || bad "preview-$P deploy-url is [$U] on $EVENT: a deploy happened"
  [ -z "$C" ] || bad "preview-$P changed-files is non-empty on $EVENT: change detection ran"
  [ -z "$D2" ] || bad "preview-$P deployment-url is [$D2] on $EVENT: a deploy happened"

  PKGJSON="${ACTIONS_SRC:?}/preview-$P/package.json"
  mapfile -t DIRS < <(ls -1dt "${RUNNER_TEMP:?}"/preview-"$P".* 2>/dev/null)
  cli="no"
  if [ "${#DIRS[@]}" -ne "${EXPECT_DIRS:?}" ]; then
    bad "found ${#DIRS[@]} $RUNNER_TEMP/preview-$P.* install dirs, expected $EXPECT_DIRS: the install step did not run (or ran more often than this job invoked it)"
  else
    newest=${DIRS[0]}
    exe="$newest/node_modules/.bin/$BIN"
    pin=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["dependencies"][sys.argv[2]])' "$PKGJSON" "$PKG" 2>/dev/null || true)
    [ -n "$pin" ] || bad "cannot read the $PKG pin from $PKGJSON"
    if [ -x "$exe" ]; then
      ver=$("$exe" --version 2>&1 | tail -n 3 | tr '\n' ' ')
      if [ -n "$pin" ] && grep -qF "$pin" <<<"$ver"; then cli="$PKG $pin"; else bad "$exe reports [$ver], expected the pin [$pin]"; fi
    else
      bad "$exe is missing: the install step's npm ci did not complete"
    fi
    cmp -s "$newest/package.json" "$PKGJSON" || bad "$newest/package.json differs from $PKGJSON: the install did not copy from the action directory"
  fi
  if [ "$FAILS" -eq "$before" ]; then reading="skipped deploy, green, silent"; else reading="**FAIL**"; fi
  echo "| $P | $O | \`${U:-<empty>}\` | \`${C:-<empty>}\` | $cli | $reading |" >> "$S"
done

if [ "$FAILS" -gt 0 ]; then
  echo "::error title=Q2 vacuous green ($LABEL)::$FAILS check(s) failed"
  exit 1
fi
echo "ok=true" >> "$GITHUB_OUTPUT"
echo "Q2 ($LABEL, $EVENT): both preview actions went green, deployed nothing, and installed their pinned CLI through \$GITHUB_ACTION_PATH"
