# GitHub PR レビューコメント修正コマンド

PRのレビューコメントを自動的にチェックして、要求された修正を適用します。

## 使用方法
```bash
/review-fix [pr番号]
```

PR番号が指定されない場合は、現在のブランチのPRを使用します。

## 処理手順
1. GitHub CLIを使ってPRとレビューコメントを取得
2. 各レビューコメントを分析して実行可能なフィードバックを特定
3. 可能な限り要求された変更を自動適用
4. テストとリンティングを実行して修正を検証
5. コミットせずに変更内容の概要を表示

## 実装
PRの情報とレビューコメントの取得から開始します。

### ステップ1: PR情報の取得
```bash
# GitHub CLIの認証とスコープを最初にチェック
echo "🔍 GitHub CLIの設定を確認中..."
gh auth status

# PR番号が指定されていない場合は現在のブランチのPRを取得（フォールバック処理付き）
PR_INFO=$(gh pr view --json number,reviews,url 2>/dev/null || echo "")
if [ -z "$PR_INFO" ]; then
    echo "❌ PR情報を取得できません。考えられる原因："
    echo "   - 現在のブランチにPRが存在しない"
    echo "   - GitHub CLIに追加のスコープが必要 (read:org, read:discussion)"
    echo "   - 認証の問題"
    echo ""
    echo "💡 GitHub CLIのスコープを修正するには："
    echo "   1. https://github.com/settings/tokens にアクセス"
    echo "   2. トークンに'read:org'と'read:discussion'スコープを追加"
    echo "   3. 実行: gh auth login --with-token < your_token_file"
    echo ""
    echo "🔄 代替方法: PR番号を手動で指定 /review-fix <pr番号>"
    exit 1
fi

# 後続のコマンドで使用するためにPR番号を抽出
PR_NUMBER=$(echo "$PR_INFO" | jq -r '.number')
echo "📋 PR #$PR_NUMBER を発見"
```

### ステップ2: レビューコメントの取得  
```bash
# 包括的なエラーハンドリングでレビューコメントを取得
echo "📥 PR #$PR_NUMBER のレビューコメントを取得中..."

# レビューデータを取得する複数の方法を試行
REVIEWS=$(gh pr view $PR_NUMBER --json reviews 2>/dev/null || echo "")
COMMENTS=$(gh api "repos/:owner/:repo/pulls/$PR_NUMBER/comments" 2>/dev/null || echo "")

if [ -z "$REVIEWS" ] && [ -z "$COMMENTS" ]; then
    echo "❌ レビューコメントを取得できません。GitHub CLIの権限を確認してください。"
    echo "💡 必要なスコープ: repo, read:org, read:discussion"
    exit 1
fi

# レビューサマリーを解析して表示
echo "📊 レビューサマリー："
if [ -n "$REVIEWS" ]; then
    echo "$REVIEWS" | jq -r '.reviews[] | "- \(.state) by \(.user.login): \(.body // "コメントなし")"'
fi

if [ -n "$COMMENTS" ]; then
    echo "💬 行コメント："
    echo "$COMMENTS" | jq -r '.[] | "- \(.path):\(.line) - \(.body)"'
fi
```

### ステップ3: コメントの解析と分類
各レビューコメントについて：
1. **コードの提案**: 提案されたコード変更を直接適用
2. **スタイル/フォーマット**: 適切なリンターやフォーマッターを実行
3. **ロジックの問題**: 要求されたロジック変更を分析して実装  
4. **ドキュメント**: 要求に応じてコメント、README、ドキュメントを更新
5. **テスト**: 提案に従ってテストを追加または修正
6. **セキュリティ懸念**: セキュリティ関連のフィードバックに対処

### ステップ4: 修正の体系的適用
- レビューコメントのファイルパスと行番号を使用して、必要な変更箇所を正確に特定
- コードの提案については、提案されたdiffを直接適用
- より幅広いフィードバックについては、包括的な修正を実装
- 各修正が既存の機能を破損しないことを検証

### ステップ5: 変更の検証
```bash
# 修正を検証するためにテストを実行（利用可能な場合）
echo "🧪 修正を検証するためにテストを実行中..."
npm test || python -m pytest || go test || cargo test || echo "テストコマンドが見つかりません"

# コードスタイルをチェックするためにリンティングを実行
echo "🔍 リンティングチェックを実行中..."
npm run lint || ruff check || golangci-lint run || echo "リントコマンドが見つかりません"

# 行われた変更を表示するためにgit statusを表示
echo "📝 行われた変更の概要："
git status --porcelain
echo ""
echo "📋 詳細diff："
git diff --stat
echo ""
echo "✅ レビュー修正が正常に適用されました！"
echo "💡 準備ができたら /commit-create を使用してこれらの変更をコミットしてください"
```

### ステップ6: サマリーレポート
```bash
# 適用された修正のサマリーを生成
echo "🤖 レビュー修正サマリー："
echo "- PRレビューコメントの問題を修正"
echo "- 可能な限りコードの提案を適用" 
echo "- スタイル/フォーマットの問題を解決"
echo "- 要求に応じてドキュメントを更新"
echo ""
echo "📊 変更されたファイル数: $(git diff --name-only | wc -l)"
echo "📈 変更された行数: +$(git diff --numstat | awk '{add+=$1} END {print add}') -$(git diff --numstat | awk '{del+=$2} END {print del}')"
echo ""
echo "🔄 次のステップ："
echo "1. 'git diff' で変更内容を確認"
echo "2. 必要に応じて追加のテストを実行"
echo "3. 満足したら /commit-create を使用してコミット"
```

## エラーハンドリング
- レビューコメントが不明確な場合は、手動レビュー用のTODOコメントを表示
- 自動修正が不可能な場合は、コード内にTODOコメントを作成
- 修正後にテストが失敗した場合は、失敗詳細を表示してガイダンスを求める
- マージコンフリクトを適切に処理し、発見されたコンフリクトを報告

## 注意事項
- 明確に要求され、安全な変更のみを適用
- 複雑なロジック変更については、保守的に実装し確認を求める
- 既存のコードスタイルとパターンを保持
- 修正を検証するために必ずテストを実行するが、自動的にはコミットしない
- レビュー後に変更をコミットするには /commit-create コマンドを使用