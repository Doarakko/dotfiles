---
description: 現在の変更を論理的な単位で複数のコミットに分割する
allowed-tools: Bash(git add *), Bash(git commit *), Bash(git push *), Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git branch *)
---

# コミット分割コマンド

現在の変更を論理的な単位で複数のコミットに分割する。

## 使用方法
```
/commit-split [ベースブランチ] [分割方式]
```

## 現在の状態（自動取得）
- ステータス: !`git status --short`
- 差分統計: !`git diff --stat`
- 直近のコミット: !`git log --oneline -5`

## 手順
1. 上記の自動取得データを元に変更を確認
2. 分割方針を決定
3. 関連する変更をグループ化してコミット
4. 各コミットはConventional Commits形式
5. 全コミット完了後にプッシュ

## 分割の指針
- ファイルタイプ別（設定、ドキュメント、コード、テスト）
- 機能別（新機能、バグ修正、リファクタリング）
- 影響範囲別（フロントエンド、バックエンド、DB）

## 絶対に守るべきルール
- 関係のない変更はコミットに含めない
- 関係のない変更を消さない
- `git checkout`、`git restore`、`git reset`、`git stash` は使わない
