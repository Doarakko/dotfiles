---
name: e2e-check
description: Playwright CLIを使ってE2Eで動作確認を行うときに使用
allowed-tools: Read, Grep, Glob, Bash(which *), Bash(playwright-cli *), Bash(curl -s -o /dev/null *), Bash(mkdir *), Bash(cat *), Bash(ls *), Bash(find *), Bash(echo *), Bash(printf *), Bash(basename *), Bash(tr *), Bash(test *), Bash(git branch *), Bash(git rev-parse *)
---

# E2E動作確認（Playwright CLI）

`playwright-cli` を使ってブラウザを操作し、アプリケーションの動作確認をE2Eで行う。

確認の記録としてスクリーンショットと動画を残す。PR作成時にそのままPR本文へ添付されるため、保存先と命名は必ずこの手順どおりにする。

## 初期チェック

最初に必ず実行:
```bash
which playwright-cli
```

コマンドが見つからない場合は処理を中断し、ユーザーにインストールを案内する。

## 成果物の保存先

対象リポジトリを汚さないよう、スクリーンショットと動画は一時領域に置く。

```bash
TOP=$(git rev-parse --show-toplevel) || exit 1
BRANCH=$(git branch --show-current)
[ -n "$BRANCH" ] || BRANCH="detached-$(git rev-parse --short HEAD)" || exit 1
DIR="${CLAUDE_E2E_OUTPUT_ROOT:-/tmp/claude/e2e}/$(basename "$TOP")/$(printf '%s' "$BRANCH" | tr '/' '-')"
mkdir -p "$DIR"
find "$DIR" -maxdepth 1 -type f -name '[0-9][0-9]-*' -delete
echo "$DIR"
```

gitが答えられない場所では中断する。パスが潰れると、別のブランチの成果物まで消してしまう。この削除は起動のたびに走るので、1回の動作確認で撮り切る。

得られたパスを以後「成果物ディレクトリ」と呼ぶ。Bashツールはコマンド間で変数を持ち越さないため、実際のパスを控えて以降はリテラルで書く。

**`--filename` には必ず絶対パスを渡す。** 相対パスを渡すとコマンドを実行したディレクトリを基準に解決され、対象リポジトリ直下に成果物が落ちて差分に混ざる。`PLAYWRIGHT_MCP_OUTPUT_DIR` は `--filename` を渡した時点で参照されないため、出力先を環境変数で寄せることはできない。

保存先のディレクトリが無いと書き込みに失敗する。撮影の前に `mkdir -p` を済ませておく。

`/tmp/claude` 配下を使うのは、PR作成ガードのhookからも同じ場所が見える必要があるため。`$TMPDIR` はサンドボックス下のBashとhookとで別の場所を指す。

### 命名規約

```
<成果物ディレクトリ>/NN-<英小文字とハイフンの説明>.png
<成果物ディレクトリ>/NN-<英小文字とハイフンの説明>.webm
```

- 先頭2桁はPR本文に並べる順序。`01` から振る
- `NN-` と拡張子を除いてハイフンを空白に直したものが、そのままPR本文の代替テキストになる。動画はプレイヤーとして表示され代替テキストを持たない
- 代替テキストの区切りに使われるため、ファイル名に `#` を含めない

例: `01-login-form-empty.png` / `02-login-error-state.png` / `10-invite-flow.webm`

## 動作確認の流れ

### 1. プロジェクトの理解
- `README.md` を読み、プロジェクトの概要・セットアップ手順・起動方法・URLなどを把握する
- 認証方法、テスト用アカウント、環境変数の設定など動作確認に必要な前提情報を確認する

### 2. アプリケーションの起動確認
- READMEの情報をもとに、動作確認対象のURLをユーザーに確認する
- `curl -s -o /dev/null -w "%{http_code}" <URL>` で疎通確認する
- 未起動の場合はユーザーに起動を依頼する

### 3. ブラウザを開く
```bash
playwright-cli open <URL>
playwright-cli resize 1280 800
```
ビューポートを固定してから進める。画面の大きさが揃い、動画の容量も抑えられる。

### 4. ページの状態を確認
```bash
playwright-cli snapshot
```
- snapshot でページ構造と各要素の ref を確認する
- 要素の ref を使って操作対象を特定する

### 5. ブラウザ操作
ユーザーの指示や状況に応じて、以下のコマンドを臨機応変に組み合わせて動作確認を行う:

| コマンド | 用途 |
|---------|------|
| `playwright-cli open <URL>` | ブラウザでURLを開く |
| `playwright-cli goto <URL>` | ページ遷移 |
| `playwright-cli resize <幅> <高さ>` | ビューポートの固定 |
| `playwright-cli snapshot` | ページ構造の確認（ref取得） |
| `playwright-cli click <ref>` | 要素のクリック |
| `playwright-cli fill <ref> <text>` | 入力欄への記入 |
| `playwright-cli type <text>` | フォーカス中の要素への入力 |
| `playwright-cli select <ref> <値>` | セレクトボックス選択 |
| `playwright-cli hover <ref>` | ホバー |
| `playwright-cli cookie-list` | Cookie一覧の確認 |
| `playwright-cli close` | ブラウザを閉じる |

### 6. 撮影
確認と並行して記録を残す。

スクリーンショット:
```bash
playwright-cli screenshot --filename "<成果物ディレクトリ>/01-login-form-empty.png"
playwright-cli screenshot --full-page --filename "<成果物ディレクトリ>/02-dashboard.png"
```
画面が切り替わる節目で撮る。レイアウトの変更なら `--full-page` を使う。修正の前後を見せたいときは変更前と変更後の両方を撮る。

動画:
```bash
playwright-cli resize 960 600
playwright-cli video-start
# 導線の操作
playwright-cli video-stop --filename "<成果物ディレクトリ>/10-invite-flow.webm"
```
- 導線ごとに1本にする。全導線を1本に詰めない
- 1本は60秒以内を目安にする。snapshot の確認や思考の待ち時間は録画に含めない
- 動画は必ず webm で保存される。GitHubはwebmを再生できる
- 撮影サイズは録画開始時のビューポートで決まる。CLIから指定する手段が無いため、容量を落としたいときは `video-start` の前に `resize` する
- `video-start` は開いているブラウザにそのまま効く。開き直す必要はない

撮り終えたら上限を超えたものが無いか確認する:
```bash
find "<成果物ディレクトリ>" -maxdepth 1 -type f ! -size -10000k
```
GitHubの添付上限は画像10MB、動画は無料プランで10MB。プランを判別する手段が無いため、常に10MBで判定する。超えたものは削除し、動画なら導線を分割して撮り直すか、同じ導線の節目のスクリーンショットで代替する。

### 7. 確認結果のサマリー
- 確認したシナリオと結果を一覧で表示する
- 成果物ディレクトリのパスと、撮影したファイルの一覧を併せて示す
- 問題が見つかった場合は、原因と対処方法を提示する

## 注意事項
- 操作の前に必ず `playwright-cli snapshot` で要素の ref を確認してから操作する
- 認証が必要な場合は、環境変数や `.env` ファイルから認証情報を取得する
- 動作確認が完了したら `playwright-cli close` でブラウザを閉じる
- 撮影の前に成果物ディレクトリを `mkdir -p` で作っておく。無いまま撮ると書き込みに失敗する
- `Operation not permitted` で失敗する場合は、`playwright-cli kill-all` で古いブラウザセッションを片付けてから開き直す
- サンドボックスがローカルへの接続を止めた場合は、ユーザーに `/sandbox` での許可を案内する。対象プロジェクト側の設定であり、このスキルからは変更できない
