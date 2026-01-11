# GitHub セキュリティアラート修正コマンド

リポジトリのセキュリティアラート（Dependabot alerts、Code scanning alerts等）を取得し、自動的に修正します。

## 使用方法
```bash
/security-fix
```

## 対象アラート
1. **Dependabot alerts**: 依存関係の脆弱性
2. **Code scanning alerts**: コードの脆弱性（GitHub Advanced Security）
3. **Secret scanning alerts**: シークレットの漏洩（参考表示のみ）

## 処理手順
1. 各種セキュリティアラートを取得
2. アラートの重要度順に並べ替え（Critical > High > Medium > Low）
3. Dependabotアラートの自動修正を適用
4. Code scanningアラートを分析して修正
5. テストとリンティングで修正を検証
6. 修正内容の概要を表示（コミットはしない）

## 実装

### ステップ1: リポジトリ情報の取得
```bash
echo "🔍 リポジトリのセキュリティアラートを確認中..."
echo ""

# リポジトリ情報を取得
REPO_INFO=$(gh repo view --json owner,name 2>/dev/null)
if [ -z "$REPO_INFO" ]; then
    echo "❌ リポジトリ情報を取得できません"
    echo "💡 GitHub CLIでログインしているか確認してください: gh auth status"
    exit 1
fi

OWNER=$(echo "$REPO_INFO" | jq -r '.owner.login')
REPO=$(echo "$REPO_INFO" | jq -r '.name')
echo "📦 リポジトリ: $OWNER/$REPO"
echo ""
```

### ステップ2: Dependabotアラートの取得
```bash
echo "🔒 Dependabotアラートを取得中..."

# Dependabotアラートを取得（openステータスのみ）
DEPENDABOT_ALERTS=$(gh api "repos/$OWNER/$REPO/dependabot/alerts?state=open&per_page=100" 2>/dev/null || echo "[]")

if [ "$DEPENDABOT_ALERTS" = "[]" ] || [ -z "$DEPENDABOT_ALERTS" ]; then
    echo "✅ Dependabotアラートはありません"
    DEPENDABOT_COUNT=0
else
    DEPENDABOT_COUNT=$(echo "$DEPENDABOT_ALERTS" | jq 'length')
    echo "⚠️ Dependabotアラート: ${DEPENDABOT_COUNT}件"
    echo ""

    # 重要度別に集計
    CRITICAL=$(echo "$DEPENDABOT_ALERTS" | jq '[.[] | select(.security_advisory.severity == "critical")] | length')
    HIGH=$(echo "$DEPENDABOT_ALERTS" | jq '[.[] | select(.security_advisory.severity == "high")] | length')
    MEDIUM=$(echo "$DEPENDABOT_ALERTS" | jq '[.[] | select(.security_advisory.severity == "medium")] | length')
    LOW=$(echo "$DEPENDABOT_ALERTS" | jq '[.[] | select(.security_advisory.severity == "low")] | length')

    echo "  🔴 Critical: $CRITICAL"
    echo "  🟠 High: $HIGH"
    echo "  🟡 Medium: $MEDIUM"
    echo "  🟢 Low: $LOW"
    echo ""

    # アラート一覧を表示
    echo "📋 アラート一覧:"
    echo "$DEPENDABOT_ALERTS" | jq -r '.[] | "  [\(.security_advisory.severity | ascii_upcase)] \(.security_advisory.summary) (\(.dependency.package.name))"' | head -20
    echo ""
fi
```

### ステップ3: Code Scanningアラートの取得
```bash
echo "🔍 Code Scanningアラートを取得中..."

# Code scanningアラートを取得
CODE_SCANNING_ALERTS=$(gh api "repos/$OWNER/$REPO/code-scanning/alerts?state=open&per_page=100" 2>/dev/null || echo "[]")

if [ "$CODE_SCANNING_ALERTS" = "[]" ] || [ -z "$CODE_SCANNING_ALERTS" ]; then
    echo "✅ Code Scanningアラートはありません"
    CODE_SCANNING_COUNT=0
else
    CODE_SCANNING_COUNT=$(echo "$CODE_SCANNING_ALERTS" | jq 'length')
    echo "⚠️ Code Scanningアラート: ${CODE_SCANNING_COUNT}件"
    echo ""

    # アラート一覧を表示
    echo "📋 アラート一覧:"
    echo "$CODE_SCANNING_ALERTS" | jq -r '.[] | "  [\(.rule.severity // "unknown" | ascii_upcase)] \(.rule.description // .rule.id) (\(.most_recent_instance.location.path):\(.most_recent_instance.location.start_line))"' | head -20
    echo ""
fi
```

