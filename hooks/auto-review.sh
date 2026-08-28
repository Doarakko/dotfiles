#!/bin/bash

# Claude Code 自動レビュー Hook
# 未レビューの差分が残ったまま作業を完了させないよう、レビューと修正を促す

set -euo pipefail

INPUT=$(cat)

# セッションごとにレビュー済みの状態を記録する（リポジトリは汚さない）
STATE_DIR="${TMPDIR:-/tmp}/claude-auto-review"
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' | tr -cd 'A-Za-z0-9._-')
if [[ -z "$SESSION_ID" ]]; then
  SESSION_ID="unknown"
fi
STATE_FILE="${STATE_DIR}/${SESSION_ID}.sha"

# hook 入力の作業ディレクトリへ移動（取得できなければ現在地のまま）
HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
if [[ -n "$HOOK_CWD" && -d "$HOOK_CWD" ]]; then
  cd "$HOOK_CWD"
fi

# git 管理外では何もしない
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

WORKTREE_STATUS=$(git status --porcelain 2>/dev/null || true)
HASH=$(
  {
    printf '%s' "$WORKTREE_STATUS"
    git diff HEAD 2>/dev/null || true
    # 未追跡ファイルは差分に現れないため、内容を個別にハッシュへ含める
    while IFS= read -r -d '' untracked_file; do
      shasum "$untracked_file" 2>/dev/null || true
    done < <(git ls-files --others --exclude-standard -z 2>/dev/null)
  } | shasum | awk '{print $1}'
)

record_hash() {
  mkdir -p "$STATE_DIR"
  printf '%s' "$HASH" >"$STATE_FILE"
}

# この hook 由来で継続中のターン。レビュー済みとして記録し停止を許可する
STOP_HOOK_ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
  record_hash
  exit 0
fi

# レビュー対象の差分がない
if [[ -z "$WORKTREE_STATUS" ]]; then
  exit 0
fi

# 前回レビュー以降に変更がない
if [[ -f "$STATE_FILE" && "$(cat "$STATE_FILE")" == "$HASH" ]]; then
  exit 0
fi

record_hash

# codex CLI が使える場合のみ、二重レビューを指示する
if command -v codex >/dev/null 2>&1; then
  REVIEWERS=$'   - doarakko-config:code-reviewer（観点: all）\n   - doarakko-config:codex-reviewer（未コミット差分をレビュー）'
else
  REVIEWERS='   - doarakko-config:code-reviewer（観点: all）'
fi

REVIEW_INSTRUCTION="未レビューの変更があります。完了する前に次を実行してください。
1. 次のサブエージェントを 1 メッセージ内で同時に起動する
${REVIEWERS}
2. 各レビュアーの指摘をマージし、同一箇所を指す重複指摘は 1 件にまとめる
3. Critical / High の指摘はこのターン内で修正する
4. Medium / Low は修正せず、最終応答に一覧として提示する（どのレビュアー由来かを併記する）
レビューと修正が終わったらそのまま完了してよい。"

jq -n --arg context "$REVIEW_INSTRUCTION" '{
  hookSpecificOutput: {
    hookEventName: "Stop",
    additionalContext: $context
  }
}'
