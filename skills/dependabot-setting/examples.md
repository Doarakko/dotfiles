# 生成例

## 個人リポジトリ（npm・GitHub Actions・Terraform・Docker）

```yaml
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "monthly"
    cooldown:
      default-days: 7
      semver-major-days: 30
      semver-minor-days: 7
      semver-patch-days: 3
    groups:
      npm-minor-and-patch:
        applies-to: version-updates
        patterns:
          - "*"
        update-types:
          - "minor"
          - "patch"

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "monthly"
    cooldown:
      default-days: 7
    groups:
      github-actions-minor-and-patch:
        applies-to: version-updates
        patterns:
          - "*"
        update-types:
          - "minor"
          - "patch"

  - package-ecosystem: "terraform"
    directory: "/"
    schedule:
      interval: "monthly"
    cooldown:
      default-days: 7
    groups:
      terraform-minor-and-patch:
        applies-to: version-updates
        patterns:
          - "*"
        update-types:
          - "minor"
          - "patch"

  - package-ecosystem: "docker"
    directory: "/"
    schedule:
      interval: "monthly"
    cooldown:
      default-days: 7
    groups:
      docker-minor-and-patch:
        applies-to: version-updates
        patterns:
          - "*"
        update-types:
          - "minor"
          - "patch"
```

## Organizationリポジトリ（間隔をweeklyにした場合）

```yaml
version: 2
updates:
  - package-ecosystem: "gomod"
    directory: "/"
    schedule:
      interval: "weekly"
    cooldown:
      default-days: 7
      semver-major-days: 30
      semver-minor-days: 7
      semver-patch-days: 3
    groups:
      gomod-minor-and-patch:
        applies-to: version-updates
        patterns:
          - "*"
        update-types:
          - "minor"
          - "patch"
```

## 可変な参照の固定

### GitHub Actions

固定前。

```yaml
steps:
  - uses: actions/checkout@v5
  - uses: actions/setup-node@v6
```

固定後。Dependabotは末尾のコメントを読み、更新時にSHAとコメントの両方を書き換える。

```yaml
steps:
  - uses: actions/checkout@93cb6efe18208431cddfb8368fd83d5badbf9bfd # v5.0.1
  - uses: actions/setup-node@2028fbc5c25fe9cf00d9f06a71cc4710d4507903 # v6.0.0
```

### Docker

固定前。`latest` はDependabotの更新対象にならず、同じ記述が別のイメージを指し続ける。

```dockerfile
FROM node:latest
FROM golang:1
```

固定後。具体的なバージョンタグにし、ダイジェストを併記して参照先を不変にする。

```dockerfile
FROM node:24.10.0-bookworm@sha256:<ダイジェスト>
FROM golang:1.25.3-bookworm@sha256:<ダイジェスト>
```

### ワークフローのランナーとバージョン入力

固定前。

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/setup-node@2028fbc5c25fe9cf00d9f06a71cc4710d4507903 # v6.0.0
        with:
          node-version: latest
```

固定後。ランナーはバージョン付きのラベルにし、ランタイムはリポジトリのファイルを読ませる。
`runs-on:` はDependabotの更新対象ではないため、自分で追う必要がある。

```yaml
jobs:
  test:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/setup-node@2028fbc5c25fe9cf00d9f06a71cc4710d4507903 # v6.0.0
        with:
          node-version-file: .node-version
```

### マニフェストの依存

固定前。`latest` と `*` は上限が無く、解決先が毎回変わりうる。

```json
{
  "dependencies": {
    "express": "latest",
    "lodash": "*"
  }
}
```

固定後。上限のあるレンジにし、解決結果は `package-lock.json` で固定する。
`react` のような既存のレンジ指定は対象外なので触らない。

```json
{
  "dependencies": {
    "express": "^5.1.0",
    "lodash": "^4.17.21",
    "react": "^19.2.0"
  }
}
```
