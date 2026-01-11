# Dependabot PR 統合コマンド

複数のDependabot PRを1つのPRにまとめます。

## 使用方法
```bash
/dependabot-merge
```

## 処理手順
1. Dependabotが作成したオープンなPRを取得
2. 統合用の新しいブランチを作成
3. 各Dependabot PRの変更を順番に適用
4. テストとリンティングで検証
5. 統合PRを作成
6. 元のDependabot PRをクローズ（オプション）

## 実装

### ステップ1: Dependabot PRの取得
```bash
echo "🔍 Dependabot PRを取得中..."
echo ""

# リポジトリ情報を取得
REPO_INFO=$(gh repo view --json owner,name,defaultBranchRef 2>/dev/null)
if [ -z "$REPO_INFO" ]; then
    echo "❌ リポジトリ情報を取得できません"
    exit 1
fi

OWNER=$(echo "$REPO_INFO" | jq -r '.owner.login')
REPO=$(echo "$REPO_INFO" | jq -r '.name')
DEFAULT_BRANCH=$(echo "$REPO_INFO" | jq -r '.defaultBranchRef.name')

echo "📦 リポジトリ: $OWNER/$REPO"
echo "🌿 デフォルトブランチ: $DEFAULT_BRANCH"
echo ""

# Dependabot PRを取得
DEPENDABOT_PRS=$(gh pr list --author "app/dependabot" --state open --json number,title,headRefName,body --limit 50 2>/dev/null || echo "[]")

if [ "$DEPENDABOT_PRS" = "[]" ] || [ -z "$DEPENDABOT_PRS" ]; then
    echo "✅ オープンなDependabot PRはありません"
    exit 0
fi

PR_COUNT=$(echo "$DEPENDABOT_PRS" | jq 'length')
echo "📋 Dependabot PR: ${PR_COUNT}件"
echo ""
echo "$DEPENDABOT_PRS" | jq -r '.[] | "  #\(.number): \(.title)"'
echo ""
```

### ステップ1.5: リアクションによるフィルタリング
```bash
echo "🔍 PRのリアクションを確認中..."
echo ""

# 👎 (thumbs down) または 👀 (eyes) リアクションがついているPRをスキップ
FILTERED_PRS="[]"
SKIPPED_PRS=""

echo "$DEPENDABOT_PRS" | jq -c '.[]' | while read -r pr; do
    PR_NUMBER=$(echo "$pr" | jq -r '.number')
    PR_TITLE=$(echo "$pr" | jq -r '.title')

    # PRのリアクションを取得
    REACTIONS=$(gh api "repos/$OWNER/$REPO/issues/$PR_NUMBER/reactions" 2>/dev/null || echo "[]")

    # 👎 (-1) または 👀 (eyes) リアクションをチェック
    HAS_THUMBS_DOWN=$(echo "$REACTIONS" | jq '[.[] | select(.content == "-1")] | length')
    HAS_EYES=$(echo "$REACTIONS" | jq '[.[] | select(.content == "eyes")] | length')

    if [ "$HAS_THUMBS_DOWN" -gt 0 ] || [ "$HAS_EYES" -gt 0 ]; then
        echo "  ⏭️ スキップ: #$PR_NUMBER ($PR_TITLE)"
        if [ "$HAS_THUMBS_DOWN" -gt 0 ]; then
            echo "     理由: 👎 リアクションあり"
        fi
        if [ "$HAS_EYES" -gt 0 ]; then
            echo "     理由: 👀 リアクションあり"
        fi
        SKIPPED_PRS="$SKIPPED_PRS $PR_NUMBER"
    else
        echo "  ✅ 対象: #$PR_NUMBER ($PR_TITLE)"
        # フィルタ済みリストに追加
        FILTERED_PRS=$(echo "$FILTERED_PRS" | jq --argjson pr "$pr" '. + [$pr]')
    fi
done

# フィルタ済みPRで上書き
DEPENDABOT_PRS="$FILTERED_PRS"
PR_COUNT=$(echo "$DEPENDABOT_PRS" | jq 'length')

echo ""
if [ -n "$SKIPPED_PRS" ]; then
    echo "⏭️ スキップされたPR:$SKIPPED_PRS"
fi
echo "📋 統合対象PR: ${PR_COUNT}件"
echo ""

if [ "$PR_COUNT" -eq 0 ]; then
    echo "✅ 統合対象のPRがありません"
    exit 0
fi
```

