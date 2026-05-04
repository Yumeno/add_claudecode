#!/usr/bin/env bash
# claude-wrapper.sh - Invoke Claude Code CLI non-interactively
# Usage: bash claude-wrapper.sh --prompt "your question" [options]
#
# Options:
#   --prompt        (required) The prompt to send to Claude Code
#   --model         (optional) Model name (e.g. claude-opus-4-7, claude-sonnet-4-6)
#   --timeout       (optional) Timeout in seconds (default: 180)
#   --workdir       (optional) Working directory for claude (default: $TMPDIR or /tmp)
#   --context       (optional) Additional context to prepend to the prompt
#   --context-file  (optional) Path to a file containing context (avoids cmdline length limits)

set -uo pipefail

PROMPT=""
MODEL=""
TIMEOUT=180
WORKDIR=""
CONTEXT=""
CONTEXT_FILE=""

# Approx. 100KB warning threshold (in characters; multibyte content will warn earlier)
MAX_CONTEXT_CHARS=102400

require_value() {
    # require_value <flag> <next_arg>
    # Only checks for missing/empty value. Values starting with "--" are
    # accepted (e.g. --prompt "--strictNullChecks の意味は?").
    if [[ $# -lt 2 ]] || [[ -z "${2-}" ]]; then
        echo "Error: $1 requires a value." >&2
        exit 1
    fi
}

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prompt)       require_value "$1" "${2-}"; PROMPT="$2"; shift 2 ;;
        --model)        require_value "$1" "${2-}"; MODEL="$2"; shift 2 ;;
        --timeout)      require_value "$1" "${2-}"; TIMEOUT="$2"; shift 2 ;;
        --workdir)      require_value "$1" "${2-}"; WORKDIR="$2"; shift 2 ;;
        --context)      require_value "$1" "${2-}"; CONTEXT="$2"; shift 2 ;;
        --context-file) require_value "$1" "${2-}"; CONTEXT_FILE="$2"; shift 2 ;;
        *) echo "Error: Unknown option: $1" >&2; exit 1 ;;
    esac
done

# --- Input validation ---
if [[ -z "$PROMPT" ]]; then
    echo "Error: --prompt is required." >&2
    exit 1
fi

if ! command -v claude &>/dev/null; then
    echo "Error: 'claude' CLI not found in PATH. Install: npm install -g @anthropic-ai/claude-code" >&2
    exit 1
fi

# --- Load context from file if specified ---
if [[ -n "$CONTEXT_FILE" ]]; then
    if [[ ! -f "$CONTEXT_FILE" ]]; then
        echo "Error: Context file not found: $CONTEXT_FILE" >&2
        exit 1
    fi
    CONTEXT=$(cat "$CONTEXT_FILE")
fi

# --- Context size warning ---
if [[ -n "$CONTEXT" ]]; then
    if (( ${#CONTEXT} > MAX_CONTEXT_CHARS )); then
        echo "Warning: Context is large (~$(( ${#CONTEXT} / 1024 ))K chars). May slow down the request." >&2
    fi
fi

# --- Determine safe working directory ---
if [[ -z "$WORKDIR" ]]; then
    WORKDIR="${TMPDIR:-/tmp}"
fi
if [[ ! -d "$WORKDIR" ]]; then
    echo "Error: --workdir does not exist: $WORKDIR" >&2
    exit 1
fi

# --- Build the full prompt ---
if [[ -n "$CONTEXT" ]]; then
    FULL_PROMPT="${CONTEXT}

---

${PROMPT}"
else
    FULL_PROMPT="$PROMPT"
fi

# --- Temp file for stderr ---
ERR_FILE=$(mktemp "${TMPDIR:-/tmp}/claude_err_XXXXXX.txt")
cleanup() { rm -f "$ERR_FILE"; }
trap cleanup EXIT

# --- Build claude arguments. Prompt is piped via stdin, never as argv. ---
CLAUDE_ARGS=(-p)
if [[ -n "$MODEL" ]]; then
    CLAUDE_ARGS+=(--model "$MODEL")
fi

# --- Pick a timeout command if available ---
TIMER=()
if command -v timeout &>/dev/null; then
    TIMER=(timeout "${TIMEOUT}s")
elif command -v gtimeout &>/dev/null; then
    TIMER=(gtimeout "${TIMEOUT}s")
else
    echo "Warning: no 'timeout'/'gtimeout' found; running without timeout enforcement (install GNU coreutils to enable)." >&2
fi

# --- Execute. Run in $WORKDIR so claude doesn't pick up the caller's project. ---
CLAUDE_EXIT=0
OUTPUT=$(
    cd "$WORKDIR"
    if [[ ${#TIMER[@]} -gt 0 ]]; then
        printf '%s' "$FULL_PROMPT" | "${TIMER[@]}" claude "${CLAUDE_ARGS[@]}" 2>"$ERR_FILE"
    else
        printf '%s' "$FULL_PROMPT" | claude "${CLAUDE_ARGS[@]}" 2>"$ERR_FILE"
    fi
) || CLAUDE_EXIT=$?

if [[ $CLAUDE_EXIT -eq 124 ]]; then
    echo "Error: Claude Code CLI timed out after ${TIMEOUT}s" >&2
    exit 2
fi

# Check non-empty (any non-whitespace) without mangling internal indentation
if [[ -n "${OUTPUT//[[:space:]]/}" ]]; then
    # Strip only trailing newlines so printf adds exactly one
    while [[ "${OUTPUT: -1}" == $'\n' ]]; do OUTPUT="${OUTPUT%$'\n'}"; done
    printf '%s\n' "$OUTPUT"
else
    echo "Claude Code CLI returned empty output." >&2
    if [[ -s "$ERR_FILE" ]]; then
        echo "Stderr:" >&2
        cat "$ERR_FILE" >&2
    fi
    exit 1
fi

if [[ $CLAUDE_EXIT -ne 0 ]]; then
    exit $CLAUDE_EXIT
fi

exit 0
