# コミット分割コマンド

Gitの差分をもとに適切にコミットを分割します。ファイル単位や機能単位で論理的にコミットを分けることで、レビューしやすく意味のあるコミット履歴を作成します。

## 使用方法
```bash
/commit-split [ベースブランチ] [分割方式]
```

### パラメータ
- `ベースブランチ`: 比較対象のブランチ（省略時は`master`または`main`を自動検出）
- `分割方式`: `file`（ファイル単位）、`feature`（機能単位）、`interactive`（インタラクティブ）

## 処理手順
1. 現在の変更状況を確認
2. 差分の分析と分割方針の決定
3. インタラクティブな分割実行
4. 各コミットの作成と確認

## 実装

### ステップ1: 初期状態の確認
```bash
# 作業ディレクトリの状態を確認
echo "📊 現在の作業状況を確認中..."
git status --porcelain

# ステージされていない変更があるかチェック
UNSTAGED_CHANGES=$(git diff --name-only)
STAGED_CHANGES=$(git diff --cached --name-only)

if [ -n "$UNSTAGED_CHANGES" ] || [ -n "$STAGED_CHANGES" ]; then
    echo "⚠️  未コミットの変更があります"
    echo "📝 ステージされていない変更: $(echo "$UNSTAGED_CHANGES" | wc -l) ファイル"
    echo "📝 ステージされた変更: $(echo "$STAGED_CHANGES" | wc -l) ファイル"
else
    echo "✅ 作業ディレクトリはクリーンです"
    exit 0
fi
```

### ステップ2: ベースブランチの決定
```bash
# ベースブランチの自動検出または指定
BASE_BRANCH="${1:-}"
if [ -z "$BASE_BRANCH" ]; then
    if git show-ref --verify --quiet refs/heads/master; then
        BASE_BRANCH="master"
    elif git show-ref --verify --quiet refs/heads/main; then
        BASE_BRANCH="main"
    else
        echo "❌ ベースブランチを特定できません。明示的に指定してください。"
        exit 1
    fi
fi

echo "🎯 ベースブランチ: $BASE_BRANCH"

# ベースブランチとの差分を確認
CURRENT_BRANCH=$(git branch --show-current)
echo "🌿 現在のブランチ: $CURRENT_BRANCH"
```

### ステップ3: 差分の分析
```bash
# 変更されたファイルの一覧と統計
echo "📈 差分の分析中..."
CHANGED_FILES=$(git diff --name-only $BASE_BRANCH..HEAD 2>/dev/null || git diff --name-only)

if [ -z "$CHANGED_FILES" ]; then
    echo "📝 ベースブランチとの差分がありません"
    # 作業ディレクトリの変更のみ処理
    CHANGED_FILES=$(git diff --name-only)
    if [ -z "$CHANGED_FILES" ]; then
        CHANGED_FILES=$(git diff --cached --name-only)
    fi
fi

echo "📁 変更されたファイル一覧:"
echo "$CHANGED_FILES" | nl

# ファイルタイプ別の分類
DOCS_FILES=$(echo "$CHANGED_FILES" | grep -E '\.(md|txt|rst)$' || true)
CONFIG_FILES=$(echo "$CHANGED_FILES" | grep -E '\.(json|yaml|yml|toml|ini|conf)$' || true)
CODE_FILES=$(echo "$CHANGED_FILES" | grep -E '\.(js|ts|py|go|rs|java|c|cpp|php|rb)$' || true)
TEST_FILES=$(echo "$CHANGED_FILES" | grep -E '(test|spec)\.' || true)

echo ""
echo "📊 ファイルタイプ別統計:"
[ -n "$DOCS_FILES" ] && echo "📖 ドキュメント: $(echo "$DOCS_FILES" | wc -l) ファイル"
[ -n "$CONFIG_FILES" ] && echo "⚙️  設定ファイル: $(echo "$CONFIG_FILES" | wc -l) ファイル"
[ -n "$CODE_FILES" ] && echo "💻 コードファイル: $(echo "$CODE_FILES" | wc -l) ファイル"
[ -n "$TEST_FILES" ] && echo "🧪 テストファイル: $(echo "$TEST_FILES" | wc -l) ファイル"
```

### ステップ4: 分割方式の決定
```bash
SPLIT_MODE="${2:-file}"

case "$SPLIT_MODE" in
    "file")
        echo "📂 ファイル単位での分割を実行します"
        commit_by_file
        ;;
    "feature")
        echo "🎯 機能単位での分割を実行します"
        commit_by_feature
        ;;
    "interactive"|*)
        echo "🤝 インタラクティブ分割を実行します"
        commit_interactive
        ;;
esac
```

