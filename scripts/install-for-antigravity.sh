#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "$script_dir/.." && pwd)"
destination_root="${1:-${HOME:?HOME is not set}/.gemini/antigravity-cli}"
scripts_root="${2:-$(dirname -- "$destination_root")/scripts}"
mkdir -p "$destination_root/skills" "$scripts_root"
stage=$(mktemp -d "$destination_root/.add-claudecode-stage.XXXXXX")
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT
mkdir -p "$stage/skills" "$stage/scripts"
for source in "$root"/.agents/skills/*; do
    [[ -d "$source" ]] || continue
    name="$(basename -- "$source")"
    cp -R -- "$source" "$stage/skills/$name"
done
for source in "$root"/scripts/claude-*; do
    [[ -f "$source" ]] || continue
    case "$source" in *.ps1|*.sh) cp -- "$source" "$stage/scripts/" ;; esac
done
cp -- "$stage"/scripts/* "$scripts_root/"
for source in "$stage"/skills/*; do
    [[ -d "$source" ]] || continue
    name="$(basename -- "$source")"
    rm -rf -- "$destination_root/skills/$name"
    mv -- "$source" "$destination_root/skills/$name"
done
printf 'Antigravity CLI用Skillをインストールしました: %s\n' "$destination_root"
