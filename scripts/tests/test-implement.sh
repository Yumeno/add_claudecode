#!/usr/bin/env bash
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TESTDIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/claude_impl_test_XXXXXX")
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name Test
printf base > "$REPO/base.txt"
git -C "$REPO" add base.txt
git -C "$REPO" commit -qm base
printf 'READMEを作成する' > "$TMP/spec.txt"

mkdir -p "$TMP/bin"
cp "$TESTDIR/fake-claude.sh" "$TMP/bin/claude"
chmod +x "$TMP/bin/claude"
export PATH="$TMP/bin:$PATH"
export FAKE_ARGS="$TMP/args.txt" FAKE_STDIN="$TMP/stdin.txt" FAKE_CWD="$TMP/cwd.txt" FAKE_MODE=success
bash "$ROOT/claude-implement.sh" --spec-file "$TMP/spec.txt" --repo "$REPO" >/dev/null
grep -qx -- '--safe-mode' "$FAKE_ARGS"
grep -qx -- 'dontAsk' "$FAKE_ARGS"
grep -q 'Mandatory safety constraints' "$FAKE_STDIN"
printf dirty > "$REPO/dirty.txt"
if bash "$ROOT/claude-implement.sh" --spec-file "$TMP/spec.txt" --repo "$REPO" >/dev/null 2>&1; then
  echo 'dirty tree was accepted' >&2
  exit 1
fi
echo 'test-implement.sh: OK'
