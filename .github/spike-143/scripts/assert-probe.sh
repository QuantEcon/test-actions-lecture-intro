#!/usr/bin/env bash
# THROWAWAY: QuantEcon/actions#143 spike.
#
# Asserts the path probe's reports for the two probe placements:
#   C_REPORT  ./.github/spike-143/probe       (committed in the canary)
#   A_REPORT  ./actions-repo/spike-143-probe  (a copy inside the candidate
#             checkout, whose sibling is the REAL ../scripts/detect-changed-lectures.sh)
#
# Hard requirements, both modes: each probe ran where this job claims
# (container/host), and $GITHUB_ACTION_PATH names a directory that exists and
# reaches the sibling (that is what preview-* and deploy-cloudflare rely on).
# Host mode: every route must work. Container mode: the two expression routes
# are RECORDED as WORKS or BROKEN (a finding either way), but anything else
# (e.g. the directory exists and the sibling does not) fails.
#
# usage: assert-probe.sh MODE          (container | host)
# out:   ok=true, inline=<WORKS|BROKEN>, envexpr=<WORKS|BROKEN>
set -uo pipefail

MODE=${1:?mode}
S=${GITHUB_STEP_SUMMARY:-/dev/stdout}
FAILS=0
bad() { echo "::error title=path probe ($MODE)::$*"; FAILS=$((FAILS + 1)); }
field() { # REPORT KEY -> value, or __missing__
  local IFS='|' kv
  for kv in $1; do
    if [ "${kv%%=*}" = "$2" ]; then printf '%s' "${kv#*=}"; return 0; fi
  done
  printf '__missing__'
}
classify() {
  case "$1:$2" in
    yes:0)  echo WORKS ;;
    no:127) echo BROKEN ;;
    *)      echo "INCONSISTENT(dir=$1,rc=$2)" ;;
  esac
}

{
  echo "### Path probe: $MODE"
  echo "| probe | route | path | dir exists | sibling rc (bash -n) | reading |"
  echo "|---|---|---|---|---|---|"
} >> "$S"

INLINE_SEEN=""
ENVEXPR_SEEN=""
for which in C A; do
  var="${which}_REPORT"
  R=${!var:-}
  if [ "$which" = C ]; then label="./.github/spike-143/probe"; else label="./actions-repo/spike-143-probe"; fi
  if [ -z "$R" ]; then
    bad "$label: no report (the probe step did not run, or wrote nothing)"
    continue
  fi
  where=$(field "$R" where)
  [ "$where" = "$MODE" ] || bad "$label ran on [$where], but this job claims [$MODE]"
  for route in inline envexpr envvar; do
    p=$(field "$R" "${route}_path")
    d=$(field "$R" "${route}_dir")
    rc=$(field "$R" "${route}_rc")
    if [ "$p" = "__missing__" ] || [ -z "$p" ]; then bad "$label: route $route reported no path"; fi
    c=$(classify "$d" "$rc")
    echo "| \`$label\` | $route | \`$p\` | $d | $rc | $c |" >> "$S"
    case "$MODE:$route:$c" in
      *:envvar:WORKS) ;;
      *:envvar:*)     bad "$label: \$GITHUB_ACTION_PATH=[$p] -> $c. preview-* and deploy-cloudflare read siblings through it and would break here" ;;
      host:*:WORKS)   ;;
      host:*:*)       bad "$label: on the host, route $route -> $c; every route should work outside a container" ;;
      container:*:WORKS|container:*:BROKEN) ;;
      container:*:*)  bad "$label: route $route -> $c, neither cleanly working nor cleanly broken" ;;
    esac
    [ "$route" = inline ] && INLINE_SEEN="$INLINE_SEEN $c"
    [ "$route" = envexpr ] && ENVEXPR_SEEN="$ENVEXPR_SEEN $c"
  done
  ar=$(field "$R" action_repository)
  af=$(field "$R" action_ref)
  echo "| \`$label\` | GITHUB_ACTION_REPOSITORY / GITHUB_ACTION_REF | \`${ar:-<empty>}\` / \`${af:-<empty>}\` | | | recorded |" >> "$S"
done

collapse() { tr ' ' '\n' <<<"$1" | sed '/^$/d' | sort -u | paste -sd, -; }
INLINE=$(collapse "$INLINE_SEEN")
ENVEXPR=$(collapse "$ENVEXPR_SEEN")
case "$INLINE" in *,*) bad "the two probes disagree about the inline expression route: $INLINE" ;; esac
case "$ENVEXPR" in *,*) bad "the two probes disagree about the env-delivered expression route: $ENVEXPR" ;; esac
echo "inline=$INLINE" >> "$GITHUB_OUTPUT"
echo "envexpr=$ENVEXPR" >> "$GITHUB_OUTPUT"

if [ "$MODE" = container ]; then
  case "$INLINE" in
    BROKEN) echo 'Finding: ${{ github.action_path }} expanded into a script is the HOST path inside the container (actions/runner#2185, the #83 shape), for a LOCAL action as for a remote one.' ;;
    WORKS)  echo '::notice title=path probe::${{ github.action_path }} expanded into a script WORKS in this container job: the runner translated it (server flag UseContainerPathForTemplate appears to be on for this repository). Record it; do not generalise it to other repositories.' ;;
  esac
  echo "| finding | \${{ github.action_path }} in a script: **$INLINE**; via env: **$ENVEXPR**; \$GITHUB_ACTION_PATH: required WORKS | | | | |" >> "$S"
fi

if [ "$FAILS" -gt 0 ]; then
  echo "::error title=path probe ($MODE)::$FAILS check(s) failed"
  exit 1
fi
echo "ok=true" >> "$GITHUB_OUTPUT"
