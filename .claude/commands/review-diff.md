# コード差分レビューコマンド

現在のコード差分を分析し、コーディング規約とベストプラクティスに従ったレビューを実施します。

## 使用方法
```bash
/review-diff [対象ファイル・ディレクトリ]
```

対象が指定されない場合は、すべての変更されたファイルをレビューします。

## 処理手順
1. 現在の変更差分を取得・分析
2. プロジェクトのコーディング規約を特定
3. 使用技術のベストプラクティスを適用
4. 問題点と改善提案を整理
5. 詳細なレビューレポートを生成

## 実装

### ステップ1: 変更差分の取得
```bash
# git statusで変更ファイルを確認
echo "📋 変更されたファイルを確認中..."
CHANGED_FILES=$(git status --porcelain)

if [ -z "$CHANGED_FILES" ]; then
    echo "ℹ️ レビュー対象の変更がありません"
    exit 0
fi

echo "📝 変更されたファイル:"
echo "$CHANGED_FILES"
echo ""

# 詳細差分を取得
echo "🔍 差分を分析中..."
DIFF_CONTENT=$(git diff --no-color)
STAGED_DIFF=$(git diff --cached --no-color)

if [ -n "$STAGED_DIFF" ]; then
    echo "📦 ステージング済みの変更も含めて分析します"
    DIFF_CONTENT="$DIFF_CONTENT\n\n=== STAGED CHANGES ===\n$STAGED_DIFF"
fi
```

### ステップ2: プロジェクト環境の分析
```bash
# プロジェクトの技術スタックを特定
echo "🔍 プロジェクト環境を分析中..."

PROJECT_TYPE=""
LANGUAGES=()
FRAMEWORKS=()
CONFIG_FILES=()

# 言語・フレームワークの検出
if [ -f "package.json" ]; then
    PROJECT_TYPE="Node.js"
    LANGUAGES+=("JavaScript" "TypeScript")
    echo "📦 Node.js プロジェクトを検出"
    
    # フレームワーク検出
    if grep -q "react" package.json; then
        FRAMEWORKS+=("React")
    fi
    if grep -q "vue" package.json; then
        FRAMEWORKS+=("Vue.js")
    fi
    if grep -q "next" package.json; then
        FRAMEWORKS+=("Next.js")
    fi
    if grep -q "express" package.json; then
        FRAMEWORKS+=("Express")
    fi
    
    CONFIG_FILES+=("package.json" ".eslintrc*" ".prettierrc*" "tsconfig.json")
fi

if [ -f "requirements.txt" ] || [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
    PROJECT_TYPE="Python"
    LANGUAGES+=("Python")
    echo "🐍 Python プロジェクトを検出"
    
    if grep -q "django" requirements.txt 2>/dev/null; then
        FRAMEWORKS+=("Django")
    fi
    if grep -q "flask" requirements.txt 2>/dev/null; then
        FRAMEWORKS+=("Flask")
    fi
    if grep -q "fastapi" requirements.txt 2>/dev/null; then
        FRAMEWORKS+=("FastAPI")
    fi
    
    CONFIG_FILES+=("requirements.txt" "pyproject.toml" ".flake8" "mypy.ini")
fi

if [ -f "go.mod" ]; then
    PROJECT_TYPE="Go"
    LANGUAGES+=("Go")
    echo "🔷 Go プロジェクトを検出"
    CONFIG_FILES+=("go.mod" "go.sum")
fi

if [ -f "Cargo.toml" ]; then
    PROJECT_TYPE="Rust"
    LANGUAGES+=("Rust")
    echo "🦀 Rust プロジェクトを検出"
    CONFIG_FILES+=("Cargo.toml" "Cargo.lock")
fi

# その他の設定ファイル
CONFIG_FILES+=(".gitignore" "README.md" ".editorconfig")

echo "🏗️ 検出された技術スタック:"
echo "  言語: ${LANGUAGES[*]}"
echo "  フレームワーク: ${FRAMEWORKS[*]}"
```