### ステップ2: 統合ブランチの作成
```bash
echo "🌿 統合ブランチを作成中..."

# 現在の日時をブランチ名に含める
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
MERGE_BRANCH="dependabot/combined-updates-$TIMESTAMP"

# デフォルトブランチを最新に更新
git fetch origin "$DEFAULT_BRANCH"
git checkout "$DEFAULT_BRANCH"
git pull origin "$DEFAULT_BRANCH"

# 統合ブランチを作成
git checkout -b "$MERGE_BRANCH"

echo "✅ ブランチ作成: $MERGE_BRANCH"
echo ""
```

### ステップ3: 各PRの変更を適用
```bash
echo "🔄 各PRの変更を適用中..."
echo ""

APPLIED_PRS=""
FAILED_PRS=""

# 各Dependabot PRの変更を順番にマージ
echo "$DEPENDABOT_PRS" | jq -c '.[]' | while read -r pr; do
    PR_NUMBER=$(echo "$pr" | jq -r '.number')
    PR_TITLE=$(echo "$pr" | jq -r '.title')
    PR_BRANCH=$(echo "$pr" | jq -r '.headRefName')

    echo "📥 PR #$PR_NUMBER: $PR_TITLE"

    # PRブランチをフェッチ
    git fetch origin "$PR_BRANCH" 2>/dev/null

    # チェリーピックまたはマージ
    if git merge "origin/$PR_BRANCH" --no-edit 2>/dev/null; then
        echo "  ✅ マージ成功"
        APPLIED_PRS="$APPLIED_PRS $PR_NUMBER"
    else
        echo "  ⚠️ コンフリクト発生"

        # コンフリクトを解決する試み
        echo "  🔧 コンフリクトの自動解決を試行中..."

        # package-lock.json や yarn.lock のコンフリクトは再生成で解決
        if git diff --name-only --diff-filter=U | grep -q "package-lock.json"; then
            git checkout --theirs package-lock.json 2>/dev/null
            npm install 2>/dev/null
            git add package-lock.json
        fi

        if git diff --name-only --diff-filter=U | grep -q "yarn.lock"; then
            git checkout --theirs yarn.lock 2>/dev/null
            yarn install 2>/dev/null
            git add yarn.lock
        fi

        # 残りのコンフリクトを確認
        if git diff --name-only --diff-filter=U | grep -v "lock" | head -1 | read -r; then
            echo "  ❌ 解決できないコンフリクトがあります"
            git merge --abort
            FAILED_PRS="$FAILED_PRS $PR_NUMBER"
        else
            git commit --no-edit 2>/dev/null
            echo "  ✅ コンフリクト解決・マージ成功"
            APPLIED_PRS="$APPLIED_PRS $PR_NUMBER"
        fi
    fi
    echo ""
done

echo "📊 適用結果:"
echo "  ✅ 成功: $APPLIED_PRS"
if [ -n "$FAILED_PRS" ]; then
    echo "  ❌ 失敗: $FAILED_PRS"
fi
echo ""
```

