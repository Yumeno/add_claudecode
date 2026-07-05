#!/usr/bin/env bash
set -uo pipefail

ERROR_SENTINEL='[CLAUDE_WRAPPER_ERROR]'
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CONFIG_FILE="$SCRIPT_DIR/claude-wrapper.conf"
PROMPT='' MODEL='' TIMEOUT=180 MAX_BUDGET_USD=0.25 WORKDIR='' CONTEXT='' CONTEXT_FILE=''
SET_MODEL='' SHOW_MODEL=0
OWNED_WORKDIR=''

cleanup() {
  [[ -z "$OWNED_WORKDIR" ]] || rm -rf -- "$OWNED_WORKDIR"
  [[ -z "${ERR:-}" ]] || rm -f -- "$ERR"
}
trap cleanup EXIT
fail() { printf '%s %s\n' "$ERROR_SENTINEL" "$2"; printf 'Error: %s\n' "$2" >&2; exit "$1"; }
require_value() { [[ $# -ge 2 && -n "${2-}" ]] || fail 1 "$1 requires a value."; }
valid_model() { [[ "$1" =~ ^[A-Za-z0-9._:/-]+$ ]] || fail 1 "unsafe model name from $2: '$1'"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt) require_value "$1" "${2-}"; PROMPT=$2; shift 2 ;;
    --model) require_value "$1" "${2-}"; MODEL=$2; shift 2 ;;
    --timeout) require_value "$1" "${2-}"; TIMEOUT=$2; shift 2 ;;
    --max-budget-usd) require_value "$1" "${2-}"; MAX_BUDGET_USD=$2; shift 2 ;;
    --workdir|--cd) require_value "$1" "${2-}"; WORKDIR=$2; shift 2 ;;
    --context) require_value "$1" "${2-}"; CONTEXT=$2; shift 2 ;;
    --context-file) require_value "$1" "${2-}"; CONTEXT_FILE=$2; shift 2 ;;
    --set-model) require_value "$1" "${2-}"; SET_MODEL=$2; shift 2 ;;
    --show-model) SHOW_MODEL=1; shift ;;
    *) fail 1 "Unknown option: $1" ;;
  esac
done

if [[ -n "$SET_MODEL" ]]; then
  valid_model "$SET_MODEL" '--set-model'
  printf '# claude-wrapper.conf\n# Model priority: CLI > CLAUDE_WRAPPER_MODEL > this file > Claude default\nmodel=%s\n' "$SET_MODEL" > "$CONFIG_FILE"
  printf "Saved model='%s' to %s\n" "$SET_MODEL" "$CONFIG_FILE"
  exit 0
fi

MODEL_SOURCE=''
if [[ -n "$MODEL" ]]; then valid_model "$MODEL" '--model'; MODEL_SOURCE=cli
elif [[ -n "${CLAUDE_WRAPPER_MODEL:-}" ]]; then MODEL=$CLAUDE_WRAPPER_MODEL; valid_model "$MODEL" env; MODEL_SOURCE=env
elif [[ -f "$CONFIG_FILE" ]]; then
  MODEL=$(sed -nE 's/^[[:space:]]*model[[:space:]]*=[[:space:]]*(.*)[[:space:]]*$/\1/p' "$CONFIG_FILE" | head -n1)
  [[ -z "$MODEL" ]] || { valid_model "$MODEL" config; MODEL_SOURCE=config; }
fi

if (( SHOW_MODEL )); then
  if [[ -n "$MODEL" ]]; then printf 'model=%s (source: %s)\n' "$MODEL" "$MODEL_SOURCE"
  else printf 'model=(unset; Claude Code default will be used)\n'; fi
  printf 'config_file=%s\n' "$CONFIG_FILE"
  exit 0
fi

[[ -n "$PROMPT" ]] || fail 1 '--prompt is required.'
[[ "$TIMEOUT" =~ ^[1-9][0-9]*$ ]] || fail 1 '--timeout must be a positive integer.'
[[ "$MAX_BUDGET_USD" =~ ^([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]] &&
  awk -v value="$MAX_BUDGET_USD" 'BEGIN { exit !(value > 0) }' ||
  fail 1 '--max-budget-usd must be greater than zero.'
command -v claude >/dev/null 2>&1 || fail 1 "'claude' CLI not found in PATH."
if [[ -n "$CONTEXT_FILE" ]]; then [[ -f "$CONTEXT_FILE" ]] || fail 1 "Context file not found: $CONTEXT_FILE"; CONTEXT=$(cat "$CONTEXT_FILE"); fi
if (( ${#CONTEXT} > 102400 )); then printf 'Warning: Context is large (~%dK chars).\n' "$(( ${#CONTEXT}/1024 ))" >&2; fi
if [[ -z "$WORKDIR" ]]; then
  WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/claude-wrapper-XXXXXX") || fail 1 'cannot create isolated workdir'
  OWNED_WORKDIR=$WORKDIR
fi
[[ -d "$WORKDIR" ]] || fail 1 "workdir does not exist: $WORKDIR"

if [[ -n "$CONTEXT" ]]; then FULL_PROMPT=$(printf '## Context\n\n%s\n\n---\n\n## Request\n\n%s' "$CONTEXT" "$PROMPT"); else FULL_PROMPT=$PROMPT; fi
ARGS=(-p --output-format text --safe-mode --tools '' --no-session-persistence --max-budget-usd "$MAX_BUDGET_USD")
if [[ -n "$MODEL" ]]; then ARGS+=(--model "$MODEL"); printf 'MODEL: %s\n' "$MODEL" >&2; fi

ERR=$(mktemp "${TMPDIR:-/tmp}/claude_err_XXXXXX") || fail 1 'cannot create stderr file'
TIMER=()
if command -v timeout >/dev/null 2>&1; then TIMER=(timeout --foreground "${TIMEOUT}s")
elif command -v gtimeout >/dev/null 2>&1; then TIMER=(gtimeout --foreground "${TIMEOUT}s")
else fail 1 "'timeout' (or 'gtimeout') is required."; fi

EXIT=0
OUTPUT=$(cd "$WORKDIR" && printf '%s' "$FULL_PROMPT" | "${TIMER[@]}" claude "${ARGS[@]}" 2>"$ERR") || EXIT=$?
[[ $EXIT -ne 124 ]] || fail 2 "Claude Code CLI timed out after ${TIMEOUT}s"
[[ $EXIT -ne 137 ]] || fail 2 "Claude Code CLI timed out after ${TIMEOUT}s"
[[ $EXIT -eq 0 ]] || fail "$EXIT" "Claude Code CLI exited with status $EXIT. $(cat "$ERR")"
[[ -n "${OUTPUT//[[:space:]]/}" ]] || fail 1 'Claude Code CLI returned empty output.'

printf '%s\n' "$OUTPUT"
