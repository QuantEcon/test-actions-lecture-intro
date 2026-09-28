#!/usr/bin/env bash
# THROWAWAY: QuantEcon/actions#143 spike. Runs in the final `evidence` job,
# on the host, with actions: read.
#
#   1. Checks every other job ended in the state this event requires.
#   2. Downloads their raw logs through the Actions API and checks the facts
#      no step can see from inside its own job: which ref each `uses:`
#      resolved to (the step headers), what the runner downloaded, the
#      composite sub-step outcome markers, and whether the nested post: hook
#      of a local composite ran.
#   3. Writes the verdict table, and keeps the logs as an artifact, because
#      job logs expire (the canary's February 2026 logs already answer 410).
#
# Each check PASSes, FAILs (the job exits 1), or is recorded as a finding.
# Missing evidence is a FAIL, never a pass.
#
# env: NEEDS (toJSON(needs)), EVENT, GH_TOKEN, CANDIDATE, CONTROL_SHA,
#      GITHUB_REPOSITORY, GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT, GITHUB_EVENT_PATH
set -uo pipefail

: "${NEEDS:?}" "${EVENT:?}" "${GH_TOKEN:?}" "${CONTROL_SHA:?}"
CANDIDATE=${CANDIDATE:-unresolved}
OUT=${OUT:-spike-143-evidence}
mkdir -p "$OUT/logs"
S=${GITHUB_STEP_SUMMARY:-/dev/null}
FAILS=0

row()  { printf '| %s | %s | %s |\n' "$1" "$2" "$3" | tee -a "$OUT/verdict.md" >> "$S"; }
pass() { row "$1" "PASS" "$2"; }
fail() { row "$1" "**FAIL**" "$2"; echo "::error title=$1::$2"; FAILS=$((FAILS + 1)); }
rec()  { row "$1" "finding" "$2"; }
warn() { row "$1" "warn" "$2"; echo "::warning title=$1::$2"; }
hdr()  { printf '\n### %s\n\n| check | status | detail |\n|---|---|---|\n' "$1" | tee -a "$OUT/verdict.md" >> "$S"; }
out()  { jq -r --arg j "$1" --arg k "$2" '.[$j].outputs[$k] // ""' <<<"$NEEDS"; }
res()  { jq -r --arg j "$1" '.[$j].result // "missing"' <<<"$NEEDS"; }
chk_min() { if [ "${2:-0}" -ge "$3" ]; then pass "$1" "$4 (found $2)"; else fail "$1" "$4: found ${2:-0}, expected at least $3"; fi; }
chk_eq()  { if [ "${2:-x}" = "$3" ]; then pass "$1" "$4 (found $2)"; else fail "$1" "$4: found ${2:-none}, expected $3"; fi; }

PR=""
if [ "$EVENT" = "pull_request" ] && [ -f "${GITHUB_EVENT_PATH:-}" ]; then
  PR=$(jq -r '.pull_request.number // empty' "$GITHUB_EVENT_PATH")
fi

{
  echo "## Spike 143 evidence: $EVENT run $GITHUB_RUN_ID (attempt $GITHUB_RUN_ATTEMPT)"
  echo
  echo "Candidate \`$CANDIDATE\`, remote control \`$CONTROL_SHA\`, image \`$(out resolve image)\`."
} | tee -a "$OUT/verdict.md" >> "$S"

# --------------------------------------------------------------------------
# 1. Job states for this event
# --------------------------------------------------------------------------
hdr "Job states"
ALL="resolve probe-container probe-host q1-local q1-remote bjc-local bjc-rewired pr-preview"
if [ "$EVENT" = "pull_request" ]; then
  RAN="resolve pr-preview"
else
  RAN="resolve probe-container probe-host q1-local q1-remote bjc-local bjc-rewired"
fi
[ "$(jq 'length' <<<"$NEEDS")" -eq 8 ] || fail "needs" "expected 8 upstream jobs in needs, found $(jq 'length' <<<"$NEEDS"); this script and the workflow disagree"
for j in $ALL; do
  r=$(res "$j")
  if [[ " $RAN " == *" $j "* ]]; then
    if [ "$r" = "success" ]; then pass "job $j" "success"; else fail "job $j" "expected success on $EVENT, got [$r]"; fi
  else
    if [ "$r" = "skipped" ]; then pass "job $j" "skipped (does not run on $EVENT)"; else fail "job $j" "expected skipped on $EVENT, got [$r]"; fi
  fi
