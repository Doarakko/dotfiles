#!/bin/bash

# Claude Code 自動レビュー Hook（セッション開始時）
# 開始時点のワークツリーを控える
# これが無いと最初の Stop で、既存の未コミット変更がこのターンのものか判別できず、
# 何も編集していないターンでもレビューを要求してしまう
# 控えるのは「前回見た時点」であって「レビュー済み」ではない
# レビュー済みの記録は触らないので、何か編集した時点で既存の変更も対象に入る

set -euo pipefail

INPUT=$(cat)

# 状態表の作り方は Stop 側と共有する。土台がずれると発火の判断も狂う
. "$(dirname "$0")/auto-review-state.sh"

SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // empty')

# 圧縮はターンの途中で起きるため、ここで控えを取り直すとそのターンの編集が飲まれる
# 圧縮が起きるほど長いターンこそレビューさせたいので、控えは残す
if [[ "$SOURCE" != "compact" ]]; then
  write_state "${STATE_DIR}/${SESSION_ID}.lastseen"
fi

# 回数の使い切りは、セッションが本当に始まり直したときだけ戻す
# 再開と圧縮は同じセッションの続きなので、使った回数を持ち越す
case "$SOURCE" in
startup | clear | fork)
  rm -f "${STATE_DIR}/${SESSION_ID}.rounds"
  ;;
esac
