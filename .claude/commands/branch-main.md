# メインブランチ最新化コマンド

メインブランチ（main/master）に移動して最新の状態に更新します。

## 使用方法
```bash
/branch-main
```

## 動作
1. メインブランチ名を自動検出（main または master）
2. 作業中の変更を確認
3. メインブランチに切り替え
4. リモートから最新の変更を取得（pull）
5. 更新後の状態を表示

## 実装

```bash
#!/bin/bash

# メインブランチ名を検出する関数
detect_main_branch() {
    # リモートのメインブランチを確認
    if git ls-remote --heads origin main >/dev/null 2>&1; then
        echo "main"
    elif git ls-remote --heads origin master >/dev/null 2>&1; then
        echo "master"
    else
        # ローカルで確認
        if git show-ref --verify --quiet refs/heads/main; then
            echo "main"
        elif git show-ref --verify --quiet refs/heads/master; then
            echo "master"
        else
            echo ""
        fi
    fi
}

# 現在のブランチ名を取得
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# メインブランチ名を検出
MAIN_BRANCH=$(detect_main_branch)

if [ -z "$MAIN_BRANCH" ]; then
    echo "❌ メインブランチ（main/master）が見つかりません"
    echo ""
    echo "💡 以下を確認してください:"
    echo "- git remote -v でリモート設定を確認"
    echo "- git branch -a でブランチ一覧を確認"
    exit 1
fi

echo "🔄 メインブランチ更新処理を開始します"
echo ""
echo "📌 現在のブランチ: $CURRENT_BRANCH"
echo "🎯 メインブランチ: $MAIN_BRANCH"

# 作業ツリーに変更があるか確認
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo ""
    echo "⚠️  作業ツリーに未コミットの変更があります"
    echo ""
    echo "💡 変更を確認:"
    git status --short
    echo ""
    echo "以下のいずれかを実行してください:"
    echo "- git stash      (変更を一時保存)"
    echo "- git commit -am \"メッセージ\"  (変更をコミット)"
    echo "- git reset --hard  (変更を破棄 ⚠️ 注意)"
    exit 1
fi

# 既にメインブランチにいる場合
if [ "$CURRENT_BRANCH" = "$MAIN_BRANCH" ]; then
    echo ""
    echo "✅ 既に$MAIN_BRANCH ブランチにいます"
else
    # メインブランチに切り替え
    echo ""
    echo "🔀 $MAIN_BRANCH ブランチに切り替え中..."
    if ! git checkout $MAIN_BRANCH; then
        echo "❌ ブランチの切り替えに失敗しました"
        exit 1
    fi
    echo "✅ $MAIN_BRANCH ブランチに切り替えました"
fi

# 最新の変更を取得
echo ""
echo "🌐 リモートから最新の変更を取得中..."
echo ""

if git pull origin $MAIN_BRANCH; then
    echo ""
    echo "✅ メインブランチの更新が完了しました！"
    echo ""
    
    # 更新後の状態を表示
    echo "📊 更新後の状態:"
    echo "- ブランチ: $MAIN_BRANCH"
    echo "- 最新コミット: $(git log -1 --pretty=format:'%h - %s')"
    
    # 元のブランチとの差分を表示（異なるブランチから来た場合）
    if [ "$CURRENT_BRANCH" != "$MAIN_BRANCH" ]; then
        echo ""
        echo "📝 元のブランチ ($CURRENT_BRANCH) との差分:"
        COMMITS_DIFF=$(git rev-list --count $CURRENT_BRANCH..$MAIN_BRANCH)
        if [ "$COMMITS_DIFF" -gt 0 ]; then
            echo "- $MAIN_BRANCH の方が $COMMITS_DIFF コミット進んでいます"
        else
            echo "- 差分はありません"
        fi
        
        echo ""
        echo "💡 元のブランチに戻るには: git checkout $CURRENT_BRANCH"
    fi
else
    echo ""
    echo "❌ 更新中にエラーが発生しました"
    echo ""
    echo "💡 以下を確認してください:"
    echo "- インターネット接続"
    echo "- リモートリポジトリへのアクセス権限"
    echo "- コンフリクトの有無"
    
    # コンフリクトがある場合
    if git status | grep -q "You have unmerged paths"; then
        echo ""
        echo "⚠️  マージコンフリクトが発生しています"
        echo ""
        echo "🔧 コンフリクトのあるファイル:"
        git diff --name-only --diff-filter=U
        echo ""
        echo "📝 解決手順:"
        echo "1. 上記のファイルを編集してコンフリクトを解決"
        echo "2. git add <ファイル名> で解決済みファイルをステージング"
        echo "3. git commit でマージを完了"
    fi
    exit 1
fi

echo ""
echo "💡 次のステップ:"
echo "- ブランチ一覧を確認: git branch"
echo "- 新しいブランチを作成: git checkout -b feature/new-feature"
echo "- 特定のブランチに切り替え: git checkout <ブランチ名>"
```

## 特徴
- **メインブランチ自動検出**: main/masterを自動的に判別
- **自動ブランチ切り替え**: メインブランチへの自動切り替え
- **安全性重視**: 未コミットの変更がある場合は警告
- **わかりやすい状態表示**: 更新後の状態と元のブランチとの差分を表示
- **視覚的なフィードバック**: 絵文字を使用した進行状況の表示
- **エラーハンドリング**: 各ステップでの適切なエラー処理

## 注意事項
- 作業中の変更は事前にコミットまたはstashしてください
- 異なるブランチから実行した場合、元のブランチに戻る方法を表示します
- 更新後は必要に応じて新しいブランチを作成して作業を開始してください

## 関連コマンド
- `/branch-create`: 新しいブランチを作成
- `/branch-switch`: ブランチを切り替え
- `/commit`: 変更をコミット
- `/push-current`: 現在のブランチをプッシュ