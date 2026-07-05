#!/usr/bin/env bash
set -euo pipefail
verify=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/claude-verify.sh
root=$(mktemp -d)
repo="$root/repo"
snap="$root/snapshot"
trap 'rm -rf "$root"' EXIT
mkdir "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email test@example.invalid
git -C "$repo" config user.name Test
printf base > "$repo/normal.txt"
git -C "$repo" add normal.txt
git -C "$repo" commit -qm initial

out=$("$verify" snapshot --repo "$repo" --snapshot "$snap")
[[ $out == *"[CLAUDE_VERIFY_OK]"* ]]
out=$("$verify" check --repo "$repo" --snapshot "$snap")
[[ $out == *"[CLAUDE_VERIFY_OK]"* ]]
printf changed > "$repo/normal.txt"
out=$("$verify" check --repo "$repo" --snapshot "$snap")
[[ $out == *"[CLAUDE_VERIFY_OK] working tree status changed"* ]]
printf secret > "$repo/.env"
set +e
out=$("$verify" check --repo "$repo" --snapshot "$snap" 2>&1); rc=$?
set -e
[[ $rc == 1 && $out == *"[CLAUDE_VERIFY_VIOLATION]"*".env"* ]]
out=$("$verify" check --repo "$repo" --snapshot "$snap" --allow .env)
[[ $out == *"[CLAUDE_VERIFY_ALLOWED] protected change: .env"* ]]
set +e
out=$("$verify" check --repo "$repo" --snapshot "$snap" --allow ../.env 2>&1); rc=$?
set -e
[[ $rc == 2 && $out == *"[CLAUDE_VERIFY_ERROR]"* ]]
git -C "$repo" add normal.txt
git -C "$repo" commit -qm changed
set +e
out=$("$verify" check --repo "$repo" --snapshot "$snap" --allow .env 2>&1); rc=$?
set -e
[[ $rc == 1 && $out == *"[CLAUDE_VERIFY_VIOLATION] head changed"* ]]
printf 'test-verify.sh: OK\n'