### ステップ3: レビュー基準の設定
```bash
# レビュー基準を設定
echo "📐 レビュー基準を設定中..."

REVIEW_CRITERIA=()

# 共通基準
REVIEW_CRITERIA+=(
    "コードの可読性と保守性"
    "命名規則の一貫性"
    "セキュリティベストプラクティス"
    "パフォーマンス最適化"
    "エラーハンドリング"
    "テスタビリティ"
    "ドキュメント整備"
)

# 言語固有の基準
for lang in "${LANGUAGES[@]}"; do
    case $lang in
        "JavaScript"|"TypeScript")
            REVIEW_CRITERIA+=(
                "ESLint/Prettier準拠"
                "型安全性（TypeScript）"
                "非同期処理のベストプラクティス"
                "メモリリーク対策"
                "バンドルサイズ最適化"
            )
            ;;
        "Python")
            REVIEW_CRITERIA+=(
                "PEP 8準拠"
                "型ヒント使用"
                "例外処理の適切性"
                "パッケージ構造"
                "docstring記述"
            )
            ;;
        "Go")
            REVIEW_CRITERIA+=(
                "Go Convention準拠"
                "エラーハンドリング"
                "Goroutineとチャネルの使用"
                "メモリ効率"
                "テストカバレッジ"
            )
            ;;
        "Rust")
            REVIEW_CRITERIA+=(
                "Rust Convention準拠"
                "所有権とライフタイム"
                "Result型でのエラーハンドリング"
                "メモリ安全性"
                "パフォーマンス"
            )
            ;;
    esac
done

echo "📋 適用されるレビュー基準:"
for criteria in "${REVIEW_CRITERIA[@]}"; do
    echo "  - $criteria"
done
```

### ステップ4: 自動チェックの実行
```bash
# 利用可能なリンター・チェッカーを実行
echo "🔧 自動チェックを実行中..."

LINT_RESULTS=()

# JavaScript/TypeScript
if command -v npm >/dev/null 2>&1 && [ -f "package.json" ]; then
    echo "📝 ESLint チェック実行中..."
    if npm run lint --silent 2>/dev/null; then
        LINT_RESULTS+=("✅ ESLint: 問題なし")
    else
        LINT_RESULTS+=("❌ ESLint: 問題が検出されました")
    fi
    
    if command -v tsc >/dev/null 2>&1 && [ -f "tsconfig.json" ]; then
        echo "🏷️ TypeScript型チェック実行中..."
        if npx tsc --noEmit --skipLibCheck 2>/dev/null; then
            LINT_RESULTS+=("✅ TypeScript: 型エラーなし")
        else
            LINT_RESULTS+=("❌ TypeScript: 型エラーが検出されました")
        fi
    fi
fi

# Python
if command -v ruff >/dev/null 2>&1; then
    echo "🐍 Ruff チェック実行中..."
    if ruff check . --quiet 2>/dev/null; then
        LINT_RESULTS+=("✅ Ruff: 問題なし")
    else
        LINT_RESULTS+=("❌ Ruff: 問題が検出されました")
    fi
fi

if command -v mypy >/dev/null 2>&1; then
    echo "🏷️ MyPy型チェック実行中..."
    if mypy . --ignore-missing-imports --quiet 2>/dev/null; then
        LINT_RESULTS+=("✅ MyPy: 型エラーなし")
    else
        LINT_RESULTS+=("❌ MyPy: 型エラーが検出されました")
    fi
fi

# Go
if command -v golangci-lint >/dev/null 2>&1 && [ -f "go.mod" ]; then
    echo "🔷 golangci-lint チェック実行中..."
    if golangci-lint run --quiet 2>/dev/null; then
        LINT_RESULTS+=("✅ golangci-lint: 問題なし")
    else
        LINT_RESULTS+=("❌ golangci-lint: 問題が検出されました")
    fi
fi

# Rust
if command -v cargo >/dev/null 2>&1 && [ -f "Cargo.toml" ]; then
    echo "🦀 Cargo clippy チェック実行中..."
    if cargo clippy --quiet -- -D warnings 2>/dev/null; then
        LINT_RESULTS+=("✅ Clippy: 問題なし")
    else
        LINT_RESULTS+=("❌ Clippy: 問題が検出されました")
    fi
fi

echo "🔍 自動チェック結果:"
for result in "${LINT_RESULTS[@]}"; do
    echo "  $result"
done
```

