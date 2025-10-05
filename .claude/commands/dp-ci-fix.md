# Dependabot PR CI修正コマンド

DependabotのプルリクエストでCIエラーが発生しているものを自動的に修正します。

## 使用方法
```bash
/dp-ci-fix
```

## 処理手順
1. Dependabotが作成したPR一覧を取得
2. CIが失敗しているPRを特定
3. 各失敗PRに対してClaudeが修正を実行
4. 修正結果をレポート

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

### ステップ2: 各失敗PRの修正
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

  # 依存関係の再インストール（Claudeがリポジトリを確認して適切なコマンドを実行）
  echo "  📦 依存関係を再インストール中..."
  echo "  ℹ️  Claudeがリポジトリの構成を確認して適切なインストールコマンドを実行します"

  # CI失敗の種類を確認
  FAILED_CHECKS=$(gh pr checks "$PR_NUMBER" 2>/dev/null | grep -E "(fail|error|✗)" || echo "")

  echo "  失敗したチェック:"
  echo "$FAILED_CHECKS" | while IFS= read -r check; do
    echo "    - $check"
  done

  # Claudeに修正を依頼
  echo "  🤖 Claudeに修正を依頼します"
  echo ""
  echo "  失敗したチェック内容に基づいて、以下の修正を行ってください:"
  echo "$FAILED_CHECKS"
  echo ""
  echo "  ⚠️  重要な制約:"
  echo "    - lintエラー: できる限りignoreコメントを使わず実際のコードを修正すること"
  echo "    - リポジトリの構成を確認して適切な修正方法を選択すること"
  echo ""

  # メジャーバージョンアップの確認
  PR_DIFF=$(gh pr diff "$PR_NUMBER" 2>/dev/null || echo "")
  if echo "$PR_DIFF" | grep -qE '^\-.*"[^"]+": *"[0-9]+\.[0-9]+'; then
    OLD_VER=$(echo "$PR_DIFF" | grep -E '^\-.*"[^"]+": *"[0-9]+\.[0-9]+' | head -1 | sed -E 's/.*"([0-9]+)\..*/\1/')
    NEW_VER=$(echo "$PR_DIFF" | grep -E '^\+.*"[^"]+": *"[0-9]+\.[0-9]+' | head -1 | sed -E 's/.*"([0-9]+)\..*/\1/')
    PACKAGE=$(echo "$PR_DIFF" | grep -E '^\+.*"[^"]+": *"[0-9]+\.[0-9]+' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')

    if [ "$OLD_VER" != "$NEW_VER" ] && [ -n "$PACKAGE" ]; then
      echo "  ⚠️  メジャーバージョンアップ: $PACKAGE ($OLD_VER.x → $NEW_VER.x)"
      echo "  🔍 マイグレーションガイドを確認中..."
      /gemini-search "$PACKAGE version $NEW_VER migration guide" 2>/dev/null | head -10 || true
      echo ""
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
      echo "  ✅ プッシュ完了"

      # CI結果を待機して確認
      echo "  ⏳ CI実行を待機中（最大5分）..."
      sleep 30  # 初回実行開始を待つ

      TIMEOUT=270  # 残り4分30秒
      INTERVAL=30
      CI_PASSED=false

      while [ $TIMEOUT -gt 0 ]; do
        CI_STATUS=$(gh pr checks "$PR_NUMBER" --json state,conclusion 2>/dev/null || echo "")

        # すべてのチェックが完了しているか確認
        if echo "$CI_STATUS" | jq -e 'all(.state == "COMPLETED")' >/dev/null 2>&1; then
          # すべて成功しているか確認
          if echo "$CI_STATUS" | jq -e 'all(.conclusion == "SUCCESS")' >/dev/null 2>&1; then
            echo "  ✅ CI成功"
            CI_PASSED=true
            SUCCESS_PRS+=("#${PR_NUMBER}: ${PR_TITLE} ✓")
            break
          else
            echo "  ❌ CI失敗"
            FAILED_FIX_PRS+=("#${PR_NUMBER}: ${PR_TITLE} (CI失敗)")
            break
          fi
        fi

        sleep $INTERVAL
        TIMEOUT=$((TIMEOUT - INTERVAL))
      done

      if [ "$CI_PASSED" = false ] && [ $TIMEOUT -le 0 ]; then
        echo "  ⏱️  CI確認タイムアウト"
        FAILED_FIX_PRS+=("#${PR_NUMBER}: ${PR_TITLE} (CI確認中)")
      fi
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
- Claudeがリポジトリを確認して修正方法を判断します
- すべてのエラーが自動修正できるわけではありません
- 複雑なエラーは手動での修正が必要です
- 修正後、CIの再実行には数分かかる場合があります
