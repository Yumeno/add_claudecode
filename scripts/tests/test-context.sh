#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COLLECTOR="$ROOT/.agents/skills/ask-claude-with-context/scripts/collect-context.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
FILE="$TMP_DIR/file with spaces.txt"
printf '%s' 'space path content' > "$FILE"
OUT="$(bash "$COLLECTOR" --mode none --file "$FILE")"
[[ "$OUT" == *"space path content"* ]]
set +e
bash "$COLLECTOR" --mode none >/dev/null 2>&1
STATUS=$?
set -e
[[ $STATUS -eq 3 ]]
printf '%s\n' "PASS: context collector (bash)"