### ステップ4: Secret Scanningアラートの確認
```bash
echo "🔐 Secret Scanningアラートを確認中..."

# Secret scanningアラートを取得
SECRET_ALERTS=$(gh api "repos/$OWNER/$REPO/secret-scanning/alerts?state=open&per_page=100" 2>/dev/null || echo "[]")

if [ "$SECRET_ALERTS" = "[]" ] || [ -z "$SECRET_ALERTS" ]; then
    echo "✅ Secret Scanningアラートはありません"
    SECRET_COUNT=0
else
    SECRET_COUNT=$(echo "$SECRET_ALERTS" | jq 'length')
    echo "🚨 Secret Scanningアラート: ${SECRET_COUNT}件"
    echo ""
    echo "⚠️ 重要: シークレットが漏洩しています！"
    echo "📋 アラート一覧:"
    echo "$SECRET_ALERTS" | jq -r '.[] | "  [\(.state)] \(.secret_type) - \(.secret_type_display_name)"' | head -20
    echo ""
    echo "💡 対応方法:"
    echo "  1. 漏洩したシークレットを直ちに無効化/ローテーション"
    echo "  2. 新しいシークレットを安全な方法で設定"
    echo "  3. コミット履歴からシークレットを削除（git filter-branch等）"
    echo ""
fi
```

### ステップ5: 修正対象の確認
```bash
# 修正対象がない場合は終了
TOTAL_ALERTS=$((DEPENDABOT_COUNT + CODE_SCANNING_COUNT))

if [ "$TOTAL_ALERTS" -eq 0 ]; then
    echo "✅ 修正が必要なセキュリティアラートはありません"

    if [ "$SECRET_COUNT" -gt 0 ]; then
        echo ""
        echo "⚠️ ただし、Secret Scanningアラートがあります。手動での対応が必要です。"
    fi

    exit 0
fi

echo ""
echo "🔧 セキュリティ修正を開始します..."
echo ""
```

### ステップ6: Dependabotアラートの自動修正
```bash
if [ "$DEPENDABOT_COUNT" -gt 0 ]; then
    echo "📦 Dependabotアラートの修正中..."
    echo ""

    # Node.js プロジェクト
    if [ -f "package.json" ]; then
        echo "🔧 npm audit fix を実行中..."
        npm audit fix 2>&1 || echo "⚠️ 一部の脆弱性は自動修正できませんでした"
        echo ""

        # 強制修正が必要な場合
        echo "🔧 npm audit fix --force を試行中..."
        echo "⚠️ 注意: --force はメジャーバージョンアップを含む可能性があります"
        npm audit fix --force 2>&1 || echo "⚠️ 強制修正も完了できませんでした"
        echo ""

        # 残りの脆弱性を確認
        echo "📊 残りの脆弱性を確認中..."
        npm audit 2>&1 | tail -20
        echo ""
    fi

    # Python プロジェクト
    if [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; then
        echo "🔧 Python依存関係の更新中..."

        # pip-audit がインストールされている場合
        if command -v pip-audit >/dev/null 2>&1; then
            echo "🔧 pip-audit --fix を実行中..."
            pip-audit --fix 2>&1 || echo "⚠️ pip-auditでの修正に失敗"
        else
            echo "💡 pip-audit がインストールされていません"
            echo "   インストール: pip install pip-audit"
        fi

        # 脆弱なパッケージを個別に更新
        echo ""
        echo "📋 脆弱なパッケージの更新を確認してください:"
        echo "$DEPENDABOT_ALERTS" | jq -r '.[] | select(.dependency.package.ecosystem == "pip") | "  pip install --upgrade \(.dependency.package.name)"' | head -10
        echo ""
    fi

    # Go プロジェクト
    if [ -f "go.mod" ]; then
        echo "🔧 Go依存関係の更新中..."

        # 脆弱なパッケージを更新
        echo "$DEPENDABOT_ALERTS" | jq -r '.[] | select(.dependency.package.ecosystem == "go") | .dependency.package.name' | while read -r pkg; do
            if [ -n "$pkg" ]; then
                echo "  更新中: $pkg"
                go get -u "$pkg@latest" 2>/dev/null || echo "  ⚠️ $pkg の更新に失敗"
            fi
        done

        go mod tidy
        echo ""
    fi

    # Ruby プロジェクト
    if [ -f "Gemfile" ]; then
        echo "🔧 Bundler依存関係の更新中..."
        bundle update --patch 2>&1 || echo "⚠️ bundle updateに失敗"
        echo ""
    fi

    echo "✅ Dependabot修正完了"
    echo ""
fi
```

