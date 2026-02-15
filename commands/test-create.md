---
description: 現在の差分から変更されたファイルを検出し、テストを自動生成する
argument-hint: [対象ファイルパス]
allowed-tools: Bash(git diff *), Bash(npm *), Bash(npx *), Bash(go test *), Bash(pytest *), Read, Write, Edit, Grep, Glob
---

# テスト自動生成コマンド

現在の差分から変更されたファイルを検出し、テストを自動生成する。

## 使用方法
```
/test-create [対象ファイルパス]
```
ファイルパス省略時は差分から自動検出。

## 変更情報（自動取得）
- 変更ファイル一覧: !`git diff --name-only HEAD 2>/dev/null; git diff --name-only --cached 2>/dev/null`

## 手順
1. 上記の変更ファイル一覧、または指定ファイル ($ARGUMENTS) を対象にする
2. 各ファイルに対して `test-generator` Subagentを**並列実行**:
   - 言語・フレームワークを識別
   - 既存テストパターンを学習
   - テストファイルを生成
3. 生成結果をまとめて表示
4. テスト実行して検証
5. `code-reviewer` Subagentで生成テストの品質を検証（test観点、test-review Skill使用）
6. 品質問題があれば修正

## Subagent活用
複数ファイルのテスト生成を `test-generator` Subagentで並列実行。

## サポート言語
- TypeScript/JavaScript: Jest, Vitest, Mocha
- Python: pytest, unittest
- Go: testing パッケージ

## 生成内容
- 公開関数・クラスのテスト
- 正常系・異常系・エッジケース
- 既存テストと同じスタイル

## 注意事項
- 生成されたテストは必ず確認
- 既存テストファイルがある場合は重複を避ける
- モック・スタブは必要に応じて手動追加
