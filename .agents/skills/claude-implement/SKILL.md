---
name: claude-implement
description: Claude Codeを実装担当として使い、cleanなGitリポジトリを最小権限で編集させ、独立検収する。
---

# claude-implement

このスキルは外部LLMへ書き込み権限を与える。質問系スキルとは安全境界が異なる。

## 必須手順

1. 対象がGit working treeで、`git status --porcelain=v1 --untracked-files=all` が空であることを確認する。
2. `claude-verify` のsnapshotを取得し、出力されたsnapshot pathを記録する。失敗時は中断する。
3. ユーザーのタスクを仕様ファイルへ保存する。認証情報や不要なファイル内容を含めない。
4. プロジェクト配置ではリポジトリルートのscripts、ユーザー配置ではCodexは
   `~/.agents/scripts/`、Geminiは `~/.gemini/scripts/` の
   `claude-implement.ps1` / `.sh` を絶対パスで呼ぶ。
5. `[CLAUDE_IMPLEMENT_ERROR]` が出た場合は失敗として扱う。
6. 成否にかかわらずsnapshotを使って `claude-verify` のcheckを実行する。
7. `[CLAUDE_VERIFY_VIOLATION]` を最優先で報告する。
8. Claudeの変更ファイル報告とGit status/diffの実態を照合する。
9. ロールバック候補は提示だけ行い、破壊的操作を自動実行しない。

保護対象ファイルの編集が必要な場合、実行前にユーザーの明示承認を得る。承認対象だけを
verifyのallowへ渡し、過大なglobは使わない。
