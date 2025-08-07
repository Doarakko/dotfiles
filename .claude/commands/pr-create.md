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
    echo "📝 PR説明を生成中..."
    
    # mainブランチからの変更履歴を取得
    COMMITS=$(git log --oneline master..$CURRENT_BRANCH 2>/dev/null || git log --oneline main..$CURRENT_BRANCH 2>/dev/null || git log --oneline -5)
    
    # 変更されたファイルの一覧を取得
    CHANGED_FILES=$(git diff --name-only master..$CURRENT_BRANCH 2>/dev/null || git diff --name-only main..$CURRENT_BRANCH 2>/dev/null || git diff --name-only HEAD~5..HEAD)
    
    if [ -n "$PR_TEMPLATE_FILE" ]; then
        echo "📋 PRテンプレートをベースに説明を生成します"
        # PRテンプレートをベースとして使用
        PR_BODY=$(cat "$PR_TEMPLATE_FILE")
        
        # テンプレート内の特定のプレースホルダーを置換
        # 概要セクションに変更内容を自動挿入
        if echo "$PR_BODY" | grep -q "## 概要\|## Overview\|## Summary"; then
            # 概要セクションの後に変更内容を挿入
            PR_BODY=$(echo "$PR_BODY" | sed '/## 概要\|## Overview\|## Summary/a\\n**このPRの主な変更:**')
            if [ -n "$COMMITS" ]; then
                COMMIT_LIST=""
                echo "$COMMITS" | while read commit; do
                    COMMIT_LIST="$COMMIT_LIST- $commit\n"
                done
                PR_BODY="$PR_BODY\n$COMMIT_LIST"
            fi
        fi
        
        # 変更されたファイルの情報を追加（テンプレートに該当セクションがない場合）
        if ! echo "$PR_BODY" | grep -q "変更.*ファイル\|Changed.*Files\|Files.*Changed"; then
            if [ -n "$CHANGED_FILES" ]; then
                PR_BODY="$PR_BODY\n\n## 変更されたファイル\n"
                echo "$CHANGED_FILES" | while read file; do
                    PR_BODY="$PR_BODY- $file\n"
                done
            fi
        fi
    else
        echo "📝 デフォルト形式でPR説明を生成します"
        # PRテンプレートがない場合のデフォルト形式
        PR_BODY="## 概要\n\nこの変更の目的と概要を記述してください\n\n"
        
        if [ -n "$COMMITS" ]; then
            PR_BODY="$PR_BODY## 変更一覧\n"
            echo "$COMMITS" | while read commit; do
                PR_BODY="$PR_BODY- $commit\n"
            done
            PR_BODY="$PR_BODY\n"
        fi
        
        if [ -n "$CHANGED_FILES" ]; then
            PR_BODY="$PR_BODY## 変更されたファイル\n"
            echo "$CHANGED_FILES" | while read file; do
                PR_BODY="$PR_BODY- $file\n"
            done
            PR_BODY="$PR_BODY\n"
        fi
        
        PR_BODY="$PR_BODY## テスト計画\n- [ ] 手動テスト実行\n- [ ] 自動テスト確認\n\n## チェックリスト\n- [ ] コードレビュー準備完了\n- [ ] ドキュメント更新（必要に応じて）\n- [ ] 破壊的変更の確認"
    fi
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
# bodyにHTMLコメントが含まれる場合の対応
PR_BODY_FILE=$(mktemp)
echo -e "$PR_BODY" > "$PR_BODY_FILE"
gh pr create --draft --title "$PR_TITLE" --body-file "$PR_BODY_FILE"
rm -f "$PR_BODY_FILE"

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
- **PRテンプレートをベースに使用**: `.github/PULL_REQUEST_TEMPLATE.md` が存在する場合は、その構造を基本として使用し、変更内容を自動で挿入
- **適切なpush**: `git push -u origin <branch_name>` のように `--set-upstream` を指定
- **意味のあるタイトル**: コミットメッセージや機能の概要を反映

## PRテンプレート活用の詳細
- **テンプレートがある場合**: テンプレートの構造を維持し、概要セクションに変更内容を自動挿入
- **テンプレートがない場合**: デフォルトの構造（概要、変更一覧、テスト計画、チェックリスト）を使用
- **多言語対応**: 英語・日本語の一般的なセクション名に対応（Overview/概要、Summary/概要、Changed Files/変更されたファイル）

## 注意事項
- PRテンプレートの既存構造を尊重し、必要な項目は自動補完します
- コミットメッセージは意味のある内容にしてください
- 破壊的変更がある場合は説明に明記してください
- レビュアーの追加は手動で行ってください