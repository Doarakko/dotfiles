# GitHub PR 自動修正コマンド

PRのレビューコメントとCIエラーを自動的に修正します。

## 使用方法
```bash
/pr-fix [pr番号]
```

PR番号が指定されない場合は、現在のブランチのPRを使用します。

## 修正対象のコメント
1. **🚀リアクション付きコメント**: 必須対応（ボット・人間問わず）
   - 修正後に自動で返信コメントを投稿
2. **リアクションなしコメント**: 内容を分析して対応が必要か判断
   - セキュリティ、バグ、型エラーなど重要な指摘は対応
   - 軽微な提案やスタイルの好みは対応をスキップ可能

## 処理手順
1. PRとレビューコメントを取得
2. 🚀リアクション付きコメントを必須対応として抽出
3. リアクションなしコメントを分析し対応要否を判断
4. CIの失敗状況を確認
5. レビューコメントの修正を適用
6. CIエラーを修正
7. テストとリンティングを実行して検証
8. 🚀リアクション付きコメントに返信を投稿
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

### ステップ2: レビューコメントの取得と分類
```bash
echo "🔍 レビューコメントを取得中..."

# PRのレビューコメントを取得
COMMENTS=$(gh api "repos/:owner/:repo/pulls/$PR_NUMBER/comments" 2>/dev/null || echo "")

if [ -z "$COMMENTS" ] || [ "$COMMENTS" = "[]" ]; then
    echo "ℹ️ レビューコメントが見つかりません"
    REQUIRED_COMMENTS=""
    OPTIONAL_COMMENTS=""
else
    # 🚀リアクション付きコメントを必須対応として抽出（ボット・人間問わず）
    REQUIRED_COMMENTS=$(echo "$COMMENTS" | jq -r '[.[] | select(.reactions.rocket > 0)] | .[] | {path: .path, line: .position, body: .body, id: .id, user: .user.login, isBot: (.user.type == "Bot" or (.user.login | test("\\[bot\\]$")))} | @json')

    # リアクションなしコメントを抽出（対応要否を判断する対象）
    OPTIONAL_COMMENTS=$(echo "$COMMENTS" | jq -r '[.[] | select(.reactions.rocket == 0 or .reactions.rocket == null)] | .[] | {path: .path, line: .position, body: .body, id: .id, user: .user.login, isBot: (.user.type == "Bot" or (.user.login | test("\\[bot\\]$")))} | @json')

    # 🚀リアクション付きコメントの表示
    if [ -n "$REQUIRED_COMMENTS" ]; then
        REQUIRED_COUNT=$(echo "$REQUIRED_COMMENTS" | wc -l | tr -d ' ')
        echo "🚀 必須対応コメント: ${REQUIRED_COUNT}件"
        echo ""
        echo "$REQUIRED_COMMENTS" | jq -r '. | "- [\(.user)] \(.path):\(.line) - \(.body | split("\n")[0])"' | head -20
        echo ""
    else
        echo "ℹ️ 🚀リアクション付きコメントはありません"
    fi

    # リアクションなしコメントの表示
    if [ -n "$OPTIONAL_COMMENTS" ]; then
        OPTIONAL_COUNT=$(echo "$OPTIONAL_COMMENTS" | wc -l | tr -d ' ')
        echo "📋 分析対象コメント: ${OPTIONAL_COUNT}件（対応要否を判断）"
        echo ""
        echo "$OPTIONAL_COMMENTS" | jq -r '. | "- [\(.user)] \(.path):\(.line) - \(.body | split("\n")[0])"' | head -20
        echo ""
    fi
fi
```

### ステップ2.5: リアクションなしコメントの対応要否判断
リアクションなしのコメントについて、内容を分析して対応が必要か判断:

**対応が必要な指摘（自動で修正対象に追加）:**
- セキュリティ脆弱性の指摘
- バグや不具合の指摘
- 型エラーや構文エラー
- パフォーマンス問題
- 必須の修正提案（suggested change）

**対応をスキップする指摘:**
- スタイルの好み
- 軽微なリファクタリング提案
- 質問やディスカッション
- 「考慮してください」レベルの提案

```bash
# 修正対象コメントを統合
REVIEW_COMMENTS=""
if [ -n "$REQUIRED_COMMENTS" ]; then
    REVIEW_COMMENTS="$REQUIRED_COMMENTS"
fi

# リアクションなしコメントから対応すべきものを選別
# ※ Claude Code が内容を分析して判断
if [ -n "$OPTIONAL_COMMENTS" ]; then
    echo "🤔 リアクションなしコメントを分析中..."
    echo ""
    echo "以下のコメントについて対応が必要か判断してください:"
    echo "$OPTIONAL_COMMENTS" | jq -r '. | "[\(.user)] \(.path):\(.line)\n\(.body)\n---"'
    echo ""
    echo "判断基準:"
    echo "  ✅ 対応すべき: セキュリティ、バグ、型エラー、パフォーマンス問題"
    echo "  ⏭️ スキップ可: スタイルの好み、軽微な提案、質問"
    echo ""
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

### ステップ7: 🚀リアクション付きコメントへの自動返信
```bash
# 🚀リアクション付きコメントに対して修正完了の返信を投稿
if [ -n "$REQUIRED_COMMENTS" ] && [ -n "$(git status --porcelain)" ]; then
    echo "💬 🚀リアクション付きコメントに返信中..."
    echo ""

    # 各コメントに返信
    echo "$REQUIRED_COMMENTS" | while read -r comment; do
        COMMENT_ID=$(echo "$comment" | jq -r '.id')
        COMMENT_USER=$(echo "$comment" | jq -r '.user')
        COMMENT_PATH=$(echo "$comment" | jq -r '.path')

        if [ -n "$COMMENT_ID" ] && [ "$COMMENT_ID" != "null" ]; then
            # 返信コメントを投稿
            REPLY_BODY="✅ 修正を適用しました。ご指摘ありがとうございます。"

            gh api "repos/:owner/:repo/pulls/$PR_NUMBER/comments/$COMMENT_ID/replies" \
                -f body="$REPLY_BODY" 2>/dev/null \
                && echo "  ✓ $COMMENT_USER のコメント (ID: $COMMENT_ID) に返信しました" \
                || echo "  ⚠️ $COMMENT_USER のコメントへの返信に失敗しました"
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
| 対象 | 条件 | 対応 | 返信 |
|------|------|------|------|
| 🚀リアクション付き | ボット・人間問わず | **必須対応** | ✅ 自動返信 |
| リアクションなし | 重要な指摘 | 対応する | ❌ 返信なし |
| リアクションなし | 軽微な提案 | スキップ可 | ❌ 返信なし |

### 対応が必要な指摘（リアクションなしでも対応）
- セキュリティ脆弱性の指摘
- バグや不具合の指摘
- 型エラーや構文エラー
- パフォーマンス問題
- 必須の修正提案（suggested change）

### 対応をスキップする指摘
- スタイルの好み
- 軽微なリファクタリング提案
- 質問やディスカッション
- 「考慮してください」レベルの提案

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
- **🚀リアクション付きコメント**: 必須対応、修正後に自動返信
- **リアクションなしコメント**: 内容を分析して対応要否を判断
- すべてのエラーが自動修正できるわけではありません
- 複雑なロジックエラーは手動での修正が必要です
- 修正後は必ずローカルでテストを実行して検証してください
- コミットとプッシュは手動で実行してください
