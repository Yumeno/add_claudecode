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

`claude-implement`はメディア添付に対応していない。画像やPDFを参照する必要がある
場合も、仕様ファイルへのBase64埋め込みや一時的なリポジトリ内コピーで回避しない。
メディアを使ったセカンドオピニオンは`ask-claude-with-context`で別途実行する。

保護対象ファイル(`.env` / `.env.*` / `*.pem` / `*.key` / `*.p12` / `*.pfx` /
`.git/config` / `.git/hooks/*`)の編集が必要な場合、実行前にユーザーの明示承認を得たうえで
`claude-implement`の`-Allow` / `--allow`にexact pathを渡す。承認対象だけを列挙し、
`*`のような過大パターンは使わない。`-Allow`はそのまま`claude-verify check`へ委譲される。

- PowerShell: `claude-implement.ps1 -SpecFile ... -Repo ... -Allow ".env.example"`
  (複数指定はcomma区切りの1引数: `-Allow ".env.example,.env.sample"`。
  `powershell -File`のCLI境界では配列syntaxが1要素にfoldされるため、内部でcomma
  splitして正規化する。値自身にcommaを含むパスは非対応)
- bash: `claude-implement.sh --spec-file ... --repo ... --allow .env.example`
  (複数指定は`--allow`を繰り返す)

承認対象以外の保護対象が変更された場合は`[CLAUDE_VERIFY_VIOLATION]`として検出される。

以下の条件では`claude-verify`のsnapshotがfail closedで拒否され、`claude-implement`も
中断する: (a) リポジトリがsubmoduleを含む(`.gitmodules`または`.git/modules/*`の
存在)、(b) リポジトリ内にリポジトリ外を指すsymlink / reparse pointが存在する。

## 非ASCII path (日本語など) の扱い

Windows で `powershell -File claude-implement.ps1 -Repo <非ASCIIパス>` を
bash 等の UTF-8 shell 経由で呼ぶと、CLI argv 境界で path が CP932 として
mangling される。回避策として `-RepoFile <ascii名の一時ファイル>` を使う:

- 呼び出し側は「repo path の絶対パス文字列をUTF-8で書き込んだASCII名の一時ファイル」を作る
- そのASCIIファイルパスを `-RepoFile` に渡す
- claude-implement / claude-verify はUTF-8 strict decoderで読み、正しいUnicode文字列として扱う

```powershell
# 例: PowerShell 版
"C:\Users\ユーザー\プロジェクト" | Out-File -Encoding utf8NoBOM $env:TEMP\claude-repo.txt
powershell -File claude-implement.ps1 -SpecFile spec.txt -RepoFile "$env:TEMP\claude-repo.txt"
```

```bash
# 例: bash 版
printf '%s' "/path/to/日本語/repo" > /tmp/claude-repo.txt
bash claude-implement.sh --spec-file spec.txt --repo-file /tmp/claude-repo.txt
```

`-Repo` と `-RepoFile` は排他。ASCII パスなら `-Repo` を使えばよい。
