#!/bin/bash

# Claude Code 自動レビュー Hook
# 未レビューの差分が残ったまま作業を完了させないよう、レビューと修正を促す
# 発火するのは編集のあったターンだけで、1セッションあたりの回数にも上限がある
# 対象は前回レビュー以降に変わったファイルだけ

set -euo pipefail

INPUT=$(cat)

# 状態表の作り方は SessionStart 側と共有する。土台がずれると発火の判断も狂う
# 読み込み元は起動時に渡された自分のパスから引く。exec 形式なので絶対パスで渡る
# 読み込みはトップレベルに置く。部分シェルへ入れると、読み込み先の終了が呼び出し元へ届かない
. "$(dirname "$0")/auto-review-state.sh"

# レビュー済みの地点。何を見せるかを決める
STATE_FILE="${STATE_DIR}/${SESSION_ID}.reviewed"
# 前回 Stop した時点。発火するかを決める
LASTSEEN_FILE="${STATE_DIR}/${SESSION_ID}.lastseen"
# このセッションで自動レビューを依頼した回数
ROUNDS_FILE="${STATE_DIR}/${SESSION_ID}.rounds"

record_state() {
  write_state "$STATE_FILE"
}

# 前回 Stop 時点の記録は、どの経路で抜けるときも残す
# 残さないと、次のターンで編集の有無を判断できない
record_lastseen() {
  write_state "$LASTSEEN_FILE"
}

# 1セッションあたりの回数。読めない値は0として扱う
# 上限で止めるより、余分に回るほうが安全
MAX_ROUNDS="${CLAUDE_AUTO_REVIEW_MAX_ROUNDS:-5}"
[[ "$MAX_ROUNDS" =~ ^[0-9]+$ ]] || MAX_ROUNDS=5
ROUNDS=$(cat "$ROUNDS_FILE" 2>/dev/null || true)
[[ "$ROUNDS" =~ ^[0-9]+$ ]] || ROUNDS=0

record_rounds() {
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$1" >"$ROUNDS_FILE"
}

