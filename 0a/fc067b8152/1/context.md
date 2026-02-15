# Session Context

## User Prompts

### Prompt 1

以下を見て活かせるものがあれば教えろhttps://code.claude.com/docs/en/skills

### Prompt 2

[Request interrupted by user for tool use]

### Prompt 3

今いるリポジトリで全て管理している

### Prompt 4

agentをskilに移行した場合、agentはどうなるの？

### Prompt 5

2,3,4をやって

### Prompt 6

<bash-input>code ./</bash-input>

### Prompt 7

<bash-stdout></bash-stdout><bash-stderr></bash-stderr>

### Prompt 8

# コード差分レビューコマンド

現在のローカル変更をレビューする。

## 使用方法
```
/review-diff [対象ファイル・ディレクトリ]
```
対象省略時は全変更をレビュー。

## 手順
1. `git status`、`git diff` で変更取得
2. プロジェクト環境を分析（言語、フレームワーク）
3. `code-reviewer` Subagentを**並列実行**してレビュー:
   - security: セキュリティチェック（security-review Skill使用）
   - ...

### Prompt 9

# コード差分レビューコマンド

現在のローカル変更をレビューする。

## 使用方法
```
/review-diff [対象ファイル・ディレクトリ]
```
対象省略時は全変更をレビュー。

## 手順
1. `git status`、`git diff` で変更取得
2. プロジェクト環境を分析（言語、フレームワーク）
3. `code-reviewer` Subagentを**並列実行**してレビュー:
   - security: セキュリティチェック（security-review Skill使用）
   - ...

