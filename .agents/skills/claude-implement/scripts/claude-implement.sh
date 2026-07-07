#!/usr/bin/env bash
set -uo pipefail
SENTINEL='[CLAUDE_IMPLEMENT_ERROR]'
SPEC='' REPO='' REPO_FILE='' MODEL='' TIMEOUT=600 MAX_BUDGET_USD=1.00
ALLOWS=()
fail(){ printf '%s %s\n' "$SENTINEL" "$2"; printf 'Error: %s\n' "$2" >&2; exit "$1"; }
need(){ [[ $# -ge 2 && -n "${2-}" ]] || fail 1 "$1 requires a value."; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --spec-file) need "$1" "${2-}"; SPEC=$2; shift 2 ;;
    --repo) need "$1" "${2-}"; REPO=$2; shift 2 ;;
    --repo-file) need "$1" "${2-}"; REPO_FILE=$2; shift 2 ;;
    --model) need "$1" "${2-}"; MODEL=$2; shift 2 ;;
    --timeout) need "$1" "${2-}"; TIMEOUT=$2; shift 2 ;;
    --max-budget-usd) need "$1" "${2-}"; MAX_BUDGET_USD=$2; shift 2 ;;
    --allow) need "$1" "${2-}"; ALLOWS+=("$2"); shift 2 ;;
    *) fail 1 "Unknown option: $1" ;;
  esac
done
if [[ -n "$REPO" && -n "$REPO_FILE" ]]; then fail 1 "--repo and --repo-file are mutually exclusive."; fi
if [[ -z "$REPO" && -z "$REPO_FILE" ]]; then fail 1 "--repo or --repo-file is required."; fi
if [[ -n "$REPO_FILE" ]]; then
  [[ -f "$REPO_FILE" ]] || fail 1 "--repo-file not found: $REPO_FILE"
  REPO=$(<"$REPO_FILE")
  while [[ ${REPO} == *[$' \t\r\n'] ]]; do REPO=${REPO:0:-1}; done
  [[ -n "$REPO" ]] || fail 1 "--repo-file contents are empty."
fi
[[ -f "$SPEC" ]] || fail 1 "Spec file not found: $SPEC"
[[ -d "$REPO" ]] || fail 1 "Repository not found: $REPO"
[[ "$TIMEOUT" =~ ^[1-9][0-9]*$ ]] || fail 1 'timeout must be a positive integer'
[[ "$MAX_BUDGET_USD" =~ ^[0-9]+([.][0-9]+)?$ ]] || fail 1 'budget must be a positive number'
[[ -z "$MODEL" || "$MODEL" =~ ^[A-Za-z0-9._:/-]+$ ]] || fail 1 'model name contains unsafe characters'
git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail 1 "Target is not a Git working tree: $REPO"
[[ -z "$(git -C "$REPO" status --porcelain=v1 --untracked-files=all)" ]] || fail 1 'Working tree is not clean. Commit or stash changes before delegation.'
command -v claude >/dev/null 2>&1 || fail 1 "'claude' CLI not found in PATH."
VERIFY=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/claude-verify.sh
[[ -x "$VERIFY" || -f "$VERIFY" ]] || fail 1 "Verification helper not found: $VERIFY"
SNAPSHOT=$(mktemp "${TMPDIR:-/tmp}/claude_verify_XXXXXX") || fail 1 'cannot create snapshot file'
rm -f "$SNAPSHOT"
bash "$VERIFY" snapshot --repo "$REPO" --snapshot "$SNAPSHOT" || fail 1 'could not create pre-execution snapshot'

SAFETY='# Mandatory safety constraints

- Modify only files inside the target repository.
- Never modify `.git/`, Git configuration, hooks, refs, branches, tags, submodules, credentials, keys, or `.env` files.
- Do not run git add, commit, checkout, switch, reset, clean, config, branch, tag, worktree, or submodule commands.
- Do not use network tools or spawn subagents.
- Do not make unrelated changes.
- At the end, list every created, modified, or deleted file and report tests run.
- If the task conflicts with these constraints, stop and report the conflict.

---
'
ARGS=(-p --output-format text --safe-mode --tools Read,Edit,Write,Glob,Grep --permission-mode dontAsk --disallowedTools Bash,WebFetch,WebSearch,Task --no-session-persistence --max-budget-usd "$MAX_BUDGET_USD")
[[ -z "$MODEL" ]] || ARGS+=(--model "$MODEL")
ERR=$(mktemp "${TMPDIR:-/tmp}/claude_impl_err_XXXXXX") || fail 1 'cannot create temp file'
trap 'rm -f "$ERR" "$SNAPSHOT"' EXIT
TIMER=()
if command -v timeout >/dev/null 2>&1; then TIMER=(timeout --foreground "${TIMEOUT}s")
elif command -v gtimeout >/dev/null 2>&1; then TIMER=(gtimeout --foreground "${TIMEOUT}s")
else fail 1 "timeout/gtimeout is required"; fi
CODE=0
OUTPUT=$(cd "$REPO" && { printf '%s' "$SAFETY"; cat "$SPEC"; } | "${TIMER[@]}" claude "${ARGS[@]}" 2>"$ERR") || CODE=$?
VERIFY_ARGS=(check --repo "$REPO" --snapshot "$SNAPSHOT")
for allow in "${ALLOWS[@]}"; do VERIFY_ARGS+=(--allow "$allow"); done
bash "$VERIFY" "${VERIFY_ARGS[@]}" || fail 1 'post-execution verification failed'
[[ $CODE -ne 124 && $CODE -ne 137 ]] || fail 2 "Claude Code timed out after ${TIMEOUT}s"
[[ $CODE -eq 0 ]] || fail "$CODE" "Claude Code exited $CODE: $(cat "$ERR")"
[[ -n "${OUTPUT//[[:space:]]/}" ]] || fail 1 'Claude Code returned empty output.'
printf '%s\n' "$OUTPUT"
