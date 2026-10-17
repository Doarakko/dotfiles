---
description: 現在のローカル変更をレビューする
argument-hint: [対象ファイル・ディレクトリ]
allowed-tools: Skill, Bash(git status *), Bash(git diff *), Bash(codex exec *), Bash(npm run lint *), Bash(npx eslint *), Bash(ruff check *), Bash(golangci-lint run *), Bash(git rev-parse *), Bash(mkdir *), Read, Edit(//tmp/claude/report/**), Edit(//private/tmp/claude/report/**), Grep, Glob
---

# コード差分レビューコマンド

現在のローカル変更をレビューする。

## 使用方法
```
/review-diff [対象ファイル・ディレクトリ]
```
対象省略時は全変更をレビュー。

## 変更情報（自動取得）
- ステータス: !`git status --short`
- 変更の規模: !`git rev-parse --verify --quiet HEAD >/dev/null 2>&1 && git diff HEAD --stat || git diff --cached --stat`

## 対象
指定された対象: $ARGUMENTS（省略時は全変更）

## 手順
1. 上記で変更の広がりを把握する。差分の中身はSubagentが各自で取得するので、ここでは全文を読まない
2. プロジェクト環境を分析（言語、フレームワーク）
3. 下の「観点のグループ」に従って起動する`doarakko-config:code-reviewer`を決め、`doarakko-config:codex-reviewer`と合わせて1メッセージ内で同時に起動する。どの`doarakko-config:code-reviewer`にも同じ対象を渡す
   - 未インストールや未ログインで`codex`が使えない環境では`doarakko-config:codex-reviewer`がスキップを報告するので、その旨を結果に含める
4. 自動チェックツール実行（ESLint、Ruff、golangci-lint等）
5. 全レビュアーの指摘をマージし、同一箇所を指す重複指摘は1件にまとめる（どのレビュアー由来かを併記）
6. 下の「反証」に従って Critical / High を検証し、結果を表示する
7. `doarakko-config:report-artifact` スキルを種別`review-diff`で起動し、その手順に従ってHTMLページを公開する
8. `doarakko-config:review-followup` スキルを起動し、その手順に従って修正に入るかを確認する
9. 修正した場合は、同じファイルパスでHTMLページを再公開する

## 観点のグループ
`doarakko-config:code-reviewer`は観点のグループごとに別々に起動する。1体へ全観点を持たせると、観点が増えるほど1つあたりの読みが浅くなる。どのグループを起動するかは変更ファイルの種類で決める。

| グループ | 渡す観点 | 起動する条件 |
| --- | --- | --- |
| 安全性 | `security,errors` | コード（スクリプト・設定・CIの定義を含む）の変更がある |
| 可読性と規約 | `quality,comments,guidelines` | 常に。ドキュメントだけの変更なら`guidelines`だけを渡す |
| テスト | `test` | コードかテストの変更がある |

ドキュメントだけの変更とは、変更ファイルがすべて`.md`・`.txt`・画像などで、実行されるものを含まない場合。Claude Codeのコマンド・スキル・エージェントの定義のように、実行時に読まれて振る舞いを決める`.md`はコードとして扱う。判断に迷うファイルがあればコードとして扱う。

## 反証
マージ後に残った Critical / High の指摘を、`doarakko-config:finding-verifier` Subagentへ1回でまとめて渡す。レビュー対象（ローカルの差分と、指定があればその範囲）も一緒に渡す。

- 反証された指摘は一覧から外し、「反証された指摘」として理由と一緒に別に並べる
- Medium / Low は反証にかけない。件数が多く、反証の費用に見合わないため。一覧では未検証と分かるようにする
- Critical / High が0件なら`doarakko-config:finding-verifier`は起動しない
- `doarakko-config:finding-verifier`が失敗したら、指摘を落とさずに未検証のまま並べ、反証できなかったことを書く

## 出力形式
- 変更統計（ファイル数、追加/削除行数）
- 自動チェック結果
- 問題点と改善提案（反証を通ったもの、未検証のもの）
- 反証された指摘とその理由
- 次のステップ
