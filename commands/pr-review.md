---
description: PRを詳細にレビューし、改善提案を行う
argument-hint: <PR番号またはURL>
allowed-tools: Bash(gh pr view *), Bash(gh pr diff *), Bash(gh pr checks *), Bash(gh pr comment *), Bash(gh api *), Bash(gh issue view *), Read, Grep, Glob, WebFetch
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
- CIステータス: !`gh pr checks $0 2>/dev/null || gh pr checks`

## 手順
1. 上記の自動取得データを元にレビュー
2. `code-reviewer` Subagentでレビュー（観点はSubagentのSkill定義に従う）
3. レビュー結果を統合して表示
4. 修正に入るか確認（AskUserQuestion）
5. 修正実行後、ボットコメントに返信
6. CLAUDE.md更新が必要か確認

## Subagent活用
`code-reviewer` Subagentに登録されたSkillの全観点で並列実行。

## 出力形式
- 全体評価（Approve/Request Changes/Comment）
- 問題点（Critical/High/Medium/Low）
- ファイルパス・行番号
- 改善提案

## ユーザー確認（AskUserQuestion）

### 修正への移行確認
レビュー結果表示後に確認:
- **AIに判断を任せる（推奨）**: セキュリティ・バグ・型エラー・パフォーマンス問題は必ず修正、それ以外は内容を読んで判断
- **個別に選択する**: 各項目について個別に確認
- **修正しない**: レビュー結果の確認のみで終了

### 個別選択の場合
各項目について確認:
- **AIに判断を任せる**: この項目についてAIが対応要否を判断
- **修正する**: この項目を修正対象に追加
- **修正しない**: この項目をスキップ

### CLAUDE.md更新確認
修正後、プロジェクト全体に適用すべきルールがあれば確認:
- セキュリティパターン、コーディング規約、繰り返し発生するエラーパターン等
