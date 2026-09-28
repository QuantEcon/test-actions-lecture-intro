#!/usr/bin/env bash
# THROWAWAY: QuantEcon/actions#143 spike.
#
# What did the runner download for this job? Reads the runner's action cache
# (<work>/_actions, which a container job sees at /__w/_actions). On a hosted
# runner it starts empty for every job, and every remote action a step uses is
# downloaded there before it runs, including the actions a composite uses.
# Local ./ actions are never downloaded, so this is direct evidence of which
# code ran.
#
# usage: assert-attribution.sh MODE [SHA]
#   local       nothing from quantecon/actions was downloaded, so every
#               quantecon step in this job ran from ./actions-repo
#   remote SHA  only quantecon/actions@SHA was downloaded, and its action
#               directories are byte-identical to ./actions-repo (checked out
#               at the same SHA)
#   nested-v0   quantecon/actions@v0 was downloaded (build-jupyter-cache's
#               nested sibling calls) and is not the candidate
# out: ok=true only when every check passed; nested-v0 also writes v0_sha
set -uo pipefail

MODE=${1:?mode}
SHA=${2:-}
S=${GITHUB_STEP_SUMMARY:-/dev/stdout}
FAILS=0
bad()  { echo "::error title=attribution ($MODE)::$*"; FAILS=$((FAILS + 1)); }
# Root in the container over a runner-owned checkout: do not depend on the
# image's system safe.directory (see check-candidate.sh).
g()    { git -c safe.directory='*' "$@"; }
note() { echo "| $1 | $2 |" >> "$S"; }

WORK=$(dirname "$(dirname "${GITHUB_WORKSPACE:?}")")
ACTIONS="$WORK/_actions"
if [ ! -d "$ACTIONS" ]; then
  echo "::error title=attribution ($MODE)::no runner action cache at $ACTIONS, so nothing can be attributed"
  exit 1
fi
echo "::group::Runner action cache ($ACTIONS)"
find "$ACTIONS" -mindepth 3 -maxdepth 3 | sed "s#^$ACTIONS/##" | sort
echo "::endgroup::"
# A listing that does not even show actions/checkout cannot be trusted.
[ -d "$ACTIONS/actions/checkout" ] || bad "actions/checkout is not in $ACTIONS, so this listing is not the runner's action cache"

QA=$(find "$ACTIONS" -mindepth 2 -maxdepth 2 -type d -ipath "$ACTIONS/quantecon/actions" | head -n 1)
REFS=""
if [ -n "$QA" ]; then
  REFS=$(find "$QA" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | paste -sd' ' -)
fi

{
  echo "### Attribution: $MODE"
  echo "| item | value |"
  echo "|---|---|"
  echo "| quantecon/actions refs in the runner's action cache | \`${REFS:-none}\` |"
} >> "$S"

case "$MODE" in
  local)
    [ -z "$QA" ] || bad "quantecon/actions was downloaded in a local-path job (refs: $REFS), so this job did not run only ./actions-repo code"
    [ -e actions-repo/.git ] || bad "actions-repo/ is gone at the end of the job"
    ;;
  remote)
    [[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || bad "remote mode needs the 40-char SHA, got [$SHA]"
    if [ -z "$QA" ] || [ ! -d "$QA/$SHA" ]; then
      bad "quantecon/actions@$SHA is not in the runner's action cache (refs: ${REFS:-none})"
    else
      [ "$REFS" = "$SHA" ] || bad "expected only [$SHA] under quantecon/actions, found [$REFS]"
      [ "$(g -C actions-repo rev-parse HEAD)" = "$SHA" ] || bad "actions-repo is not at $SHA, so the comparison below means nothing"
      for d in restore-jupyter-cache build-lectures preview-netlify preview-cloudflare scripts; do
        if diff -r -q "$QA/$SHA/$d" "actions-repo/$d" >/dev/null; then
          note "downloaded $d vs actions-repo/$d" "identical"
        else
          bad "the downloaded $d differs from actions-repo/$d at the same SHA"
          note "downloaded $d vs actions-repo/$d" "**differs**"
        fi
      done
    fi
    ;;
  nested-v0)
    if [ -z "$QA" ] || [ ! -d "$QA/v0" ]; then
      bad "quantecon/actions@v0 is not in the runner's action cache (refs: ${REFS:-none}); the nested sibling calls did not resolve to @v0"
    else
      # Positive identification against the v0 tag (corroboration; the
      # evidence job also reads the SHA from the runner's download log line).
      if g -C actions-repo fetch -q --no-tags --depth=1 origin +refs/tags/v0:refs/tags/v0 2>/dev/null; then
        V0=$(g -C actions-repo rev-parse 'v0^{commit}')
        echo "v0_sha=$V0" >> "$GITHUB_OUTPUT"
        note "v0 at run time" "\`$V0\`"
      else
        echo "::warning title=attribution (nested-v0)::could not fetch tag v0 for positive identification; the evidence job reads the SHA from the log instead"
        V0=""
      fi
      for a in setup-environment build-lectures; do
        h_dl=$(sha256sum < "$QA/v0/$a/action.yml" | cut -d' ' -f1)
        h_cand=$(sha256sum < "actions-repo/$a/action.yml" | cut -d' ' -f1)
        if [ -n "$V0" ]; then
          h_v0=$(g -C actions-repo show "v0:$a/action.yml" | sha256sum | cut -d' ' -f1)
          [ "$h_dl" = "$h_v0" ] || bad "the downloaded v0/$a/action.yml does not match tag v0"
        fi
        if [ "$h_dl" = "$h_cand" ]; then
          note "nested $a" "downloaded @v0 copy is identical to the candidate's, so the two cannot be told apart for this action"
        else
          note "nested $a" "ran **@v0**, not the candidate (action.yml differs)"
        fi
      done
      # With the candidate at c0ac111 and v0 at a53dbe4, build-lectures differs,
      # so at least one nested action must be distinguishable.
      if [ "$(sha256sum < "$QA/v0/build-lectures/action.yml" | cut -d' ' -f1)" = "$(sha256sum < actions-repo/build-lectures/action.yml | cut -d' ' -f1)" ]; then
        echo "::warning title=attribution (nested-v0)::v0's build-lectures is identical to the candidate's; the residual is real but invisible for this candidate"
      fi
    fi
    ;;
  *)
    bad "unknown mode [$MODE]"
    ;;
esac

if [ "$FAILS" -gt 0 ]; then
  echo "::error title=attribution ($MODE)::$FAILS check(s) failed"
  exit 1
fi
echo "ok=true" >> "$GITHUB_OUTPUT"
