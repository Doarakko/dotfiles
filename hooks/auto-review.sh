#!/bin/bash

# Claude Code 自動レビュー Hook
# 未レビューの差分が残ったまま作業を完了させないよう、レビューと修正を促す
# 2周目以降は前回レビュー以降に変わったファイルだけを対象にする

set -euo pipefail

INPUT=$(cat)

TAB=$'\t'

# セッションごとにレビュー済みの状態を記録する（リポジトリは汚さない）
# 記録するのは変更のあるパスと、その時点の内容の目印
# この記録は hook だけが読み書きするため一時ディレクトリでよい
# レビュー範囲は記録ではなく依頼文へ載せて渡すので、外部と置き場所を共有しない
STATE_DIR="${TMPDIR:-/tmp}/claude-auto-review"
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' | tr -cd 'A-Za-z0-9._-')
if [[ -z "$SESSION_ID" ]]; then
  SESSION_ID="unknown"
fi
STATE_FILE="${STATE_DIR}/${SESSION_ID}.reviewed"

# hook 入力の作業ディレクトリへ移動（取得できなければ現在地のまま）
HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
if [[ -n "$HOOK_CWD" && -d "$HOOK_CWD" ]]; then
  cd "$HOOK_CWD"
fi

# git 管理外では何もしない
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

# リポジトリのルートへ揃える
# 差分の列挙はルート基準のパスを返すが、未追跡ファイルの列挙とファイルの存在判定は現在地基準になる
# サブディレクトリで起動していると両者が噛み合わず、変更を取りこぼす
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [[ -n "$REPO_ROOT" && -d "$REPO_ROOT" ]]; then
  cd "$REPO_ROOT"
fi

HEAD_EXISTS=false
if git rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
  HEAD_EXISTS=true
fi

# 目印を作る手段そのものが使えないか
# ファイル個別の「読めない」と混ぜると、すべてが同じ値で固定され変更が黙って落ち続ける
HASH_USABLE=true
printf '' | shasum >/dev/null 2>&1 || HASH_USABLE=false

# 変更のあるパスを列挙する
list_changed_paths() {
  if [[ "$HEAD_EXISTS" == "true" ]]; then
    # 名前の付け替えは検出させない。片側のパスしか挙がらないと記録と突き合わせられない
    git diff HEAD --name-only --no-renames -z 2>/dev/null || true
  else
    # 最初のコミットがまだ無いリポジトリでは、記録済みのものがそのまま変更にあたる
    git ls-files --cached -z 2>/dev/null || true
  fi
  # 未追跡ファイルは差分に現れないため、別に挙げる
  git ls-files --others --exclude-standard -z 2>/dev/null || true
}

# パスごとの内容の目印を作る
# 先頭がハイフンのパスをオプションと解釈させないため、区切りを必ず置く
mark_for() {
  local target=$1 sum=""
  if [[ -f "$target" ]]; then
    sum=$(shasum -- "$target" 2>/dev/null) || sum=""
  elif [[ -e "$target" || -L "$target" ]]; then
    # 中身を直接読めないもの（入れ子のリポジトリ、ディレクトリを指すリンク）
    # 差分から目印を作れるのは最初のコミットがある場合だけ
    if [[ "$HEAD_EXISTS" == "true" ]]; then
      sum=$(git diff HEAD -- "$target" 2>/dev/null | shasum 2>/dev/null) || sum=""
    fi
  else
    # 消えたファイル。目印が無いこと自体が変化になる
    printf 'gone'
    return
  fi
  if [[ -z "$sum" ]]; then
    # 読めないので中身の変化までは追えない
    # 消えた場合と同じ値にすると、変化しない値のまま状態の移り変わりも拾えなくなる
    printf 'unknown'
    return
  fi
  # 実行ビットだけが変わった場合も拾えるよう、目印に混ぜる
  printf '%s%s' "${sum%% *}" "$([[ -x "$target" ]] && printf 'x')"
}

# レビュー範囲を絞れるか。絞れないときは未コミットの変更すべてを対象にする
SCOPE_USABLE=$HASH_USABLE

RECORDS=""
# ループをパイプラインへ入れない。部分シェルになると絞り込みの可否が外へ伝わらない
while IFS= read -r -d '' changed_path; do
  case "$changed_path" in
  *"$TAB"* | *$'\n'*)
    # 1行1ファイルで記録するため、改行やタブを含む名前は一覧へ出せない
    # 記録には残して変化を追えるようにし、範囲の提示だけ諦める
    SCOPE_USABLE=false
    RECORDS="${RECORDS}$(mark_for "$changed_path")${TAB}$(printf '%s' "$changed_path" | tr '\n\t' '??')"$'\n'
    continue
    ;;
  esac
  RECORDS="${RECORDS}$(mark_for "$changed_path")${TAB}${changed_path}"$'\n'
done < <(list_changed_paths)
RECORDS=$(printf '%s' "$RECORDS" | LC_ALL=C sort -u)

record_state() {
  mkdir -p "$STATE_DIR"
  if [[ -n "$RECORDS" ]]; then
    printf '%s\n' "$RECORDS" >"$STATE_FILE"
  else
    : >"$STATE_FILE"
  fi
}

# この hook 由来で継続中のターン。レビュー済みとして記録し停止を許可する
STOP_HOOK_ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
  record_state
  exit 0
fi

# レビュー対象の差分がない
if [[ -z "$RECORDS" ]]; then
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
パスはリポジトリのルート基準。現在地に関わらず効くよう \`git diff HEAD -- :/<パス>\` の形で渡す。
範囲内の変更を理解するために、範囲外のファイルを Read / Grep で読むのは構わない。指摘の対象にはしない。"
else
  SCOPE_SECTION="レビュー範囲は未コミットの変更すべて。"
fi

# レビュー済みの記録は、依頼を出せると確定してから残す
# 途中で落ちた場合にレビュー済みとみなされ、この差分が二度と対象にならないのを避けるため
record_state

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
