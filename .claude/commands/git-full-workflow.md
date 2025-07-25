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
- `gh pr create --draft` でドラフトPRを作成
- .github/PULL_REQUEST_TEMPLATE.md に従ってPR本文を作成

## パラメータ
- branch_name: 作成するブランチ名（feature/で始まる）
- commit_strategy: auto（自動分割）または manual（手動確認）

## 注意事項
- 実装とテストが含まれる場合、typeはfeat/fixを優先
- PRはDraftで作成し、レビュー準備ができてからDraftを外す
- コミット分割は論理的な変更単位を意識する