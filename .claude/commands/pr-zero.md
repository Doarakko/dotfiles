# Git Full Workflow - ブランチ作成からPR作成まで

ブランチ作成、コミット分割、PR作成を一連で実行するワークフロー

## 実行手順

### 1. ブランチ作成
- ブランチ名は [Conventional Branch](https://conventional-branch.github.io/) に従う
- feature/[FeatureName]-[実装した機能名] の形式
- 例: `feature/admin-user-role-edit-invite-form`
- 現在の変更をstashしてから新しいブランチを作成

### 2. 変更内容の確認と分析
- `git status` で変更ファイルを確認
- `git diff` で変更内容を確認
- 論理的な単位で複数のコミットに分割する計画を立てる

### 3. コミット分割と作成
- 関連する変更をグループ化して段階的にコミット
- [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) に従う
- type(scope): subject の形式（例: feat(auth): add user login validation）
- タイトルは50文字以内、本文は72文字程度で改行
- 動詞は原形を使用（add, fix, updateなど）
- コミットメッセージは小文字で始める

### 4. プッシュとPR作成
- `git push -u origin <branch_name>` でプッシュ
- GitHub CLI認証状態を確認
- プライベートリポジトリの場合、認証エラー時はフォールバック処理を実行
- PRテンプレートの確認：
  - 以下の順序で検索：
    1. `.github/PULL_REQUEST_TEMPLATE.md`
    2. `.github/pull_request_template.md`
    3. `.github/PULL_REQUEST_TEMPLATE/*.md`
    4. `find . -name "*PULL_REQUEST_TEMPLATE*" -o -name "*pull_request_template*"`
  - テンプレートが存在する場合は、その構造をベースとして使用
  - 概要セクション（## 概要/## Overview/## Summary）に変更内容を自動挿入
  - 変更ファイル情報も適切なセクションに追加
- `gh pr create --draft` でドラフトPRを作成
- 認証エラーの場合、手動PR作成URLを提供

## パラメータ
- branch_name: 作成するブランチ名（feature/で始まる）
- commit_strategy: auto（自動分割）または manual（手動確認）

## 注意事項
- 実装とテストが含まれる場合、typeはfeat/fixを優先
- PRはDraftで作成し、レビュー準備ができてからDraftを外す
- コミット分割は論理的な変更単位を意識する
- プライベートリポジトリでは認証スコープ不足時に自動フォールバック
- GitHub CLIエラー時は手動PR作成用のURLを提供する
- PRテンプレートがある場合は、既存の構造を尊重しつつ必要な情報を自動補完
- 多言語対応：英語・日本語の一般的なセクション名に対応

## エラーハンドリング
### GitHub CLI認証エラー
- プライベートリポジトリで "Could not resolve to a Repository" エラーが発生した場合
- 以下の手動PR作成URLを提供：
  `https://github.com/{owner}/{repo}/compare/{base}...{branch}`
- 必要に応じて認証の再設定を案内

### 認証スコープ不足
- GITHUB_TOKEN環境変数使用時は、十分なスコープ(repo, read:org)が必要
- 環境変数未設定の場合は `gh auth refresh -s repo,read:org` で再認証