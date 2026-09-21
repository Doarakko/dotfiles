#!/bin/bash

# hooks/auto-review.sh の判定表。codex の状態と、レビュー依頼に codex が並ぶかを突き合わせる。
# codex 本体は呼ばず、スタブを PATH の先頭に置いて状態を作る。

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
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
# 実機に入っている codex を経路から外す
# 残っていると未インストールのケースが本物を拾い、ログイン済みの開発機では結果が変わる
CODEX_FREE_PATH=""
while IFS= read -r -d ':' path_entry || [[ -n "$path_entry" ]]; do
  [[ -z "$path_entry" || -x "${path_entry}/codex" ]] && continue
  CODEX_FREE_PATH="${CODEX_FREE_PATH:+${CODEX_FREE_PATH}:}${path_entry}"
done < <(printf '%s:' "$PATH")
export PATH="$WORK/bin:$CODEX_FREE_PATH"
unset CODEX_API_KEY CODEX_ACCESS_TOKEN OPENAI_API_KEY

# 差分のあるリポジトリを用意する。レビュー対象が無いと hook は黙るため
# 追跡ファイルの変更を試すにはコミットが1つ要る。CI の runner には署名者の設定が無い
git -C "$WORK/repo" init --quiet
printf 'base\n' >"$WORK/repo/tracked.txt"
printf 'gone\n' >"$WORK/repo/gone.txt"
git -C "$WORK/repo" add tracked.txt gone.txt
git -C "$WORK/repo" -c user.email=test@example.com -c user.name=test commit --quiet -m base
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

# 特定のファイルだけ目印を作れない状態にする
REAL_SHASUM=$(command -v shasum) || REAL_SHASUM=""
if [[ -z "$REAL_SHASUM" ]]; then
  echo "shasum が見つかりません。このテストは目印の作成を差し替えて確かめるため、本物が要ります"
  exit 1
fi
install_failing_shasum() {
  cat >"$WORK/bin/shasum" <<EOF
#!/bin/bash
for arg in "\$@"; do
  [[ "\$arg" == *unreadable.txt ]] && exit 1
done
exec ${REAL_SHASUM} "\$@"
EOF
  chmod +x "$WORK/bin/shasum"
}

uninstall_shasum_stub() {
  rm -f "$WORK/bin/shasum"
}

# 目印を作る手段そのものが無い状態にする
install_broken_shasum() {
  printf '#!/bin/bash\nexit 127\n' >"$WORK/bin/shasum"
  chmod +x "$WORK/bin/shasum"
}

