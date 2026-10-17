---
description: PRを詳細にレビューし、改善提案を行う
argument-hint: <PR番号またはURL>
allowed-tools: Skill, Bash(gh pr view *), Bash(gh pr diff *), Bash(gh pr checks *), Bash(gh pr comment *), Bash(gh api *), Bash(gh issue view *), Bash(git rev-parse *), Bash(mkdir *), Read, Edit(//tmp/claude/report/**), Edit(//private/tmp/claude/report/**), Grep, Glob, WebFetch
---

# PRレビューコマンド

指定されたPRを詳細にレビューし、改善提案を行う。

## 使用方法
```
/pr-review <PR番号またはURL>
```

## PR情報（自動取得）
- PR詳細: !`gh pr view $0 --json title,body,url,labels,milestone,additions,deletions,changedFiles 2>/dev/null || gh pr view --json title,body,url,labels,milestone,additions,deletions,changedFiles`
- 変更ファイル一覧: !`gh pr diff $0 --name-only 2>/dev/null || gh pr diff --name-only`
- CIステータス: !`gh pr checks $0 2>/dev/null || gh pr checks 2>/dev/null || echo "No CI checks"`

## 手順
1. 上記で変更の広がりを把握する。差分の中身はSubagentが取得するので、ここでは全文を読まない
2. 下の「観点のグループ」に従って起動する`doarakko-config:code-reviewer`を決め、1メッセージ内で同時に起動する。どれにも対象のPR番号を渡す
3. 指摘をマージし、同一箇所を指す重複指摘は1件にまとめる（どのグループ由来かを併記）
4. 下の「反証」に従って Critical / High を検証し、結果を表示する
5. `doarakko-config:report-artifact` スキルを種別`pr-review`で起動し、その手順に従ってHTMLページを公開する
6. `doarakko-config:review-followup` スキルを起動し、その手順に従って修正に入るかを確認する
7. 修正実行後、同じファイルパスでHTMLページを再公開してから、ボットコメントに返信

## 観点のグループ
`doarakko-config:code-reviewer`は観点のグループごとに別々に起動する。1体へ全観点を持たせると、観点が増えるほど1つあたりの読みが浅くなる。どのグループを起動するかは変更ファイルの種類で決める。

| グループ | 渡す観点 | 起動する条件 |
| --- | --- | --- |
| 安全性 | `security,errors` | コード（スクリプト・設定・CIの定義を含む）の変更がある |
| 可読性と規約 | `quality,comments,guidelines` | 常に。ドキュメントだけの変更なら`guidelines`だけを渡す |
| テスト | `test` | コードかテストの変更がある |
| 要件 | `pr-compliance` | 常に |

ドキュメントだけの変更とは、変更ファイルがすべて`.md`・`.txt`・画像などで、実行されるものを含まない場合。Claude Codeのコマンド・スキル・エージェントの定義のように、実行時に読まれて振る舞いを決める`.md`はコードとして扱う。判断に迷うファイルがあればコードとして扱う。

## 反証
マージ後に残った Critical / High の指摘を、`doarakko-config:finding-verifier` Subagentへ1回でまとめて渡す。レビュー対象（PR番号）も一緒に渡す。

- 反証された指摘は一覧から外し、「反証された指摘」として理由と一緒に別に並べる
- Medium / Low は反証にかけない。件数が多く、反証の費用に見合わないため。一覧では未検証と分かるようにする
- Critical / High が0件なら`doarakko-config:finding-verifier`は起動しない
- `doarakko-config:finding-verifier`が失敗したら、指摘を落とさずに未検証のまま並べ、反証できなかったことを書く

## 出力形式
- 全体評価（Approve/Request Changes/Comment）
- 問題点（Critical/High/Medium/Low。反証を通ったもの、未検証のもの）
- 反証された指摘とその理由
- ファイルパス・行番号
- 改善提案
