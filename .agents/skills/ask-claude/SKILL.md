---
name: ask-claude
description: Get a second opinion from Claude Code (Anthropic's `claude` CLI) on a design decision, bug investigation, or programming question. Use when the user wants a cross-check from a different model, says "ask Claude" / "Claude にも聞いて" / "セカンドオピニオン", or directly invokes this skill by name. Does NOT include file content or diffs — use ask-claude-with-context for code review or audit tasks.
---

# ask-claude — Claude Code にセカンドオピニオンを求める

ユーザーの質問をそのまま Claude Code (`claude -p`) に投げて、回答を取得し提示します。

## 手順

1. **ラッパーの絶対パスを特定する。** プロジェクト配置ではリポジトリルートの
   `scripts/claude-wrapper.*`、ユーザー配置ではCodexは
   `~/.agents/scripts/claude-wrapper.*`、Geminiは
   `~/.gemini/scripts/claude-wrapper.*` を使う。

2. **OS を判定し、`$SKILL_DIR/scripts/` 以下のラッパーを呼び出す。** プロンプトは stdin で渡されるためコマンドライン長制限を受けない。

   - Linux / macOS / WSL:
     ```bash
     bash "<絶対パス>/claude-wrapper.sh" --prompt "<ユーザーの質問>"
     ```
   - Windows (PowerShell):
     ```powershell
     powershell -ExecutionPolicy Bypass -NoProfile -File "<絶対パス>\claude-wrapper.ps1" -Prompt "<ユーザーの質問>"
     ```

   主なオプション:
   - `--prompt` / `-Prompt` — （必須）質問本文
   - `--model` / `-Model` — 例: `claude-opus-4-7`、`claude-sonnet-4-6`
   - `--timeout` / `-Timeout` — タイムアウト秒（デフォルト 180）

3. 出力行が `[CLAUDE_WRAPPER_ERROR]` で始まる場合はClaudeの回答として扱わず、
   wrapperの失敗として提示する。成功時だけ以下の形式で提示する:

   ```
   ## Claude Code のセカンドオピニオン

   > <ユーザーの質問>

   <Claude Code の回答>

   ---
   *via Claude Code CLI*
   ```

4. 必要に応じて、自分自身の見解と比較したコメントを添える。

## 前提条件

- Claude Code CLI が PATH にある: `npm install -g @anthropic-ai/claude-code`
- 認証済み: `claude login` または `ANTHROPIC_API_KEY` 環境変数

## エラー対応

- ラッパーが exit 2 を返した → タイムアウト。`--timeout 300` 等で延長して再試行を提案。
- ラッパーが exit 1 + 「empty output」を返した → `claude login` が必要、または認証切れの可能性をユーザーに伝える。
- `claude: command not found` → インストール手順を案内。
