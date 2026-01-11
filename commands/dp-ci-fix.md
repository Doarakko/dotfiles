# Dependabot PR CI修正コマンド

DependabotのPRでCI失敗しているものを自動修正する。

## 使用方法
```
/dp-ci-fix
```

## 手順
1. `gh pr list --author "app/dependabot"` でDependabot PRを取得
2. CI失敗しているPRをフィルタリング
3. 各PRに対して `pr-ci-fixer` Subagentを**並列実行**:
   - ブランチをチェックアウト
   - CI失敗を分析・修正
   - 修正があればコミット・プッシュ
   - CI結果を待機して確認
4. 元のブランチに戻る
5. 結果レポートを表示

## Subagent活用
複数PRの修正を並列で実行するため、Task toolで `pr-ci-fixer` Subagentを各PRに対して起動する。

## 制約
- メジャーバージョンアップの場合はマイグレーションガイドを確認
- ignoreコメントは極力避け、実コードを修正
