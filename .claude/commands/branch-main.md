# メインブランチ最新化コマンド

メインブランチ（main/master）に移動して最新の状態に更新します。

## 使用方法
```bash
/branch-main
```

## 動作
1. メインブランチ名を自動検出（main または master）
2. 作業中の変更を確認し、あれば自動的にstashで一時保存
3. メインブランチに切り替え
4. リモートから最新の変更を取得（pull）
5. stashした変更を自動復元
6. 更新後の状態を表示

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
STASH_NEEDED=false
if ! git diff-index --quiet HEAD -- 2>/dev/null || [ -n "$(git ls-files --others --exclude-standard)" ]; then
    echo ""
    echo "📝 未コミットの変更を検出しました"
    echo ""
    echo "💡 変更内容:"
    git status --short
    echo ""
    echo "🔄 変更を一時保存（stash）します..."
    
    # stashにメッセージ付きで保存
    STASH_MSG="Auto-stash by branch-main command from $CURRENT_BRANCH"
    if git stash push -m "$STASH_MSG" --include-untracked; then
        STASH_NEEDED=true
        echo "✅ 変更を一時保存しました"
    else
        echo "❌ 変更の一時保存に失敗しました"
        exit 1
    fi
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
    
    # stashした変更を復元
    if [ "$STASH_NEEDED" = true ]; then
        echo ""
        echo "🔄 一時保存した変更を復元中..."
        if git stash pop; then
            echo "✅ 変更を復元しました"
            echo ""
            echo "📝 復元された変更:"
            git status --short
        else
            echo "⚠️  変更の復元中にコンフリクトが発生しました"
            echo ""
            echo "💡 手動で解決してください:"
            echo "1. コンフリクトのあるファイルを編集"
            echo "2. git add <ファイル名> でステージング"
            echo "3. git stash drop で不要なstashを削除"
            echo ""
            echo "📋 stashリストを確認: git stash list"
        fi
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
    
    # エラーが発生してもstashした変更を復元
    if [ "$STASH_NEEDED" = true ]; then
        echo ""
        echo "🔄 一時保存した変更を復元中..."
        if git stash pop; then
            echo "✅ 変更を復元しました"
        else
            echo "⚠️  変更の復元中にコンフリクトが発生しました"
            echo "📋 stashリストを確認: git stash list"
        fi
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
- **自動stash機能**: 未コミットの変更を自動的に一時保存・復元
- **追跡ファイル対応**: 新規ファイル（untracked）も含めてstash
- **わかりやすい状態表示**: 更新後の状態と元のブランチとの差分を表示
- **視覚的なフィードバック**: 絵文字を使用した進行状況の表示
- **エラーハンドリング**: 各ステップでの適切なエラー処理とstash復元

## 注意事項
- 作業中の変更は自動的にstashされ、更新後に復元されます
- stash復元時にコンフリクトが発生した場合は手動解決が必要です
- 異なるブランチから実行した場合、元のブランチに戻る方法を表示します
- 更新後は必要に応じて新しいブランチを作成して作業を開始してください

## 関連コマンド
- `/branch-create`: 新しいブランチを作成
- `/branch-switch`: ブランチを切り替え
- `/commit`: 変更をコミット
- `/push-current`: 現在のブランチをプッシュ