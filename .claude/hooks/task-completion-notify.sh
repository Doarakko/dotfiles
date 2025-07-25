#!/bin/bash

# Claude Code タスク完了通知 Hook
# タスク完了時にmacOS通知を送信

# プロジェクト名を取得（ディレクトリ名から）
PROJECT_NAME=$(basename "$(pwd)")

# シンプルにタスク完了メッセージを設定
TASK_CONTENT="タスクが完了しました"

# 現在時刻を取得
CURRENT_TIME=$(date "+%H:%M")

# 通知タイトルと内容を設定
NOTIFICATION_TITLE="🚀 ${PROJECT_NAME}"
NOTIFICATION_MESSAGE="タスク完了 (${CURRENT_TIME})"

# osascriptを使用してmacOS通知を送信
osascript -e "
display notification \"${NOTIFICATION_MESSAGE}\" with title \"${NOTIFICATION_TITLE}\" sound name \"Glass\"
" 2>/dev/null

# 通知が送信されたことをログに記録
echo "✅ 通知送信完了: ${PROJECT_NAME} - ${TASK_CONTENT}" >&2