# 作業記録

このファイルは開発時の判断、実装内容、検証結果を記録するためのものです。
配布用Skillではなく、`scripts/install-for-antigravity.*`を含む各installerのコピー対象外です。

## 2026-07-05: Claude Code連携機能の拡張

### 背景

- 対になる `Yumeno/add_codexcli` の更新内容を調査した。
- `Yumeno/add_claudecode` Issue #1として、同等の利用目的をClaude Code向けに実現する要件を整理した。
- Claude Code CLI 2.1.200の実機helpと最小probeを使い、非対話実行の契約を確認した。

### 実装

- 質問用wrapperをリポジトリ直下の`scripts/`へ統合した。
- `ask-claude`と`ask-claude-with-context`を中央wrapperへ移行した。
- 次のSkillを追加した。
  - `set-claude-model`
  - `list-claude-models`
  - `claude-implement`
- モデル設定をCLI引数、環境変数、設定ファイル、Claude Code既定の順で解決するようにした。
- wrapper/helperの失敗をLLM回答と区別するsentinelを追加した。
- `claude-verify.ps1` / `.sh`へGit snapshot/checkを実装した。
- `claude-implement`でclean tree、事前snapshot、最小ツール、事後checkを必須化した。
- PowerShell 5.1とbash用のfake CLI unit testを追加した。
- READMEを現実装へ同期した。

### レビューで修正した主な事項

- OAuth認証を読まない`--bare`を既定採用せず、`--safe-mode`を使用した。
- 質問用wrapperと書き込み用entry pointを分離した。
- timeout時に子プロセスツリーを終了するようにした。
- timeoutコマンドがないbash環境では無期限実行せず、fail closedにした。
- 旧wrapperの重複を削除し、中央wrapperへ一本化した。
- `CLAUDE_VERIFY_ALLOWED`をユーザー承認済み保護対象だけに限定した。
- worktreeなど`.git`がgitfileになる構成でも、実git pathのconfig/hooksを検証するようにした。
- Windows引数quote、モデル名検証、stdin経由のprompt/contextをテストした。

### 検証

- PowerShell版wrapper、context collector、verify、implementのunit testに成功した。
- Git for Windowsのbashで同等のtest suiteに成功した。
- 実Claude Code wrapper E2Eで`OK`応答を確認した。
- コミット`bed10d8`を`main`へpushした。

### 既知の境界

- `claude-implement`のリポジトリ外アクセス防止は、Claude Codeの`--safe-mode`と
  `dontAsk` permission modeに依存する。OSレベルのsandboxではない。
- Claude Code CLIに契約上利用可能な全モデルを列挙する公式コマンドがないため、
  モデル一覧を推測で生成していない。

## 2026-07-06: Antigravity CLI導入と複数メディア対応

### 背景

- Issue #2としてAntigravity CLI向けのSkillインストール方法を整理した。
- Issue #3として複数メディアをClaude CodeのVLM contextとして渡す要件を整理した。
- `Yumeno/add_antigravitycli`のmedia staging実装を参照した。
- Antigravity 2.0 IDEとAntigravity CLIの配置仕様を混同しないよう、CLI公式資料を再調査した。

### Antigravity CLIの配置判断

Antigravity CLI 1.0.16向けには、CLI公式ドキュメントを基準として次を採用した。

- workspace Skill: `<workspace>/.agents/skills/`
- global Skill: `~/.gemini/antigravity-cli/skills/`
- 共通Claude helper: `~/.gemini/scripts/`

古いAntigravity IDE向け資料にある`.agent/skills/`や
`~/.gemini/antigravity/skills/`は、CLI installerの対象にしていない。

### Antigravity installer

- `scripts/install-for-antigravity.ps1`と`.sh`を追加した。
- 同名の5 Skillだけを更新し、無関係なSkillを保持する。
- copy完了前に旧Skillを削除しないよう、temp stagingを追加した。
- helperを先に更新してからSkillを置換し、「新Skill + 旧helper」になる時間を避けた。
- PowerShell版とGit Bash版のinstaller unit testに成功した。
- global pathに置いた一時Skillを、Skillのない`C:\tmp`からslash commandで直接実行し、
  `AGY_CLI_GLOBAL_SKILL_OK`を確認した。
- workspace Skillのheadless `agy --print`検証はtimeoutした。workspace対応自体は
  CLI公式仕様に記載されているため、interactive TUIのslash command候補で確認する方針とした。

### 複数メディア対応

- `claude-wrapper.ps1`へ`-Attachment`と`-AttachmentList`を追加した。
- `claude-wrapper.sh`へ反復可能な`--attachment`と`--attachment-list`を追加した。
- 指定された順序を保持して、wrapper所有の一時ディレクトリへcopyする。
- magic bytesでMIMEを判定し、元の拡張子を信用しない。
- canonicalな連番ファイル名とmanifestを生成する。
- directory、symlink/reparse point、未知形式、音声、動画を拒否する。
- 添付時だけClaude Codeの`Read` toolを有効にし、staging directoryだけを`--add-dir`する。
- Read範囲を広げないため、attachmentと明示`WorkDir`の併用を拒否する。
- ファイル数、総byte数、各MIME、byte数、support状態を実行前にstderrへ表示する。
- 成功、CLI失敗、timeoutの通常終了経路でstagingを削除する。
- `ask-claude-with-context`を画像・PDF対応へ更新した。
- `claude-implement`はmedia未対応とし、Base64埋め込みなどによる回避を禁止した。

### サポート状態

- `probe-verified`
  - PNG
- `experimental`
  - JPEG
  - GIF
  - WebP
  - BMP
  - TIFF
  - SVG
  - PDF
- `unsupported`
  - 音声
  - 動画
  - 未認識バイナリ

音声・動画はClaude Code Read toolの公式対応を確認できなかったため、参照実装が扱えることだけを
根拠に許可していない。

### 検証

- PowerShell版wrapperのmedia unit testに成功した。
- Git Bash版wrapperのmedia unit testに成功した。
- BOM付き・CRLFのattachment listをbashで処理できることを確認した。
- Antigravity installerのPowerShell/bash unit testに成功した。
- 64×64の赤PNGと青PNGを1回のClaude Code E2Eへ渡し、
  `1: 赤, 2: 青`の応答を得た。複数画像の順序と実内容の参照を確認した。
- Codexサブエージェントによるmedia、installer、Skill/READMEの独立レビューを実施し、
  Read範囲、manifest差異、PNG magic判定、CRLF/BOM、非atomic更新を修正した。
- コミット`529af65`を`main`へpushし、Issue #2とIssue #3がcloseされたことを確認した。

### 作業中の事象

- Cドライブ空き容量が0になり、Antigravity向けglobal installが途中停止した。
- この作業で`C:\tmp`へ作成した参照cloneを削除し、ユーザーが追加の空き容量を確保した後に再実行した。
- 中断時に`~/.gemini/scripts/claude-*`が一時的に削除されたが、空き容量回復後にinstallerを
  再実行し、6 helperが配置されたことを確認した。
- この事象を受け、installerへ事前stagingを追加した。