### ステップ5: ファイル単位分割の実装
```bash
commit_by_file() {
    echo "$CHANGED_FILES" | while read -r file; do
        if [ -n "$file" ]; then
            echo ""
            echo "📝 処理中: $file"
            
            # ファイルの変更内容を表示
            git diff --stat "$file" 2>/dev/null || git diff --cached --stat "$file" 2>/dev/null || true
            
            # コミットメッセージの自動生成
            FILE_EXT="${file##*.}"
            DIR_NAME=$(dirname "$file")
            FILE_NAME=$(basename "$file")
            
            # ファイルタイプに基づいたプレフィックス
            if echo "$file" | grep -q -E '\.(md|txt|rst)$'; then
                PREFIX="docs"
            elif echo "$file" | grep -q -E '\.(json|yaml|yml|toml|ini|conf)$'; then
                PREFIX="config"
            elif echo "$file" | grep -q -E '(test|spec)\.'; then
                PREFIX="test"
            else
                PREFIX="feat"
            fi
            
            COMMIT_MSG="$PREFIX: update $FILE_NAME"
            
            # 自動でコミット（確認なし）
            echo "💬 提案されたコミットメッセージ: $COMMIT_MSG"
            git add "$file"
            git commit -m "$COMMIT_MSG"
            echo "✅ コミット完了: $file"
        fi
    done
}
```

### ステップ6: 機能単位分割の実装
```bash
commit_by_feature() {
    # ディレクトリ構造に基づいた機能別グループ化
    echo "🔍 機能別にファイルをグループ化中..."
    
    # ディレクトリごとにファイルをグループ化
    DIRECTORIES=$(echo "$CHANGED_FILES" | xargs dirname | sort | uniq)
    
    echo "$DIRECTORIES" | while read -r dir; do
        if [ -n "$dir" ]; then
            DIR_FILES=$(echo "$CHANGED_FILES" | grep "^$dir/")
            
            if [ -n "$DIR_FILES" ]; then
                echo ""
                echo "📁 ディレクトリ: $dir"
                echo "$DIR_FILES" | sed 's/^/  - /'
                
                # ディレクトリ名に基づいたコミットメッセージ
                case "$dir" in
                    "src"|"lib"|"app")
                        PREFIX="feat"
                        ;;
                    "test"|"tests"|"__tests__")
                        PREFIX="test"
                        ;;
                    "docs"|"doc")
                        PREFIX="docs"
                        ;;
                    "config"|".github")
                        PREFIX="config"
                        ;;
                    *)
                        PREFIX="update"
                        ;;
                esac
                
                COMMIT_MSG="$PREFIX: update $dir module"
                
                echo "💬 提案されたコミットメッセージ: $COMMIT_MSG"
                echo "$DIR_FILES" | xargs git add
                git commit -m "$COMMIT_MSG"
                echo "✅ コミット完了: $dir"
            fi
        fi
    done
}
```

