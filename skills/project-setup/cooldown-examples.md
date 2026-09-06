# クールダウンの書き込み例

7日相当を設定する場合。単位はパッケージマネージャごとに異なる。

```ini
; .npmrc
min-release-age=7
```

```yaml
# pnpm-workspace.yaml
minimumReleaseAge: 10080
```

```yaml
# .yarnrc.yml
npmMinimalAgeGate: 10080
```

```toml
# bunfig.toml
[install]
minimumReleaseAge = 604800
```

```toml
# pyproject.toml
[tool.uv]
exclude-newer = "7 days"
```