done

# --------------------------------------------------------------------------
# 2. Logs
# --------------------------------------------------------------------------
API="${GITHUB_API_URL:-https://api.github.com}/repos/$GITHUB_REPOSITORY"
get() {
  curl -fsSL --retry 3 --retry-delay 5 \
    -H "Authorization: Bearer $GH_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" "$1"
}
JOBS=$(get "$API/actions/runs/$GITHUB_RUN_ID/attempts/$GITHUB_RUN_ATTEMPT/jobs?per_page=100" 2>/dev/null || true)
if [ -z "$JOBS" ] || ! jq -e '.jobs' >/dev/null 2>&1 <<<"$JOBS"; then
  hdr "Evidence plumbing"
  fail "evidence plumbing: job list" "could not list this run's jobs through the API (this job needs actions: read)"
  JOBS='{"jobs":[]}'
fi
printf '%s\n' "$JOBS" > "$OUT/jobs.json"

declare -A HAVE
jobid() { jq -r --arg p "$1: " '[.jobs[] | select(.name | startswith($p))][0].id // empty' <<<"$JOBS"; }
fetch() {
  local key=$1 id _try
  id=$(jobid "$key")
  if [ -z "$id" ]; then
    fail "evidence plumbing: $key" "no job named '$key: …' in this run's job list"
    return
  fi
  for _try in 1 2 3 4 5 6; do
    if get "$API/actions/jobs/$id/logs" > "$OUT/logs/$key.raw" 2>/dev/null && [ -s "$OUT/logs/$key.raw" ]; then
      tr -d '\r' < "$OUT/logs/$key.raw" > "$OUT/logs/$key.log"
      rm -f "$OUT/logs/$key.raw"
      HAVE[$key]=1
      return
    fi
    sleep 10
  done
  fail "evidence plumbing: $key" "could not download the log of job $id after 6 tries"
}
LOG() { printf '%s' "$OUT/logs/$1.log"; }
# Line counts. A log that could not be fetched counts 0, which fails every
# "at least" check below, and the plumbing row above already says why.
n_f() { if [ -n "${HAVE[$1]:-}" ]; then grep -ciF -- "$2" "$(LOG "$1")" || true; else echo 0; fi; }
n_e() { if [ -n "${HAVE[$1]:-}" ]; then grep -cE -- "$2" "$(LOG "$1")" || true; else echo 0; fi; }
# Composite sub-step end markers: '##[end-action id=<prefix>.<step id>;outcome=<o>;...'
sub() {
  if [ -z "${HAVE[$1]:-}" ]; then echo 0; return; fi
  grep -oE '##\[end-action id=[^;]+;outcome=[a-z]+' "$(LOG "$1")" \
    | sed -E 's/^##\[end-action id=(.*);outcome=(.*)$/\1 \2/' \
    | awk -v s="$2" -v o="$3" '{ n = split($1, a, "."); if (a[n] == s && $2 == o) c++ } END { print c + 0 }'
}
# Exact sub-step id: '<outer step id>.<inner step id>'. The runner names a
# composite's scope after the outer step's id: (canary PR #67's log shows
# 'cache.cache-key' for `id: cache`); an inner step without an id is
# '__run' / '__run_2' / '__<owner>_<action>'. In preview-*, the only anonymous
# run: step is 'Skip notification' (-> __run) and the comment step is the only
# github-script (-> __actions_github-script).
subp() {
  if [ -z "${HAVE[$1]:-}" ]; then echo 0; return; fi
  grep -cF -- "##[end-action id=$2;outcome=$3;" "$(LOG "$1")" || true
}
has_prefix() { [ -n "${HAVE[$1]:-}" ] && grep -qF -- "##[end-action id=$2." "$(LOG "$1")"; }
# One preview invocation, by its outer step id. SHAPE: skipped (a real action
# on push/dispatch), ctl (the ungated copy, dummy token), deployed (the PR run).
inv() { # key outer shape
  local k=$1 o=$2 shape=$3 st oc want n
  if ! has_prefix "$k" "$o"; then
    warn "$k: $o sub-steps" "no '##[end-action id=$o.' markers in the log although other markers exist; the per-invocation reading falls back to the aggregate counts (see markers-$k.txt)"
    return
  fi
  case "$shape" in
    skipped)  want="check-trust:success install-cli:success detect-changes:skipped deploy:skipped __actions_github-script:skipped __run:skipped" ;;
    ctl)      want="check-trust:success install-cli:success detect-changes:skipped deploy:failure __actions_github-script:skipped __run:skipped" ;;
    deployed) want="check-trust:success detect-changes:success install-cli:success deploy:success __actions_github-script:success __run:skipped" ;;
  esac
  local got="" bad=""
  for st in $want; do
    oc=${st#*:}; st=${st%%:*}
    n=$(subp "$k" "$o.$st" "$oc")
    got="$got $st=$oc×$n"
    [ "$n" = 1 ] || bad="$bad $st(expected $oc once, found $n)"
  done
  if [ -z "$bad" ]; then
    pass "$k: $o sub-steps ($shape)" "$got"
  else
    fail "$k: $o sub-steps ($shape)" "$bad; markers:$got"
  fi
}
subchecks() { # key profile
  local k=$1 prof=$2
  if [ "$(n_f "$k" '##[end-action id=')" -eq 0 ]; then
    warn "$k: composite sub-step markers" "no '##[end-action' lines in this log; the sub-step reading rests on step outputs and the positive control"
    return
  fi
  grep -oE '##\[end-action id=[^;]+;outcome=[a-z]+' "$(LOG "$k")" \
    | sed -E 's/^##\[end-action id=//; s/;outcome=/ /' | sort | uniq -c > "$OUT/markers-$k.txt"
  rec "$k: preview sub-step markers (id outcome ×n)" "$(awk '$2 ~ /\.(check-trust|detect-changes|install-cli|deploy)$/ { printf "%s=%s×%s ", $2, $3, $1 }' "$OUT/markers-$k.txt" | cut -c1-900)"
  case "$prof" in
    nonpr-local)
      chk_eq  "$k: deploy sub-steps that succeeded" "$(sub "$k" deploy success)" 0 "no deploy may succeed on $EVENT"
      chk_min "$k: deploy sub-steps skipped" "$(sub "$k" deploy skipped)" 2 "the two real preview invocations skip deploy"
      chk_min "$k: deploy sub-steps failed" "$(sub "$k" deploy failure)" 2 "the two positive-control copies reach deploy and fail on the dummy token"
      chk_min "$k: install-cli sub-steps succeeded" "$(sub "$k" install-cli success)" 4 "all four invocations install their CLI through \$GITHUB_ACTION_PATH"
      chk_min "$k: detect-changes sub-steps skipped" "$(sub "$k" detect-changes skipped)" 4 "change detection is pull_request-only"
      # Per invocation, including the silence: the comment step and the
      # 'Skip notification' step (the only thing that ever says a deploy was
      # skipped) are both skipped, so nothing in the log says so.
      inv "$k" pn_local skipped
      inv "$k" pc_local skipped
      inv "$k" pn_ctl ctl
      inv "$k" pc_ctl ctl
      ;;
    nonpr-remote)
      chk_eq  "$k: deploy sub-steps that succeeded" "$(sub "$k" deploy success)" 0 "no deploy may succeed on $EVENT"
      chk_min "$k: deploy sub-steps skipped" "$(sub "$k" deploy skipped)" 2 "both remote preview invocations skip deploy"
      chk_min "$k: install-cli sub-steps succeeded" "$(sub "$k" install-cli success)" 2 "both install their CLI"
      inv "$k" pn_remote skipped
      inv "$k" pc_remote skipped
      ;;
    pr)
      chk_eq  "$k: deploy sub-steps that succeeded" "$(sub "$k" deploy success)" "$NDEPLOY" "one real deploy per provider exercised"
      chk_eq  "$k: detect-changes sub-steps that succeeded" "$(sub "$k" detect-changes success)" "$NDEPLOY" "\$GITHUB_ACTION_PATH/../scripts ran per provider"
      chk_eq  "$k: deploy sub-steps skipped" "$(sub "$k" deploy skipped)" 0 "nothing skipped on pull_request"
      inv "$k" pn_pr deployed
      if [ "$NDEPLOY" = 2 ]; then inv "$k" pc_pr deployed; fi
      ;;
  esac
}
postcheck() { # key outer-step-name
  local k=$1 name=$2 concl saves
  concl=$(jq -r --arg p "$k: " --arg n "Post $name" \
    '[.jobs[] | select(.name | startswith($p)) | .steps[]? | select(.name == $n)][0].conclusion // "absent"' <<<"$JOBS")
  saves=$(n_e "$k" 'Cache saved with key: build-|Unable to reserve cache|another job may be creating this cache|Failed to save')
  local t="$k: nested post: hook of a composite in a container (actions/cache save)"
  if [ "$concl" = "success" ]; then
    pass "$t" "step 'Post $name' concluded success; cache-save lines in the log: $saves"
  elif [ "$(res "$k")" != "success" ]; then
    rec "$t" "not evaluable: the job did not succeed, and actions/cache's post-if is success()"
  elif [ "${saves:-0}" -gt 0 ]; then
    pass "$t" "no step listed as 'Post $name', but the log has $saves cache-save line(s)"
  else
    fail "$t" "no 'Post $name' step and no cache-save line: the nested post hook did not run"
  fi
}

