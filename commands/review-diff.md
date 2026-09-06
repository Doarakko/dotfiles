---
description: 現在のローカル変更をレビューする
argument-hint: [対象ファイル・ディレクトリ]
allowed-tools: Skill, Bash(git status *), Bash(git diff *), Bash(codex exec *), Bash(npm run lint *), Bash(npx eslint *), Bash(ruff check *), Bash(golangci-lint run *), Bash(git rev-parse *), Bash(mkdir *), Read, Edit(//tmp/claude/report/**), Edit(//private/tmp/claude/report/**), Grep, Glob
---

# コード差分レビューコマンド

現在のローカル変更をレビューする。

## 使用方法
```
/review-diff [対象ファイル・ディレクトリ]
```
対象省略時は全変更をレビュー。

## 変更情報（自動取得）
- ステータス: !`git status --short`
- ステージ済み差分: !`git diff --cached`
- 未ステージ差分: !`git diff`

## 対象
指定された対象: $ARGUMENTS（省略時は全変更）

## 手順
1. 上記の自動取得データを元にレビュー
2. プロジェクト環境を分析（言語、フレームワーク）
3. `code-reviewer` Subagentと`codex-reviewer` Subagentを1メッセージ内で同時に起動（`code-reviewer`の観点はSubagentのSkill定義に従う）
   - 未インストールや未ログインで`codex`が使えない環境では`codex-reviewer`がスキップを報告するので、その旨を結果に含める
4. 自動チェックツール実行（ESLint、Ruff、golangci-lint等）
5. 両レビュアーの指摘をマージし、同一箇所を指す重複指摘は1件にまとめて表示（どのレビュアー由来かを併記）
6. `doarakko-config:report-artifact` スキルを種別`review-diff`で起動し、その手順に従ってHTMLページを公開する
7. `doarakko-config:review-followup` スキルを起動し、その手順に従って修正に入るかを確認する
8. 修正した場合は、同じファイルパスでHTMLページを再公開する

## Subagent活用
`code-reviewer` Subagentに登録されたSkillの全観点で並列実行。あわせて`codex-reviewer` Subagentを並列で起動し、別モデルによるsecond opinionを得る。

## 出力形式
- 変更統計（ファイル数、追加/削除行数）
- 自動チェック結果
- 問題点と改善提案
- 次のステップ