### ステップ4: テストと検証
```bash
echo "🧪 修正の検証中..."
echo ""

# 依存関係のインストール
if [ -f "package.json" ]; then
    echo "📦 npm install を実行中..."
    npm install 2>/dev/null
fi

if [ -f "requirements.txt" ]; then
    echo "📦 pip install を実行中..."
    pip install -r requirements.txt 2>/dev/null
fi

if [ -f "go.mod" ]; then
    echo "📦 go mod tidy を実行中..."
    go mod tidy 2>/dev/null
fi

# リンティング
echo ""
echo "🔍 リンティングチェックを実行中..."
if [ -f "package.json" ]; then
    npm run lint 2>/dev/null || echo "lintコマンドをスキップ"
fi

# テスト
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

### ステップ5: 統合PRの作成
```bash
echo "📝 統合PRを作成中..."
echo ""

# ブランチをプッシュ
git push -u origin "$MERGE_BRANCH"

# PR本文を生成
PR_BODY="## 概要
複数のDependabot PRを1つに統合しました。

## 統合されたPR
$(echo "$DEPENDABOT_PRS" | jq -r '.[] | "- #\(.number): \(.title)"')

## 変更内容
依存関係のセキュリティ更新・バージョンアップを適用しました。

## テスト
- [ ] テストが通ることを確認
- [ ] 動作確認を実施
"

# PRを作成
gh pr create \
    --title "chore(deps): combine dependabot updates" \
    --body "$PR_BODY" \
    --base "$DEFAULT_BRANCH" \
    --head "$MERGE_BRANCH"

echo ""
echo "✅ 統合PRを作成しました"
echo ""
```

### ステップ6: 元のPRのクローズ（オプション）
```bash
echo "💡 元のDependabot PRをクローズしますか？"
echo ""
echo "以下のコマンドで個別にクローズできます:"
echo "$DEPENDABOT_PRS" | jq -r '.[] | "  gh pr close \(.number) --comment \"Closed in favor of combined PR\""'
echo ""
echo "または一括でクローズ:"
echo "  /dependabot-merge --close-originals"
echo ""
```

### ステップ7: 結果の表示
```bash
echo "📊 統合結果:"
echo ""
echo "🌿 統合ブランチ: $MERGE_BRANCH"
echo "📋 統合されたPR: ${PR_COUNT}件"
echo ""
echo "🔄 次のステップ:"
echo "1. PRのCIが通ることを確認"
echo "2. 動作確認を実施"
echo "3. PRをマージ"
echo "4. 元のDependabot PRをクローズ"
echo ""
```

## オプション機能

### 元のPRを自動クローズ
```bash
# --close-originals オプションが指定された場合
if [ "$1" = "--close-originals" ]; then
    echo "🗑️ 元のDependabot PRをクローズ中..."
    echo "$DEPENDABOT_PRS" | jq -r '.[] | .number' | while read -r pr_num; do
        gh pr close "$pr_num" --comment "Closed in favor of combined dependency update PR" 2>/dev/null
        echo "  ✅ PR #$pr_num をクローズしました"
    done
fi
```

## スキップルール
以下のリアクションがついているPRは統合対象から除外されます：
- 👎 (thumbs down): 統合したくないPR
- 👀 (eyes): 確認中・保留中のPR

統合したくないPRがある場合は、事前に該当PRに👎または👀リアクションをつけてください。

## 注意事項
- 👎または👀リアクションがついているPRは自動的にスキップされます
- コンフリクトが発生した場合は手動での解決が必要な場合があります
- ロックファイル（package-lock.json, yarn.lock）のコンフリクトは自動解決を試みます
- テストが失敗した場合は個別のPRを確認してください
- 元のDependabot PRは自動ではクローズされません（安全のため）
- 統合PRのマージ後に元のPRをクローズしてください

## トラブルシューティング

### コンフリクトが解決できない場合
```bash
# 問題のあるPRを除外して再実行
gh pr list --author "app/dependabot" --state open --json number,title | \
    jq -r '.[] | select(.number != 問題のPR番号) | .number'
```

### マージ後の動作確認
```bash
# 依存関係の更新を確認
npm outdated  # Node.js
pip list --outdated  # Python
go list -u -m all  # Go
```
