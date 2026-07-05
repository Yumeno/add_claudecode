---
name: set-claude-model
description: claude-wrapperのデフォルトモデルを保存・確認する。引数なしで現状表示、モデル名を渡すと保存する。
---

# set-claude-model

共通wrapperと同じディレクトリの `claude-wrapper.conf` を管理する。

## 手順

- 引数なし:
  - PowerShell: `claude-wrapper.ps1 -ShowModel`
  - bash: `claude-wrapper.sh --show-model`
- モデル名あり:
  - PowerShell: `claude-wrapper.ps1 -SetModel "<model>"`
  - bash: `claude-wrapper.sh --set-model "<model>"`

wrapperはCLI引数、`CLAUDE_WRAPPER_MODEL`、設定ファイル、Claude Code既定の順で解決する。
`[CLAUDE_WRAPPER_ERROR]` が出た場合は保存成功として扱わない。
