# セキュリティアラート修正コマンド

リポジトリのセキュリティアラートを取得し、自動修正する。

## 使用方法
```
/dp-security-fix
```

## 対象アラート
1. Dependabot alerts: 依存関係の脆弱性
2. Code scanning alerts: コードの脆弱性
3. Secret scanning alerts: シークレット漏洩（参考表示のみ）

## 手順
1. `gh api repos/:owner/:repo/dependabot/alerts` でアラート取得
2. `gh api repos/:owner/:repo/code-scanning/alerts` でアラート取得
3. 重要度順に並べ替え（Critical > High > Medium > Low）
4. Dependabotアラート修正:
   - Node.js: `npm audit fix`
   - Python: `pip-audit --fix`
   - Go: `go get -u` + `go mod tidy`
   - Ruby: `bundle update --patch`
5. Code scanningアラートを分析・修正
6. テスト・リント実行
7. 修正内容を表示（コミットしない）

## 優先度
1. Secret Scanning（即座に対応）
2. Critical/High（自動修正）
3. Medium/Low（計画的に対応）