### ステップ5: レビューレポート生成
```bash
# レビューレポートを生成
echo ""
echo "📊 コード差分レビューレポート"
echo "=================================="
echo ""
echo "📅 レビュー実施日時: $(date '+%Y年%m月%d日 %H:%M:%S')"
echo "🏗️ プロジェクトタイプ: $PROJECT_TYPE"
echo "💻 検出言語: ${LANGUAGES[*]}"
echo "🚀 使用フレームワーク: ${FRAMEWORKS[*]}"
echo ""

echo "## 📋 変更ファイル一覧"
git status --porcelain | while read -r line; do
    status=${line:0:2}
    file=${line:3}
    case $status in
        "M ") echo "  📝 変更: $file" ;;
        "A ") echo "  ➕ 追加: $file" ;;
        "D ") echo "  ❌ 削除: $file" ;;
        "R ") echo "  🔄 リネーム: $file" ;;
        "??") echo "  ❓ 未追跡: $file" ;;
        *) echo "  📄 $status: $file" ;;
    esac
done
echo ""

echo "## 🔧 自動チェック結果"
for result in "${LINT_RESULTS[@]}"; do
    echo "  $result"
done
echo ""

echo "## 📐 レビューポイント"
echo ""
echo "### ✅ 良い点"
echo "- Conventional Commits形式でのコミットメッセージ作成"
echo "- 適切なファイル構造とディレクトリ組織"
echo "- 設定ファイルの適切な管理"
echo ""

echo "### 🔍 改善提案"
echo ""

# ファイル別の具体的な改善提案
git diff --name-only | while read -r file; do
    echo "#### 📄 $file"
    
    case $file in
        *.js|*.ts|*.jsx|*.tsx)
            echo "- **JavaScript/TypeScript ベストプラクティス**"
            echo "  - console.log の削除を確認"
            echo "  - 未使用インポートの削除"
            echo "  - 適切な型定義の使用"
            echo "  - エラーハンドリングの実装"
            ;;
        *.py)
            echo "- **Python ベストプラクティス**"
            echo "  - PEP 8準拠の確認"
            echo "  - 型ヒントの追加"
            echo "  - docstringの記述"
            echo "  - 例外処理の適切な実装"
            ;;
        *.go)
            echo "- **Go ベストプラクティス**"
            echo "  - エラーハンドリングの確認"
            echo "  - 未使用変数の削除"
            echo "  - 適切なパッケージ構造"
            echo "  - テストの追加"
            ;;
        *.rs)
            echo "- **Rust ベストプラクティス**"
            echo "  - 所有権とライフタイムの確認"
            echo "  - Result型の適切な使用"
            echo "  - パフォーマンス最適化"
            echo "  - 安全性の確認"
            ;;
        *.md)
            echo "- **Markdown ドキュメント**"
            echo "  - リンクの有効性確認"
            echo "  - 見出し構造の整理"
            echo "  - コードブロックの言語指定"
            echo "  - 誤字脱字の確認"
            ;;
        *.json)
            echo "- **JSON設定ファイル**"
            echo "  - フォーマットの統一"
            echo "  - 不要なプロパティの削除"
            echo "  - セキュリティ設定の確認"
            ;;
        *)
            echo "- **一般的な改善点**"
            echo "  - ファイル形式の適切性"
            echo "  - 文字エンコーディングの確認"
            echo "  - 改行コードの統一"
            ;;
    esac
    echo ""
done

echo "### 🚀 次のステップ"
echo "1. 自動チェックで検出された問題の修正"
echo "2. 改善提案の検討・実装"
echo "3. テストの実行・追加"
echo "4. ドキュメントの更新"
echo "5. コードレビューの依頼"
echo ""

echo "## 📈 品質メトリクス"
echo ""
TOTAL_FILES=$(git diff --name-only | wc -l)
ADDED_LINES=$(git diff --numstat | awk '{add+=$1} END {print add+0}')
DELETED_LINES=$(git diff --numstat | awk '{del+=$2} END {print del+0}')

echo "📊 変更統計:"
echo "  - 変更ファイル数: $TOTAL_FILES"
echo "  - 追加行数: +$ADDED_LINES"
echo "  - 削除行数: -$DELETED_LINES"
echo "  - 正味変更: $((ADDED_LINES - DELETED_LINES))"
echo ""

echo "🎯 レビュー完了！改善提案を参考にコードの品質向上を図ってください。"
```

