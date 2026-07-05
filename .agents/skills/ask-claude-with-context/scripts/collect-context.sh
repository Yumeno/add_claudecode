#!/usr/bin/env bash
# collect-context.sh — Emit context (git diff / log / files) to stdout
# Usage: bash collect-context.sh "<user arguments>"
#
# Recognizes (case-insensitive):
#   review | レビュー | diff       → git diff + git diff --staged
#   security | セキュリティ | 監査 | audit → git diff + changed files
#   log | 履歴 | history            → git log --oneline -20
# Tokens that resolve to existing files → that file's contents

set -uo pipefail

ARGS=""
MODE="auto"
FILES=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prompt) ARGS="${2:?--prompt requires a value}"; shift 2 ;;
        --mode) MODE="${2:?--mode requires a value}"; shift 2 ;;
        --file) FILES+=("${2:?--file requires a value}"); shift 2 ;;
        --) shift; break ;;
        *) if [[ -z "$ARGS" ]]; then ARGS="$1"; shift; else echo "Error: unknown argument: $1" >&2; exit 1; fi ;;
    esac
done
case "$MODE" in auto|review|security|log|none) ;; *) echo "Error: invalid mode: $MODE" >&2; exit 1 ;; esac

emit_section() {
    local title="$1"; shift
    printf '\n### %s\n\n```\n' "$title"
    "$@" 2>&1 || true
    printf '```\n'
}

emit_file() {
    local path="$1"
    printf '\n### File: %s\n\n```\n' "$path"
    cat "$path" 2>&1 || true
    printf '\n```\n'
}

# Whole-word match for English keywords (avoid catching "catalog" → "log",
# "different" → "diff"). Japanese keywords use simple substring match because
# CJK has no word-boundary concept.
matches_word() {
    # matches_word <haystack> <english-alternation>
    printf '%s' "$1" | grep -qiE "(^|[^A-Za-z0-9_])($2)([^A-Za-z0-9_]|\$)"
}
matches_substr() {
    # matches_substr <haystack> <pattern-alternation>
    printf '%s' "$1" | grep -qE "$2"
}

DID_ANY=0
DID_DIFF=0

if [[ "$MODE" == review ]] || { [[ "$MODE" == auto ]] && { matches_word "$ARGS" 'review|diff' || matches_substr "$ARGS" 'レビュー'; }; }; then
    emit_section "git diff (working tree)" git diff
    emit_section "git diff --staged" git diff --staged
    DID_ANY=1
    DID_DIFF=1
fi

if [[ "$MODE" == security ]] || { [[ "$MODE" == auto ]] && { matches_word "$ARGS" 'security|audit' || matches_substr "$ARGS" 'セキュリティ|監査'; }; }; then
    if [[ $DID_DIFF -eq 0 ]]; then
        emit_section "git diff (working tree)" git diff
        emit_section "git diff --staged" git diff --staged
        DID_DIFF=1
    fi
    emit_section "Changed files (working tree)" git diff --name-only
    emit_section "Changed files (staged)" git diff --staged --name-only
    emit_section "Untracked files" git ls-files --others --exclude-standard
    DID_ANY=1
fi

if [[ "$MODE" == log ]] || { [[ "$MODE" == auto ]] && { matches_word "$ARGS" 'log|history' || matches_substr "$ARGS" '履歴'; }; }; then
    emit_section "git log --oneline -20" git log --oneline -20
    DID_ANY=1
fi

# Explicit, repeated --file arguments preserve spaces.
for path in "${FILES[@]}"; do
    if [[ ! -f "$path" ]]; then
        echo "(file not found: $path)" >&2
        exit 1
    fi
    emit_file "$path"
    DID_ANY=1
done

if [[ $DID_ANY -eq 0 ]]; then
    echo "(no context selected; use --mode or --file)" >&2
    exit 3
fi

exit 0