# この hook 由来で継続中のターン。レビュー済みとして記録し停止を許可する
# ただし上限で止めたあとの継続では記録しない
# 上限の通知もターンを続けるため、ここで記録すると見ていない変更がレビュー済みになる
STOP_HOOK_ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
  if (( 10#$ROUNDS <= 10#$MAX_ROUNDS )); then
    record_state
  fi
  record_lastseen
  exit 0
fi

# レビュー対象の差分がない
if [[ -z "$RECORDS" ]]; then
  record_lastseen
  exit 0
fi

# 前回 Stop から何も変わっていなければ、このターンは編集していない
# 記録が無い・読めない場合は判断できないので、編集があったものとして進む
# 目印を作れない環境では状態表が固定されるため、一致しても変化していない証拠にならない
if [[ "$HASH_USABLE" == "true" && -f "$LASTSEEN_FILE" ]] &&
  [[ "$RECORDS" == "$(cat "$LASTSEEN_FILE" 2>/dev/null)" ]]; then
  exit 0
fi

PREVIOUS=""
# 壊れた記録は読まなかったことにする。絞り込みを誤るより全体を見せるほうが安全
if [[ -f "$STATE_FILE" ]] && ! grep -qv "$TAB" "$STATE_FILE" 2>/dev/null; then
  PREVIOUS=$(LC_ALL=C sort -u "$STATE_FILE" 2>/dev/null || true)
fi

if [[ -n "$PREVIOUS" ]]; then
  # 前回に無く今回にある行が、レビューされていない変更
  PENDING=$(LC_ALL=C comm -13 <(printf '%s\n' "$PREVIOUS") <(printf '%s\n' "$RECORDS") 2>/dev/null | cut -f2- || true)
else
  # 記録が無ければ絞り込みの土台も無いので、全体を見せる
  PENDING=$(printf '%s\n' "$RECORDS" | cut -f2-)
  SCOPE_USABLE=false
fi

# 前回から増えた変更がない（元に戻した、ステージしただけ）
# 目印を作れない環境では変化していないと言い切れないため、黙らずに全体を見せ続ける
if [[ -z "$PENDING" && "$HASH_USABLE" == "true" ]]; then
  record_state
  record_lastseen
  exit 0
fi

# 上限に達したことは1度だけ伝える
# 黙って止まると、見るものが無いのか止まったのかが分からない
# 伝えたあとも記録は更新しない。未レビューのまま残す
if (( 10#$ROUNDS >= 10#$MAX_ROUNDS )); then
  record_lastseen
  if (( 10#$ROUNDS > 10#$MAX_ROUNDS )); then
    exit 0
  fi
  record_rounds "$(( 10#$ROUNDS + 1 ))"
  if [[ -n "$PENDING" ]]; then
    LIMIT_REMAINING="未レビューの変更が $(printf '%s\n' "$PENDING" | wc -l | tr -d ' ') 件残っています。"
  else
    # 目印を作れない環境では範囲を出せず、件数も数えられない
    LIMIT_REMAINING="未レビューの変更が残っています。"
  fi
  LIMIT_NOTICE="自動レビューは1セッションあたり ${MAX_ROUNDS} 回までです。上限に達したので、以降このセッションでは自動で依頼しません。
${LIMIT_REMAINING}見るなら /review-diff を使ってください。"
  jq -n --arg context "$LIMIT_NOTICE" '{
    hookSpecificOutput: {
      hookEventName: "Stop",
      additionalContext: $context
    }
  }'
  exit 0
fi

# 一覧が長くなると、絞り込みで浮いたぶんを一覧自体が食う
MAX_SCOPE_FILES="${CLAUDE_AUTO_REVIEW_MAX_SCOPE_FILES:-40}"
[[ "$MAX_SCOPE_FILES" =~ ^[0-9]+$ ]] || MAX_SCOPE_FILES=40
# 先頭がゼロの指定を8進数と解釈させない
if (( $(printf '%s\n' "$PENDING" | wc -l) > 10#$MAX_SCOPE_FILES )); then
  SCOPE_USABLE=false
fi

# codex が使えるかどうかの判定
# ログイン済みでもトークン切れなら 401 になる
# 次のターンでも直らない類の失敗を直前に起こしていれば、一定時間は codex レビューを誘わない
# 待機の目印は codex レビュー側が理由付きで作る。hook は読み、待ち終わったら消す
# 目印は codex レビュー側と hook の両方から同じ場所に見える必要がある
# 一時ディレクトリは両者が同じ値を見る保証が無いため、固定のパスを使う
COOLDOWN_FILE="${CLAUDE_CODEX_COOLDOWN_FILE:-/tmp/claude/codex-review-cooldown}"
COOLDOWN_SECONDS="${CLAUDE_CODEX_COOLDOWN_SECONDS:-21600}"
[[ "$COOLDOWN_SECONDS" =~ ^[0-9]+$ ]] || COOLDOWN_SECONDS=21600
CODEX_AUTH_FILE="${CODEX_HOME:-${HOME}/.codex}/auth.json"

# 認証できない codex は 401 を返さず応答しなくなることがある
# hook 自体に制限時間があるため、待たされる可能性のある呼び出しは打ち切る
run_briefly() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 5 "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout 5 "$@"
  elif command -v perl >/dev/null 2>&1; then
    # macOS には打ち切り用のコマンドが無いが、perl は標準で入っている
    perl -e 'alarm shift; exec @ARGV' 5 "$@"
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

  # 時計のずれで未来の時刻になっていると、そのぶん待ち続けてしまう
  # 現在時刻に置き換えるだけでは経過ゼロで待機が続くため、目印自体を打ち直す
  if (( marked_at > now )); then
    touch "$COOLDOWN_FILE"
    return 1
  fi

  # 先頭がゼロの指定を8進数と解釈させない
  if (( now - marked_at >= 10#$COOLDOWN_SECONDS )); then
    rm -f "$COOLDOWN_FILE"
    return 0
  fi
  return 1
}

if codex_usable; then
  REVIEWERS=$'   - doarakko-config:code-reviewer（観点: all）\n   - doarakko-config:codex-reviewer'
else
  REVIEWERS='   - doarakko-config:code-reviewer（観点: all）'
fi

if [[ "$SCOPE_USABLE" == "true" ]]; then
  SCOPE_SECTION="レビュー範囲は次のファイルの未コミット変更だけ。ほかのファイルは前回のレビューで見ているので読み直さない。
$(printf '%s\n' "$PENDING" | sed 's/^/   - /')
パスはリポジトリのルート基準。差分の取り方は各レビュアーの定義に従う。
範囲内の変更を理解するために、範囲外のファイルを Read / Grep で読むのは構わない。指摘の対象にはしない。"
else
  SCOPE_SECTION="レビュー範囲は未コミットの変更すべて。"
fi

# 記録は、依頼を出せると確定してから残す
# 途中で落ちた場合にレビュー済みとみなされ、この差分が二度と対象にならないのを避けるため
record_state
record_lastseen
record_rounds "$(( 10#$ROUNDS + 1 ))"

REVIEW_INSTRUCTION="未レビューの変更があります。完了する前に次を実行してください。

${SCOPE_SECTION}

1. 次のサブエージェントを 1 メッセージ内で同時に起動する。上のレビュー範囲をそのまま渡す
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
