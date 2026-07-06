#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "$script_dir/../.." && pwd)"
target="$(mktemp -d)"
scripts_target="$(mktemp -d)"
trap 'rm -rf -- "$target" "$scripts_target"' EXIT
mkdir -p "$target/skills/unrelated" "$target/skills/ask-claude"
touch "$target/skills/ask-claude/stale"
bash "$root/scripts/install-for-antigravity.sh" "$target" "$scripts_target" >/dev/null
for source in "$root"/.agents/skills/*; do
    [[ -d "$source" ]] || continue
    [[ -f "$target/skills/$(basename -- "$source")/SKILL.md" ]] || exit 1
done
[[ ! -e "$target/skills/ask-claude/stale" ]]
[[ -d "$target/skills/unrelated" ]]
[[ -f "$scripts_target/claude-wrapper.sh" ]]
[[ ! -e "$target/scripts/claude-wrapper.sh" ]]
printf 'PASS: Antigravity CLI installer\n'
