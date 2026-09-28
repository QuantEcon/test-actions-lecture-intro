#!/usr/bin/env bash
# THROWAWAY: QuantEcon/actions#143 spike. Q2 positive control, part 1.
#
# For each preview action, copies actions-repo/<action> to
# actions-repo/<action>-ctl (a sibling, so $GITHUB_ACTION_PATH/../scripts still
# resolves) and removes ONLY the event clause from the deploy step's if:.
# Invoked with the same dummy token, the copy must then FAIL. That shows the
# deploy step is reachable on this event with these inputs and cannot succeed
# with a dummy token, so the unmodified action's "success + empty deploy-url"
# can only mean its deploy step was skipped.
#
# Refuses (exit 1) unless the change is exactly one line, so formatting drift
# in the candidate cannot silently turn the control into a no-op.
#
# usage: make-ctl.sh ACTION...
# out:   <action>_before=<number of $RUNNER_TEMP/<action>.* dirs before the control runs>
set -euo pipefail

GATED="      if: steps.check-trust.outputs.skip != 'true' && github.event_name == 'pull_request'"
UNGATED="      if: steps.check-trust.outputs.skip != 'true'"
fail() { echo "::error title=positive control::$*"; exit 1; }

for a in "$@"; do
  src="actions-repo/$a"
  dst="actions-repo/$a-ctl"
  [ -f "$src/action.yml" ] || fail "$src/action.yml is missing"
  rm -rf "$dst"
  cp -r "$src" "$dst"

  n=$(grep -c '^      id: deploy$' "$src/action.yml" || true)
  [ "$n" = 1 ] || fail "$a: expected exactly one '      id: deploy' line, found $n"
  ln=$(grep -n '^      id: deploy$' "$src/action.yml" | cut -d: -f1)
  next=$((ln + 1))
  line=$(sed -n "${next}p" "$src/action.yml")
  [ "$line" = "$GATED" ] || fail "$a: line $next is not the expected gated condition (formatting drift): [$line]"

  awk -v n="$next" -v repl="$UNGATED" 'NR == n { print repl; next } { print }' "$src/action.yml" > "$dst/action.yml"

  changed=$(diff "$src/action.yml" "$dst/action.yml" | grep -c '^[<>]' || true)
  [ "$changed" = 2 ] || fail "$a: the control differs from the candidate in $changed diff lines, expected exactly 2 (one line out, one in)"
  echo "::group::$a-ctl: the only change"
  diff "$src/action.yml" "$dst/action.yml" || true
  echo "::endgroup::"

  before=$(find "${RUNNER_TEMP:?}" -maxdepth 1 -name "$a.*" -type d | wc -l)
  echo "${a//-/_}_before=$before" >> "$GITHUB_OUTPUT"
done
