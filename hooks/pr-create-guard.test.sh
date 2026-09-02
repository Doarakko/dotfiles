#!/bin/bash

# hooks/pr-create-guard.sh の判定表。入力コマンドと期待する判定を突き合わせる。
# 判定は deny / context / silent の3種。

set -uo pipefail

cd "$(dirname "$0")/.."
GUARD="hooks/pr-create-guard.sh"
FAILURES=0

# 成果物の有無で判定が変わる。実際の置き場所を読まないよう使い捨ての場所へ向ける
# サンドボックス下では既定の一時領域に作れないため、そこで書ける場所を使う
MEDIA_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/pr-create-guard.XXXXXX") || exit 1
trap 'rm -rf "$MEDIA_ROOT"' EXIT
export CLAUDE_E2E_OUTPUT_ROOT="$MEDIA_ROOT"
MEDIA_DIR="$MEDIA_ROOT/$(basename "$(git rev-parse --show-toplevel)")/$(git branch --show-current | tr '/' '-')"
mkdir -p "$MEDIA_DIR"

# 添付を受け付けない gh では成果物があっても差し戻さない。その版では該当ケースを見送る
if gh --version 2>/dev/null | grep -qE 'gh version (2\.(99|[0-9]{3,})|[3-9])'; then
  ATTACH_SUPPORTED=1
else
  ATTACH_SUPPORTED=0
fi

verdict() {
  local output=$1
  if [[ -z "$output" ]]; then
    printf 'silent'
  elif printf '%s' "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null; then
    printf 'deny'
  else
    printf 'context'
  fi
}

judge() {
  verdict "$(jq -Rn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}' | bash "$GUARD" 2>/dev/null)"
}

# 作業ディレクトリを伝えると、そのブランチの成果物まで見に行く
judge_here() {
  verdict "$(jq -Rn --arg c "$1" --arg d "$PWD" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' | bash "$GUARD" 2>/dev/null)"
}

expect() {
  local expected=$1 command=$2 actual
  actual=$(judge "$command")
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL  expected=%-8s actual=%-8s %s\n' "$expected" "$actual" "${command//$'\n'/\\n}"
    FAILURES=$((FAILURES + 1))
  fi
}

expect_here() {
  local expected=$1 command=$2 actual
  actual=$(judge_here "$command")
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL  expected=%-8s actual=%-8s %s\n' "$expected" "$actual" "${command//$'\n'/\\n}"
    FAILURES=$((FAILURES + 1))
  fi
}

# ドラフト指定がないPR作成は差し戻す
expect deny 'gh pr create'
expect deny 'gh pr create --title "x"'
expect deny 'gh pr create --fill'
expect deny 'gh pr create --draft=false'
expect deny 'gh pr create --draft=FALSE'
expect deny 'gh pr create -d=false'
expect deny 'gh pr create -Fdesc'

# ドラフト指定があれば通し、pr-zero の手順を添える
expect context 'gh pr create --draft'
expect context 'gh pr create -d'
expect context 'gh pr create -dt "x"'
expect context 'gh pr create -de'
expect context 'gh pr create -ed'
expect context 'gh pr create -dR owner/repo'
expect context 'gh pr create -d=true'
expect context 'gh pr create --draft=True'
expect context 'gh pr create --draft=t'

# PRを直接作らない呼び出しには干渉しない
expect silent 'gh pr create --web'
expect silent 'gh pr create -w'
expect silent 'gh pr create -fw'
expect silent 'gh pr create --help'
expect silent 'gh pr create --dry-run'

# PR作成と無関係なコマンドには干渉しない
expect silent 'npm test'
expect silent 'grep -rn "gh pr create" README.md'
expect silent 'git commit -m "docs: explain gh pr create"'
expect silent 'echo "gh pr create --fill"'

# クォート内の区切り文字やフラグを引数と取り違えない
expect context 'gh pr create --title "feat: a | b" --draft'
expect context 'gh pr create --title "fix; cleanup" --draft'
expect context 'gh pr create --title "a && b" --draft'
expect context 'gh pr create --title "x" --body "| col | col |" --draft'
expect context 'gh pr create --title "x" --body "Fixes #12; adds tests" --draft'
expect context 'gh pr create --title "x" --body "run cmd; done" -d'
expect context 'gh pr create --draft --body "(gh pr create)"'
expect deny 'gh pr create --title "add -d flag"'
expect deny "gh pr create --title 'a -d b'"