DL_ANY="Download action repository 'quantecon/actions@"
DEPLOY_OUT='Deploying preview for PR #[^$]'   # the scripts' output, not their echoed source (#${PR_NUMBER})

runner_versions() { # keys...
  local k v img
  for k in "$@"; do
    [ -n "${HAVE[$k]:-}" ] || continue
    v=$(grep -m1 -oE "Current runner version: '[^']+'" "$(LOG "$k")" | grep -oE "'[^']+'" || true)
    img=$(grep -m1 -oE 'Digest: sha256:[0-9a-f]{64}' "$(LOG "$k")" || true)
    rec "$k: runner / image digest in log" "runner ${v:-unknown}; ${img:-no image digest (host job)}"
  done
}

if [ "$EVENT" != "pull_request" ]; then
  # resolve and the probes are fetched to keep their logs (the #83 route
  # table, the digest, the trust refs) in the artifact; their facts are
  # asserted in-job.
  for k in resolve probe-container probe-host q1-local q1-remote bjc-local bjc-rewired; do fetch "$k"; done
  hdr "Runner and image per job (Q1's inline-expression result depends on the runner)"
  runner_versions resolve probe-container probe-host q1-local q1-remote bjc-local bjc-rewired
  rec "resolve: candidate contained in" "$(out resolve trusted_by)"

  hdr "q1-local: canary chain through ./actions-repo (container)"
  k=q1-local
  chk_min "$k: build-lectures resolved locally" "$(n_e $k '##\[group\]Run (\./)?actions-repo/build-lectures$')" 3 "step headers 'Run ./actions-repo/build-lectures'"
  chk_min "$k: restore-jupyter-cache resolved locally" "$(n_e $k '##\[group\]Run (\./)?actions-repo/restore-jupyter-cache$')" 1 "step header 'Run ./actions-repo/restore-jupyter-cache'"
  chk_min "$k: preview-netlify resolved locally" "$(n_e $k '##\[group\]Run (\./)?actions-repo/preview-netlify$')" 1 "step header 'Run ./actions-repo/preview-netlify'"
  chk_min "$k: preview-cloudflare resolved locally" "$(n_e $k '##\[group\]Run (\./)?actions-repo/preview-cloudflare$')" 1 "step header 'Run ./actions-repo/preview-cloudflare'"
  chk_eq  "$k: nothing downloaded from quantecon/actions" "$(n_f $k "$DL_ANY")" 0 "runner 'Download action repository quantecon/actions@…' lines"
  chk_eq  "$k: deploy scripts that started" "$(n_e $k "$DEPLOY_OUT")" 2 "'Deploying preview for PR #' output lines: only the two positive-control copies may print one"
  # The positive control must fail because its CLI exited non-zero, not
  # because a 6-minute step timeout killed it: the actions print these
  # ::error:: lines only after the CLI returned (a timeout kills first).
  chk_eq  "$k: positive-control steps that timed out" "$(n_f $k 'has timed out')" 0 "runner 'has timed out' lines"
  chk_eq  "$k: ungated preview-netlify failed on its own terms" "$(n_e $k '##\[error\](netlify deploy failed \(exit [0-9]+\)|no deploy URL in netlify)')" 1 "the action's own error line after netlify returned"
  chk_eq  "$k: ungated preview-cloudflare failed on its own terms" "$(n_e $k '##\[error\]wrangler pages deploy failed \(exit [0-9]+\)')" 1 "the action's own error line after wrangler returned"
  if [ -n "${HAVE[$k]:-}" ]; then
    rec "$k: what the dummy token got (first matching CLI lines)" "$(sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z //' "$(LOG $k)" | grep -m6 -iE 'unauthori[sz]ed|\b40[13]\b|authentication error|invalid (api )?token|\[code: [0-9]{4,5}\]' | tr '|' '/' | paste -sd';' - | cut -c1-600)"
  fi
  subchecks $k nonpr-local
  postcheck $k "Restore build cache (local)"

  hdr "q1-remote: the same chain through quantecon/actions@$CONTROL_SHA (container)"
  k=q1-remote
  chk_min "$k: control SHA downloaded" "$(n_f $k "Download action repository 'quantecon/actions@$CONTROL_SHA'")" 1 "runner download line for the literal SHA"
  chk_min "$k: build-lectures resolved remotely" "$(n_f $k "##[group]Run quantecon/actions/build-lectures@$CONTROL_SHA")" 3 "step headers 'Run quantecon/actions/build-lectures@<sha>'"
  chk_eq  "$k: no @v0 download" "$(n_f $k "Download action repository 'quantecon/actions@v0'")" 0 "runner download lines for @v0"
  chk_eq  "$k: deploy scripts that started" "$(n_e $k "$DEPLOY_OUT")" 0 "'Deploying preview for PR #' output lines"
  subchecks $k nonpr-remote
  postcheck $k "Restore build cache (remote)"

  hdr "build-jupyter-cache through ./actions-repo (container)"
  k=bjc-local
  chk_min "$k: build-jupyter-cache resolved locally" "$(n_e $k '##\[group\]Run (\./)?actions-repo/build-jupyter-cache$')" 1 "step header"
  V0LOG=""
  if [ -n "${HAVE[$k]:-}" ]; then
    V0LOG=$(grep -oiE "Download action repository 'quantecon/actions@v0' \(SHA:[0-9a-f]{40}\)" "$(LOG $k)" | head -n 1 | grep -oE '[0-9a-f]{40}' || true)
  fi
  if [ -n "$V0LOG" ]; then
    rec "$k: nested siblings (the known residual)" "setup-environment and build-lectures ran quantecon/actions@v0 = \`$V0LOG\`, not the candidate"
    V0JOB=$(out bjc-local v0_sha)
    if [ -n "$V0JOB" ]; then
      chk_eq "$k: log SHA agrees with the in-job tag lookup" "$V0LOG" "$V0JOB" "v0 commit"
    fi
  else
    fail "$k: nested siblings" "no 'Download action repository quantecon/actions@v0 (SHA:…)' line: the residual did not show as expected"
  fi
  k=bjc-rewired
  chk_min "$k: build-jupyter-cache resolved locally" "$(n_e $k '##\[group\]Run (\./)?actions-repo/build-jupyter-cache$')" 1 "step header"
  chk_eq  "$k: nothing downloaded from quantecon/actions" "$(n_f $k "$DL_ANY")" 0 "runner download lines: the rewired nested calls resolved to ./actions-repo"
  rec "$k: nested local step headers" "setup-environment: $(n_e $k '##\[group\]Run (\./)?actions-repo/setup-environment$'), build-lectures: $(n_e $k '##\[group\]Run (\./)?actions-repo/build-lectures$')"
