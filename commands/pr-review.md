---
description: PRを詳細にレビューし、改善提案を行う
argument-hint: <PR番号またはURL>
allowed-tools: Skill, Bash(gh pr view *), Bash(gh pr diff *), Bash(gh pr checks *), Bash(gh pr comment *), Bash(gh api *), Bash(gh issue view *), Read, Grep, Glob, WebFetch
---

# PRレビューコマンド

指定されたPRを詳細にレビューし、改善提案を行う。

## 使用方法
```
/pr-review <PR番号またはURL>
```

## PR情報（自動取得）
- PR詳細: !`gh pr view $0 --json title,body,url,labels,milestone 2>/dev/null || gh pr view --json title,body,url,labels,milestone`
- PR差分: !`gh pr diff $0 2>/dev/null || gh pr diff`
- 変更ファイル一覧: !`gh pr diff $0 --name-only 2>/dev/null || gh pr diff --name-only`
- CIステータス: !`gh pr checks $0 2>/dev/null || gh pr checks 2>/dev/null || echo "No CI checks"`

## 手順
1. 上記の自動取得データを元にレビュー
2. `code-reviewer` Subagentでレビュー（観点はSubagentのSkill定義に従う）
3. レビュー結果を統合して表示
4. `doarakko-config:review-followup` スキルを起動し、その手順に従って修正に入るかを確認する
5. 修正実行後、ボットコメントに返信

## Subagent活用
`code-reviewer` Subagentに登録されたSkillの全観点で並列実行。

## 出力形式
- 全体評価（Approve/Request Changes/Comment）
- 問題点（Critical/High/Medium/Low）
- ファイルパス・行番号
- 改善提案
