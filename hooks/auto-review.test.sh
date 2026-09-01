#!/bin/bash

# hooks/auto-review.sh の判定表。codex の状態と、レビュー依頼に codex が並ぶかを突き合わせる。
# codex 本体は呼ばず、スタブを PATH の先頭に置いて状態を作る。

set -uo pipefail

cd "$(dirname "$0")/.."
HOOK="${AUTO_REVIEW_HOOK:-hooks/auto-review.sh}"
FAILURES=0

WORK=$(mktemp -d "${TMPDIR:-/tmp}/auto-review-test.XXXXXX") || exit 1
if [[ -z "$WORK" || ! -d "$WORK" ]]; then
  echo "作業ディレクトリを作成できませんでした"
  exit 1
fi
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin" "$WORK/codex-home" "$WORK/repo"
export CODEX_HOME="$WORK/codex-home"
export CLAUDE_CODEX_COOLDOWN_FILE="$WORK/cooldown"
# 既定値と違う長さにする。同じ値だと hook が変数を読めていなくてもテストが通ってしまう
export CLAUDE_CODEX_COOLDOWN_SECONDS=1800
export PATH="$WORK/bin:$PATH"
unset CODEX_API_KEY CODEX_ACCESS_TOKEN OPENAI_API_KEY

# 差分のあるリポジトリを用意する。レビュー対象が無いと hook は黙るため
git -C "$WORK/repo" init --quiet
printf 'x\n' >"$WORK/repo/dirty.txt"

# ログイン状態を切り替えられるスタブ
install_codex() {
  cat >"$WORK/bin/codex" <<EOF
#!/bin/bash
[[ "\$1" == "login" && "\$2" == "status" ]] && exit ${1}
exit 0
EOF
  chmod +x "$WORK/bin/codex"
}

uninstall_codex() {
  rm -f "$WORK/bin/codex"
}

# 待機の判定は現在時刻との差で決まるため、固定の日付ではなく何分前かで指定する
minutes_ago() {
  date -v-"$1"M +%Y%m%d%H%M 2>/dev/null || date -d "$1 minutes ago" +%Y%m%d%H%M
}

login_at() {
  touch -t "$(minutes_ago "$1")" "$CODEX_HOME/auth.json"
}

cooldown_at() {
  touch -t "$(minutes_ago "$1")" "$CLAUDE_CODEX_COOLDOWN_FILE"
}

# セッションIDを変え、レビュー済みの記録も作業ディレクトリに閉じ込める
# 記録が残っていると、差分が変わっていないとみなされて hook が黙るため
CASE=0
judge() {
  local output
  output=$(jq -n --arg s "auto-review-test-${CASE}" --arg c "${CWD_OVERRIDE:-$WORK/repo}" \
    --argjson active "${STOP_HOOK_ACTIVE:-false}" \
    '{session_id:$s,cwd:$c,stop_hook_active:$active}' | TMPDIR="$WORK" bash "$HOOK" 2>/dev/null)
  # 何か言うときは Stop hook の形式に沿っていること
  if [[ -n "$output" ]] &&
    ! printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "Stop"' >/dev/null 2>&1; then
    printf 'malformed'
    return
  fi
  if printf '%s' "$output" | grep -q 'codex-reviewer'; then
    printf 'both'
  elif printf '%s' "$output" | grep -q 'code-reviewer'; then
    printf 'claude-only'
  else
    printf 'silent'
  fi
}

expect() {
  local expected=$1 label=$2 actual
  # 番号を進めるのは呼び出し側。判定は部分シェルで動くため、そちらでは引き継がれない
  CASE=$((CASE + 1))
  actual=$(judge)
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL  expected=%-12s actual=%-12s %s\n' "$expected" "$actual" "$label"
    FAILURES=$((FAILURES + 1))
  fi
}

# codex が無ければ Claude のレビューだけを依頼する
uninstall_codex
rm -f "$CLAUDE_CODEX_COOLDOWN_FILE"
expect claude-only '未インストール'

# 未ログインでは呼ばない。呼んでも 401 になるため
install_codex 1
expect claude-only '未ログイン'

# 環境変数による認証はログイン状態の照会に出ないので、こちらで拾う
for auth_var in OPENAI_API_KEY CODEX_API_KEY CODEX_ACCESS_TOKEN; do
  export "${auth_var}=dummy"
  expect both "未ログインだが ${auth_var} で認証"
  unset "$auth_var"
done

# ログイン済みで待機の目印が無ければ両方に依頼する
install_codex 0
login_at 600
expect both 'ログイン済み'

# 直前に失敗していれば待機する。トークン切れで毎ターン 401 を踏まないため
cooldown_at 10
expect claude-only '失敗直後'
# 目印には失敗の理由が書かれている。待機中に消してはいけない
if [[ ! -f "$CLAUDE_CODEX_COOLDOWN_FILE" ]]; then
  printf 'FAIL  待機中に目印が消えている\n'
  FAILURES=$((FAILURES + 1))
fi

# 待機時間を過ぎたら再開し、目印は消す
cooldown_at 60
expect both '待機時間を経過'
if [[ -f "$CLAUDE_CODEX_COOLDOWN_FILE" ]]; then
  printf 'FAIL  待機時間の経過後に目印が残っている\n'
  FAILURES=$((FAILURES + 1))
fi

# 再ログインすれば待機を打ち切る
cooldown_at 10
login_at 5
expect both '再ログイン済み'
if [[ -f "$CLAUDE_CODEX_COOLDOWN_FILE" ]]; then
  printf 'FAIL  再ログイン後に目印が残っている\n'
  FAILURES=$((FAILURES + 1))
fi

# 壊れた待機時間で hook を落とさない。落ちると差分がレビュー済みとして記録されてしまう
login_at 600
cooldown_at 10
export CLAUDE_CODEX_COOLDOWN_SECONDS=bad
expect claude-only '待機時間の指定が数値でない'
export CLAUDE_CODEX_COOLDOWN_SECONDS=1800

# この hook 由来で継続中のターンでは繰り返し依頼しない
rm -f "$CLAUDE_CODEX_COOLDOWN_FILE"
export STOP_HOOK_ACTIVE=true
expect silent 'hook 由来の継続ターン'
unset STOP_HOOK_ACTIVE

# git 管理外では何もしない
export CWD_OVERRIDE="$WORK"
expect silent 'git 管理外'
unset CWD_OVERRIDE

# 差分が無ければ何も言わない
rm -f "$WORK/repo/dirty.txt"
expect silent '差分なし'

if [[ "$FAILURES" -eq 0 ]]; then
  echo "すべてのケースが期待どおりです"
else
  echo "${FAILURES} 件が期待と異なります"
  exit 1
fi
