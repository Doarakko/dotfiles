# PRゼロからワークフロー

新規ブランチ作成からPR作成までを一連で実行する。

## 使用方法
```
/pr-zero [--from-main]
```
- `--from-main`: メインブランチから新規ブランチ作成
- 省略時: 現在のブランチから新規ブランチ作成

## 重要ルール
**既存ブランチには絶対にpushしない。必ず新規ブランチを作成する。**

## 手順
1. 新規ブランチ作成（Conventional Branch形式）
   - 例: `feature/admin-user-role-edit-invite-form`
2. `git status`、`git diff` で変更確認
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
