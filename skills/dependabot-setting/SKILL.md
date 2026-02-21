---
name: dependabot-setting
description: Dependabotの設定ファイル（.github/dependabot.yml）を生成するときに使用
allowed-tools: Read, Write, Glob, Grep, Bash(ls *), Bash(git remote *), Bash(mkdir *)
---

# Dependabot設定ファイル生成

リポジトリの構成を検出し、`.github/dependabot.yml` を生成する。

## 手順

### 1. リポジトリ解析
以下のファイルを検索し、使用されているパッケージエコシステムを検出する。

| ファイル | エコシステム |
|----------|-------------|
| `package.json` | npm |
| `requirements.txt`, `Pipfile`, `pyproject.toml`, `setup.py`, `setup.cfg` | pip |
| `Gemfile` | bundler |
| `go.mod` | gomod |
| `pom.xml` | maven |
| `build.gradle`, `build.gradle.kts` | gradle |
| `Dockerfile`, `docker-compose.yml`, `docker-compose.yaml` | docker |
| `.github/workflows/*.yml` | github-actions |
| `*.tf` | terraform |
| `composer.json` | composer |
| `Cargo.toml` | cargo |

### 2. スケジュール間隔の決定
`git remote get-url origin` からオーナーを取得し、リポジトリの種別を判定する。

- **個人リポジトリ**: `interval: "monthly"` を使用
- **Organizationリポジトリ**: ユーザーに希望するスケジュール間隔（`daily`, `weekly`, `monthly`）を確認する

### 3. 既存設定の確認
- `.github/dependabot.yml` が既に存在する場合、内容を読み取りユーザーに上書き確認する

### 4. アプリケーション非影響の依存関係を特定
マニフェストファイルを読み取り、ビルド成果物に含まれないツール群を特定する。
以下のカテゴリに該当するもののみを `development` グループのパターンとする。

**対象カテゴリ:**
- linter（例: `eslint*`, `stylelint*`, `pylint*`, `flake8*`, `rubocop*`, `golangci-lint*`）
- formatter（例: `prettier*`, `black*`, `isort*`）
- 型定義（例: `@types/*`）
- テストツール（例: `jest*`, `vitest*`, `pytest*`, `rspec*`, `@testing-library/*`）
- Git hooks / CI補助（例: `husky*`, `lint-staged*`, `commitlint*`）

**必ずマニフェストに実在する依存のみをパターンに含めること。**

### 5. 設定ファイル生成

#### グルーピングルール

**development（アプリケーション非影響の依存関係）:**
- 手順4で特定したツール群を `patterns` で明示指定:
  ```yaml
  groups:
    development:
      patterns:
        - "eslint*"
        - "prettier*"
        - "@types/*"
        - "jest*"
  ```

**GitHub Actions:**
- 全アクションを1つのグループにまとめる:
  ```yaml
  groups:
    all-actions:
      patterns:
        - "*"
  ```

**Terraform:**
- 全プロバイダーを1つのグループにまとめる:
  ```yaml
  groups:
    all-providers:
      patterns:
        - "*"
  ```

#### 共通設定
- `schedule.interval`: 手順2で決定した値
- `directory`: マニフェストファイルが存在するディレクトリ（ルートなら `"/"`）

### 6. 出力
- `.github/dependabot.yml` に書き出す
- `.github/` ディレクトリが存在しない場合は作成する
- 生成した設定の概要をユーザーに表示する

## 生成例（個人リポジトリの場合）

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

## 絶対に守るべきルール
- 検出されたエコシステムのみ設定に含める（推測で追加しない）
- developmentグループにはマニフェストに実在するアプリケーション非影響の依存のみを含める
- 既存の `.github/dependabot.yml` がある場合は必ず確認してから上書きする
- development・GitHub Actions・Terraformは必ずグルーピングする
