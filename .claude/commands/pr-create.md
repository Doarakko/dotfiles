# プルリクエスト作成コマンド

現在のブランチからプルリクエストを作成します。

## 使用方法
```bash
/pr-create [タイトル] [説明]
```

## 処理手順
1. 現在のブランチの変更をpush（まだpushされていない場合）
2. PRテンプレートを読み込み（存在する場合）
3. コミット履歴から適切なタイトルと説明を生成
4. ドラフトPRとして作成
5. PR URLを表示

## 実装

### ステップ1: ブランチの状態確認
```bash
# 現在のブランチ名を取得
CURRENT_BRANCH=$(git branch --show-current)
echo "🌿 現在のブランチ: $CURRENT_BRANCH"

# リモートブランチとの同期状態を確認
git fetch origin

# pushが必要かチェック
UNPUSHED_COMMITS=$(git rev-list --count origin/$CURRENT_BRANCH..$CURRENT_BRANCH 2>/dev/null || echo "new")
if [ "$UNPUSHED_COMMITS" = "new" ] || [ "$UNPUSHED_COMMITS" -gt 0 ]; then
    echo "📤 リモートブランチにpushします..."
    git push -u origin $CURRENT_BRANCH
else
    echo "✅ ブランチは既にpushされています"
fi
```

### ステップ2: PRテンプレートの確認
```bash
# PRテンプレートが存在するかチェック
PR_TEMPLATE_FILE=""
if [ -f ".github/PULL_REQUEST_TEMPLATE.md" ]; then
    PR_TEMPLATE_FILE=".github/PULL_REQUEST_TEMPLATE.md"
    echo "📋 PRテンプレートを発見: $PR_TEMPLATE_FILE"
elif [ -f ".github/pull_request_template.md" ]; then
    PR_TEMPLATE_FILE=".github/pull_request_template.md"
    echo "📋 PRテンプレートを発見: $PR_TEMPLATE_FILE"
else
    echo "📝 PRテンプレートが見つかりません。デフォルトの形式を使用します。"
fi
```

### ステップ3: PRタイトルと説明の生成
```bash
# コミット履歴からタイトルを生成（引数で指定されていない場合）
if [ -z "$1" ]; then
    # 最新のコミットメッセージをタイトルに使用
    PR_TITLE=$(git log -1 --pretty=format:"%s")
    echo "💡 コミットメッセージからタイトルを生成: $PR_TITLE"
else
    PR_TITLE="$1"
    echo "📝 指定されたタイトル: $PR_TITLE"
fi

# PRの説明を生成
if [ -z "$2" ]; then
    # コミット履歴から説明を生成
    echo "📝 PR説明を生成中..."
    
    # mainブランチからの変更履歴を取得
    COMMITS=$(git log --oneline master..$CURRENT_BRANCH 2>/dev/null || git log --oneline main..$CURRENT_BRANCH 2>/dev/null || git log --oneline -5)
    
    PR_BODY="## 概要\n"
    if [ -n "$PR_TEMPLATE_FILE" ]; then
        PR_BODY="$PR_BODY\n$(cat $PR_TEMPLATE_FILE)\n\n"
    fi
    
    PR_BODY="$PR_BODY## 変更一覧\n"
    echo "$COMMITS" | while read commit; do
        PR_BODY="$PR_BODY- $commit\n"
    done
    
    # 変更されたファイルの概要
    CHANGED_FILES=$(git diff --name-only master..$CURRENT_BRANCH 2>/dev/null || git diff --name-only main..$CURRENT_BRANCH 2>/dev/null || git diff --name-only HEAD~5..HEAD)
    if [ -n "$CHANGED_FILES" ]; then
        PR_BODY="$PR_BODY\n## 変更されたファイル\n"
        echo "$CHANGED_FILES" | while read file; do
            PR_BODY="$PR_BODY- $file\n"
        done
    fi
    
    PR_BODY="$PR_BODY\n## テスト計画\n- [ ] 手動テスト実行\n- [ ] 自動テスト確認\n\n## チェックリスト\n- [ ] コードレビュー準備完了\n- [ ] ドキュメント更新（必要に応じて）\n- [ ] 破壊的変更の確認"
else
    PR_BODY="$2"
    echo "📝 指定された説明を使用"
fi
```

### ステップ4: PRの作成
```bash
# ドラフトPRとして作成
echo "🚀 ドラフトPRを作成中..."

# PRを作成（HEREDOCを使用して適切にフォーマット）
gh pr create --draft --title "$PR_TITLE" --body "$(echo -e "$PR_BODY")"

if [ $? -eq 0 ]; then
    echo "✅ ドラフトPRが正常に作成されました！"
    
    # PR URLを取得して表示
    PR_URL=$(gh pr view --json url -q .url)
    echo "🔗 PR URL: $PR_URL"
    
    echo ""
    echo "📋 次のステップ："
    echo "1. PRの内容を確認・編集"
    echo "2. レビュアーを追加"
    echo "3. 準備ができたらドラフト状態を解除"
    echo "4. 必要に応じてラベルやマイルストーンを設定"
else
    echo "❌ PR作成に失敗しました"
    echo "💡 トラブルシューティング："
    echo "- GitHub CLIの認証状態を確認: gh auth status"
    echo "- リポジトリの権限を確認"
    echo "- ブランチが正しくpushされているか確認"
fi
```

## 重要なルール
- **必ずドラフト状態で作成**: コードレビューの準備ができるまでドラフト状態を維持
- **PRテンプレートに従う**: `.github/PULL_REQUEST_TEMPLATE.md` が存在する場合は内容を含める
- **適切なpush**: `git push -u origin <branch_name>` のように `--set-upstream` を指定
- **意味のあるタイトル**: コミットメッセージや機能の概要を反映

## 注意事項
- PRテンプレートが存在する場合は、その形式に従ってください
- コミットメッセージは意味のある内容にしてください
- 破壊的変更がある場合は説明に明記してください
- レビュアーの追加は手動で行ってください