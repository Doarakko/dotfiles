---
description: PRのレビューコメントとCIエラーを自動修正する
argument-hint: [PR番号]
allowed-tools: Bash(gh pr view *), Bash(gh pr diff *), Bash(gh pr checks *), Bash(gh pr comment *), Bash(gh api repos/*/pulls/*/comments*), Bash(gh api repos/*/pulls/*/reviews*), Bash(gh repo view *), Bash(gh run view *), Bash(git add *), Bash(git commit *), Bash(git push *), Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git branch *), Bash(git merge *), Bash(npm *), Bash(npx *), Bash(ruff *), Bash(golangci-lint *), Read, Write, Edit, Grep, Glob, WebFetch
---

# PR自動修正コマンド

PRのレビューコメントとCIエラーを自動修正する。

## 使用方法
```text
/pr-fix [PR番号]
```
PR番号省略時は現在のブランチのPRを使用。

## PR情報（自動取得）
- PR詳細: !`gh pr view $0 --json title,body,url,number 2>/dev/null || gh pr view --json title,body,url,number`
- CIステータス: !`gh pr checks $0 2>/dev/null || gh pr checks`
- PR差分: !`gh pr diff $0 2>/dev/null || gh pr diff`

## PR情報（手動取得）
以下はBashツールで手動実行すること:
1. リポジトリ名とPR番号を取得: `gh repo view --json nameWithOwner -q .nameWithOwner` と `gh pr view $0 --json number -q .number`
2. レビューコメント（インライン）: `gh api repos/{owner}/{repo}/pulls/{number}/comments`
3. レビュー（承認・変更要求）: `gh api repos/{owner}/{repo}/pulls/{number}/reviews`

## 修正対象
### レビューコメント
- 必ず修正: セキュリティ、バグ、型エラー、パフォーマンス問題
- それ以外: 内容を読み、修正すべきかを判断する

### CIエラー
- lint/type/test/build エラーを自動修正

## 手順
1. 自動取得データと手動取得データ（レビューコメント・レビュー）を元に修正対象を特定
2. コンフリクト確認、あれば解消
3. ユーザーに修正方針を確認（AskUserQuestion）
4. 各レビューコメント修正について:
   a. 修正を適用
   b. コミット・プッシュ
   c. ボットコメントに返信（人間のコメントには返信しない）
5. CIエラー修正を適用
6. コミット・プッシュ
7. CLAUDE.md更新が必要か確認

## ユーザー確認（AskUserQuestion）

### 全体の修正方針
検出された修正項目について確認:
- **AIに判断を任せる（推奨）**: セキュリティ・バグ・型エラー・パフォーマンス問題は必ず修正、それ以外は内容を読んで判断
- **個別に選択する**: 各項目について個別に確認

### 個別選択の場合
各項目について確認:
- **AIに判断を任せる**: この項目についてAIが対応要否を判断
- **修正する**: この項目を修正対象に追加
- **修正しない**: この項目をスキップ

### CLAUDE.md更新確認
修正後、プロジェクト全体に適用すべきルールがあれば確認:
- セキュリティパターン、コーディング規約、繰り返し発生するエラーパターン等

## 自動返信ルール
- 修正した: `Done. <コミットURL>`
  - コミットURL形式: `https://github.com/{owner}/{repo}/commit/{sha}`
- 対応不要と判断: `Skipped: [理由]`