else
  fetch resolve
  fetch pr-preview
  hdr "Runner and image per job"
  runner_versions resolve pr-preview
  NDEPLOY=1
  [ "$(out pr-preview cloudflare_ran)" = "true" ] && NDEPLOY=2
  hdr "pr-preview: real deploys through ./actions-repo on pull_request #${PR:-?} (container)"
  k=pr-preview
  chk_min "$k: build-lectures resolved locally" "$(n_e $k '##\[group\]Run (\./)?actions-repo/build-lectures$')" 3 "step headers"
  chk_min "$k: preview-netlify resolved locally" "$(n_e $k '##\[group\]Run (\./)?actions-repo/preview-netlify$')" 1 "step header"
  chk_eq  "$k: nothing downloaded from quantecon/actions" "$(n_f $k "$DL_ANY")" 0 "runner download lines"
  chk_eq  "$k: deploy scripts that started" "$(n_e $k "Deploying preview for PR #${PR:-x}[^0-9]")" "$NDEPLOY" "'Deploying preview for PR #$PR' output lines"
  # detect-changed-lectures.sh swallows git errors (an empty changed-files can
  # mean "git diff failed"), so separate "the ../scripts file ran through
  # \$GITHUB_ACTION_PATH" (its own output lines) from "it found the change"
  # (the changed-files assertion in pr-preview).
  chk_eq  "$k: ../scripts/detect-changed-lectures.sh ran" "$(n_f $k 'Detecting changed lecture files in lectures')" "$NDEPLOY" "the script's first output line, once per provider"
  chk_eq  "$k: detect-changed-lectures.sh reached its end" "$(n_f $k '_toc.yml found in lectures/')" "$NDEPLOY" "the script's last output line, once per provider"
  subchecks $k pr
  postcheck $k "Restore build cache (local)"
