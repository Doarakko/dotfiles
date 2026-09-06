# 生成例

## クールダウンなし（個人リポジトリの場合）

```yaml
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "monthly"
    groups:
      development:
        patterns:
          - "eslint*"
          - "prettier*"
          - "@types/*"
          - "jest*"
          - "@testing-library/*"

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "monthly"
    groups:
      all-actions:
        patterns:
          - "*"

  - package-ecosystem: "terraform"
    directory: "/"
    schedule:
      interval: "monthly"
    groups:
      all-providers:
        patterns:
          - "*"

  - package-ecosystem: "docker"
    directory: "/"
    schedule:
      interval: "monthly"
```

## クールダウンあり

```yaml
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"
    cooldown:
      default-days: 3
      semver-major-days: 14
      semver-minor-days: 7
      semver-patch-days: 3
    groups:
      development:
        patterns:
          - "eslint*"
          - "prettier*"
          - "@types/*"
          - "jest*"
          - "@testing-library/*"

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    cooldown:
      default-days: 7
    groups:
      all-actions:
        patterns:
          - "*"
```
