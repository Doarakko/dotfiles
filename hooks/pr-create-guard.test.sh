#!/bin/bash

# hooks/pr-create-guard.sh の判定表。入力コマンドと期待する判定を突き合わせる。
# 判定は deny / context / silent の3種。

set -uo pipefail

cd "$(dirname "$0")/.."
GUARD="hooks/pr-create-guard.sh"
FAILURES=0

judge() {
  local output
  output=$(jq -Rn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}' | bash "$GUARD" 2>/dev/null)
  if [[ -z "$output" ]]; then
    printf 'silent'
  elif printf '%s' "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null; then
    printf 'deny'
  else
    printf 'context'
  fi
}

expect() {
  local expected=$1 command=$2 actual
  actual=$(judge "$command")
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

# 壊れた入力でセッションを止めない
expect silent ''
expect silent 'not json'
expect silent '{}'
expect silent 'gh pr create --title "unterminated'

if [[ "$FAILURES" -eq 0 ]]; then
  echo "すべてのケースが期待どおりです"
else
  echo "${FAILURES} 件が期待と異なります"
  exit 1
fi
