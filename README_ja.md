# PathWeave

[English README](README.md)

PathWeave は、PowerShell 向けの曖昧パス補完ツールです。

ファイル名やディレクトリ名の先頭ではなく、意味のある一部分だけを入力して、任意のコマンド引数でパスを補完できます。

```powershell
nvim inbox<Tab>
Get-Content daily<Tab>
Copy-Item notes<Tab> .\backup\
rg keyword archive<Tab>
```

PathWeave は 2 つの部品で構成されています。

- `pwv`: ファイルシステムを走査し、候補を一致判定・スコアリングして出力する Rust CLI
- `PathWeave`: PSReadLine の入力バッファを読み取り、`pwv` を呼び出して、選択したパスを挿入する PowerShell モジュール

Rust 側は親 PowerShell の入力行を直接変更しません。プロンプト、カーソル、キーバインド、挿入処理は PowerShell 側が担当します。

ライセンス: MIT。詳細は [LICENSE](LICENSE) を参照してください。

## インストール

PowerShell から最新 release をインストール:

```powershell
irm https://raw.githubusercontent.com/ryuabiru/PathWeave/main/install.ps1 | iex
```

最初から `Tab` 統合も有効にしたい場合:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/ryuabiru/PathWeave/main/install.ps1))) -UseTab
```

Scoop でインストール:

```powershell
scoop install https://raw.githubusercontent.com/ryuabiru/PathWeave/main/packaging/scoop/pathweave.json
```

その後、PowerShell profile にモジュールを追加します:

```powershell
Import-Module "$env:SCOOP\apps\pathweave\current\powershell\PathWeave.psd1" -Force
Enable-PathWeave -UseTab
```

## 現在の状態

現在の MVP でできること:

- 現在のディレクトリ以下を再帰検索
- 部分一致、単語境界一致、整理用プレフィックスを弱く扱う一致、fuzzy 一致
- PowerShell 連携向けの JSON 出力
- `Ctrl+Spacebar` による明示的な PathWeave 補完
- 任意の `Tab` 統合
- `Tab` で PathWeave 候補を順送り
- `Shift+Tab` で PathWeave 候補を逆送り
- 標準 PowerShell 補完を優先し、標準候補がない場合だけ PathWeave にフォールバック
- Rust と PowerShell の自己完結テスト

## ビルド

リポジトリのルートで実行します。

```bash
cargo build --release
```

生成されるバイナリ:

```text
target/release/pwv
```

Windows では次の名前になります。

```text
target\release\pwv.exe
```

開発中は、PowerShell モジュールが `target/release` と `target/debug` のローカルビルドも探します。そのため、試すだけなら正式にインストールしなくても使えます。

## インストールせずに試す

PowerShell で、リポジトリのルートから実行します。

```powershell
Import-Module .\powershell\PathWeave.psd1 -Force
Enable-PathWeave -UseTab
```

次のように試せます。

```powershell
nvim tom<Tab>
```

標準 PowerShell 補完に候補がない場合、PathWeave が現在のディレクトリ以下を検索します。`Tab` を繰り返すと候補を順送りし、`Shift+Tab` で逆送りできます。

`Tab` を変更せず、明示的に PathWeave を起動したい場合:

```powershell
Import-Module .\powershell\PathWeave.psd1 -Force
Enable-PathWeave
```

クエリの後で `Ctrl+Spacebar` を押します。

```powershell
nvim inbox<Ctrl+Spacebar>
```

## 普段使いの設定

日常的に使う場合は、PowerShell から 2 つの部品が見えるようにします。

1. `pwv` を `PATH` に置く、またはリポジトリ内のローカルビルドを使う
2. PowerShell profile からモジュールを import する
3. 明示的補完または `Tab` 統合を有効にする

profile の例:

```powershell
Import-Module "C:\path\to\PathWeave\powershell\PathWeave.psd1"
Enable-PathWeave -UseTab
```

標準の `Tab` を触りたくない場合:

```powershell
Import-Module "C:\path\to\PathWeave\powershell\PathWeave.psd1"
Enable-PathWeave
```

## PowerShell での挙動

`Enable-PathWeave -UseTab` を有効にした場合、`Tab` は次の順に動きます。

1. PowerShell の標準補完候補を確認する
2. 標準補完候補があれば通常の PowerShell 補完を使う
3. 標準補完候補がなければ `pwv search` を呼び出す
4. PathWeave の最上位候補を、現在のトークンへ挿入する
5. `Tab` を繰り返すと PathWeave 候補を順送りする
6. `Shift+Tab` で PathWeave 候補を逆送りする

挿入はトークン単位です。たとえば次の入力では:

```powershell
Copy-Item inbox .\backup\
```

`inbox` だけが候補パスに置き換わり、後続の `.\backup\` はそのまま残ります。

## CLI の使い方

現在のディレクトリから検索:

```powershell
pwv search --query inbox --cwd . --format json
```

短縮形:

```powershell
pwv s inbox --cwd .
```

主なオプション:

```text
--query <QUERY>
--cwd <PATH>
--type <any|file|dir>
--max-results <NUMBER>
--max-depth <NUMBER>
--hidden
--follow-links
--format <plain|json|jsonl>
```

JSON 出力例:

```json
[
  {
    "path": ".\\00-Inbox\\",
    "display": "00-Inbox",
    "kind": "directory",
    "score": 1090
  }
]
```

## 一致判定と順位付け

PathWeave は決定的なスコアリングで候補を並べます。優先される一致の例:

- ファイル名の完全一致
- `00-`、`01_`、`@`、`_`、日付らしいプレフィックスを弱く扱った完全一致
- ファイル名の先頭一致
- 単語境界一致
- 部分一致
- fuzzy 一致
- パス全体への fuzzy 一致

さらに、次の候補を少し優先します。

- 現在のディレクトリに近いパス
- パス全体ではなくファイル名部分に一致したもの
- 同点の場合は短いパス

隠しファイルはデフォルトで除外されます。デフォルトの除外ディレクトリ:

```text
.git
node_modules
target
.venv
```

## テスト

Rust のテスト:

```bash
cargo test
```

Pester なしで実行できる PowerShell 自己テスト:

```powershell
pwsh -NoProfile -File powershell\tests\run-tests.ps1
```

Windows 向けの release zip を作る場合:

```powershell
pwsh -NoProfile -File powershell\package-release.ps1
```

`dist\` 以下に、`pwv.exe`、`install.ps1`、`SHA256SUMS.txt`、PowerShell モジュール、profile のサンプル、トップレベルのドキュメントをまとめた配布用 zip が生成されます。

PowerShell テストで確認していること:

- パスのクォート
- トークン抽出
- 挿入範囲
- `Tab` フォールバック
- `Tab` の順送り
- `Shift+Tab` の逆送り
- 実際の `pwv` CLI 結果を使った入力バッファ置換

## 軽量性について

PathWeave は意図的にシンプルです。

- バックグラウンドプロセスなし
- インデックス DB なし
- 長寿命キャッシュなし
- Rust 側でターミナル UI を持たない
- 検索中に保持する候補数を制限

CLI は必要なときに現在のディレクトリツリーを走査し、最終ソート前に上位候補だけを保持します。これにより、メモリ使用量が一致した全パス数ではなく `--max-results` に近い規模へ収まりやすくなっています。

大量の一致ファイルを作成し、`--max-results` が守られ、かつ上位候補が保持されることを確認する CLI 統合テストもあります。

## トラブルシュート

`Tab` で PathWeave が動かない場合は、モジュールを再読み込みして `Tab` 統合を有効にします。

```powershell
Import-Module .\powershell\PathWeave.psd1 -Force
Enable-PathWeave -UseTab
```

`pwv` が見つからない場合はビルドします。

```bash
cargo build --release
```

そのままリポジトリ内のローカルビルドを使うか、release バイナリを `PATH` に置いてください。

標準 PowerShell 補完に候補がある場合、PathWeave は意図的に出しゃばりません。ファイル名の途中など、標準補完では解決できないクエリで試してください。

## ディレクトリ構成

```text
src/
  cli.rs
  config.rs
  matcher.rs
  output.rs
  scorer.rs
  search.rs
powershell/
  PathWeave.psd1
  PathWeave.psm1
  tests/run-tests.ps1
tests/
  matcher_tests.rs
  scorer_tests.rs
  search_tests.rs
docs/
  architecture.md
  completion-behavior.md
examples/
  Microsoft.PowerShell_profile.ps1
```
