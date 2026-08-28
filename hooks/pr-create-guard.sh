#!/bin/bash

# Claude Code PR作成ガード Hook
# pr-zero の手順を通さずに PR が作られるのを防ぐ

set -uo pipefail

# 判定できない環境では何もしない。hook の都合でセッションを止めない
if ! command -v python3 >/dev/null 2>&1; then
  cat >/dev/null
  exit 0
fi

python3 "$(dirname "$0")/pr-create-guard.py" || true

exit 0
