# Branch Switch

指定したブランチに切り替えるカスタムコマンド。PR番号を指定することも可能。

```bash
# 引数チェック
if [ -z "$1" ]; then
  echo "📋 利用可能なブランチ一覧:"
  echo "=========================="
  
  # ローカルブランチ一覧を表示
  echo ""
  echo "🏠 ローカルブランチ:"
  git branch --format='  %(if)%(HEAD)%(then)* %(else)  %(end)%(refname:short) %(upstream:track)'
  
  echo ""
  echo "☁️  リモートブランチ:"
  git branch -r --format='  %(refname:short)' | grep -v 'HEAD'
  
  echo ""
  echo "使用方法: /branch-switch <ブランチ名 | PR番号>"
  echo "例: /branch-switch feature/new-feature"
  echo "    /branch-switch main"
  echo "    /branch-switch 123  (PR #123のブランチに切り替え)"
  exit 0
fi

INPUT="$1"

# PR番号かどうかをチェック（数字のみの場合）
if [[ "$INPUT" =~ ^[0-9]+$ ]]; then
  PR_NUMBER="$INPUT"
  echo "🔍 PR #$PR_NUMBER の情報を取得中..."
  
  # GitHub CLIを使ってPR情報を取得
  if ! command -v gh &> /dev/null; then
    echo "❌ Error: GitHub CLI (gh) がインストールされていません"
    echo "インストール方法: https://cli.github.com/"
    exit 1
  fi
  
  # PR情報を取得
  PR_INFO=$(gh pr view "$PR_NUMBER" --json headRefName,state,mergeable 2>/dev/null)
  
  if [ $? -ne 0 ]; then
    echo "❌ Error: PR #$PR_NUMBER が見つかりません"
    exit 1
  fi
  
  # ブランチ名を抽出
  BRANCH_NAME=$(echo "$PR_INFO" | jq -r '.headRefName')
  PR_STATE=$(echo "$PR_INFO" | jq -r '.state')
  
  if [ "$PR_STATE" = "CLOSED" ] || [ "$PR_STATE" = "MERGED" ]; then
    echo "⚠️  警告: PR #$PR_NUMBER は既に $PR_STATE されています"
    echo "それでもブランチ '$BRANCH_NAME' に切り替えますか? (y/n)"
    read -r CONTINUE
    if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
      exit 0
    fi
  fi
  
  echo "📋 PR #$PR_NUMBER のブランチ: $BRANCH_NAME"
else
  BRANCH_NAME="$INPUT"
fi

# 現在のブランチを取得
CURRENT_BRANCH=$(git branch --show-current)

if [ "$CURRENT_BRANCH" = "$BRANCH_NAME" ]; then
  echo "✅ すでに '$BRANCH_NAME' ブランチにいます"
  exit 0
fi

# 未コミットの変更をチェック
if ! git diff --quiet || ! git diff --staged --quiet; then
  echo "⚠️  未コミットの変更があります:"
  git status --short
  echo ""
  echo "変更を保存しますか?"
  echo "1) stashに保存して切り替え"
  echo "2) 変更を破棄して切り替え"
  echo "3) キャンセル"
  read -r -p "選択してください (1-3): " choice
  
  case $choice in
    1)
      echo "📦 変更をstashに保存中..."
      git stash push -m "Auto-stash before switching to $BRANCH_NAME"
      ;;
    2)
      echo "⚠️  変更を破棄します..."
      git reset --hard
      git clean -fd
      ;;
    *)
      echo "❌ キャンセルしました"
      exit 1
      ;;
  esac
fi

# ブランチが存在するかチェック
if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
  # ローカルブランチが存在する場合
  echo "🔄 ローカルブランチ '$BRANCH_NAME' に切り替え中..."
  git checkout "$BRANCH_NAME"
elif git show-ref --verify --quiet "refs/remotes/origin/$BRANCH_NAME"; then
  # リモートブランチのみ存在する場合
  echo "📥 リモートブランチ 'origin/$BRANCH_NAME' をチェックアウト中..."
  git checkout -b "$BRANCH_NAME" "origin/$BRANCH_NAME"
else
  # ブランチが存在しない場合
  echo "❌ Error: ブランチ '$BRANCH_NAME' が見つかりません"
  echo ""
  echo "新しいブランチを作成しますか? (y/n)"
  read -r CREATE_NEW
  
  if [ "$CREATE_NEW" = "y" ] || [ "$CREATE_NEW" = "Y" ]; then
    echo "🌱 新しいブランチ '$BRANCH_NAME' を作成中..."
    git checkout -b "$BRANCH_NAME"
  else
    exit 1
  fi
fi

if [ $? -eq 0 ]; then
  echo "✅ ブランチ '$BRANCH_NAME' に切り替えました"
  
  # リモートの最新情報を取得
  if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH_NAME"; then
    echo ""
    echo "🔄 リモートとの差分をチェック中..."
    git fetch origin "$BRANCH_NAME" --quiet
    
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse "origin/$BRANCH_NAME" 2>/dev/null)
    
    if [ "$LOCAL" != "$REMOTE" ]; then
      echo "⚠️  リモートブランチとの差分があります"
      echo "   最新の変更を取得するには: git pull"
    fi
  fi
  
  # stashがある場合は通知
  if [ "$choice" = "1" ]; then
    echo ""
    echo "💡 stashに保存した変更を復元するには: git stash pop"
  fi
else
  echo "❌ ブランチの切り替えに失敗しました"
  exit 1
fi
```