## レビュー対象

### **セキュリティ（最重要・厚めにチェック）**
- **認証・認可**
  - ハードコードされた認証情報（API key, password, token等）
  - 認証トークンの安全な保管方法
  - 認可チェックの実装（権限検証の欠落）
  - セッション管理の安全性
- **インジェクション攻撃**
  - SQLインジェクション脆弱性
  - NoSQLインジェクション
  - コマンドインジェクション
  - XSS（Stored/Reflected/DOM-based）
  - LDAP/XMLインジェクション
- **入力検証とサニタイゼーション**
  - ユーザー入力の検証不足
  - ファイルアップロードの検証
  - Content-Type検証
  - サイズ制限の実装
  - ホワイトリスト方式の採用
- **データ保護**
  - 機密情報のログ出力
  - 暗号化の適切な実装
  - 安全でない乱数生成
  - パスワードのハッシュ化（bcrypt、Argon2等）
- **API/ネットワークセキュリティ**
  - CORS設定の安全性
  - CSRF対策の実装
  - Rate limiting の実装
  - HTTPSの強制
- **依存関係のセキュリティ**
  - 既知の脆弱性を持つライブラリ
  - 最新版への更新の必要性
- **その他のセキュリティ**
  - パストラバーサル脆弱性
  - XXE（XML External Entity）攻撃
  - サーバーサイドリクエストフォージェリ（SSRF）
  - 安全でないデシリアライゼーション

### **テストケース（重要・厚めにチェック）**
- **テストカバレッジ**
  - 新規機能に対するテストの有無
  - 既存機能への影響範囲のテスト
  - エッジケースのカバー状況
  - エラーケースのテスト
- **テストの種類と品質**
  - 単体テスト（Unit Test）の適切性
  - 統合テスト（Integration Test）の必要性
  - E2Eテストの必要性
  - テストの可読性と保守性
- **テストケースの十分性**
  - 正常系のテスト
  - 異常系のテスト（バリデーションエラー、ネットワークエラー等）
  - 境界値テスト
  - 並行処理のテスト（該当する場合）
- **セキュリティテスト**
  - 認証・認可のテスト
  - 入力検証のテスト
  - エラーハンドリングのテスト
- **モックとテストデータ**
  - 外部依存のモック化
  - テストデータの適切性
  - テスト環境の分離
- **パフォーマンステスト**
  - 負荷テストの必要性評価
  - レスポンスタイムの検証
- **過剰なテストの検出**
  - 実装の詳細に依存しすぎたテスト（脆弱なテスト）
  - 重複したテストケース
  - 価値の低いテスト（自明な処理のテスト）
  - メンテナンスコストが高すぎるテスト
  - 不要にモックが多すぎるテスト

### **コード品質**
- 可読性、保守性、パフォーマンス
- 命名規則の一貫性
- 重複コードの検出
- 複雑度の評価
- デッドコードの検出

### **ベストプラクティス**
- 言語・フレームワーク固有の推奨事項
- 既存のアーキテクチャとの整合性
- 適切なエラーハンドリング

### **ドキュメント**
- README、コメント、型定義
- API仕様の更新
- 変更履歴の記録

## 技術スタック別対応
- **Node.js**: ESLint、Prettier、TypeScript
- **Python**: Ruff、MyPy、PEP 8
- **Go**: golangci-lint、Go Convention
- **Rust**: Clippy、Rust Convention

## 注意事項
- 自動チェックツールが利用可能な場合のみ実行
- プロジェクト固有のルールがある場合は設定ファイルを参照
- レビュー結果は参考として活用し、最終判断は開発者が行う
- セキュリティに関わる問題は特に注意深く確認