fi

# --------------------------------------------------------------------------
# 3. Verdict
# --------------------------------------------------------------------------
hdr "Verdict for this $EVENT run"
if [ "$EVENT" != "pull_request" ]; then
  if [ "$(out q1-local builds_ok)" = "true" ] && [ "$(out q1-local attribution_ok)" = "true" ]; then
    pass "Q1: local ./actions-repo/<action> in a container job" "WORKS: restore-jupyter-cache and build-lectures ×3 resolved from a subpath of the candidate checkout and produced every asserted output; nothing came from quantecon/actions"
  else
    fail "Q1: local ./actions-repo/<action> in a container job" "FAILS or unproven: builds_ok=[$(out q1-local builds_ok)] attribution_ok=[$(out q1-local attribution_ok)]; read the q1-local job"
  fi
  if [ "$(out probe-container ok)" = "true" ] && [ "$(out q1-local q2_ok)" = "true" ]; then
    pass "Q1: \$GITHUB_ACTION_PATH through a local path in a container" "WORKS: the probe reached ../scripts (the real detect-changed-lectures.sh) through it, and both local preview actions copied package.json from it and installed the pinned CLI"
  else
    fail "Q1: \$GITHUB_ACTION_PATH through a local path in a container" "FAILS or unproven: probe ok=[$(out probe-container ok)], preview install ok=[$(out q1-local q2_ok)]"
  fi
  rec "Q1: \${{ github.action_path }} expanded into a script, in a container" "$(out probe-container inline) (BROKEN is actions/runner#2185, as in #83, for a local action too; WORKS would mean the runner's UseContainerPathForTemplate flag is on here). Via env: $(out probe-container envexpr). On the host: probe-host ok=[$(out probe-host ok)]"
  if [ "$CANDIDATE" != "$CONTROL_SHA" ]; then
    rec "Q1: local vs remote parity" "not applicable: this run's candidate differs from the control's literal SHA"
  else
    lh=$(out q1-local html_list_sha)
    rh=$(out q1-remote html_list_sha)
    if [ "$(out q1-remote builds_ok)" = "true" ] && [ "$(out q1-remote attribution_ok)" = "true" ] && [ -n "$lh" ] && [ "$lh" = "$rh" ]; then
      pass "Q1: local vs remote parity" "SAME: both chains green; identical html page set ($(out q1-local html_pages) pages, list sha256 $lh)"
    else
      fail "Q1: local vs remote parity" "DIFFERENT: remote builds_ok=[$(out q1-remote builds_ok)] attribution_ok=[$(out q1-remote attribution_ok)]; page-list sha local=[$lh] remote=[$rh]"
    fi
    lk=$(out q1-local cache_key)
    rk=$(out q1-remote cache_key)
    if [ "$lk" = "$rk" ]; then
      rec "Q1: restored cache, local vs remote" "same key \`${lk:-none}\`"
    else
      warn "Q1: restored cache, local vs remote" "local \`${lk:-none}\` vs remote \`${rk:-none}\` (a job that started late can pick up a cache saved earlier in this run)"
    fi
  fi
  if [ "$(out bjc-local ok)" = "true" ] && [ "$(out bjc-local attribution_ok)" = "true" ]; then
    pass "Q1: build-jupyter-cache through a local path, as shipped" "WORKS for its own steps; its nested siblings ran @v0 (see above): the residual stands for a plain local-path gate"
  else
    fail "Q1: build-jupyter-cache through a local path, as shipped" "ok=[$(out bjc-local ok)] attribution_ok=[$(out bjc-local attribution_ok)]"
  fi
  if [ "$(out bjc-rewired ok)" = "true" ] && [ "$(out bjc-rewired attribution_ok)" = "true" ] && [ "$(out bjc-rewired rewrites)" = "4" ]; then
    pass "Q1: build-jupyter-cache with its 4 nested @v0 calls rewired to ./actions-repo" "WORKS: nested ./ resolved against the workspace; the whole chain ran the candidate (a local-path gate can close the residual)"
  else
    fail "Q1: build-jupyter-cache with nested calls rewired" "ok=[$(out bjc-rewired ok)] attribution_ok=[$(out bjc-rewired attribution_ok)] rewrites=[$(out bjc-rewired rewrites)]"
  fi
  if [ "$(out q1-local q2_ok)" = "true" ] && [ "$(out q1-local ctl_ok)" = "true" ] && [ "$(out q1-remote q2_ok)" = "true" ]; then
    pass "Q2: preview-netlify + preview-cloudflare on $EVENT" "CONFIRMED vacuous green, local and remote alike: step success, deploy-url empty, deploy sub-step skipped, and silent (comment and Skip notification sub-steps skipped: see the per-invocation rows); the ungated copy, whose CLI returned an error, proves the deploy step would have failed if it had run"
  else
    fail "Q2: preview-* on $EVENT" "not established: local q2_ok=[$(out q1-local q2_ok)] ctl_ok=[$(out q1-local ctl_ok)] remote q2_ok=[$(out q1-remote q2_ok)]"
  fi
