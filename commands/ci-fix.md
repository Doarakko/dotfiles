---
description: 現在のブランチのPRでCI失敗を自動修正する
allowed-tools: Bash(gh pr checks *), Bash(gh run view *), Bash(git add *), Bash(git commit *), Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git merge *), Bash(npm *), Bash(npx *), Bash(ruff *), Bash(golangci-lint *), Read, Write, Edit, Grep, Glob
---

# CI修正コマンド

現在のブランチのPRでCI失敗を自動修正する。

## 使用方法
```
/ci-fix
```

## CI情報（自動取得）
- CIステータス: !`gh pr checks 2>/dev/null || echo "PRが見つかりません"`
- 現在のブランチ: !`git branch --show-current`
- 未コミットの変更: !`git status --short`

## 手順
1. 上記の自動取得データからCI失敗を特定
2. コンフリクト確認、あれば解消
3. 失敗タイプに応じて修正:
   - lint: 自動修正ツール実行
   - type: 型エラーを分析・修正
   - test: テスト実行して失敗箇所を修正
   - build: 依存関係更新
   - security: セキュリティ修正
4. 修正内容を表示（コミットしない）

## 制約
- ignoreコメントは極力避け、実コードを修正
- 修正後はローカルで検証してから `/commit` でコミット
