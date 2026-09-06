#!/usr/bin/env bash
# コマンド・スキル・エージェントの定義を検証する。
# CIとローカルの両方から実行する。依存はbashとgrep/sedのみ。
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

status=0
fail() {
  printf 'FAIL %s\n' "$1" >&2
  status=1
}

definitions() {
  ls commands/*.md 2>/dev/null
  ls skills/*/SKILL.md 2>/dev/null
  ls agents/*.md 2>/dev/null
}

# 0. 検査対象を見失っていないか。
#    definitions と grep は失敗を握りつぶすので、
#    ディレクトリ構成が変わると全検査が0件で通ってしまう
for pattern in 'commands/*.md' 'skills/*/SKILL.md' 'agents/*.md'; do
  # shellcheck disable=SC2086
  if [ "$(ls $pattern 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]; then
    fail "$pattern が0件。ディレクトリ構成を確認する"
  fi
done

# 1. frontmatterが存在し、閉じているか
for f in $(definitions); do
  if [ "$(head -1 "$f")" != "---" ]; then
    fail "$f: frontmatterが --- で始まっていない"
    continue
  fi
  if ! sed -n '2,50p' "$f" | grep -qx -- '---'; then
    fail "$f: frontmatterが閉じていない"
  fi
done

# 2. 照合されない権限指定を使っていないか。
#    Claude Codeは Edit(...) と Read(...) しか照合せず、
#    Write(...) / NotebookEdit(...) / MultiEdit(...) / Glob(...) は無視して起動時に警告を出す。
for f in $(definitions); do
  frontmatter=$(sed -n '2,50p' "$f" | sed -n '1,/^---$/p')
  bad=$(printf '%s\n' "$frontmatter" \
    | grep -o -E '\b(Write|NotebookEdit|MultiEdit|Glob)\([^)]*\)' || true)
  if [ -n "$bad" ]; then
    fail "$f: 照合されない権限指定がある。Edit(...) か Read(...) で書く: $(printf '%s' "$bad" | tr '\n' ' ')"
  fi
done

# 3. doarakko-config:<name> の参照先が実在するか
refs=$(grep -rho -E 'doarakko-config:[a-z0-9-]+' commands skills agents hooks 2>/dev/null \
  | sed 's/^doarakko-config://' | sort -u)
if [ -z "$refs" ]; then
  fail "doarakko-config: の参照が1件も見つからない。検査が空振りしている"
fi
for name in $refs; do
  if [ ! -f "skills/$name/SKILL.md" ] && [ ! -f "agents/$name.md" ] && [ ! -f "commands/$name.md" ]; then
    fail "doarakko-config:$name の参照先が無い（skills/ agents/ commands/ のいずれにも $name が無い）"
  fi
done

if [ "$status" -eq 0 ]; then
  echo "definitions ok"
fi
exit "$status"
