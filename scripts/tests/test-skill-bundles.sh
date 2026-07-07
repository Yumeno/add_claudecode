#!/usr/bin/env bash
set -euo pipefail
root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
check() {
  local skill=$1 file=$2
  local bundled="$root/.agents/skills/$skill/scripts/$file"
  [[ -f "$bundled" ]] || { printf 'missing bundled helper: %s/scripts/%s\n' "$skill" "$file"; exit 1; }
  if [[ "$file" == claude-* ]]; then
    cmp -s "$root/scripts/$file" "$bundled" || { printf 'helper content mismatch: %s/scripts/%s\n' "$skill" "$file"; exit 1; }
  fi
}
check ask-claude claude-wrapper.ps1
check ask-claude claude-wrapper.sh
check ask-claude-with-context claude-wrapper.ps1
check ask-claude-with-context claude-wrapper.sh
check ask-claude-with-context collect-context.ps1
check ask-claude-with-context collect-context.sh
check set-claude-model claude-wrapper.ps1
check set-claude-model claude-wrapper.sh
check list-claude-models claude-wrapper.ps1
check list-claude-models claude-wrapper.sh
check claude-implement claude-implement.ps1
check claude-implement claude-implement.sh
check claude-implement claude-verify.ps1
check claude-implement claude-verify.sh
printf 'PASS: Skill bundled helpers\n'