### ステップ7: インタラクティブ分割の実装
```bash
commit_interactive() {
    echo "🎮 自動モードでコミットを分割します"
    
    # 現在の状態を確認
    REMAINING_UNSTAGED=$(git diff --name-only)
    REMAINING_STAGED=$(git diff --cached --name-only)
    
    if [ -z "$REMAINING_UNSTAGED" ] && [ -z "$REMAINING_STAGED" ]; then
        echo "📝 変更がありません"
        return
    fi
    
    # 全ファイルをステージして一度にコミット
    git add .
    commit_staged_changes
    
    echo "🎉 すべての変更が処理されました！"
}

select_files_for_staging() {
    ALL_CHANGED=$(git status --porcelain | awk '{print $2}')
    if [ -z "$ALL_CHANGED" ]; then
        echo "📝 変更されたファイルがありません"
        return
    fi
    
    echo "📁 変更されたファイル一覧:"
    echo "$ALL_CHANGED" | nl
    echo ""
    
    # 全ファイルを自動でステージ
    echo "$ALL_CHANGED" | while read -r file; do
        if [ -n "$file" ]; then
            git add "$file"
            echo "✅ ステージ完了: $file"
        fi
    done
}

commit_staged_changes() {
    STAGED=$(git diff --cached --name-only)
    if [ -z "$STAGED" ]; then
        echo "📦 ステージされた変更がありません"
        return
    fi
    
    echo "📦 ステージされたファイル:"
    echo "$STAGED" | sed 's/^/  - /'
    echo ""
    
    # 自動でコミット
    commit_msg="update: staged changes"
    git commit -m "$commit_msg"
    echo "✅ コミット完了！"
}

show_diff_summary() {
    echo "📊 変更サマリー:"
    git diff --stat
    echo ""
    git diff --cached --stat
    echo ""
    # 詳細な差分を自動的に表示
    echo "📖 詳細な差分:"
    git diff
    git diff --cached
}

auto_push_changes() {
    # 現在のブランチ名を取得
    CURRENT_BRANCH=$(git branch --show-current)
    
    echo "📤 リモートブランチにプッシュ中..."
    
    # リモートブランチが存在するかチェック
    if git ls-remote --heads origin "$CURRENT_BRANCH" | grep -q "$CURRENT_BRANCH"; then
        # リモートブランチが存在する場合は通常のpush
        git push
        if [ $? -eq 0 ]; then
            echo "✅ プッシュ完了: $CURRENT_BRANCH"
        else
            echo "⚠️  プッシュでエラーが発生しました"
        fi
    else
        # リモートブランチが存在しない場合は -u オプション付きでpush
        git push -u origin "$CURRENT_BRANCH"
        if [ $? -eq 0 ]; then
            echo "✅ 新しいブランチを作成してプッシュ完了: $CURRENT_BRANCH"
        else
            echo "⚠️  プッシュでエラーが発生しました"
        fi
    fi
}

show_help() {
    echo "📚 コミット分割ヘルプ"
    echo ""
    echo "🎯 目的: 大きな変更を論理的に分割して複数のコミットに分ける"
    echo ""
    echo "💡 推奨される分割方針:"
    echo "  - 📁 ファイルタイプ別（設定、ドキュメント、コード、テスト）"
    echo "  - 🎯 機能別（新機能、バグ修正、リファクタリング）"
    echo "  - 📦 影響範囲別（フロントエンド、バックエンド、DB）"
    echo ""
    echo "🔧 便利なGitコマンド:"
    echo "  - git add -p : パッチ単位での選択的ステージング"
    echo "  - git diff --cached : ステージされた変更の確認"
    echo "  - git reset <file> : ファイルのアンステージ"
    echo "  - git status : 現在の状態確認"
    echo ""
    echo "📤 プッシュ機能:"
    echo "  - 各コミット後に個別でプッシュするか選択可能"
    echo "  - 最終処理で全てのコミットを一括プッシュ"
}
```

### ステップ8: 完了処理とプッシュ
```bash
# 最終確認と統計
echo ""
echo "🎉 コミット分割が完了しました！"
echo ""
echo "📈 作成されたコミット:"
git log --oneline -10

echo ""
echo "📤 自動プッシュを実行します..."

# 現在のブランチ名を取得
CURRENT_BRANCH=$(git branch --show-current)

# リモートブランチが存在するかチェック
if git ls-remote --heads origin "$CURRENT_BRANCH" | grep -q "$CURRENT_BRANCH"; then
    # リモートブランチが存在する場合は通常のpush
    git push
    echo "✅ プッシュ完了: $CURRENT_BRANCH"
else
    # リモートブランチが存在しない場合は -u オプション付きでpush
    git push -u origin "$CURRENT_BRANCH"
    echo "✅ 新しいブランチを作成してプッシュ完了: $CURRENT_BRANCH"
fi

echo ""
echo "🚀 すべてのコミットがリモートに反映されました！"
```

## 重要なルール
- **段階的なコミット**: 関連する変更をまとめて、レビューしやすい単位でコミット
- **意味のあるメッセージ**: 各コミットが何を変更したかを明確に記述
- **ファイルタイプの考慮**: 設定ファイル、ドキュメント、コード、テストを適切に分離
- **レビュー性の向上**: 1つのコミットで1つの論理的変更を実現
- **自動プッシュ**: 各コミット後にプッシュ選択可能、最終的に全コミットをリモートに反映

## 使用例

### ファイル単位での分割
```bash
/commit-split master file
```

### 機能単位での分割  
```bash
/commit-split main feature
```

### インタラクティブ分割
```bash
/commit-split
```

## 注意事項
- 実行前に重要な変更はバックアップを取ってください
- `git add -p` を使用する際は、パッチの内容をよく確認してください
- 各コミット後にプッシュするかどうかを選択できます
- 最終的にすべてのコミットがリモートに反映されます
- リモートにプッシュ済みのコミットは分割しないでください