---
name: ask-claude-with-context
description: Get a second opinion from Claude Code with file content, git diff, or git log attached as context. Use for code review, security audit, design review, or any question where Claude needs to see specific code or recent changes. Triggers on keywords like "review", "レビュー", "diff", "security", "セキュリティ", "監査", "audit", or when a file path is mentioned alongside a question.
---

# ask-claude-with-context — コンテキスト付きで Claude Code にセカンドオピニオンを求める

ファイル内容や `git diff`、画像・PDFを添えて Claude Code に
質問・レビュー・監査を依頼します。添付は複数指定できます。

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
         --context-file "$TMPCTX" \
         --attachment "/absolute/path/image-1.png" \
         --attachment "/absolute/path/document.pdf"
     ```
   - PowerShell:
     ```powershell
      powershell -ExecutionPolicy Bypass -NoProfile -File "<絶対パス>\claude-wrapper.ps1" `
         -Prompt "<質問本文>" -ContextFile $tmpCtx `
         -AttachmentList "C:\absolute\attachments.txt"
     ```

   添付がない場合はattachmentオプションを省略する。複数指定は、bashでは
   `--attachment`を繰り返す。PowerShellで複数指定する場合は、改行区切りの絶対パスを
   格納したUTF-8テキストファイルを`-AttachmentList`で指定する。bashでも同じ形式を
   `--attachment-list`で指定できる。PowerShellの`-Attachment`は単一media用とする。

   質問本文に日本語などの非ASCII文字を含む場合、Windowsで `powershell -File`
   のCLI argv境界がCP932でmanglingする可能性がある。回避策として `-Prompt` の代わりに
   `-PromptFile` / `--prompt-file` にUTF-8で質問文を書いた一時ファイル(ASCII名)を渡す:
   ```powershell
   $tmpPrompt = Join-Path $env:TEMP ("claude_prompt_{0}.txt" -f (Get-Random))
   [IO.File]::WriteAllText($tmpPrompt, "<質問本文>", (New-Object Text.UTF8Encoding($false)))
   powershell -ExecutionPolicy Bypass -NoProfile -File "<絶対パス>\claude-wrapper.ps1" `
       -PromptFile $tmpPrompt -ContextFile $tmpCtx
   ```

   wrapperは添付ファイルを隔離された一時ディレクトリへコピーし、その
   ディレクトリだけをClaude Codeへ明示的に公開する。元ファイルの親ディレクトリを
   公開せず、添付時だけClaude Codeの`Read` toolを有効にする。質問本文には
   staging後のファイル名が自動的に追記されるため、呼び出し側でパスを埋め込まない。

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
- 添付した画像・PDFの内容もAnthropicへ送信される。ユーザーが明示していない
  ファイルを推測で追加せず、送信対象のファイル一覧を回答に明記する。
- 添付は通常のテキストコンテキストへBase64変換して埋め込まず、必ずwrapperの
  attachmentオプションを使う。
- 初期対応はClaude Codeの`Read` toolが対応する画像とPDFに限定する。音声・動画は
  対応外であり、別形式として偽装したり無断変換して再送したりしない。
- wrapperはMIME、ファイル数、合計byte数、サポート状態を送信前に表示する。正常な
  大容量入力を黙って切り捨てず、過大と判断した場合は実行前にユーザーへ確認する。
- 100KB 相当の文字数を超えると警告が出る。大きすぎる場合は関連部分のみ抜粋する。
- スペースを含むパスは `-Path` / `--file` で明示する。互換用の引数全文からの自動検出は空白区切りのため、明示指定を優先する。

## 前提条件

- Claude Code CLI がインストール済み: `npm install -g @anthropic-ai/claude-code`
- 認証済み: `claude login` または `ANTHROPIC_API_KEY`
- `git` コマンドが PATH にある（diff/log 系のコンテキストを使う場合）
