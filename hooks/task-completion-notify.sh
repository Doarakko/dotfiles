#!/bin/bash

# Claude Code タスク完了通知 Hook
# タスク完了時にmacOS通知を送信

# プロジェクト名を取得
PROJECT_NAME=$(basename "$(pwd)")

# ブランチ名を取得（空の場合はフォールバック）
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [[ -z "$BRANCH_NAME" || "$BRANCH_NAME" == "HEAD" ]]; then
  BRANCH_NAME="タスク完了"
fi

# AppleScriptインジェクション対策: ダブルクォートとバックスラッシュをエスケープ
escape_for_applescript() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

SAFE_TITLE=$(escape_for_applescript "🚀 ${PROJECT_NAME}")
SAFE_MESSAGE=$(escape_for_applescript "$BRANCH_NAME")

# osascriptを使用してmacOS通知を送信
osascript -e "display notification \"${SAFE_MESSAGE}\" with title \"${SAFE_TITLE}\" sound name \"Glass\"" 2>/dev/null