### ステップ7: Code Scanningアラートの修正
```bash
if [ "$CODE_SCANNING_COUNT" -gt 0 ]; then
    echo "🔍 Code Scanningアラートの修正中..."
    echo ""

    # 各アラートの詳細を取得して修正
    echo "📋 修正が必要なコードの脆弱性:"
    echo ""
    echo "$CODE_SCANNING_ALERTS" | jq -r '.[] | "ファイル: \(.most_recent_instance.location.path)\n行: \(.most_recent_instance.location.start_line)-\(.most_recent_instance.location.end_line)\n問題: \(.rule.description // .rule.id)\n重要度: \(.rule.severity // "unknown")\n---"' | head -50
    echo ""

    echo "💡 上記の脆弱性を確認し、以下の一般的な修正を適用してください:"
    echo "  - SQLインジェクション: パラメータ化クエリを使用"
    echo "  - XSS: 出力のエスケープを追加"
    echo "  - コマンドインジェクション: 入力の検証とサニタイズ"
    echo "  - パストラバーサル: パスの正規化と検証"
    echo "  - ハードコードされた認証情報: 環境変数を使用"
    echo ""

    # Code scanningアラートの詳細情報を元に修正を適用
    # Claude Codeが実際のコードを読んで修正を提案
    echo "🔧 各アラートを分析して修正を適用します..."
    echo ""
fi
```

### ステップ8: 修正の検証
```bash
echo "🧪 修正の検証中..."
echo ""

# リンティングチェック
echo "🔍 リンティングチェックを実行中..."
if [ -f "package.json" ]; then
    npm run lint 2>/dev/null || echo "lintコマンドをスキップ"
fi

if command -v ruff >/dev/null 2>&1; then
    ruff check . 2>/dev/null || echo "ruffチェックで問題あり"
fi

# テスト実行
echo ""
echo "🧪 テストを実行中..."
if [ -f "package.json" ]; then
    npm test 2>/dev/null && echo "✅ テスト成功" || echo "⚠️ テストで問題が発生"
elif [ -f "pytest.ini" ] || [ -f "pyproject.toml" ]; then
    python -m pytest 2>/dev/null && echo "✅ テスト成功" || echo "⚠️ テストで問題が発生"
elif [ -f "go.mod" ]; then
    go test ./... 2>/dev/null && echo "✅ テスト成功" || echo "⚠️ テストで問題が発生"
fi

echo ""
```

### ステップ9: 修正結果の表示
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
    echo "✅ セキュリティ修正が適用されました！"
    echo ""
    echo "🔄 次のステップ："
    echo "1. 'git diff' で変更内容を詳細確認"
    echo "2. 破壊的変更がないかテストを実行"
    echo "3. /commit でコミット作成"
    echo "4. /push-current でリモートにpush"
    echo ""
    echo "⚠️ 注意事項："
    echo "  - メジャーバージョンアップが含まれる場合は動作確認を徹底してください"
    echo "  - npm audit fix --force は破壊的変更を含む可能性があります"
    echo "  - 本番環境への適用前にステージング環境でテストしてください"
else
    echo ""
    echo "ℹ️ 自動修正可能な変更が見つかりませんでした"
    echo ""
    echo "💡 手動での対応が必要な項目："

    if [ "$DEPENDABOT_COUNT" -gt 0 ]; then
        echo "  📦 Dependabotアラート: ${DEPENDABOT_COUNT}件"
        echo "     一部のパッケージは互換性の問題で自動更新できません"
        echo "     手動でパッケージをアップグレードしてください"
    fi

    if [ "$CODE_SCANNING_COUNT" -gt 0 ]; then
        echo "  🔍 Code Scanningアラート: ${CODE_SCANNING_COUNT}件"
        echo "     コードの脆弱性は手動で修正が必要です"
    fi

    if [ "$SECRET_COUNT" -gt 0 ]; then
        echo "  🔐 Secret Scanningアラート: ${SECRET_COUNT}件"
        echo "     漏洩したシークレットの無効化が必要です"
    fi
fi
```

## 修正対象の優先度

| 優先度 | アラート種別 | 対応方法 |
|--------|-------------|----------|
| 🔴 最優先 | Secret Scanning | 即座にシークレットを無効化 |
| 🔴 Critical | Dependabot | npm audit fix / pip-audit --fix |
| 🟠 High | Dependabot / Code Scanning | 自動修正 + 手動確認 |
| 🟡 Medium | Dependabot / Code Scanning | 自動修正を試行 |
| 🟢 Low | Dependabot / Code Scanning | 計画的に対応 |

## 言語別の修正コマンド

### Node.js
```bash
npm audit fix           # 自動修正
npm audit fix --force   # 破壊的変更を含む修正
npm update              # 依存関係の更新
```

### Python
```bash
pip-audit --fix         # 自動修正
pip install --upgrade <package>  # 個別更新
```

### Go
```bash
go get -u ./...         # 依存関係の更新
go mod tidy             # 不要な依存関係の削除
```

### Ruby
```bash
bundle update --patch   # パッチレベルの更新
bundle audit fix        # 脆弱性の修正
```

## エラーハンドリング
- GitHub CLIの権限エラー時は対処法を案内
- APIレート制限時は待機を提案
- 自動修正が不可能な場合は手動修正の必要性を通知

## 注意事項
- すべての脆弱性が自動修正できるわけではありません
- メジャーバージョンアップは破壊的変更を含む可能性があります
- Secret Scanningアラートは手動での対応が必須です
- 修正後は必ずテストを実行して動作確認してください
- 本番環境への適用前にステージング環境でテストしてください
