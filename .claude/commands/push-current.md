# Git Push Current Branch

現在のブランチをリモートにpushするカスタムコマンド

```bash
# 現在のブランチ名を取得
CURRENT_BRANCH=$(git branch --show-current)

if [ -z "$CURRENT_BRANCH" ]; then
  echo "Error: ブランチ名を取得できませんでした"
  exit 1
fi

echo "現在のブランチ: $CURRENT_BRANCH"

# メインブランチのチェック
if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
  echo "❌ Error: メインブランチ ($CURRENT_BRANCH) への直接pushは禁止されています"
  echo "フィーチャーブランチを作成してください"
  exit 1
fi

# リモートブランチの存在確認
if git ls-remote --heads origin "$CURRENT_BRANCH" | grep -q "$CURRENT_BRANCH"; then
  echo "リモートブランチが存在します。pushを実行..."
  git push origin "$CURRENT_BRANCH"
else
  echo "リモートにブランチが存在しません。upstream設定付きでpushを実行..."
  git push -u origin "$CURRENT_BRANCH"
fi

if [ $? -eq 0 ]; then
  echo "✅ push完了: $CURRENT_BRANCH"
else
  echo "❌ pushに失敗しました"
  exit 1
fi
```
