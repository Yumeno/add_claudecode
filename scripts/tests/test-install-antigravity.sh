#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "$script_dir/../.." && pwd)"
target="$(mktemp -d)"
trap 'rm -rf -- "$target"' EXIT
mkdir -p "$target/skills/unrelated" "$target/skills/ask-claude"
touch "$target/skills/ask-claude/stale"
bash "$root/scripts/install-for-antigravity.sh" "$target" "$target/scripts" >/dev/null
for source in "$root"/.agents/skills/*; do
    [[ -d "$source" ]] || continue
    [[ -f "$target/skills/$(basename -- "$source")/SKILL.md" ]] || exit 1
done
[[ ! -e "$target/skills/ask-claude/stale" ]]
[[ -d "$target/skills/unrelated" ]]
[[ -f "$target/scripts/claude-wrapper.sh" ]]
printf 'PASS: Antigravity CLI installer\n'