# 標準入力は通るがファイル引数では落ちる状態にする
# 手段の有無を標準入力だけで判定すると、この形を取り逃がす
install_argument_failing_shasum() {
  cat >"$WORK/bin/shasum" <<EOF
#!/bin/bash
[ "\$#" -gt 0 ] && exit 1
exec ${REAL_SHASUM}
EOF
  chmod +x "$WORK/bin/shasum"
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
# 応答しない codex を掴んでも、判定側は必ず戻ってくるようにする
run_hook() {
  if command -v perl >/dev/null 2>&1; then
    perl -e 'alarm shift; exec @ARGV' 15 env TMPDIR="$WORK" bash "$HOOK"
  else
    TMPDIR="$WORK" bash "$HOOK"
  fi
}

judge() {
  local output status
  output=$(jq -n --arg s "${SESSION_OVERRIDE:-auto-review-test-${CASE}}" --arg c "${CWD_OVERRIDE:-$WORK/repo}" \
    --argjson active "${STOP_HOOK_ACTIVE:-false}" \
    '{session_id:$s,cwd:$c,stop_hook_active:$active}' | run_hook 2>/dev/null)
  status=$?
  # 途中で落ちたのか、意図して黙っているのかを取り違えないようにする
  if [[ "$status" -ne 0 ]]; then
    printf 'error'
    return
  fi
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

SESSION_START_HOOK="${AUTO_REVIEW_SESSION_START_HOOK:-hooks/auto-review-session-start.sh}"

session_start() {
  jq -n --arg s "$1" --arg c "${CWD_OVERRIDE:-$WORK/repo}" --arg src "${2:-startup}" \
    '{session_id:$s,cwd:$c,source:$src}' |
    env TMPDIR="$WORK" bash "$SESSION_START_HOOK" >/dev/null 2>&1
}

# 依頼・上限の通知・無言を見分ける
verdict_for() {
  local context status
  context=$(context_for "$1")
  status=$?
  if [[ "$status" -ne 0 ]]; then
    printf 'error'
  elif [[ -z "$context" ]]; then
    printf 'silent'
  elif printf '%s' "$context" | grep -q '上限に達した'; then
    printf 'limit'
  else
    printf 'review'
  fi
}

context_for() {
  local raw status
  raw=$(jq -n --arg s "$1" --arg c "${CWD_OVERRIDE:-$WORK/repo}" \
    --argjson active "${STOP_HOOK_ACTIVE:-false}" \
    '{session_id:$s,cwd:$c,stop_hook_active:$active}' | run_hook 2>/dev/null)
  status=$?
  # 途中で落ちたのか、意図して黙っているのかを取り違えないようにする
  [[ "$status" -ne 0 ]] && return "$status"
  printf '%s' "$raw" | jq -r '.hookSpecificOutput.additionalContext // ""'
}

check() {
  local label=$1 actual=$2 expected=$3
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL  expected=%-12s actual=%-12s %s\n' "$expected" "$actual" "$label"
    FAILURES=$((FAILURES + 1))
  fi
}

# 依頼文からレビュー範囲を取り出す。絞れていないときは all
scope_for() {
  local context status
  context=$(context_for "$1")
  status=$?
  if [[ "$status" -ne 0 ]]; then
    printf 'error'
    return
  fi
  if [[ -z "$context" ]]; then
    printf 'silent'
  elif printf '%s' "$context" | grep -q '未コミットの変更すべて'; then
    printf 'all'
  else
    printf '%s' "$context" | sed -n 's/^   - \(.*\)$/\1/p' |
      grep -v '^doarakko-config:' | sort | tr '\n' ',' | sed 's/,$//'
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
export CLAUDE_CODEX_COOLDOWN_SECONDS=0800
expect claude-only '待機時間の先頭がゼロ'
export CLAUDE_CODEX_COOLDOWN_SECONDS=1800

# 時計のずれで目印が未来に飛んでも、待機は待機時間の長さで終わる
future_at() {
  touch -t "$(date -v+"$1"M +%Y%m%d%H%M 2>/dev/null || date -d "$1 minutes" +%Y%m%d%H%M)" \
    "$CLAUDE_CODEX_COOLDOWN_FILE"
}
future_at 1440
expect claude-only '目印が未来の時刻'
marker_mtime=$(stat -c %Y "$CLAUDE_CODEX_COOLDOWN_FILE" 2>/dev/null ||
  stat -f %m "$CLAUDE_CODEX_COOLDOWN_FILE" 2>/dev/null || echo 0)
if (( marker_mtime > $(date +%s) + 60 )); then
  printf 'FAIL  目印が未来の時刻のまま据え置かれている\n'
  FAILURES=$((FAILURES + 1))
fi

# 同じセッションで差分が変わっていなければ、二度目は依頼しない
# レビュー済みの記録が残っていることの確認でもある
rm -f "$CLAUDE_CODEX_COOLDOWN_FILE"
export SESSION_OVERRIDE="auto-review-test-repeat"
expect both '同じ差分の一度目'
expect silent '同じ差分の二度目'
unset SESSION_OVERRIDE

# 応答しない codex に付き合わない。hook には制限時間があるため
cat >"$WORK/bin/codex" <<'EOF'
#!/bin/bash
sleep 30
EOF
chmod +x "$WORK/bin/codex"
expect claude-only '応答しない codex'

# 途中で打ち切られた差分は、レビュー済みにしてはいけない
jq -n --arg s "auto-review-test-killed" --arg c "$WORK/repo" \
  '{session_id:$s,cwd:$c,stop_hook_active:false}' |
  TMPDIR="$WORK" bash "$HOOK" >/dev/null 2>&1 &
hook_pid=$!
sleep 1
kill "$hook_pid" 2>/dev/null
wait "$hook_pid" 2>/dev/null
if [[ -f "$WORK/claude-auto-review/auto-review-test-killed.reviewed" ]]; then
  printf 'FAIL  打ち切られたのにレビュー済みとして記録されている\n'
  FAILURES=$((FAILURES + 1))
fi
install_codex 0

# この hook 由来で継続中のターンでは繰り返し依頼しない
rm -f "$CLAUDE_CODEX_COOLDOWN_FILE"
export STOP_HOOK_ACTIVE=true
expect silent 'hook 由来の継続ターン'
unset STOP_HOOK_ACTIVE

# git 管理外では何もしない
export CWD_OVERRIDE="$WORK"
expect silent 'git 管理外'
unset CWD_OVERRIDE

# ここからレビュー範囲の絞り込み。記録が残らないよう、ケースごとにセッションを分ける
# 回数の上限で止まると範囲を確かめられないので、この区間では十分に大きくしておく
export CLAUDE_AUTO_REVIEW_MAX_ROUNDS=1000
rm -f "$CLAUDE_CODEX_COOLDOWN_FILE"

# 初回は絞り込みの土台が無いので全体を見せる
printf 'y\n' >"$WORK/repo/tracked.txt"
check '初回は全体' "$(scope_for scope-first)" all

# 前回レビュー以降に変わったファイルだけを対象にする。これが絞り込みの本命
printf 'z\n' >"$WORK/repo/second.txt"
check '2ファイルの一度目は全体' "$(scope_for scope-narrow)" all
printf 'zz\n' >"$WORK/repo/second.txt"
check '変えた1ファイルだけを対象にする' "$(scope_for scope-narrow)" second.txt

# 内容を変えずにステージしても、レビュー対象は増えない
git -C "$WORK/repo" add second.txt
check 'ステージしただけでは黙る' "$(scope_for scope-narrow)" silent

# レビュー済みの内容へ戻したら、レビューするものは残らない
check '戻す前の一度目' "$(scope_for scope-revert)" all
printf 'base\n' >"$WORK/repo/tracked.txt"
printf 'zz\n' >"$WORK/repo/second.txt"
check '元に戻したら黙る' "$(scope_for scope-revert)" silent

# 実行ビットだけの変更も拾う。内容が同じでも差分にはなる
check '実行ビットを変える前' "$(scope_for scope-mode)" all
chmod +x "$WORK/repo/second.txt"
check '実行ビットだけの変更を拾う' "$(scope_for scope-mode)" second.txt
chmod -x "$WORK/repo/second.txt"

# 消えたファイルもレビュー対象。削除そのものを見てもらう
check '削除する前' "$(scope_for scope-delete)" all
rm -f "$WORK/repo/gone.txt"
check '削除したファイルを対象にする' "$(scope_for scope-delete)" gone.txt

# 空白を含む名前が1行に収まる
check '空白を含む名前の前' "$(scope_for scope-space)" all
printf 'sp\n' >"$WORK/repo/with space.txt"
check '空白を含む名前を1件として出す' "$(scope_for scope-space)" 'with space.txt'
rm -f "$WORK/repo/with space.txt"

# 改行を含む名前は一覧へ出せない。黙って落とさず全体へ倒す
check '改行を含む名前の前' "$(scope_for scope-newline)" all
printf 'nl\n' >"$WORK/repo/$(printf 'a\nb').txt"
check '改行を含む名前があれば全体へ倒す' "$(scope_for scope-newline)" all
rm -f "$WORK/repo/$(printf 'a\nb').txt"

# 記録が壊れていたら読まない。絞り込みを誤るより全体を見せる
check '記録を壊す前' "$(scope_for scope-broken)" all
printf 'zzz\n' >"$WORK/repo/second.txt"
printf 'garbage\n' >"$WORK/claude-auto-review/scope-broken.reviewed"
check '壊れた記録は全体へ倒す' "$(scope_for scope-broken)" all

# 一覧が長いと絞り込みで浮いたぶんを一覧自体が食う
export CLAUDE_AUTO_REVIEW_MAX_SCOPE_FILES=1
check '上限を超える前' "$(scope_for scope-cap)" all
printf '1\n' >"$WORK/repo/cap1.txt"
printf '2\n' >"$WORK/repo/cap2.txt"
check '上限を超えたら全体へ倒す' "$(scope_for scope-cap)" all
printf '1b\n' >"$WORK/repo/cap1.txt"
check '上限の内側なら絞る' "$(scope_for scope-cap)" cap1.txt

# 壊れた上限で落とさない。落ちると差分がレビュー済みとして記録されてしまう
export CLAUDE_AUTO_REVIEW_MAX_SCOPE_FILES=bad
printf '3\n' >"$WORK/repo/cap1.txt"
check '上限の指定が数値でない' "$(scope_for scope-cap)" cap1.txt
unset CLAUDE_AUTO_REVIEW_MAX_SCOPE_FILES

# 先頭がゼロの上限を8進数と解釈させない
# 上限が実際に効く件数でないと、8進数として読んでも同じ結果になり検査にならない
# 010 は10進で10、8進で8。その間の件数を保留にして両者を分ける
export CLAUDE_AUTO_REVIEW_MAX_SCOPE_FILES=010
check '先頭がゼロの上限の一度目' "$(scope_for scope-octal)" all
octal_expected=""
for n in 1 2 3 4 5 6 7 8 9; do
  printf '%s\n' "$n" >"$WORK/repo/oct-${n}.txt"
  octal_expected="${octal_expected:+${octal_expected},}oct-${n}.txt"
done
check '上限の先頭がゼロ' "$(scope_for scope-octal)" "$octal_expected"
unset CLAUDE_AUTO_REVIEW_MAX_SCOPE_FILES
rm -f "$WORK/repo"/oct-*.txt

# サブディレクトリで起動しても取りこぼさない
# 差分の列挙はルート基準、未追跡ファイルの列挙と存在判定は現在地基準で、噛み合わないと黙る
mkdir -p "$WORK/repo/sub"
printf 'base\n' >"$WORK/repo/sub/nested.txt"
git -C "$WORK/repo" add sub/nested.txt
git -C "$WORK/repo" -c user.email=test@example.com -c user.name=test commit --quiet -m sub -- sub/nested.txt
export CWD_OVERRIDE="$WORK/repo/sub"
printf 'x\n' >"$WORK/repo/sub/nested.txt"
check 'サブディレクトリ起動の一度目' "$(scope_for scope-subdir)" all
printf 'xx\n' >"$WORK/repo/sub/nested.txt"
check 'サブディレクトリ配下の再編集を拾う' "$(scope_for scope-subdir)" sub/nested.txt
# 現在地より上にある未追跡ファイルも対象にする
printf 'up\n' >"$WORK/repo/above.txt"
check '現在地より上の未追跡ファイルを拾う' "$(scope_for scope-subdir)" above.txt
rm -f "$WORK/repo/above.txt"
unset CWD_OVERRIDE

# 先頭がハイフンの名前をオプションと解釈させない
printf 'd\n' >"$WORK/repo/-dash.txt"
check '先頭ハイフンの一度目' "$(scope_for scope-dash)" all
printf 'dd\n' >"$WORK/repo/-dash.txt"
check '先頭ハイフンの再編集を拾う' "$(scope_for scope-dash)" '-dash.txt'
rm -f -- "$WORK/repo/-dash.txt"

# 目印を作れないファイルの扱い
# 読めないファイルはレビューもできないので、全量レビューを毎ターン要求してはいけない
printf 'readable\n' >"$WORK/repo/unreadable.txt"
git -C "$WORK/repo" add unreadable.txt
git -C "$WORK/repo" -c user.email=test@example.com -c user.name=test commit --quiet -m unreadable -- unreadable.txt
printf 'changed\n' >"$WORK/repo/unreadable.txt"
check '目印を作れるうちの一度目' "$(scope_for scope-unknown)" all
install_failing_shasum
check '目印を作れなくなった変化を拾う' "$(scope_for scope-unknown)" unreadable.txt
check '読めないままなら繰り返し要求しない' "$(scope_for scope-unknown)" silent
# 消えた場合と同じ目印にすると、この変化が拾えなくなる
rm -f "$WORK/repo/unreadable.txt"
check '読めないファイルの削除を拾う' "$(scope_for scope-unknown)" unreadable.txt
uninstall_shasum_stub
printf 'readable again\n' >"$WORK/repo/unreadable.txt"
check '読めるようになったら再び拾う' "$(scope_for scope-unknown)" unreadable.txt

# 目印を作る手段そのものが無ければ、絞り込みの根拠が無い
# ファイル個別の事情と混ぜると、すべてが同じ値で固定され変更が黙って落ちる
check '手段が使えるうちの一度目' "$(scope_for scope-nohash)" all
install_broken_shasum
printf 'A\n' >"$WORK/repo/tracked.txt"
check '手段が無ければ全体へ倒す' "$(scope_for scope-nohash)" all
printf 'AA\n' >"$WORK/repo/tracked.txt"
check '手段が無いまま変更しても黙らない' "$(scope_for scope-nohash)" all
uninstall_shasum_stub
printf 'base\n' >"$WORK/repo/tracked.txt"

# 標準入力だけが通る手段も、使えないものとして扱う
check '引数で落ちる手段の一度目' "$(scope_for scope-argfail)" all
install_argument_failing_shasum
printf 'B\n' >"$WORK/repo/tracked.txt"
check '引数で落ちる手段なら全体へ倒す' "$(scope_for scope-argfail)" all
printf 'BB\n' >"$WORK/repo/tracked.txt"
check '引数で落ちる手段のまま変更しても黙らない' "$(scope_for scope-argfail)" all
uninstall_shasum_stub
printf 'base\n' >"$WORK/repo/tracked.txt"
printf 'readable\n' >"$WORK/repo/unreadable.txt"

# 最初のコミットがまだ無いリポジトリでも落ちず、ステージ済みが対象になる
mkdir -p "$WORK/fresh"
git -C "$WORK/fresh" init --quiet
printf 'staged\n' >"$WORK/fresh/staged.txt"
git -C "$WORK/fresh" add staged.txt
export CWD_OVERRIDE="$WORK/fresh"
check 'コミット無しの一度目' "$(scope_for scope-fresh)" all
printf 'more\n' >"$WORK/fresh/staged.txt"
check 'コミット無しでもステージ済みを追える' "$(scope_for scope-fresh)" staged.txt
unset CWD_OVERRIDE

# 編集の無いターンでは黙る
printf 'turn\n' >"$WORK/repo/tracked.txt"
check '編集のあるターンは依頼する' "$(verdict_for scope-turn)" review
check '編集の無いターンは黙る' "$(verdict_for scope-turn)" silent
printf 'turn2\n' >"$WORK/repo/tracked.txt"
check '再び編集すれば依頼する' "$(verdict_for scope-turn)" review

# セッション開始時点を控えておけば、既存の未コミット変更があっても最初のターンは黙る
session_start scope-fresh-start
check '開始時点の変更だけなら黙る' "$(verdict_for scope-fresh-start)" silent

# 前回 Stop 時点の記録が無ければ、編集の有無を判断できない。黙らず発火する
session_start scope-lastseen-gone
check '控えがあるうちは黙る' "$(verdict_for scope-lastseen-gone)" silent
rm -f "$WORK/claude-auto-review/scope-lastseen-gone.lastseen"
check '前回時点の控えが無ければ黙らない' "$(verdict_for scope-lastseen-gone)" review
# ただしレビュー済みにはしない。何か編集すれば既存の変更も対象に入る
printf 'edited\n' >"$WORK/repo/tracked.txt"
check '編集すれば開始時点の変更も対象になる' "$(scope_for scope-fresh-start)" all

# 1セッションあたりの回数に上限がある
export CLAUDE_AUTO_REVIEW_MAX_ROUNDS=2
REVIEWED_RECORD="$WORK/claude-auto-review/scope-rounds.reviewed"
printf 'r1\n' >"$WORK/repo/tracked.txt"
check '上限の内側は依頼する' "$(verdict_for scope-rounds)" review
printf 'r2\n' >"$WORK/repo/tracked.txt"
check '上限ちょうどまでは依頼する' "$(verdict_for scope-rounds)" review

# 上限ちょうどの回は実際に依頼を出しているので、その継続ターンは記録する
# 記録しないと、次の通知がレビュー済みのファイルまで未レビューとして数え直す
before_continue=$(cat "$REVIEWED_RECORD" 2>/dev/null || true)
printf 'r2-fixed\n' >"$WORK/repo/tracked.txt"
STOP_HOOK_ACTIVE=true verdict_for scope-rounds >/dev/null
if [[ "$(cat "$REVIEWED_RECORD" 2>/dev/null || true)" == "$before_continue" ]]; then
  printf 'FAIL  上限ちょうどの回の継続ターンが記録されていない\n'
  FAILURES=$((FAILURES + 1))
fi

reviewed_at_limit=$(cat "$REVIEWED_RECORD" 2>/dev/null || true)
printf 'r3\n' >"$WORK/repo/tracked.txt"
check '上限に達したら知らせる' "$(verdict_for scope-rounds)" limit

# 上限で止めた変更は未レビューのまま残す。記録そのものを比べる
# 内容の文字列は記録に現れないため、それを探す検査は常に素通りする
if [[ "$(cat "$REVIEWED_RECORD" 2>/dev/null || true)" != "$reviewed_at_limit" ]]; then
  printf 'FAIL  上限の通知でレビュー済みとして記録されている\n'
  FAILURES=$((FAILURES + 1))
fi

# 上限の通知もターンを続けるため、直後の継続ターンで記録してはいけない
STOP_HOOK_ACTIVE=true verdict_for scope-rounds >/dev/null
if [[ "$(cat "$REVIEWED_RECORD" 2>/dev/null || true)" != "$reviewed_at_limit" ]]; then
  printf 'FAIL  上限の通知後の継続ターンでレビュー済みとして記録されている\n'
  FAILURES=$((FAILURES + 1))
fi

printf 'r4\n' >"$WORK/repo/tracked.txt"
check '知らせるのは一度だけ' "$(verdict_for scope-rounds)" silent

# 壊れた回数は0として扱う。上限で止めるより余分に回るほうが安全
printf 'broken\n' >"$WORK/claude-auto-review/scope-rounds.rounds"
printf 'r5\n' >"$WORK/repo/tracked.txt"
check '回数が数値でなければ0として扱う' "$(verdict_for scope-rounds)" review

# hook 由来の継続ターンは回数に数えない
printf 'r6\n' >"$WORK/repo/tracked.txt"
STOP_HOOK_ACTIVE=true verdict_for scope-rounds >/dev/null
if [[ "$(cat "$WORK/claude-auto-review/scope-rounds.rounds" 2>/dev/null)" != "1" ]]; then
  printf 'FAIL  継続ターンが回数に数えられている\n'
  FAILURES=$((FAILURES + 1))
fi
unset CLAUDE_AUTO_REVIEW_MAX_ROUNDS

# 使い切った回数を戻すのは、セッションが始まり直したときだけ
printf '3\n' >"$WORK/claude-auto-review/scope-reset.rounds"
session_start scope-reset resume
if [[ "$(cat "$WORK/claude-auto-review/scope-reset.rounds" 2>/dev/null)" != "3" ]]; then
  printf 'FAIL  再開で回数が戻っている\n'
  FAILURES=$((FAILURES + 1))
fi
session_start scope-reset compact
if [[ "$(cat "$WORK/claude-auto-review/scope-reset.rounds" 2>/dev/null)" != "3" ]]; then
  printf 'FAIL  圧縮後の再開で回数が戻っている\n'
  FAILURES=$((FAILURES + 1))
fi
session_start scope-reset startup
if [[ -f "$WORK/claude-auto-review/scope-reset.rounds" ]]; then
  printf 'FAIL  開始で回数が戻っていない\n'
  FAILURES=$((FAILURES + 1))
fi

# 圧縮はターンの途中で起きる。そこで控えを取り直すと、そのターンの編集が飲まれる
session_start scope-compact
printf 'compacted\n' >"$WORK/repo/tracked.txt"
session_start scope-compact compact
check '圧縮を挟んでも編集のあったターンは依頼する' "$(verdict_for scope-compact)" review

session_start scope-compact-quiet
session_start scope-compact-quiet compact
check '圧縮を挟んでも編集が無ければ黙る' "$(verdict_for scope-compact-quiet)" silent
printf 'base\n' >"$WORK/repo/tracked.txt"

# 差分が無ければ何も言わない
# ステージしたものが残っているので、作業ツリーと索引の両方をコミット時点へ戻す
rm -f "$WORK/repo/cap1.txt" "$WORK/repo/cap2.txt" "$WORK/repo/second.txt" "$WORK/repo/dirty.txt"
printf 'base\n' >"$WORK/repo/tracked.txt"
printf 'gone\n' >"$WORK/repo/gone.txt"
printf 'base\n' >"$WORK/repo/sub/nested.txt"
printf 'readable\n' >"$WORK/repo/unreadable.txt"
git -C "$WORK/repo" add -A
expect silent '差分なし'

if [[ "$FAILURES" -eq 0 ]]; then
  echo "すべてのケースが期待どおりです"
else
  echo "${FAILURES} 件が期待と異なります"
  exit 1
fi
