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

# codex が使えるかどうかの判定
# ログイン済みでもトークン切れなら 401 になり、サンドボックスの制約でも起動に失敗する
# 次のターンでも直らない類の失敗を直前に起こしていれば、一定時間は codex レビューを誘わない
# 待機の目印は codex レビュー側が理由付きで作る。hook は読み、待ち終わったら消す
# 目印は codex レビューが動くサンドボックスからも書けて、hook からも同じ場所に見える必要がある
# セッションごとに変わる一時ディレクトリでは指せないため、固定のパスを使う
COOLDOWN_FILE="${CLAUDE_CODEX_COOLDOWN_FILE:-/tmp/claude/codex-review-cooldown}"
COOLDOWN_SECONDS="${CLAUDE_CODEX_COOLDOWN_SECONDS:-21600}"
[[ "$COOLDOWN_SECONDS" =~ ^[0-9]+$ ]] || COOLDOWN_SECONDS=21600
CODEX_AUTH_FILE="${CODEX_HOME:-${HOME}/.codex}/auth.json"

# 認証できない codex は 401 を返さず応答しなくなることがある
# hook 自体に制限時間があるため、待たされる可能性のある呼び出しは打ち切る
run_briefly() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 5 "$@"
  else
    "$@"
  fi
}

codex_usable() {
  command -v codex >/dev/null 2>&1 || return 1
  # ログイン状態の照会は環境変数による認証を見ないため、そちらも許容する
  run_briefly codex login status >/dev/null 2>&1 ||
    [[ -n "${CODEX_API_KEY:-}" || -n "${CODEX_ACCESS_TOKEN:-}" || -n "${OPENAI_API_KEY:-}" ]] ||
    return 1
  [[ -f "$COOLDOWN_FILE" ]] || return 0

  # 再ログインしていれば待機を打ち切る
  if [[ -f "$CODEX_AUTH_FILE" && "$CODEX_AUTH_FILE" -nt "$COOLDOWN_FILE" ]]; then
    rm -f "$COOLDOWN_FILE"
    return 0
  fi

  local marked_at now
  # 更新時刻の取得方法は GNU 版と BSD 版で異なる
  marked_at=$(stat -c %Y "$COOLDOWN_FILE" 2>/dev/null || stat -f %m "$COOLDOWN_FILE" 2>/dev/null || echo '')
  now=$(date +%s)

  # 時刻が読めなければ待機は解くが、目印は残す。書かれた理由を後から読めるようにするため
  [[ "$marked_at" =~ ^[0-9]+$ ]] || return 0

  # 時計のずれで未来の時刻になっていると、いつまでも待ち続けてしまう
  if (( marked_at > now )); then
    marked_at=$now
  fi

  if (( now - marked_at >= COOLDOWN_SECONDS )); then
    rm -f "$COOLDOWN_FILE"
    return 0
  fi
  return 1
}

if codex_usable; then
  REVIEWERS=$'   - doarakko-config:code-reviewer（観点: all）\n   - doarakko-config:codex-reviewer（未コミット差分をレビュー）'
else
  REVIEWERS='   - doarakko-config:code-reviewer（観点: all）'
fi

# レビュー済みの記録は、依頼を出せると確定してから残す
# 途中で落ちた場合にレビュー済みとみなされ、この差分が二度と対象にならないのを避けるため
record_hash

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
