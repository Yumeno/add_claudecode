---
name: set-claude-model
description: claude-wrapperのデフォルトモデルを保存・確認する。引数なしで現状表示、モデル名を渡すと保存する。
---

# set-claude-model

このSkillに同梱された `scripts/claude-wrapper.*` を呼び、配置に応じた共通
`claude-wrapper.conf` を管理する。Skill同梱wrapperから実行した場合でも設定は
Skillごとに分散させず、repo配置ならrepo直下 `scripts/claude-wrapper.conf`、
user/global配置なら `~/.agents/add_claudecode/claude-wrapper.conf` を使う。

## 手順

- 引数なし:
  - PowerShell: `$SKILL_DIR\scripts\claude-wrapper.ps1 -ShowModel`
  - bash: `$SKILL_DIR/scripts/claude-wrapper.sh --show-model`
- モデル名あり:
  - PowerShell: `$SKILL_DIR\scripts\claude-wrapper.ps1 -SetModel "<model>"`
  - bash: `$SKILL_DIR/scripts/claude-wrapper.sh --set-model "<model>"`

wrapperはCLI引数、`CLAUDE_WRAPPER_MODEL`、設定ファイル、Claude Code既定の順で解決する。
`[CLAUDE_WRAPPER_ERROR]` が出た場合は保存成功として扱わない。
