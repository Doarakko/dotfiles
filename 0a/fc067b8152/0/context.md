# Session Context

## User Prompts

### Prompt 1

allowManagedPermissionRulesOnlyとは？

### Prompt 2

claudecode のsandboxのデフォルトは？

### Prompt 3

autoAllowBashIfSandboxedha

### Prompt 4

[Request interrupted by user]

### Prompt 5

autoAllowBashIfSandboxedをtruにしたときのリスクは？

### Prompt 6

サンドボックスモードを有効にして

### Prompt 7

<bash-input>code ./</bash-input>

### Prompt 8

<bash-stdout></bash-stdout><bash-stderr></bash-stderr>

### Prompt 9

このリポジトリのファイルを変更しろ

### Prompt 10

.claude/settings.json

### Prompt 11

サンドボックスモードの話をしている

### Prompt 12

設定はそれで十分なのか？

### Prompt 13

network.allowedDomainsとは？

### Prompt 14

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

### Prompt 15

commit-splitの引数入らない

