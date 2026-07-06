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

## 2026-07-07: レビュー指摘の修正、非ASCII path 対応、Windows PS 5.1 の Console encoding 修正

### 背景

- Claude Code (Fable 5) がリポジトリ初見レビューを実施し、5 件の指摘 (Antigravity bash installer 配置ミス、
  claude-verify の symlink hook 検出漏れ、claude-implement の `.env.example` 承認経路欠如、submodule metadata 未監視、
  外向き symlink 未検出) を Codex サブエージェントに委任して実装した。
- 実装後、Fable 5 が再度独立レビューを行い、Codex 実装に残っていた 2 件の bug (PS `File-State` の broken symlink 耐性、
  claude-implement.ps1 の `-Allow` 多値 silent drop) を追加修正した。
- ユーザーの指摘 (「日本語パスだめなんだ？」) を受けて、Windows で `powershell -File` の argv 境界が
  CP932 で mangling する問題への対応を追加した。

### 実装

- Codex 委任分 (修正 A ～ E):
  - `install-for-antigravity.sh` に第 2 引数 `scripts_root` を追加し、helper 配置先を README・PS 版と揃えた。
  - `claude-verify` の hooks 走査で `find -type f` → `\( -type f -o -type l \)` に変更し、symlink hook を検出可能にした。
    PS 版も `-File` から `Where-Object { -not $_.PSIsContainer }` に変更した。
  - `claude-implement` に `-Allow` / `--allow` を追加し、`claude-verify check` へ委譲するようにした。
    保護対象ファイル (`.env.example` 等) をユーザー承認経由で編集できるようになった。
  - `assert_snapshot_safe` を追加し、`.gitmodules` または `.git/modules/*` の存在時に snapshot を fail closed で拒否。
  - 同関数でリポジトリ内から外を指す symlink / reparse point も fail closed で拒否。
- Fable 5 追加分:
  - PS `File-State` を修正し、reparse point の hash を target 文字列から計算する (bash 準拠、broken symlink 耐性)。
  - `claude-implement.ps1` の verify 呼び出しを `powershell -File` 中継から in-process `& $verify` に変更し、
    多値 `-Allow` の silent drop を解消。boundary 経由の comma 区切り 1 引数も内部で split する正規化を追加。
  - test-implement に多値 `-Allow` の positive / partial-allow-fails ケースを追加、fake-claude に対応 mode 追加。
- 非 ASCII path 対応 (追加要件):
  - `claude-verify` / `claude-implement` に `-RepoFile` / `--repo-file` を追加。UTF-8 で書かれたファイルから
    repo path を strict decoder で読む。
  - `claude-wrapper` に `-PromptFile` / `--prompt-file` を追加。非 ASCII 質問を UTF-8 ファイル経由で渡せるようにした。
  - `claude-verify.ps1` に `[Console]::OutputEncoding = UTF8` の設定を追加した (wrapper / implement は既に持っていた)。
    これが欠けていたため git.exe の UTF-8 stdout が CP932 で decode されて日本語 path が別文字列に化けていた。
- テスト:
  - 全 script の PS/bash unit test に -RepoFile / -PromptFile の positive / negative / conflict / missing / empty ケースを追加。
  - fake-claude.ps1 の stdin 読み込みを byte 配列経由に変更し、CP932 での mangling を回避した。
  - 日本語 path repo に対する end-to-end probe で snapshot / check / dirty tree detection まで動作を確認した。

### レビューで修正した主な事項

- Codex 実装の PS 側 `File-State` 回帰 (Get-FileHash が broken symlink target で例外) を修正。
- Codex 実装の PS 側 `claude-implement -Allow` 多値 silent drop を修正。
- 私自身が「pre-existing 環境問題」と誤診した `test-verify.ps1` の日本語 temp path 失敗を、Codex の助言を受けた
  A/B 比較で真因 (verify.ps1 の [Console]::OutputEncoding 未設定) を特定して修正した。

### 検証

- PowerShell 5/5 スイート PASS (test-verify.ps1 も含む)。
- bash 5/5 スイート PASS (test-verify.sh の symlink 系 2 ケースは MSYS 環境で SKIP)。
- 日本語 path (`C:\...\Temp\日本語_XXXXX\repo`) に対する `powershell -File claude-verify.ps1 snapshot -RepoFile ...`
  および check の end-to-end 動作を確認。dirty tree の変更検知も動作。
- Codex にセカンドオピニオンを 2 回依頼した (1: レビュー内容の妥当性、2: 日本語 path 失敗の原因)。
  2 回目の指摘 (「同一ファイル比較になっていない」+ strict decoder / Test-Path 明示追加) が真因特定の鍵になった。

### 既知の境界

- Windows Git Bash 環境で `ln -s` が実 symlink を作れない場合、test-verify の symlink 関連 2 ケースは自動 SKIP になる
  (test 側で `[[ -L $link ]]` プローブして判定)。
- `-RepoFile` / `-PromptFile` は path / 質問本文の非 ASCII 対応であり、その他の param (`-WorkDir`、`-Attachment` パス、
  `-Context` テキスト等) は現状 argv 境界依存のまま。必要が生じたら同じ pattern で拡張可能。


