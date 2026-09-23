---
description: 自動レビューをどこまで行うかをこのセッションで切り替える
argument-hint: [off|review|fix|auto]
disable-model-invocation: true
allowed-tools: Bash(mkdir *), Bash(printf *), Bash(cat *), Bash(rm *), Bash(find *)
---

# 自動レビュー切り替えコマンド

ターンの終わりに走る自動レビューを、このセッションでどこまで行うかを切り替える。

## 使用方法
```
/auto-review [off|review|fix|auto]
```

| 指定 | 挙動 |
| --- | --- |
| `off` | レビューも修正もしない |
| `review` | レビューするが修正はしない |
| `fix` | レビューし、Critical / High は同じターンで修正する |
| `auto` | 指定を消して権限の状態へ合わせる（既定） |

省略時は現在の指定を表示するだけで、何も書き換えない。

## 現在の状態（自動取得）
- セッション: !`printf '%s\n' "${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID}}"`
- 指定: !`cat "/tmp/claude/auto-review-mode/${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID}}" 2>/dev/null || printf '指定なし、またはセッションを取得できません\n'`

## 指定
$ARGUMENTS

## 手順

1. 指定が空なら、上の現在の状態と、指定が無いときの対応づけを表示して終わる

   | 権限の状態 | 指定が無いときの挙動 |
   | --- | --- |
   | plan | 何もしない（指定より優先される） |
   | default（Manual） | レビューするが修正はしない |
   | acceptEdits / auto / dontAsk / bypassPermissions | レビューし、Critical / High は修正する |

2. 指定が `off` / `review` / `fix` / `auto` のいずれでもなければ、受け付ける値を示して終わる。書き換えはしない
3. 上のセッションが取得できていなければ、取得できなかったことを伝えて終わる。セッションを特定できないまま書くと、ほかのセッションまで巻き込む
4. 置き場を用意する

   ```bash
   mkdir -p /tmp/claude/auto-review-mode
   ```

5. 指定を書く。`auto` なら消す

   ```bash
   printf '%s\n' "<指定>" > "/tmp/claude/auto-review-mode/<セッション>"
   ```

   ```bash
   rm -f "/tmp/claude/auto-review-mode/<セッション>"
   ```

6. 古い指定を掃除する。セッションは戻ってこないため、残っていても読まれない

   ```bash
   find /tmp/claude/auto-review-mode -type f -mtime +7 -delete 2>/dev/null || true
   ```

7. 切り替えた結果を1行で伝える

## 制約

- 指定はこのセッションだけに効く。新しいセッションは必ず既定から始まる
- 確認は挟まない。この操作だけで完結させる
- セッションが取得できないときに、全体へ効く場所へ書き換えてはいけない
- セッションの取得に2つの名前が並ぶのは、どちらが先に評価されても壊れないようにするため。`${CLAUDE_SESSION_ID}`は公式の置換で、この綴りのままでないと展開されない（`:-`を挟むと一致しない）。`CLAUDE_CODE_SESSION_ID`は文書化されていないが実機に存在する環境変数で、置換より先にシェルが評価された場合の受け皿になる。どちらも同じセッションを指すため、先に解決したほうを使ってよい
