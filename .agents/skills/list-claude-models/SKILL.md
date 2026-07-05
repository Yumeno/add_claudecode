---
name: list-claude-models
description: Claude Codeのモデル指定方法とclaude-wrapperの現在のモデル設定を確認する。
---

# list-claude-models

Claude Code CLIには現時点で、契約上利用可能なモデルを列挙する公式コマンドがない。
存在しない一覧を推測せず、次を提示する。

1. wrapperを `-ShowModel` / `--show-model` で呼び、現在の解決モデルを表示する。
2. `claude --help` の `--model` 説明を確認する。
3. Claude Codeはalias（例: `opus`, `sonnet`）またはfull model nameを受け付けることを説明する。
4. 実際の利用可否は認証方式、契約、提供状況に依存すると明記する。

モデル設定を変更する場合は `set-claude-model` を使う。
