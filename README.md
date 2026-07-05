# add_claudecode

OpenAI Codex CLI および Google Gemini CLI から **Claude Code** にセカンドオピニオンを求めるための **Agent Skills** 集。

[`Yumeno/add_codexcli`](https://github.com/Yumeno/add_codexcli) の逆方向版です。あちらは Claude Code → Codex、こちらは Codex / Gemini → Claude Code。

## 概要

`SKILL.md` ベースの Agent Skills 形式（[agentskills.io](https://agentskills.io) 標準）で実装。Codex CLI は公式 docs で `.agents/skills/` を認識することが確認できており、Gemini CLI も Agent Skills および `.agents/skills` alias 対応版で利用可能です（**1 セットのスキルで両方のツールから利用できる**ことを意図しています。Gemini 側の `.agents` alias 対応はバージョン依存があるため、認識されない場合は `~/.gemini/skills/` にも配置してください）。

提供スキル:

| スキル | 用途 |
|---|---|
| `ask-claude` | コンテキストなしで Claude Code に質問する |
| `ask-claude-with-context` | ファイル / `git diff` / `git log` / 複数の画像・PDFを添えて質問・レビュー・監査 |
| `set-claude-model` | wrapperの既定モデルを保存・確認 |
| `list-claude-models` | モデル指定方法と現在のwrapper設定を確認 |
| `claude-implement` | Claude Codeへ実装を委任し、Gitの実態を独立検収 |

質問系はClaude Codeを隔離された一時ディレクトリから、ツールなし・セッション非永続で実行します。
`claude-implement` だけは書き込みを伴う別カテゴリで、clean tree、実行前snapshot、最小ツール、
実行後checkを必須とします。

## 前提条件

- [Claude Code CLI](https://docs.claude.com/en/docs/claude-code) がインストール済み・認証済み
  ```bash
  npm install -g @anthropic-ai/claude-code
  claude login   # または環境変数 ANTHROPIC_API_KEY を設定
  ```
- 質問元として以下のいずれか:
  - [Codex CLI](https://github.com/openai/codex)（Skills 対応バージョン）
  - [Gemini CLI](https://github.com/google-gemini/gemini-cli)（Skills 対応バージョン）
  - [Antigravity CLI](https://antigravity.google/docs/cli-overview)（検証済み: `agy 1.0.16`）

## クイックスタート

```powershell
git clone https://github.com/Yumeno/add_claudecode.git
Set-Location add_claudecode

# Codex + Geminiへインストール
foreach ($base in @("$env:USERPROFILE\.agents", "$env:USERPROFILE\.gemini")) {
    New-Item -ItemType Directory -Force "$base\skills", "$base\scripts" | Out-Null
    Get-ChildItem .agents\skills -Directory | Copy-Item -Destination "$base\skills" -Recurse -Force
    Copy-Item scripts\claude-* "$base\scripts\" -Force
}

# Antigravity CLIへインストール
powershell -ExecutionPolicy Bypass -NoProfile -File scripts\install-for-antigravity.ps1
```

インストール後、新しいセッションを開始して次のように呼び出します。

```text
# Codex
$ask-claude この設計の弱点を指摘して

# Antigravity CLI
/ask-claude この設計の弱点を指摘して
```

## ファイル構成

```
add_claudecode/
├── README.md
├── LICENSE
└── .agents/
    └── skills/
        ├── ask-claude/
        │   └── SKILL.md
        ├── ask-claude-with-context/
            ├── SKILL.md
            └── scripts/
                ├── collect-context.sh
                └── collect-context.ps1
        ├── set-claude-model/SKILL.md
        ├── list-claude-models/SKILL.md
        └── claude-implement/SKILL.md
└── scripts/
    ├── claude-wrapper.ps1 / .sh
    ├── claude-implement.ps1 / .sh
    ├── claude-verify.ps1 / .sh
    └── tests/
```

## インストール

### ユーザー全体（推奨）

`~/.agents/skills/` は Codex CLI のユーザースキルディレクトリです。Gemini CLI は `~/.gemini/skills/` を一次扱いし、`~/.agents/skills/` は alias として扱う実装になっているため、両方に置くのが確実です。

**Linux / macOS / WSL:**
```bash
mkdir -p ~/.agents/skills ~/.agents/scripts ~/.gemini/skills ~/.gemini/scripts
for s in ask-claude ask-claude-with-context set-claude-model list-claude-models claude-implement; do
    cp -r ".agents/skills/$s" ~/.agents/skills/
    cp -r ".agents/skills/$s" ~/.gemini/skills/
    chmod +x ~/.agents/skills/$s/scripts/*.sh ~/.gemini/skills/$s/scripts/*.sh 2>/dev/null || true
done
cp scripts/claude-* ~/.agents/scripts/
cp scripts/claude-* ~/.gemini/scripts/
chmod +x ~/.agents/scripts/*.sh ~/.gemini/scripts/*.sh
```

**Windows (PowerShell):**
```powershell
foreach ($base in @("$env:USERPROFILE\.agents\skills", "$env:USERPROFILE\.gemini\skills")) {
    New-Item -ItemType Directory -Force -Path $base | Out-Null
    Get-ChildItem .agents\skills -Directory | Copy-Item -Destination $base -Recurse -Force
}
foreach ($base in @("$env:USERPROFILE\.agents", "$env:USERPROFILE\.gemini")) {
    New-Item -ItemType Directory -Force "$base\scripts" | Out-Null
    Copy-Item scripts\claude-* "$base\scripts\" -Force
}
```

Codex CLI のみ使う、または Gemini CLI が `.agents` alias を認識する版なら `~/.agents/skills/` だけでも動きます。

### プロジェクト内のみ

リポジトリ直下の `.agents/skills/` に置くと、そのプロジェクトを Codex / Gemini で開いたときだけ有効になります。このリポジトリをそのままクローンして使う場合はインストール不要です。

### Antigravity CLI

Antigravity CLI 1.0.16の現行公式仕様では、workspace Skillは `.agents/skills/`、
global Skillは `~/.gemini/antigravity-cli/skills/` に配置します。workspace配置は
Codexと共通です。専用installerはglobal SkillをこのAntigravity CLI専用領域へ、
共通helperを `~/.gemini/scripts/` へコピーします。
詳細は[Antigravity CLI: Plugins & skills](https://antigravity.google/docs/cli/plugins)
および[Gemini CLIからのmigration](https://antigravity.google/docs/gcli-migration)を参照してください。

```powershell
powershell -ExecutionPolicy Bypass -NoProfile -File scripts\install-for-antigravity.ps1
```

```bash
bash scripts/install-for-antigravity.sh
```

既存の同名Skillだけを置換し、他のSkillは保持します。全ファイルを一時領域へ
stagingしてから更新するため、容量不足などのcopy失敗で旧Skillを先に失いません。
1.0.8以降では会話切替時や `/add-dir` 後にcustom skillsが再探索されます。

更新時もリポジトリで`git pull`した後、同じinstallerを再実行します。

```powershell
git pull
powershell -ExecutionPolicy Bypass -NoProfile -File scripts\install-for-antigravity.ps1
```

installerが配置する場所:

| 内容 | 配置先 |
|---|---|
| 5つのSkill | `~/.gemini/antigravity-cli/skills/` |
| Claude wrapper/helper | `~/.gemini/scripts/` |

アンインストールする場合は、上記global skills配下の
`ask-claude`、`ask-claude-with-context`、`set-claude-model`、
`list-claude-models`、`claude-implement`だけを削除してください。
`~/.gemini/scripts/claude-*`はGemini CLIと共有しているため、Geminiからも利用している場合は残します。

古いAntigravity IDE向け資料には `.agent/skills/` や
`~/.gemini/antigravity/skills/` と書かれたものがありますが、Antigravity CLI
1.0.16では上記の `.agents/skills/` / `~/.gemini/antigravity-cli/skills/` を使います。

### 動作確認

- Gemini CLI: 起動して `/skills` または `/skills list` でスキル一覧に表示されることを確認。新規追加直後は `/skills reload` が必要な場合あり。
- Codex CLI: `/skills` でスキル一覧を表示。`$skill-name` でスキル名を入力補完できる。
- Antigravity CLI: 新しい会話を開始するかworkspaceを追加し、slash command候補にSkill名が表示されることを確認。

Antigravity CLI 1.0.16では、global pathへ置いた一時Skillをskillsのないディレクトリから
slash commandとして直接実行し、global discoveryを確認済みです。workspace discoveryは
公式対応ですが、headless `agy --print`による直接実行はこの環境でtimeoutしたため、
interactive TUIの候補表示で確認してください。

## 使い方

### ask-claude — シンプルな質問

ユーザーが自然言語で「Claude にも聞いて」「ask Claude」「セカンドオピニオン」などと頼むか、明示的にスキル名を指定すると発火します。

```
> このアーキテクチャはオーバーエンジニアリング？ Claude にも聞いて
> Rust のライフタイムについて簡単に説明して。ask-claude で
```

明示呼び出し:

| 呼び出し元 | 例 |
|---|---|
| Codex | `$ask-claude この設計を評価して` |
| Gemini | `ask-claudeを使ってこの設計を評価して` |
| Antigravity CLI | `/ask-claude この設計を評価して` |

### ask-claude-with-context — コンテキスト付き

「レビュー」「security」「監査」「diff」などのキーワード、またはファイルパスが質問に含まれていると発火します。

```
> このコミットをレビューして
> security check してほしい
> src/main.ts の型シグネチャはどう？
> log 最近のコミットを Claude に評価してもらって
> screenshot-before.png と screenshot-after.png のUI差分をレビューして
> design.pdf と mockup.webp を参照して実装方針を検討して
```

画像・PDFは複数指定できます。Claude Codeの`Read` toolに公式な対応記載がない
音声・動画は初期対応の対象外です。添付は隔離された一時ディレクトリへコピーされ、
元ファイルの親ディレクトリはClaude Codeへ公開されません。添付内容はAnthropicへ
送信されるため、送信前に対象ファイルと秘匿情報の有無を確認してください。
`claude-implement`は現時点でメディア添付に対応していません。

#### 複数メディアを指定する

PowerShellでは、絶対パスを1行1件で記載したUTF-8ファイルを作成します。

```powershell
$attachments = @(
    "C:\work\before.png"
    "C:\work\after.png"
    "C:\work\design.pdf"
)
[IO.File]::WriteAllLines(
    "C:\work\attachments.txt",
    $attachments,
    (New-Object Text.UTF8Encoding($false))
)

powershell -ExecutionPolicy Bypass -NoProfile `
    -File scripts\claude-wrapper.ps1 `
    -Prompt "1番目と2番目のUI差分を確認し、3番目の仕様と矛盾しないか評価して" `
    -AttachmentList "C:\work\attachments.txt"
```

bashでは`--attachment`を繰り返すか、同じ1行1件のリストを使います。

```bash
bash scripts/claude-wrapper.sh \
  --prompt "順番に比較して" \
  --attachment "/work/before.png" \
  --attachment "/work/after.png"

bash scripts/claude-wrapper.sh \
  --prompt "順番に比較して" \
  --attachment-list "/work/attachments.txt"
```

Skill経由では、対象ファイルを明示して
「この2枚をClaudeに比較して」のように依頼してください。送信順序を保持したまま
`ask-claude-with-context`がwrapperを呼び出します。

### キーワード自動マッピング

| キーワード | 添えるコンテキスト |
|---|---|
| `review`, `レビュー`, `diff` | `git diff` + `git diff --staged` |
| `security`, `セキュリティ`, `監査`, `audit` | `git diff` + 変更ファイル一覧 |
| `log`, `履歴`, `history` | `git log --oneline -20` |
| ファイルパス（既存のもの） | そのファイルの内容 |

## 直接呼び出し

スキルを介さずラッパー単体でも実行できます。

```bash
# bash
bash scripts/claude-wrapper.sh \
    --prompt "この2枚を比較して" --timeout 60 \
    --attachment "/absolute/path/before.png" \
    --attachment "/absolute/path/after.png"

# PowerShell
powershell -ExecutionPolicy Bypass -NoProfile `
    -File "scripts\claude-wrapper.ps1" `
    -Prompt "この2枚を比較して" -Timeout 60 `
    -AttachmentList "C:\absolute\attachments.txt"
```

オプション:

| bash | PowerShell | 説明 |
|---|---|---|
| `--prompt` | `-Prompt` | （必須）Claude に送る質問 |
| `--model` | `-Model` | モデル指定（例: `claude-opus-4-7`） |
| `--timeout` | `-Timeout` | タイムアウト秒（デフォルト 180） |
| `--workdir` | `-WorkDir` | claude を実行する作業ディレクトリ |
| `--context` | `-Context` | プロンプトの前に付加する文字列 |
| `--context-file` | `-ContextFile` | 上記をファイルから読み込む |
| `--attachment`（反復可） | `-Attachment`（単一） | 参照する画像またはPDF |
| `--attachment-list` | `-AttachmentList` | 添付の絶対パスを改行区切りで格納したUTF-8ファイル |

対応状態:

| 状態 | 形式 |
|---|---|
| `probe-verified` | PNG（複数画像の順序と実内容をClaude Code 2.1.200で確認） |
| `experimental` | JPEG、GIF、WebP、BMP、TIFF、SVG、PDF |
| `unsupported` | 音声、動画、未知のバイナリ |

拡張子ではなくmagic bytesで判定します。正常ワークロードを一律size capで切り捨てず、
送信前にファイル数と総byte数を表示します。

## 設計方針

- **Agent Skills 形式**: `SKILL.md` + `scripts/` の標準構造。Codex / Gemini 両対応。
- **CLI 経由**: Anthropic API を直接呼ばず `claude -p` を使う。認証・課金・モデル選択は Claude Code 側に委ねる。
- **stdin 経由でプロンプトを渡す**: コマンドライン長制限と引数解釈リスクを回避。
- **外部依存ゼロ**: Markdown / bash / PowerShell のみ。npm パッケージなし。
- **クロスプラットフォーム**: Windows PowerShell 5.1+ と bash の両方に対応。
- **失敗sentinel**: wrapper/helperの失敗をLLM回答と誤認しない。
- **課金上限**: 非対話呼び出しに `--max-budget-usd` を設定可能。
- **独立検収**: 実装委任ではClaudeの自己申告ではなくGit snapshot/checkで確認。

## モデル設定

解決順位は、wrapperの `-Model` / `--model`、環境変数 `CLAUDE_WRAPPER_MODEL`、
`scripts/claude-wrapper.conf`、Claude Code既定の順です。未指定時のモデル名は推測表示しません。

Claude Code CLIには現時点で契約上利用可能な全モデルの列挙コマンドがないため、
`list-claude-models` は現在設定とCLIの指定方法を表示します。実際の利用可否は認証・契約に依存します。

```text
# Codex
$set-claude-model sonnet
$list-claude-models

# Antigravity CLI
/set-claude-model sonnet
/list-claude-models
```

## Claudeへ実装を委任する

`claude-implement`は質問ではなく、Claude Codeへファイル編集を許可するSkillです。
開始時にGit working treeがcleanである必要があります。

```text
# Codex
$claude-implement READMEのインストール例を更新し、関連テストを実行して

# Antigravity CLI
/claude-implement READMEのインストール例を更新し、関連テストを実行して
```

実行前snapshotと実行後checkで、HEAD、branch、変更ファイル、`.env`や鍵などの
保護対象を検査します。commit、push、rollbackは自動実行しません。

## テスト

実Claude通信を必要としないunit test:

```powershell
powershell -ExecutionPolicy Bypass -NoProfile -File scripts\tests\test-wrapper.ps1
powershell -ExecutionPolicy Bypass -NoProfile -File scripts\tests\test-context.ps1
powershell -ExecutionPolicy Bypass -NoProfile -File scripts\tests\test-verify.ps1
powershell -ExecutionPolicy Bypass -NoProfile -File scripts\tests\test-implement.ps1
powershell -ExecutionPolicy Bypass -NoProfile -File scripts\tests\test-install-antigravity.ps1
```

bash版は対応する `.sh` を実行します。実Claudeを呼ぶE2Eは課金・レート制限の影響があるため、
unit testと分離し、必要時だけ代表ケースを1件実行してください。

## セキュリティ

- **送信先は Anthropic**: `ask-claude-with-context` ではファイル内容や `git diff` が Anthropic API に送信される。秘匿情報を含むリポジトリでの自動利用には注意。
- **メディア添付も外部送信**: 指定した画像・PDFもAnthropicへ送信される。wrapperは
  MIME、個数、合計byte数、サポート状態を送信前に表示し、元ファイルではなく
  隔離コピーだけをClaude Codeへ公開する。音声・動画は対応外。
- **stdin 渡し**: プロンプトはプロセスリスト（`ps`、Process Explorer）に表示されない。
- **PowerShell 版の `.cmd` 実行について**: `Process.Start(UseShellExecute=false)` で `claude.cmd` を起動するが、`.cmd` 内部では cmd.exe による解釈が行われる。プロンプトを引数ではなく stdin で渡すことでコマンド注入リスクを抑えているが、シェル解釈を完全に避けているわけではない点に注意。

## 既知の制約

- **自動パス検出の制約**: 互換用の引数全文からの検出は空白区切りです。スペース入りパスはPowerShellの `-Path`、bashの `--file` で明示してください。

## トラブルシューティング

### スキルが認識されない
- 配置場所が `~/.agents/skills/<name>/SKILL.md`（または Gemini なら `~/.gemini/skills/<name>/SKILL.md`）になっているか確認。
- Gemini: `/skills reload` または再起動。`/skills list` で表示確認。`.agents` alias を認識しないバージョンでは `~/.gemini/skills/` に置く。
- Codex: バージョンが Skills 対応のものか確認。`/skills` で一覧表示。
- Antigravity CLI: global配置が
  `~/.gemini/antigravity-cli/skills/<name>/SKILL.md`になっているか確認し、
  新しい会話を開始する。Antigravity 2.0 IDE向けの
  `~/.gemini/antigravity/skills/`と混同しない。
- `SKILL.md` の YAML frontmatter（`name`, `description`）に構文エラーがないか確認。

### `claude: command not found`
```bash
npm install -g @anthropic-ai/claude-code
```

### 認証エラー
```bash
claude login
```
または `ANTHROPIC_API_KEY="sk-ant-..."` を設定。

### タイムアウト
デフォルト 180 秒。`--timeout 300` または `-Timeout 300` で延長。

### bash 版でタイムアウトが効かない
bash 版は `timeout`（GNU coreutils）または `gtimeout` を使う。macOS 標準には入っていないため:
```bash
brew install coreutils  # gtimeout が入る
```
どちらも見つからない場合は、タイムアウトなしで実行せずエラー終了する。

## ライセンス

MIT License — [LICENSE](./LICENSE) を参照。
