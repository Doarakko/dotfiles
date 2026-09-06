---
description: プランファイルをHTMLページとして表示する
argument-hint: [プランファイルのパス]
allowed-tools: Skill, Read, Bash(ls *), Bash(head *), Bash(mkdir *), Edit(//tmp/claude/report/**), Edit(//private/tmp/claude/report/**)
---

# プラン表示コマンド

プランファイルをHTMLページとして公開し、ブラウザで読めるようにする。

## 使用方法
```
/plan-view [プランファイルのパス]
```
パス省略時は最新のプランを表示。

## プラン候補（自動取得）
- 新しい順: !`ls -t ~/.claude/plans/*.md .claude/plans/*.md 2>/dev/null | head -10`

## 対象
指定されたパス: $ARGUMENTS（省略時は上記の先頭）

## 手順
1. 対象のプランファイルを読む
2. `doarakko-config:report-artifact` スキルを種別`plan`で起動し、その手順に従って公開する
3. 公開されたURLを表示する
