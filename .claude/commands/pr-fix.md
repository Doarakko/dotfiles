# GitHub PR 自動修正コマンド

PRのレビューコメント(🚀リアクション付き)とCIエラーを自動的に修正します。

## 使用方法
```bash
/pr-fix [pr番号]
```

PR番号が指定されない場合は、現在のブランチのPRを使用します。

**重要**: 修正したいレビューコメントに🚀リアクションを追加してから実行してください。🚀リアクションがついたコメントのみが修正対象になります。

## 処理手順
1. PRとレビューコメント(🚀リアクション付き)を取得
2. CIの失敗状況を確認
3. レビューコメントの修正を適用
4. CIエラーを修正
5. テストとリンティングを実行して検証
6. コミットせずに変更内容の概要を表示

## 実装

### ステップ1: PR情報の取得
```bash
# PR番号の取得または指定
if [ -z "$1" ]; then
    # 現在のブランチのPRを取得
    CURRENT_BRANCH=$(git branch --show-current)
    echo "🌿 現在のブランチ: $CURRENT_BRANCH"

    PR_INFO=$(gh pr list --head "$CURRENT_BRANCH" --json number 2>/dev/null)
    if [ -z "$PR_INFO" ] || [ "$PR_INFO" = "[]" ]; then
        echo "❌ 現在のブランチにPRが見つかりません"
        echo "💡 /pr-create でPRを作成するか、PR番号を指定してください: /pr-fix <PR番号>"
        exit 1
    fi
    PR_NUMBER=$(echo "$PR_INFO" | jq -r '.[0].number')
else
    PR_NUMBER=$1
fi

echo "📋 PR #$PR_NUMBER を修正します"
echo ""
```

### ステップ2: レビューコメント(🚀リアクション付き)の取得
```bash
echo "🚀 🚀リアクション付きレビューコメントを取得中..."

# PRのレビューコメントを取得
COMMENTS=$(gh api "repos/:owner/:repo/pulls/$PR_NUMBER/comments" 2>/dev/null || echo "")

if [ -z "$COMMENTS" ] || [ "$COMMENTS" = "[]" ]; then
    echo "ℹ️ レビューコメントが見つかりません"
    REVIEW_COMMENTS=""
else
    # 🚀リアクション(rocket)がついたコメントのみを抽出
    REVIEW_COMMENTS=$(echo "$COMMENTS" | jq -r '.[] | select(.reactions.rocket > 0) | {path: .path, line: .position, body: .body, id: .id} | @json')

    if [ -z "$REVIEW_COMMENTS" ]; then
        echo "ℹ️ 🚀リアクションがついたレビューコメントが見つかりません"
        echo "💡 修正したいコメントに🚀リアクションを追加してから再実行してください"
    else
        COMMENT_COUNT=$(echo "$REVIEW_COMMENTS" | wc -l | tr -d ' ')
        echo "📋 🚀リアクション付きコメント: ${COMMENT_COUNT}件"
        echo ""
        echo "$REVIEW_COMMENTS" | jq -r '. | "- \(.path):\(.line) - \(.body)"'
        echo ""
    fi
fi
```

### ステップ3: CIエラーの確認
```bash
echo "🔍 CIエラーを確認中..."

# PRのチェック状態を取得
CHECK_RUNS=$(gh pr checks "$PR_NUMBER" 2>/dev/null || echo "")

if [ -n "$CHECK_RUNS" ]; then
    FAILED_CHECKS=$(echo "$CHECK_RUNS" | grep -E "(fail|error|✗)" || echo "")

    if [ -n "$FAILED_CHECKS" ]; then
        echo "❌ CIエラーが見つかりました:"
        echo "$FAILED_CHECKS"
        echo ""
    else
        echo "✅ CIエラーはありません"
        FAILED_CHECKS=""
    fi
else
    echo "ℹ️ CI情報を取得できませんでした"
    FAILED_CHECKS=""
fi

# 修正対象が何もない場合は終了
if [ -z "$REVIEW_COMMENTS" ] && [ -z "$FAILED_CHECKS" ]; then
    echo "✅ 修正対象が見つかりませんでした"
    exit 0
fi

echo "🔧 修正を開始します..."
echo ""
```

### ステップ4: レビューコメントの修正適用
レビューコメントの種類に応じて適切な修正を実行:

1. **コードの提案**: 提案されたコード変更を直接適用
2. **スタイル/フォーマット**: リンターやフォーマッターを実行
3. **ロジックの問題**: 要求されたロジック変更を実装
4. **ドキュメント**: コメント、README、ドキュメントを更新
5. **テスト**: テストを追加または修正
6. **セキュリティ**: セキュリティ関連の修正を実施

```bash
if [ -n "$REVIEW_COMMENTS" ]; then
    echo "📝 レビューコメントの修正を適用中..."
    echo ""
    echo "以下のレビューコメントを修正してください:"
    echo "$REVIEW_COMMENTS" | jq -r '. | "\(.path):\(.line) - \(.body)"'
    echo ""
    echo "⚠️ 重要な制約:"
    echo "  - コードの品質を保ちながら修正すること"
    echo "  - 既存のコードスタイルに従うこと"
    echo "  - テストが通ることを確認すること"
    echo ""
fi
```

### ステップ5: CIエラーの修正
CIエラーの種類に応じて自動修正を実行:

