---
description: 現在のローカル変更をレビューする
argument-hint: [対象ファイル・ディレクトリ]
allowed-tools: Bash(git status *), Bash(git diff *), Bash(codex exec *), Bash(npm run lint *), Bash(npx eslint *), Bash(ruff check *), Bash(golangci-lint run *), Read, Grep, Glob
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
   - `codex`が使えない環境では`codex-reviewer`がスキップを報告するので、その旨を結果に含める
4. 自動チェックツール実行（ESLint、Ruff、golangci-lint等）
5. 両レビュアーの指摘をマージし、同一箇所を指す重複指摘は1件にまとめて表示（どのレビュアー由来かを併記）
6. 修正に入るか確認（AskUserQuestion）
7. CLAUDE.md更新が必要か確認

## Subagent活用
`code-reviewer` Subagentに登録されたSkillの全観点で並列実行。あわせて`codex-reviewer` Subagentを並列で起動し、別モデルによるsecond opinionを得る。

## 出力形式
- 変更統計（ファイル数、追加/削除行数）
- 自動チェック結果
- 問題点と改善提案
- 次のステップ

## ユーザー確認（AskUserQuestion）

### 修正への移行確認
レビュー結果表示後に確認:
- **AIに判断を任せる（推奨）**: セキュリティ・バグ・型エラー・パフォーマンス問題は必ず修正、それ以外は内容を読んで判断
- **個別に選択する**: 各項目について個別に確認
- **修正しない**: レビュー結果の確認のみで終了

### 個別選択の場合
各項目について確認:
- **AIに判断を任せる**: この項目についてAIが対応要否を判断
- **修正する**: この項目を修正対象に追加
- **修正しない**: この項目をスキップ

### CLAUDE.md更新確認
修正後、プロジェクト全体に適用すべきルールがあれば確認:
- セキュリティパターン、コーディング規約、繰り返し発生するエラーパターン等
