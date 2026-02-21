---
name: e2e-check
description: Playwright CLIを使ってE2Eで動作確認を行うときに使用
allowed-tools: Read, Grep, Glob, Bash
---

# E2E動作確認（Playwright CLI）

`playwright-cli` を使ってブラウザを操作し、アプリケーションの動作確認をE2Eで行う。

## 初期チェック

最初に必ず実行:
```bash
which playwright-cli
```

コマンドが見つからない場合は処理を中断し、ユーザーにインストールを案内する。

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
```

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
| `playwright-cli snapshot` | ページ構造の確認（ref取得） |
| `playwright-cli screenshot` | スクリーンショット取得 |
| `playwright-cli click --ref <ref>` | 要素のクリック |
| `playwright-cli type --ref <ref> --text <text>` | テキスト入力 |
| `playwright-cli select-option --ref <ref> --value <value>` | セレクトボックス選択 |
| `playwright-cli hover --ref <ref>` | ホバー |
| `playwright-cli cookie-list` | Cookie一覧の確認 |
| `playwright-cli close` | ブラウザを閉じる |

### 6. 確認結果のサマリー
- 確認したシナリオと結果を一覧で表示する
- 問題が見つかった場合は、原因と対処方法を提示する

## 注意事項
- 操作の前に必ず `playwright-cli snapshot` で要素の ref を確認してから操作する
- 認証が必要な場合は、環境変数や `.env` ファイルから認証情報を取得する
- 動作確認が完了したら `playwright-cli close` でブラウザを閉じる