# シングルクォート内のアポストロフィやエスケープでペアリングを崩さない
expect deny "gh pr create --fill --body 'don'\\''t forget -d here'"
expect deny "gh pr create --fill --title 'Doarakko'\\''s PR' --body 'adds --draft flag'"
expect deny "gh pr create --fill --body 'it'\\''s --web ready'"
expect deny 'gh pr create --fill --body "x \" --draft \" y"'

# 複数行やヒアドキュメントで他行のフラグを拾わない
expect deny 'git log -d
gh pr create --title "x"'
expect deny 'gh pr create --title "x"
docker run -d nginx'
expect deny 'gh pr create --fill
gh pr view -w'
expect deny 'gh pr create --fill

docker run -d nginx'
expect deny 'gh pr create --fill&
docker run -d nginx'
expect context 'gh pr create --draft
docker run -d nginx'

# 行継続は1つの呼び出し。改行で切り離さない
expect context 'gh pr create \
  --draft \
  --title "x"'
expect deny 'gh pr create \
  --title "x" \
  --fill'
expect deny 'gh pr view --web
gh pr create --title "x"'
expect deny 'gh pr create --title "x" --body "$(cat <<EOF
use -d for draft
EOF
)"'

# 後続コマンドのフラグを拾わない
expect deny 'gh pr create --fill && docker run -d nginx'
expect context 'git push -u origin foo && gh pr create -d'

# 実行されるのは最初の呼び出し。後続の出現に引きずられない
expect deny 'gh pr create --fill; echo gh pr create --draft'
expect context 'gh pr create --draft -t X; echo gh pr create done'

# コマンド位置がどこであっても捕捉する
expect deny 'gh pr create;'
expect deny 'gh pr create&'
expect deny '$(gh pr create)'
expect deny 'if true; then gh pr create; fi'
expect deny 'for b in a; do gh pr create; done'
expect deny '{ gh pr create; }'
expect deny 'time gh pr create'
expect deny 'echo x | xargs -I{} gh pr create'

# 置換の結果は展開できないため、引数として読めるものだけで判定する
expect context 'gh pr create --title $(gen_title) --draft'

# 入出力を渡す形の置換も、閉じたあとに語が続く
expect deny 'gh pr create --draft --title <(echo a)#x --draft=false'
expect context 'gh pr create --draft --title >(cat)#x --fill'

# 置換が生む文字列の中の文字列をフラグと取り違えない
expect deny 'gh pr create --fill --title $(echo --web)'
expect deny 'gh pr create --fill --title $(echo -w)'
expect deny 'gh pr create --fill --title $(printf -- --dry-run)'
expect deny 'gh pr create --fill --title $(echo --draft)'
expect deny 'gh pr create --title `echo --web` --fill'

# 壊れた入力でセッションを止めない
expect silent ''
expect silent 'not json'
expect silent '{}'
expect silent 'gh pr create --title "unterminated'

# 語の先頭の注釈はその行の終わりまで捨てる。後続のコマンドを見失わない
expect deny 'gh pr create --fill # make a pr
gh pr view -w'
expect deny 'gh pr create --fill --title "x" # draft is fine'

# 注釈の中の例示を実行されるコマンドと取り違えない
expect context '# example: gh pr create --fill
gh pr create --draft --title "x"'
expect deny '# how to open a draft
gh pr create --fill'

# 部分式を閉じた直後の注釈で、呼び出しを見失わない
expect deny "(gh pr create --fill)#it's fine"
expect deny '(gh pr create --fill)#plain'
expect deny '(gh pr create --fill)# see --web'
expect deny '{ gh pr create --fill; }#it$(printf "\47")s fine'
expect context '(gh pr create --draft)#c'

# エスケープされた文字は語の一部。区切りとして数えない
expect context 'gh pr create --title fix\ the\ #123 --draft'
expect deny 'gh pr create --draft --title \)#y --draft=false'
expect deny 'gh pr create --fill --title a\ b\ #c'

# 置換の中の部分式でも、閉じたのが置換かどうかを取り違えない
expect deny 'gh pr create --draft --title $( (echo a) )#z --draft=false'
expect context 'gh pr create --title $( (echo a) )#z --draft'

