---
name: ask-claude-with-context
description: Get a second opinion from Claude Code with file content, git diff, or git log attached as context. Use for code review, security audit, design review, or any question where Claude needs to see specific code or recent changes. Triggers on keywords like "review", "レビュー", "diff", "security", "セキュリティ", "監査", "audit", or when a file path is mentioned alongside a question.
---

# ask-claude-with-context — コンテキスト付きで Claude Code にセカンドオピニオンを求める

ファイル内容や `git diff` などを添えて Claude Code に質問・レビュー・監査を依頼します。

## キーワードと収集されるコンテキスト

| キーワード | 添えるコンテキスト |
|---|---|
| `review`, `レビュー`, `diff` | `git diff` + `git diff --staged` |
| `security`, `セキュリティ`, `監査`, `audit` | `git diff` + 変更ファイル一覧 |
| `log`, `履歴`, `history` | `git log --oneline -20` |
| 既存ファイルへのパス | そのファイルの内容 |

## 手順

1. **このスキルディレクトリの絶対パスを特定する。** ランタイムが提供する skill のディレクトリ（この `SKILL.md` が置かれている場所）を `$SKILL_DIR` として扱う。`scripts/` はそこに同梱されている。
   作業ディレクトリ（cwd）が skill ディレクトリと一致する保証はないため、必ず**絶対パス**でスクリプトを呼ぶ。

2. **コンテキストを収集する。** スキル同梱のヘルパースクリプトをユーザーの引数で呼び出し、stdout を一時ファイルに保存する。

   - Linux / macOS / WSL:
     ```bash
     TMPCTX=$(mktemp "${TMPDIR:-/tmp}/claude_ctx_XXXXXX.txt")
     bash "$SKILL_DIR/scripts/collect-context.sh" "<ユーザーの引数全文>" > "$TMPCTX"
     ```
   - Windows (PowerShell):
     ```powershell
     $tmpCtx = Join-Path $env:TEMP ("claude_ctx_{0}.txt" -f (Get-Random))
     powershell -ExecutionPolicy Bypass -NoProfile -File "$SKILL_DIR\scripts\collect-context.ps1" "<ユーザーの引数全文>" |
         Out-File -FilePath $tmpCtx -Encoding UTF8
     ```

   スペースを含むファイルパスは自動抽出に頼らず明示指定する:
   - PowerShell: `collect-context.ps1 -Mode none -Path "C:\My Project\foo.ts"`
   - bash: `collect-context.sh --mode none --file "/path/My Project/foo.ts"`
   review/security/logも `-Mode` / `--mode` で明示できる。

   ヘルパーが何も検出しなかった場合 (キーワード/ファイルパスなし)、ユーザーに何のコンテキストを添えたいか確認する、または明示的にファイルパスを聞く。

3. **共通ラッパーを呼び出す。** プロジェクト配置ではリポジトリルートの
   `scripts/claude-wrapper.*`、ユーザー配置ではCodexは `~/.agents/scripts/`、
   Geminiは `~/.gemini/scripts/` のwrapperを絶対パスで使う。

   - bash:
     ```bash
     bash "<絶対パス>/claude-wrapper.sh" \
         --prompt "<質問本文>" \
         --context-file "$TMPCTX"
     ```
   - PowerShell:
     ```powershell
     powershell -ExecutionPolicy Bypass -NoProfile -File "<絶対パス>\claude-wrapper.ps1" `
         -Prompt "<質問本文>" -ContextFile $tmpCtx
     ```

4. **一時ファイルを削除する:**
   ```bash
   rm -f "$TMPCTX"
   ```
   ```powershell
   Remove-Item $tmpCtx -Force -ErrorAction SilentlyContinue
   ```

5. 出力行が `[CLAUDE_WRAPPER_ERROR]` で始まる場合はClaudeの回答として扱わず、
   wrapperの失敗として提示する。成功時だけ以下の形式で提示する:

   ```
   ## Claude Code のセカンドオピニオン（コンテキスト付き）

   > 質問: <ユーザーの質問>
   > コンテキスト: <添えたものの要約 (例: "git diff", "src/main.ts", ...)>

   <Claude Code の回答>

   ---
   *via Claude Code CLI*
   ```

6. 必要に応じて、自分自身の見解と比較したコメントを添える。

## 注意

- コンテキストはすべて Anthropic に送信される。秘匿情報（資格情報、個人情報、未公開コード）が含まれていないか送信前に確認する。
- 100KB 相当の文字数を超えると警告が出る。大きすぎる場合は関連部分のみ抜粋する。
- スペースを含むパスは `-Path` / `--file` で明示する。互換用の引数全文からの自動検出は空白区切りのため、明示指定を優先する。

## 前提条件

- Claude Code CLI がインストール済み: `npm install -g @anthropic-ai/claude-code`
- 認証済み: `claude login` または `ANTHROPIC_API_KEY`
- `git` コマンドが PATH にある（diff/log 系のコンテキストを使う場合）
