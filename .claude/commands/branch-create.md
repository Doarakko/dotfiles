# ブランチ作成コマンド

新しいフィーチャーブランチを作成します。

## 使用方法
```bash
/branch-create [ブランチ名]
```

## ブランチ命名規則
- [Conventional Branch](https://conventional-branch.github.io/) に従う
- 形式: `feature/[FeatureName]-[実装した機能名]`
- 例: `feature/admin-user-role-edit-invite-form`

## 処理手順
1. 現在の変更をstashして保存
2. メインブランチから新しいブランチを作成
3. stashした変更を適用
4. ブランチの作成完了を確認

## 実装
```bash
# 現在の変更をstashに保存
echo "💾 現在の変更をstashに保存中..."
git stash push -m "branch-create: temporary stash before creating new branch"

# メインブランチに移動してリモートから最新を取得
echo "🔄 メインブランチから最新の変更を取得中..."
git checkout master 2>/dev/null || git checkout main
git pull origin master 2>/dev/null || git pull origin main

# 新しいブランチを作成
BRANCH_NAME="$1"
if [ -z "$BRANCH_NAME" ]; then
    echo "❌ ブランチ名を指定してください"
    echo "使用方法: /branch-create feature/your-feature-name"
    exit 1
fi

echo "🌿 新しいブランチを作成中: $BRANCH_NAME"
git checkout -b "$BRANCH_NAME"

# stashした変更を適用
echo "📥 stashした変更を適用中..."
git stash pop

echo "✅ ブランチ作成完了: $BRANCH_NAME"
echo "📋 次のステップ:"
echo "1. 必要な変更を実装"
echo "2. /commit-create でコミット作成"
echo "3. /push-current でリモートにpush"
```

## 注意事項
- ブランチ名は意味のある名前にしてください
- feature/ プレフィックスを使用してください
- 既存のブランチ名と重複しないよう注意してください