# 置換を閉じる括弧は語の内側。そのうしろの記号は注釈ではない
expect context 'gh pr create --title $(gen_title)#x --draft'
expect context 'gh pr create --title x$((1+2))#y --draft'
expect context 'gh pr create --title "$(gen_title)"#x --draft'

# クォートの内側の記号は注釈ではない
expect context 'gh pr create --title "# heading" --draft'
expect context "gh pr create --title '#1 fix' --draft"
expect deny 'gh pr create --title "# heading" --fill'

# 代替テキストを添えた添付指定で引数の読み取りが途中で終わらない
expect context 'gh pr create --draft --attach shot.png#login-error'
expect context 'gh pr create --draft --body "a#b" --attach shot.png#login-error'
expect context 'gh pr create --attach shot.png#login-error --draft'
expect context "gh pr create --draft --attach 'shot.png#login error'"
expect deny 'gh pr create --attach shot.png#login-error'

# 撮った成果物がなければ、作業ディレクトリを伝えても判定は変わらない
expect_here context 'gh pr create --draft'
expect_here deny 'gh pr create --fill'

if [[ "$ATTACH_SUPPORTED" -eq 0 ]]; then
  echo "gh が 2.99.0 未満のため、成果物の添付に関するケースは見送りました"
fi

# 成果物と呼べない中身では差し戻さない
: > "$MEDIA_DIR/notes.txt"
expect_here context 'gh pr create --draft'

# 撮った成果物があるのに添付がなければ差し戻す
: > "$MEDIA_DIR/01-login-form.png"
if [[ "$ATTACH_SUPPORTED" -eq 1 ]]; then
  expect_here deny 'gh pr create --draft'
  expect_here deny 'gh pr create --draft --title "x"'
else
  expect_here context 'gh pr create --draft'
fi
expect_here context 'gh pr create --draft --attach 01-login-form.png'
expect_here context 'gh pr create --draft --attach=01-login-form.png'
expect_here context "gh pr create --draft --attach '01-login-form.png#login form'"

# 添付できない成果物では差し戻さない。応えようのない差し戻しを繰り返さない
rm -f "$MEDIA_DIR/01-login-form.png"
: > "$MEDIA_DIR/01-shot.jpg"
expect_here context 'gh pr create --draft'
rm -f "$MEDIA_DIR/01-shot.jpg"
dd if=/dev/zero of="$MEDIA_DIR/10-big.webm" bs=1048576 count=11 2>/dev/null
expect_here context 'gh pr create --draft'
rm -f "$MEDIA_DIR/10-big.webm"

# 成果物と同じ名前のディレクトリは、手順が選べないので数えない
mkdir -p "$MEDIA_DIR/01-shot.png"
expect_here context 'gh pr create --draft'
rmdir "$MEDIA_DIR/01-shot.png"

# 手順が選ぶのと同じ綴りだけを数える
: > "$MEDIA_DIR/01-SHOT.PNG"
expect_here context 'gh pr create --draft'
rm -f "$MEDIA_DIR/01-SHOT.PNG"

# 注釈を切り出せない入力でも、字句解析器に任せて読み直すので素通りしない
expect deny "gh pr create --fill --title x\$(y)#it's fine"

# 動画だけでも成果物として数える
: > "$MEDIA_DIR/10-invite-flow.webm"
if [[ "$ATTACH_SUPPORTED" -eq 1 ]]; then
  expect_here deny 'gh pr create --draft'
  # 添付が後続コマンド側にあっても、この呼び出しの引数にはならない
  expect_here deny 'gh pr create --draft && echo --attach 10-invite-flow.webm'
fi

# ドラフトでない指定は成果物の有無によらず、ドラフトを求める文面で差し戻す
expect_here deny 'gh pr create --attach 10-invite-flow.webm'

# PRを直接作らない呼び出しには成果物があっても干渉しない
expect_here silent 'gh pr create --dry-run'
expect_here silent 'gh pr create --web'

# 作業ディレクトリを伝えなければ成果物は見に行かない
expect context 'gh pr create --draft'

if [[ "$FAILURES" -eq 0 ]]; then
  echo "すべてのケースが期待どおりです"
else
  echo "${FAILURES} 件が期待と異なります"
  exit 1
fi
