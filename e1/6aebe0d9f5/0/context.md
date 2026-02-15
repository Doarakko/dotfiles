# Session Context

## User Prompts

### Prompt 1

# コミットコマンド

現在の変更をコミットし、リモートにプッシュする。

## 使用方法
```
/commit
```

## 手順
1. `git status` で変更を確認
2. Conventional Commits形式でコミットメッセージ作成
3. `git push` でリモートに反映

## Conventional Commits形式
- `type(scope): subject`
- タイトルは50文字以内、本文は72文字で改行
- 動詞は原形（add, fix, update等）
- scopeは原則記述、適切なものがなければ...

### Prompt 2

# PR自動修正コマンド

PRのレビューコメントとCIエラーを自動修正する。

## 使用方法
```
/pr-fix [pr番号]
```
PR番号省略時は現在のブランチのPRを使用。

## 修正対象
### レビューコメント
- 必ず修正: セキュリティ、バグ、型エラー、パフォーマンス問題
- それ以外: 内容を読み、修正すべきかを判断する

### CIエラー
- lint/type/test/build エラーを自動修正

## 手順
1. PR番号が指定...

