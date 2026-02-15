---
description: 現在の変更をコミットし、リモートにプッシュする
allowed-tools: Bash(git add *), Bash(git commit *), Bash(git push *), Bash(git status *), Bash(git diff *), Bash(git log *)
---

# コミットコマンド

現在の変更をコミットし、リモートにプッシュする。

## 使用方法
```
/commit
```

## 現在の状態（自動取得）
- ステータス: !`git status --short`
- 差分: !`git diff --stat`
- 直近のコミット: !`git log --oneline -5`

## 手順
1. 上記の自動取得データを元に変更を確認
2. Conventional Commits形式でコミットメッセージ作成
3. `git push` でリモートに反映

## Conventional Commits形式
- `type(scope): subject`
- タイトルは50文字以内、本文は72文字で改行
- 動詞は原形（add, fix, update等）
- scopeは原則記述、適切なものがなければ省略可
- 小文字で始める
- 実装とテストが含まれる場合、typeはfeat/fixを優先

## 絶対に守るべきルール
- 関係のない変更はコミットに含めない
- 関係のない変更を消さない
- `git checkout`、`git restore`、`git reset`、`git stash` は使わない
