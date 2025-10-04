# Dependabot PR CI修正コマンド

DependabotのプルリクエストでCIエラーが発生しているものを自動的に修正します。

## 使用方法
```bash
/dp-ci-fix
```

## 処理手順
1. Dependabotが作成したPR一覧を取得
2. CIが失敗しているPRを特定
3. READMEや設定ファイルからプロジェクトの修正方法を調査
4. 各失敗PRに対して自動修正を実行
5. 修正結果をレポート

## 実装

### ステップ1: Dependabot PRとCIステータスの取得
```bash
# GitHub CLIの確認
if ! command -v gh &> /dev/null; then
  echo "❌ Error: GitHub CLI (gh) がインストールされていません"
  echo "インストール方法: https://cli.github.com/"
  exit 1
fi

echo "🤖 Dependabot PRのCIエラーを確認中..."
echo "========================================"

# Dependabotが作成したPRを取得
DEPENDABOT_PRS=$(gh pr list --state open --author "app/dependabot" --json number,title,headRefName,statusCheckRollup)

if [ "$DEPENDABOT_PRS" = "[]" ]; then
  echo "✨ Dependabotのオープン中のPRはありません"
  exit 0
fi

# CIが失敗しているPRをフィルタリング
FAILED_PRS=$(echo "$DEPENDABOT_PRS" | jq -r '.[] | select(.statusCheckRollup != null) | select(.statusCheckRollup | map(select(.conclusion == "FAILURE")) | length > 0) | @json')

if [ -z "$FAILED_PRS" ]; then
  echo "✅ CIエラーのあるDependabot PRはありません"
  exit 0
fi

FAILED_COUNT=$(echo "$FAILED_PRS" | wc -l | tr -d ' ')
echo "❌ CIエラーが見つかりました: ${FAILED_COUNT}件のPR"
echo ""
```

### ステップ2: プロジェクトの修正方法を調査
```bash
echo "🔍 プロジェクトの修正方法を調査中..."

# READMEを読む
README_CONTENT=""
if [ -f "README.md" ]; then
  README_CONTENT=$(cat README.md)
elif [ -f "README" ]; then
  README_CONTENT=$(cat README)
fi

# lintコマンドの特定
LINT_CMD=""
if echo "$README_CONTENT" | grep -qi "lint"; then
  LINT_CMD=$(echo "$README_CONTENT" | grep -i "lint" | head -3)
fi

# testコマンドの特定
TEST_CMD=""
if echo "$README_CONTENT" | grep -qi "test"; then
  TEST_CMD=$(echo "$README_CONTENT" | grep -i "test" | head -3)
fi

# buildコマンドの特定
BUILD_CMD=""
if echo "$README_CONTENT" | grep -qi "build"; then
  BUILD_CMD=$(echo "$README_CONTENT" | grep -i "build" | head -3)
fi

echo "📋 検出された修正方法:"
[ -n "$LINT_CMD" ] && echo "  Lint: ${LINT_CMD}"
[ -n "$TEST_CMD" ] && echo "  Test: ${TEST_CMD}"
[ -n "$BUILD_CMD" ] && echo "  Build: ${BUILD_CMD}"
echo ""
```

