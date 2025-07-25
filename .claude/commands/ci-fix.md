# GitHub PR CI 修正コマンド

現在のブランチのPRのCI失敗を自動的に修正します。

## 使用方法
```bash
/ci-fix
```

## 処理手順
1. まずPR CIチェックを実行して失敗を特定
2. よくあるCI失敗パターンを分析
3. 適切な修正を自動的に適用
4. 可能な場合はローカルでテストを実行
5. 修正内容の概要を表示（コミットはしない）

## 実装
PR CIチェックコマンドを実行して失敗の詳細を取得することから開始します。

### ステップ1: CI失敗の分析
```bash
# まずCI状態をチェック
echo "🔍 CI失敗を分析中..."
CURRENT_BRANCH=$(git branch --show-current)

# PRの存在確認
PR_INFO=$(gh pr list --head "$CURRENT_BRANCH" --json number 2>/dev/null)
if [ -z "$PR_INFO" ] || [ "$PR_INFO" = "[]" ]; then
    echo "❌ 現在のブランチにPRが見つかりません"
    echo "💡 まず /pr-create でPRを作成してください"
    exit 1
fi

PR_NUMBER=$(echo "$PR_INFO" | jq -r '.[0].number')
echo "📋 PR #$PR_NUMBER のCI失敗を修正します"

# チェック状態を取得
CHECK_RUNS=$(gh pr checks "$PR_NUMBER" 2>/dev/null)
FAILED_CHECKS=$(echo "$CHECK_RUNS" | grep -E "(fail|error|✗)" || echo "")

if [ -z "$FAILED_CHECKS" ]; then
    echo "✅ CIに失敗はありません"
    exit 0
fi

echo "❌ 検出された失敗："
echo "$FAILED_CHECKS"
```

### ステップ2: 失敗の種類別自動修正
実装する一般的なCI修正：

#### リンティングエラーの修正
```bash
if echo "$FAILED_CHECKS" | grep -qi "lint"; then
    echo "📝 リンティングエラーを修正中..."
    
    # よくあるリンターを実行
    if [ -f "package.json" ]; then
        echo "🔧 npm run lint --fix を実行中..."
        npm run lint --fix 2>/dev/null || echo "npm lintコマンドが見つかりません"
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
fi
```

#### 型エラーの修正
```bash
if echo "$FAILED_CHECKS" | grep -qi "type\|typescript"; then
    echo "🏷️ 型エラーを分析中..."
    
    if [ -f "tsconfig.json" ]; then
        echo "🔧 TypeScript型チェックを実行中..."
        npx tsc --noEmit 2>&1 | head -20
        echo ""
        echo "💡 型エラーの修正が必要です。上記のエラーを確認してください。"
    fi
fi
```

#### テスト失敗の修正
```bash
if echo "$FAILED_CHECKS" | grep -qi "test"; then
    echo "🧪 テスト失敗を分析中..."
    
    # テストをローカルで実行
    if [ -f "package.json" ]; then
        echo "🔧 npm test を実行中..."
        npm test 2>&1 | tail -20
    elif [ -f "pytest.ini" ] || [ -f "pyproject.toml" ]; then
        echo "🔧 pytest を実行中..."
        python -m pytest -v --tb=short 2>&1 | tail -20
    elif [ -f "go.mod" ]; then
        echo "🔧 go test を実行中..."
        go test ./... -v 2>&1 | tail -20
    fi
    
    echo ""
    echo "💡 テスト失敗の詳細を確認して手動で修正してください"
fi
```

#### ビルド失敗の修正
```bash
if echo "$FAILED_CHECKS" | grep -qi "build"; then
    echo "🏗️ ビルドエラーを修正中..."
    
    # 依存関係の更新
    if [ -f "package.json" ]; then
        echo "📦 依存関係を更新中..."
        npm install
        
        echo "🔧 ビルドを試行中..."
        npm run build 2>&1 | tail -20
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
fi
```

#### セキュリティ問題の修正
```bash
if echo "$FAILED_CHECKS" | grep -qi "security"; then
    echo "🔒 セキュリティ問題を修正中..."
    
    if [ -f "package.json" ]; then
        echo "🔧 npm audit fix を実行中..."
        npm audit fix
    fi
    
    if [ -f "requirements.txt" ]; then
        echo "🔧 pip-audit を実行中..."
        pip-audit --fix 2>/dev/null || echo "pip-audit が利用できません"
    fi
    
    echo "✅ セキュリティ修正完了"
fi
```

### ステップ3: 修正の検証と結果表示
```bash
# 修正内容を確認
echo ""
echo "📝 修正内容の確認："
git status --porcelain

if [ -n "$(git status --porcelain)" ]; then
    echo "✅ 修正が適用されました"
    
    # ローカルテストを実行（可能な場合）
    echo "🧪 修正の検証中..."
    if [ -f "package.json" ]; then
        npm test 2>/dev/null && echo "✅ テスト成功" || echo "⚠️ テストで問題が残っています"
    fi
    
    # 変更の詳細を表示
    echo ""
    echo "📋 修正されたファイル："
    git diff --name-only
    echo ""
    echo "📊 変更統計："
    git diff --stat
    echo ""
    echo "✅ CI修正が適用されました！"
    echo ""
    echo "🔄 次のステップ："
    echo "1. 'git diff' で変更内容を詳細確認"
    echo "2. 追加のテストが必要な場合は実行"
    echo "3. /commit-create でコミット作成"
    echo "4. /push-current でリモートにpush"
    echo "5. 数分後に /ci-check で状態を確認"
else
    echo "ℹ️ 自動修正可能な問題が見つかりませんでした"
    echo "💡 手動での修正が必要です"
fi
```

## 各失敗タイプの修正方法

### 1. **リンティングエラー**: リンターを実行して自動修正
### 2. **型エラー**: TypeScript/型の問題を分析して修正
### 3. **テスト失敗**: テストをローカルで実行して失敗したテストを修正  
### 4. **ビルド失敗**: 依存関係とビルド設定をチェック
### 5. **セキュリティ問題**: 依存関係を更新してセキュリティ脆弱性を修正

各失敗タイプについて：
1. エラーメッセージを解析して問題を理解
2. 利用可能なツールを使用して適切な修正を適用
3. 可能な場合はローカルで修正を検証
4. 修正内容を表示して次のステップを案内

修正後は、ユーザーが手動で内容を確認してからコミット・pushできるようになります。

## 注意事項
- すべてのCI失敗が自動修正できるわけではありません
- 複雑なロジックエラーは手動での修正が必要です
- 修正後は必ずローカルでテストを実行して検証してください
- 修正内容を確認してから /commit-create でコミットしてください
- セキュリティ関連の修正は慎重に確認してください