#### リンティングエラーの修正
```bash
if echo "$FAILED_CHECKS" | grep -qi "lint"; then
    echo "📝 リンティングエラーを修正中..."

    if [ -f "package.json" ]; then
        echo "🔧 npm run lint --fix を実行中..."
        npm run lint --fix 2>/dev/null || npm run lint:fix 2>/dev/null || echo "lintコマンドが見つかりません"
    fi

    if command -v ruff >/dev/null 2>&1; then
        echo "🔧 ruff check --fix を実行中..."
        ruff check --fix .
    fi

    if command -v golangci-lint >/dev/null 2>&1; then
        echo "🔧 golangci-lint を実行中..."
        golangci-lint run --fix
    fi

    echo "✅ リンティング修正完了"
    echo ""
fi
```

#### 型エラーの修正
```bash
if echo "$FAILED_CHECKS" | grep -qi "type\|typescript"; then
    echo "🏷️ 型エラーを分析中..."

    if [ -f "tsconfig.json" ]; then
        echo "🔧 TypeScript型チェックを実行中..."
        npx tsc --noEmit 2>&1 | head -30
        echo ""
        echo "💡 上記の型エラーを修正してください"
        echo ""
    fi
fi
```

#### テスト失敗の修正
```bash
if echo "$FAILED_CHECKS" | grep -qi "test"; then
    echo "🧪 テスト失敗を分析中..."

    if [ -f "package.json" ]; then
        echo "🔧 npm test を実行中..."
        npm test 2>&1 | tail -30
    elif [ -f "pytest.ini" ] || [ -f "pyproject.toml" ]; then
        echo "🔧 pytest を実行中..."
        python -m pytest -v --tb=short 2>&1 | tail -30
    elif [ -f "go.mod" ]; then
        echo "🔧 go test を実行中..."
        go test ./... -v 2>&1 | tail -30
    fi

    echo ""
    echo "💡 テスト失敗の詳細を確認して修正してください"
    echo ""
fi
```

#### ビルドエラーの修正
```bash
if echo "$FAILED_CHECKS" | grep -qi "build"; then
    echo "🏗️ ビルドエラーを修正中..."

    if [ -f "package.json" ]; then
        echo "📦 依存関係を更新中..."
        npm install

        echo "🔧 ビルドを試行中..."
        npm run build 2>&1 | tail -30
    fi

    if [ -f "requirements.txt" ]; then
        echo "📦 Python依存関係を更新中..."
        pip install -r requirements.txt
    fi

    if [ -f "go.mod" ]; then
        echo "📦 Go依存関係を更新中..."
        go mod tidy
        go build ./...
    fi

    echo ""
fi
```

### ステップ6: 修正の検証
```bash
echo "🧪 修正の検証中..."
echo ""

# リンティングチェック
echo "🔍 リンティングチェックを実行中..."
if [ -f "package.json" ]; then
    npm run lint 2>/dev/null || echo "lintコマンドをスキップ"
fi

# テスト実行
echo "🧪 テストを実行中..."
if [ -f "package.json" ]; then
    npm test 2>/dev/null && echo "✅ テスト成功" || echo "⚠️ テストで問題が残っています"
elif [ -f "pytest.ini" ] || [ -f "pyproject.toml" ]; then
    python -m pytest 2>/dev/null && echo "✅ テスト成功" || echo "⚠️ テストで問題が残っています"
fi

echo ""
```

### ステップ7: 修正結果の表示
```bash
# 変更内容の確認
echo "📝 修正内容の確認："
git status --porcelain

if [ -n "$(git status --porcelain)" ]; then
    echo ""
    echo "📋 修正されたファイル："
    git diff --name-only
    echo ""
    echo "📊 変更統計："
    git diff --stat
    echo ""
    echo "✅ 修正が適用されました！"
    echo ""
    echo "🔄 次のステップ："
    echo "1. 'git diff' で変更内容を詳細確認"
    echo "2. 必要に応じて追加の修正を実施"
    echo "3. /commit でコミット作成"
    echo "4. /push-current でリモートにpush"
    echo "5. 数分後に /ci-check で状態を確認"
else
    echo ""
    echo "ℹ️ 自動修正可能な変更が見つかりませんでした"
    echo "💡 以下の対応が必要です："
    if [ -n "$REVIEW_COMMENTS" ]; then
        echo "  - レビューコメントの手動修正"
    fi
    if [ -n "$FAILED_CHECKS" ]; then
        echo "  - CIエラーの手動修正"
    fi
fi
```

## 修正対象のまとめ

### レビューコメント修正
- 🚀リアクションがついたコメントのみを対象
- コードの提案を直接適用
- スタイル、ロジック、ドキュメント、テストの修正

### CIエラー修正
1. **リンティングエラー**: 自動修正ツールを実行
2. **型エラー**: TypeScript等の型チェックと分析
3. **テスト失敗**: テストを実行して失敗箇所を特定
4. **ビルドエラー**: 依存関係の更新とビルド実行

## エラーハンドリング
- PRが存在しない場合は適切なメッセージを表示
- GitHub CLIの権限エラー時は対処法を案内
- レビューコメントが不明確な場合はTODOコメントを追加
- 自動修正が不可能な場合は手動修正の必要性を通知

## 注意事項
- **🚀リアクション必須**: 修正したいコメントに🚀リアクションを追加してください
- すべてのエラーが自動修正できるわけではありません
- 複雑なロジックエラーは手動での修正が必要です
- 修正後は必ずローカルでテストを実行して検証してください
- コミットとプッシュは手動で実行してください
