#!/usr/bin/env bash
set -euo pipefail
verify=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/claude-verify.sh
root=$(mktemp -d)
repo="$root/repo"
snap="$root/snapshot"
hook_snap="$root/hook-snapshot"
external_snap="$root/external-snapshot"
submodule_snap="$root/submodule-snapshot"
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

hook="$repo/.git/hooks/test-hook"
if ln -s "$repo/normal.txt" "$hook" 2>/dev/null && [[ -L "$hook" ]]; then
  "$verify" snapshot --repo "$repo" --snapshot "$hook_snap" >/dev/null
  rm -- "$hook"
  set +e
  out=$("$verify" check --repo "$repo" --snapshot "$hook_snap" 2>&1); rc=$?
  set -e
  [[ $rc == 1 && $out == *"[CLAUDE_VERIFY_VIOLATION]"*".git/hooks/test-hook"* ]]
else
  rm -f -- "$hook"
  printf 'SKIP: symlink hook test (real symlink creation unavailable)\n'
fi

outside="$root/outside.txt"
printf outside > "$outside"
if ln -s "$outside" "$repo/external-link" 2>/dev/null && [[ -L "$repo/external-link" ]]; then
  set +e
  out=$("$verify" snapshot --repo "$repo" --snapshot "$external_snap" 2>&1); rc=$?
  set -e
  [[ $rc == 2 && $out == *"[CLAUDE_VERIFY_ERROR] symlink escapes repository: external-link ->"* ]]
  rm -- "$repo/external-link"
else
  rm -f -- "$repo/external-link"
  printf 'SKIP: escaping symlink test (real symlink creation unavailable)\n'
fi

printf '[submodule "sample"]\n\tpath = sample\n\turl = local\n' > "$repo/.gitmodules"
set +e
out=$("$verify" snapshot --repo "$repo" --snapshot "$submodule_snap" 2>&1); rc=$?
set -e
[[ $rc == 2 && $out == *"[CLAUDE_VERIFY_ERROR] repository contains submodules; not supported by claude-verify"* ]]

rm -- "$repo/.gitmodules"
repo_file="$root/repo-file.txt"
printf '%s' "$repo" > "$repo_file"
repofile_snap="$root/repofile-snapshot"
out=$("$verify" snapshot --repo-file "$repo_file" --snapshot "$repofile_snap")
[[ $out == *"[CLAUDE_VERIFY_OK] snapshot created"* ]]
set +e
out=$("$verify" snapshot --repo "$repo" --repo-file "$repo_file" --snapshot "$repofile_snap" 2>&1); rc=$?
set -e
[[ $rc == 2 && $out == *"mutually exclusive"* ]]
set +e
out=$("$verify" snapshot --snapshot "$repofile_snap" 2>&1); rc=$?
set -e
[[ $rc == 2 && $out == *"required"* ]]
set +e
out=$("$verify" snapshot --repo-file "$root/does-not-exist.txt" --snapshot "$repofile_snap" 2>&1); rc=$?
set -e
[[ $rc == 2 && $out == *"not found"* ]]
: > "$root/empty.txt"
set +e
out=$("$verify" snapshot --repo-file "$root/empty.txt" --snapshot "$repofile_snap" 2>&1); rc=$?
set -e
[[ $rc == 2 && $out == *"empty"* ]]
printf 'test-verify.sh: OK\n'
