# Dependabot PR統合コマンド

複数のDependabot PRを1つのPRにまとめる。

## 使用方法
```
/dp-merge [--close-originals]
```

## 手順
1. `gh pr list --author "app/dependabot"` でDependabot PRを取得
2. リアクションでフィルタリング（thumbs_down/eyesはスキップ）
3. 統合ブランチを作成（`dependabot/combined-updates-{timestamp}`）
4. 各PRの変更を**並列で分析**し、順次マージ:
   - コンフリクトはロックファイル再生成で自動解決を試行
5. テスト・リント実行
6. 統合PRを作成
7. `--close-originals` 指定時は元PRをクローズ

## Subagent活用
各PRの変更分析をTask toolで並列実行し、マージ可否を判断。

## スキップルール
- thumbs_down: 統合したくないPR
- eyes: 確認中・保留中のPR
