# GitHub PR 自動修正コマンド

PRのレビューコメント(🚀リアクション付き + ボットからのコメント)とCIエラーを自動的に修正します。

## 使用方法
```bash
/pr-fix [pr番号]
```

PR番号が指定されない場合は、現在のブランチのPRを使用します。

## 修正対象のコメント
1. **ボットからのコメント**: 自動で修正対象になります（リアクション不要）
   - GitHub Actions, CodeRabbit, Dependabot, Renovate 等のボットを自動検出
   - 修正後に自動で返信コメントを投稿
2. **人間からのコメント**: 🚀リアクションを追加したコメントのみ修正対象

## 処理手順
1. PRとレビューコメントを取得
2. ボットからのコメントを自動検出
3. 🚀リアクション付きの人間コメントを取得
4. CIの失敗状況を確認
5. レビューコメントの修正を適用
6. CIエラーを修正
7. テストとリンティングを実行して検証
8. ボットコメントに返信を投稿
9. コミットせずに変更内容の概要を表示

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

### ステップ2: レビューコメントの取得とボット検出
```bash
echo "🔍 レビューコメントを取得中..."

# PRのレビューコメントを取得
COMMENTS=$(gh api "repos/:owner/:repo/pulls/$PR_NUMBER/comments" 2>/dev/null || echo "")

if [ -z "$COMMENTS" ] || [ "$COMMENTS" = "[]" ]; then
    echo "ℹ️ レビューコメントが見つかりません"
    BOT_COMMENTS=""
    HUMAN_COMMENTS=""
else
    # ボットからのコメントを抽出（リアクション不要）
    # ボット判定: user.type == "Bot" または user.login に [bot] が含まれる
    BOT_COMMENTS=$(echo "$COMMENTS" | jq -r '[.[] | select(.user.type == "Bot" or (.user.login | test("\\[bot\\]$")))] | .[] | {path: .path, line: .position, body: .body, id: .id, user: .user.login} | @json')

    # 人間からの🚀リアクション付きコメントを抽出
    HUMAN_COMMENTS=$(echo "$COMMENTS" | jq -r '[.[] | select(.user.type != "Bot" and (.user.login | test("\\[bot\\]$") | not) and .reactions.rocket > 0)] | .[] | {path: .path, line: .position, body: .body, id: .id, user: .user.login} | @json')

    # ボットコメントの表示
    if [ -n "$BOT_COMMENTS" ]; then
        BOT_COUNT=$(echo "$BOT_COMMENTS" | wc -l | tr -d ' ')
        echo "🤖 ボットからのコメント: ${BOT_COUNT}件（自動修正対象）"
        echo ""
        echo "$BOT_COMMENTS" | jq -r '. | "- [\(.user)] \(.path):\(.line) - \(.body | split("\n")[0])"' | head -20
        echo ""
    else
        echo "ℹ️ ボットからのコメントはありません"
    fi

    # 人間コメントの表示
    if [ -n "$HUMAN_COMMENTS" ]; then
        HUMAN_COUNT=$(echo "$HUMAN_COMMENTS" | wc -l | tr -d ' ')
        echo "👤 🚀リアクション付き人間コメント: ${HUMAN_COUNT}件"
        echo ""
        echo "$HUMAN_COMMENTS" | jq -r '. | "- [\(.user)] \(.path):\(.line) - \(.body | split("\n")[0])"'
        echo ""
    else
        echo "ℹ️ 🚀リアクション付きの人間コメントはありません"
        echo "💡 人間からのコメントを修正するには🚀リアクションを追加してください"
    fi
fi

# 全修正対象コメントを統合
REVIEW_COMMENTS=""
if [ -n "$BOT_COMMENTS" ]; then
    REVIEW_COMMENTS="$BOT_COMMENTS"
fi
if [ -n "$HUMAN_COMMENTS" ]; then
    if [ -n "$REVIEW_COMMENTS" ]; then
        REVIEW_COMMENTS="$REVIEW_COMMENTS
$HUMAN_COMMENTS"
    else
        REVIEW_COMMENTS="$HUMAN_COMMENTS"
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

### ステップ7: ボットコメントへの自動返信
```bash
# ボットからのコメントに対して修正完了の返信を投稿
if [ -n "$BOT_COMMENTS" ] && [ -n "$(git status --porcelain)" ]; then
    echo "💬 ボットコメントに返信中..."
    echo ""

    # 各ボットコメントに返信
    echo "$BOT_COMMENTS" | while read -r comment; do
        COMMENT_ID=$(echo "$comment" | jq -r '.id')
        BOT_USER=$(echo "$comment" | jq -r '.user')
        COMMENT_PATH=$(echo "$comment" | jq -r '.path')

        if [ -n "$COMMENT_ID" ] && [ "$COMMENT_ID" != "null" ]; then
            # 返信コメントを投稿
            REPLY_BODY="✅ 修正を適用しました。ご指摘ありがとうございます。"

            gh api "repos/:owner/:repo/pulls/$PR_NUMBER/comments/$COMMENT_ID/replies" \
                -f body="$REPLY_BODY" 2>/dev/null \
                && echo "  ✓ $BOT_USER のコメント (ID: $COMMENT_ID) に返信しました" \
                || echo "  ⚠️ $BOT_USER のコメントへの返信に失敗しました"
        fi
    done
    echo ""
fi
```

### ステップ8: 修正結果の表示
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
- **ボットコメント**: リアクション不要で自動的に修正対象
  - 修正後に自動で返信コメントを投稿
- **人間コメント**: 🚀リアクションがついたコメントのみを対象
- コードの提案を直接適用
- スタイル、ロジック、ドキュメント、テストの修正

### ボット検出ルール
以下の条件でボットを自動検出:
- GitHubユーザータイプが `Bot` のアカウント
- ユーザー名が `[bot]` で終わるアカウント
- 例: `github-actions[bot]`, `coderabbitai[bot]`, `dependabot[bot]`, `renovate[bot]`

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
- **ボットコメント**: リアクション不要で自動的に修正対象となり、修正後に返信を投稿
- **人間コメント**: 修正したいコメントに🚀リアクションを追加してください
- すべてのエラーが自動修正できるわけではありません
- 複雑なロジックエラーは手動での修正が必要です
- 修正後は必ずローカルでテストを実行して検証してください
- コミットとプッシュは手動で実行してください
