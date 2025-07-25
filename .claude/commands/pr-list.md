# PR List

オープン中のPR一覧を表示するカスタムコマンド。

```bash
# GitHub CLIの確認
if ! command -v gh &> /dev/null; then
  echo "❌ Error: GitHub CLI (gh) がインストールされていません"
  echo "インストール方法: https://cli.github.com/"
  exit 1
fi

echo "📋 オープン中のPR一覧:"
echo "=========================="

# オープン中のPRを取得して表示
PR_COUNT=$(gh pr list --state open --json number | jq length)

if [ "$PR_COUNT" -eq 0 ]; then
  echo ""
  echo "✨ 現在オープン中のPRはありません"
else
  gh pr list --state open --json number,title,headRefName,author,createdAt,url,statusCheckRollup | jq -r '.[] | 
"🔹 #\(.number) \(.title)
   📂 Branch: \(.headRefName)
   👤 Author: \(.author.login)
   📅 Created: \(.createdAt)
   \(if .statusCheckRollup and (.statusCheckRollup | length) > 0 then "🔍 CI Status: \(.statusCheckRollup | group_by(.conclusion) | map(if .[0].conclusion == "SUCCESS" then "✅ 成功: \(length)" elif .[0].conclusion == "FAILURE" then "❌ 失敗: \(length)" elif .[0].conclusion == null then "🔄 実行中: \(length)" else "\(.[0].conclusion): \(length)" end) | join(", "))" else "🔍 CI Status: No checks" end)
   🔗 URL: \(.url)
"'
fi
```