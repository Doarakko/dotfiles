---
description: 新規ブランチ作成からPR作成までを一連で実行する
argument-hint: [--from-main]
allowed-tools: Bash(git add *), Bash(git commit *), Bash(git push *), Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git branch *), Bash(git stash *), Bash(git checkout *), Bash(gh pr create *), Bash(gh auth refresh *)
---

# PRゼロからワークフロー

新規ブランチ作成からPR作成までを一連で実行する。

## 使用方法
```
/pr-zero [--from-main]
```
- `--from-main`: メインブランチから新規ブランチ作成
- 省略時: 現在のブランチから新規ブランチ作成

## 現在の状態（自動取得）
- ブランチ: !`git branch --show-current`
- ステータス: !`git status --short`
- 差分統計: !`git diff --stat`

## オプション
指定されたオプション: $ARGUMENTS（省略時は現在のブランチから作成）

## 重要ルール
**既存ブランチには絶対にpushしない。必ず新規ブランチを作成する。**

## 手順
1. 新規ブランチ作成（Conventional Branch形式）
   - 例: `feature/admin-user-role-edit-invite-form`
2. 上記の自動取得データを元に変更確認
3. コミット分割・作成（Conventional Commits形式）
4. `git push -u origin <branch>` でプッシュ
5. PRテンプレート確認（`.github/PULL_REQUEST_TEMPLATE.md`等）
6. `gh pr create --draft` でドラフトPR作成

## エラーハンドリング
- 認証エラー時は手動PR作成URLを提供
- `gh auth refresh -s repo,read:org` で再認証案内

## 絶対に守るべきルール
- 関係のない変更はコミットに含めない
- 関係のない変更を消さない
- `git checkout`、`git restore`、`git reset`、`git stash` は使わない（ブランチ作成時の明示的stashは除く）