### ステップ3: 各失敗PRの修正
```bash
# 元のブランチを保存
ORIGINAL_BRANCH=$(git branch --show-current)
echo "💾 元のブランチ: $ORIGINAL_BRANCH"
echo ""

# 修正結果を記録
SUCCESS_PRS=()
FAILED_FIX_PRS=()

# 各PRを処理
echo "$FAILED_PRS" | while IFS= read -r pr_json; do
  PR_NUMBER=$(echo "$pr_json" | jq -r '.number')
  PR_TITLE=$(echo "$pr_json" | jq -r '.title')
  PR_BRANCH=$(echo "$pr_json" | jq -r '.headRefName')

  echo "🔧 PR #${PR_NUMBER} を修正中: ${PR_TITLE}"
  echo "  ブランチ: ${PR_BRANCH}"

  # ブランチをチェックアウト
  if ! git fetch origin "$PR_BRANCH" 2>/dev/null; then
    echo "  ❌ ブランチの取得に失敗"
    FAILED_FIX_PRS+=("#${PR_NUMBER}")
    continue
  fi

  if ! git checkout "$PR_BRANCH" 2>/dev/null; then
    echo "  ❌ チェックアウトに失敗"
    FAILED_FIX_PRS+=("#${PR_NUMBER}")
    continue
  fi

  # CI失敗の種類を確認
  FAILED_CHECKS=$(gh pr checks "$PR_NUMBER" 2>/dev/null | grep -E "(fail|error|✗)" || echo "")

  echo "  失敗したチェック:"
  echo "$FAILED_CHECKS" | while IFS= read -r check; do
    echo "    - $check"
  done

  # 修正を実行
  FIXED=false

  # Lintエラーの修正
  if echo "$FAILED_CHECKS" | grep -qi "lint"; then
    echo "  📝 Lintエラーを修正中..."

    # READMEから取得したコマンドを実行（fix付き）
    if echo "$LINT_CMD" | grep -q "fix"; then
      eval "$LINT_CMD" 2>/dev/null && FIXED=true
    fi

    # 一般的なlint fixコマンドも試行
    if [ -f "Makefile" ] && grep -q "lint" Makefile; then
      make lint-fix 2>/dev/null && FIXED=true
    fi
  fi

  # 依存関係の更新
  if echo "$FAILED_CHECKS" | grep -qi "build\|dependencies"; then
    echo "  📦 依存関係を更新中..."

    # Makefileがあれば使用
    if [ -f "Makefile" ]; then
      if grep -q "install\|deps" Makefile; then
        make install 2>/dev/null || make deps 2>/dev/null
        FIXED=true
      fi
    fi
  fi

  # セキュリティ問題の修正
  if echo "$FAILED_CHECKS" | grep -qi "security\|audit"; then
    echo "  🔒 セキュリティ問題を修正中..."

    if [ -f "Makefile" ] && grep -q "audit" Makefile; then
      make audit-fix 2>/dev/null && FIXED=true
    fi
  fi

  # 変更があればコミット
  if [ -n "$(git status --porcelain)" ]; then
    echo "  💾 変更をコミット中..."

    git add .
    git commit -m "fix: CI errors for dependabot PR

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"

    # プッシュ
    echo "  📤 リモートにプッシュ中..."
    if git push origin "$PR_BRANCH"; then
      echo "  ✅ 修正完了"
      SUCCESS_PRS+=("#${PR_NUMBER}: ${PR_TITLE}")
    else
      echo "  ❌ プッシュに失敗"
      FAILED_FIX_PRS+=("#${PR_NUMBER}: ${PR_TITLE}")
    fi
  else
    echo "  ℹ️ 自動修正可能な変更なし"
    FAILED_FIX_PRS+=("#${PR_NUMBER}: ${PR_TITLE} (要手動修正)")
  fi

  echo ""
done

# 元のブランチに戻る
echo "🔙 元のブランチに戻ります: $ORIGINAL_BRANCH"
git checkout "$ORIGINAL_BRANCH"
```

### ステップ4: 結果レポート
```bash
echo ""
echo "📊 修正結果レポート"
echo "========================================"

if [ ${#SUCCESS_PRS[@]} -gt 0 ]; then
  echo ""
  echo "✅ 修正成功 (${#SUCCESS_PRS[@]}件):"
  for pr in "${SUCCESS_PRS[@]}"; do
    echo "  - $pr"
  done
fi

if [ ${#FAILED_FIX_PRS[@]} -gt 0 ]; then
  echo ""
  echo "❌ 修正失敗または手動対応が必要 (${#FAILED_FIX_PRS[@]}件):"
  for pr in "${FAILED_FIX_PRS[@]}"; do
    echo "  - $pr"
  done
fi

echo ""
echo "🔄 次のステップ:"
echo "1. 数分待ってCIが再実行されるのを確認"
echo "2. 手動対応が必要なPRは個別に確認"
echo "3. /pr-list でPRの状態を確認"
echo ""
echo "✅ Dependabot PR CI修正処理が完了しました"
```

## 注意事項
- GitHub CLIが必要です
- 修正方法はREADMEやMakefileから自動検出されます
- すべてのエラーが自動修正できるわけではありません
- 複雑なエラーは手動での修正が必要です
- 修正後、CIの再実行には数分かかる場合があります
