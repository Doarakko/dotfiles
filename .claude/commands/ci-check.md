# GitHub PR CI チェックコマンド

現在のブランチのPRのCI状態をチェックし、失敗の詳細を取得します。

## 使用方法
```bash
/ci-check
```

## 処理手順
1. 現在のブランチ名を取得
2. このブランチに関連するPRを検索
3. GitHub CLIを使用してCI状態をチェック
4. 失敗したチェックの詳細を表示
5. 失敗したチェックのログを表示

## 実装
まず、`git branch --show-current` を使用して現在のブランチを取得します。

### ステップ1: 現在のブランチとPRの取得
```bash
# 現在のブランチ名を取得
CURRENT_BRANCH=$(git branch --show-current)
echo "🌿 現在のブランチ: $CURRENT_BRANCH"

# このブランチのPRを検索
echo "🔍 ブランチに関連するPRを検索中..."
PR_INFO=$(gh pr list --head "$CURRENT_BRANCH" --json number,title,url 2>/dev/null)

if [ -z "$PR_INFO" ] || [ "$PR_INFO" = "[]" ]; then
    echo "❌ 現在のブランチ ($CURRENT_BRANCH) に関連するPRが見つかりません"
    echo "💡 まずPRを作成してください: /pr-create"
    exit 1
fi

PR_NUMBER=$(echo "$PR_INFO" | jq -r '.[0].number')
PR_TITLE=$(echo "$PR_INFO" | jq -r '.[0].title')
PR_URL=$(echo "$PR_INFO" | jq -r '.[0].url')

echo "📋 PR情報:"
echo "  番号: #$PR_NUMBER"
echo "  タイトル: $PR_TITLE"
echo "  URL: $PR_URL"
```

### ステップ2: CI チェック状態の取得
```bash
# PRのチェック状態を取得
echo "🔍 CI チェック状態を確認中..."
CHECK_RUNS=$(gh pr checks "$PR_NUMBER" 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "❌ CI チェック情報を取得できませんでした"
    echo "💡 GitHub CLIの権限を確認してください"
    exit 1
fi

echo "$CHECK_RUNS"
```

### ステップ3: 失敗したチェックの詳細分析
```bash
# 失敗したチェックを特定
echo "🔍 失敗したチェックの詳細を分析中..."

# チェック結果を解析して失敗したものを特定
FAILED_CHECKS=$(echo "$CHECK_RUNS" | grep -E "(fail|error|✗)" || echo "")

if [ -z "$FAILED_CHECKS" ]; then
    echo "✅ すべてのCIチェックが成功しています！"
    echo "🎉 PRの準備が整いました"
    exit 0
fi

echo "❌ 失敗したチェック:"
echo "$FAILED_CHECKS"
echo ""

# 失敗したワークフローの詳細ログを取得
echo "📋 失敗の詳細ログ:"
WORKFLOW_RUNS=$(gh run list --branch "$CURRENT_BRANCH" --json databaseId,status,conclusion,name --limit 5)
echo "$WORKFLOW_RUNS" | jq -r '.[] | select(.conclusion == "failure") | "- \(.name): \(.conclusion)"'
```

### ステップ4: 失敗の種類別分析と提案
```bash
# 一般的な失敗パターンを分析
echo ""
echo "🔧 よくある修正方法:"

if echo "$FAILED_CHECKS" | grep -qi "lint"; then
    echo "📝 リンティングエラー:"
    echo "  - /ci-fix を実行して自動修正を試行"
    echo "  - npm run lint または該当するlintコマンドを実行"
fi

if echo "$FAILED_CHECKS" | grep -qi "test"; then
    echo "🧪 テストエラー:"
    echo "  - ローカルでテストを実行: npm test"
    echo "  - 失敗したテストを確認して修正"
fi

if echo "$FAILED_CHECKS" | grep -qi "build"; then
    echo "🏗️ ビルドエラー:"
    echo "  - 依存関係を確認: npm install"
    echo "  - TypeScriptエラーを確認"
fi

if echo "$FAILED_CHECKS" | grep -qi "security"; then
    echo "🔒 セキュリティ問題:"
    echo "  - 依存関係の脆弱性を確認"
    echo "  - npm audit fix を実行"
fi

echo ""
echo "🔄 次のステップ:"
echo "1. 上記の提案に従って問題を修正"
echo "2. /ci-fix を使用して自動修正を試行"
echo "3. 修正後に再度このコマンドで確認"
```

## 表示形式
結果を明確な形式で表示:
- 現在のブランチと関連PR
- 全体的なCI状態
- 失敗したチェック名
- エラーメッセージとログ
- よくある修正方法の提案

現在のブランチにPRが存在しない場合は、まずPRを作成するよう提案します。

## 注意事項
- GitHub CLIの認証が必要です
- プライベートリポジトリでは適切な権限が必要です
- CI システムが設定されている場合のみ有効です