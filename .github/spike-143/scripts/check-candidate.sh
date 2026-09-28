#!/usr/bin/env bash
# THROWAWAY: QuantEcon/actions#143 spike.
#
# Verifies the two checkouts before any local action is used, and records what
# the job is about to run. Fails loudly on anything that would make a later
# "Can't find action.yml" or a green result ambiguous.
#
# usage: check-candidate.sh EXPECTED_SHA ACTION_DIR...
# env:   JOB_LABEL (for the summary), IMAGE (the container image the job uses)
set -euo pipefail

WANT=${1:?expected QuantEcon/actions SHA}
shift
LABEL=${JOB_LABEL:-job}
fail() { echo "::error title=checkouts ($LABEL)::$*"; exit 1; }
# Steps in the container run as root over a workspace owned by the runner's
# uid, so plain git trusts it only because the image sets safe.directory '*'
# system-wide (added 2026-09-18, #165). Passing it per call makes this check
# measure the checkout, not the image's git config (a dispatch may pin an
# older digest). It changes nothing the actions themselves see.
g() { git -c safe.directory='*' "$@"; }

[[ "$WANT" =~ ^[0-9a-f]{40}$ ]] || fail "expected SHA [$WANT] is not 40 lowercase hex characters"

# The canary must be the repository at the workspace root.
origin=$(g remote get-url origin 2>/dev/null) || fail "the workspace root is not a git checkout"
case "$origin" in
  *[Qq]uant[Ee]con/test-actions-lecture-intro*) ;;
  *) fail "the workspace root's origin is [$origin], not the canary" ;;
esac

# The candidate must be a separate checkout at ./actions-repo, at exactly WANT.
# A canary checkout that ran after it would have git-cleaned it away.
[ -e actions-repo/.git ] || fail "actions-repo/ is not a git checkout (did a later checkout of the workspace root wipe it?)"
got=$(g -C actions-repo rev-parse HEAD)
[ "$got" = "$WANT" ] || fail "actions-repo is at $got, expected $WANT"
aorigin=$(g -C actions-repo remote get-url origin)
case "$aorigin" in
  *github.com/[Qq]uant[Ee]con/actions|*github.com/[Qq]uant[Ee]con/actions.git) ;;
  *) fail "actions-repo's origin is [$aorigin], not QuantEcon/actions" ;;
esac
# actions-repo must be invisible to the canary's own git: untracked, and so
# outside anything the canary commits or keys a cache on.
if g ls-files --error-unmatch actions-repo >/dev/null 2>&1; then
  fail "actions-repo is tracked by the canary checkout"
fi

for a in "$@"; do
  [ -f "actions-repo/$a/action.yml" ] || fail "actions-repo/$a/action.yml is missing"
done
# preview-* and deploy-cloudflare read ../scripts through $GITHUB_ACTION_PATH,
# so the checkout must be the full tree, not a sparse one.
[ -f actions-repo/scripts/detect-changed-lectures.sh ] || fail "actions-repo/scripts/ is missing (sparse checkout?)"

echo "Canary:    $(g rev-parse HEAD) ($origin)"
echo "Candidate: $got ($aorigin)"
echo "::group::sha256 of every action.yml in the candidate"
sha256sum actions-repo/*/action.yml
echo "::endgroup::"

# Static scan, recorded rather than asserted: an action that expands
# github.action_path inside ${{ }} in a script breaks in a container job
# whatever the ref form (the probe job shows why). Comment lines are skipped.
scan=$(grep -nE '\$\{\{[^}]*github\.action_path' actions-repo/*/action.yml | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)
if [ -n "$scan" ]; then
  echo "::warning title=static scan ($LABEL)::the candidate expands github.action_path in an expression; that path is the HOST path inside a container job:"
  echo "$scan"
  scan_note="**expression uses found** (see log)"
else
  scan_note="none outside comments"
fi

marker=$( (tr '\n' ' ' < /etc/quantecon-container) 2>/dev/null || echo "n/a (not in a quantecon container)")
{
  echo "### Checkouts: $LABEL ($GITHUB_EVENT_NAME)"
  echo "| item | value |"
  echo "|---|---|"
  echo "| canary | \`$(g rev-parse HEAD)\` |"
  echo "| QuantEcon/actions at ./actions-repo | \`$got\` |"
  echo "| image | \`${IMAGE:-none (host)}\` |"
  echo "| /etc/quantecon-container | $marker |"
  echo "| system safe.directory | \`$(git config --system --get-all safe.directory 2>/dev/null | paste -sd' ' - || true)\` |"
  echo "| \${{ github.action_path }} expression uses in candidate action.yml files | $scan_note |"
  for a in "$@"; do
    echo "| sha256 actions-repo/$a/action.yml | \`$(sha256sum < "actions-repo/$a/action.yml" | cut -c1-16)…\` |"
  done
} >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
