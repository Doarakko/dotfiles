#!/bin/bash

# Claude Code アイドル通知 Hook
# ユーザー入力待ち時にmacOS通知を送信

# プロジェクト名を取得
PROJECT_NAME=$(basename "$(pwd)")

# ブランチ名を取得
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

# 通知タイトルと内容を設定
NOTIFICATION_TITLE="💬 ${PROJECT_NAME}"
NOTIFICATION_MESSAGE="${BRANCH_NAME}"

# osascriptを使用してmacOS通知を送信
osascript -e "
display notification \"${NOTIFICATION_MESSAGE}\" with title \"${NOTIFICATION_TITLE}\" sound name \"Glass\"
" 2>/dev/null