else
  if [ "$(out pr-preview builds_ok)" = "true" ] && [ "$(out pr-preview attribution_ok)" = "true" ]; then
    pass "Q1: local chain in a container on pull_request" "WORKS (builds and attribution)"
  else
    fail "Q1: local chain in a container on pull_request" "builds_ok=[$(out pr-preview builds_ok)] attribution_ok=[$(out pr-preview attribution_ok)]"
  fi
  if [ "$(out pr-preview netlify_ok)" = "true" ]; then
    pass "Q1: local preview-netlify on pull_request (../scripts via \$GITHUB_ACTION_PATH, real deploy)" "WORKS: $(out pr-preview netlify_url) serves this run's marker; changed-files named the spike lecture"
  else
    fail "Q1: local preview-netlify on pull_request" "netlify_ok=[$(out pr-preview netlify_ok)]"
  fi
  if [ "$(out pr-preview cloudflare_ran)" = "true" ] && [ "$(out pr-preview cloudflare_ok)" = "true" ]; then
    pass "Q1: local preview-cloudflare on pull_request (real deploy)" "WORKS: $(out pr-preview cloudflare_url)"
  else
    fail "Q1: local preview-cloudflare on pull_request" "ran=[$(out pr-preview cloudflare_ran)] ok=[$(out pr-preview cloudflare_ok)] (ran=false means the Cloudflare secrets were empty in this run: NOT EXERCISED)"
  fi
  if [ "$(out pr-preview comments_ok)" = "true" ]; then
    pass "Q1: local preview comment steps on pull_request" "both marker comments link this run"
  else
    fail "Q1: local preview comment steps" "comments_ok=[$(out pr-preview comments_ok)]"
  fi
fi

echo "failures=$FAILS" >> "$OUT/verdict.md"
if [ "$FAILS" -gt 0 ]; then
  echo "::error title=spike 143 evidence::$FAILS check(s) failed; see the job summary"
  exit 1
fi
echo "All evidence checks passed for this $EVENT run."
