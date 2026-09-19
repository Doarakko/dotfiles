---
name: dependabot-setting
description: Dependabotの設定ファイル（.github/dependabot.yml）を生成するときに使用
allowed-tools: Read, Write, Edit, Glob, Bash(git remote *), Bash(mkdir *), Bash(gh api *), Bash(docker buildx imagetools inspect *)
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
| `.github/workflows/*.yml`, `.github/workflows/*.yaml` | github-actions |
| `*.tf` | terraform |
| `composer.json` | composer |
| `Cargo.toml` | cargo |
| `.pre-commit-config.yaml` | pre-commit |

### 2. スケジュール間隔の決定
`git remote get-url origin` からオーナーを取得し、リポジトリの種別を判定する。

- **個人リポジトリ**: `interval: "monthly"` を使用
- **Organizationリポジトリ**: ユーザーに希望するスケジュール間隔（`daily`, `weekly`, `monthly`）を確認する

### 3. 既存設定の確認

`.github/dependabot.yml` が既に存在する場合、内容を読み取り、以下の方針で追記する。ファイルごと作り直さない。

既存グループの扱いは `applies-to` で分かれる。以下では `applies-to` 未指定を `version-updates` として扱う。省略時の既定がそれだから。

**確認せず入れるもの:**
- 手順1で検出したエコシステムの `updates` エントリが無ければ、新しいエントリを追加する
- `cooldown` が無い、または手順4の値と違う場合は、手順4の値へ書き換える。必須なので、値が入っていることを理由に現状維持にしない
- `applies-to` が `version-updates` のグループが1つも無ければ、手順4の基準どおりに追加する

**ユーザーに確認してから変えるもの:**
- `applies-to` が `version-updates` の既存グループがあり、それが手順4の基準と違う場合。`patterns` が特定のパッケージだけを拾っているもの、`dependency-type` の `development` / `production` で分けているもの、このスキルの旧版が出力した `development` / `all-actions` / `all-providers` が該当する
- 残したままだと該当パッケージがそちらへ先に吸われ、マイナー・パッチのPRが割れる。依存は最初に一致したグループにしか入らないため
- `<エコシステム名>-minor-and-patch` へ統合する案を示し、PRの立ち方がどう変わるかを添えて確認する
- 確認が取れるまで既存グループを消さない

**既存エントリで触らないもの:**
- `applies-to: security-updates` のグループ。必須にしているのは `version-updates` のグループなので排他ではなく、消す理由がない
- `ignore`、`labels`、`reviewers`、`assignees`、`open-pull-requests-limit`、`registries`、`target-branch`、`commit-message`、`directories`、`schedule`、ルート以外の `directory`
- 値が入っていればそのまま残し、変えた方がよいと判断した場合も現状を報告するだけにする
- 新しく追加する `updates` エントリには手順4の共通設定どおり `schedule.interval` と `directory` を入れる

### 4. 設定ファイル生成

#### グルーピングルール（必須）

検出した全エコシステムに、マイナー・パッチをまとめるグループを1つ置く。
アプリケーションのパッケージマネージャに限定せず、`github-actions`・`docker`・`terraform` にも同じグループを置く。

```yaml
groups:
  npm-minor-and-patch:
    applies-to: version-updates
    patterns:
      - "*"
    exclude-patterns:
      - "eslint*"
      - "prettier*"
    update-types:
      - "minor"
      - "patch"
```

- グループ名は `<エコシステム名>-minor-and-patch` にする。グループ名はPRタイトルとブランチ名に出るため、`minor-and-patch` だけだとどのエコシステムのPRか区別できない

| エコシステム | グループ名 |
|-------------|-----------|
| `npm` | `npm-minor-and-patch` |
| `pip` | `pip-minor-and-patch` |
| `bundler` | `bundler-minor-and-patch` |
| `gomod` | `gomod-minor-and-patch` |
| `maven` | `maven-minor-and-patch` |
| `gradle` | `gradle-minor-and-patch` |
| `composer` | `composer-minor-and-patch` |
| `cargo` | `cargo-minor-and-patch` |
| `github-actions` | `github-actions-minor-and-patch` |
| `docker` | `docker-minor-and-patch` |
| `terraform` | `terraform-minor-and-patch` |
| `pre-commit` | `pre-commit-minor-and-patch` |

- グループ名に使えるのは英字・`|`・`_`・`-` で、先頭と末尾は英字。数字は使えない
- 開発用パッケージかどうかで分けない。`dependency-type` の `development` / `production` を使うとPRが割れ、まとめる意図と逆になる
- Lint系だけは `exclude-patterns` でグループから外す。下の「Lint系の除外」を見る
- メジャー更新はグループへ入れず、個別PRのままにする。破壊的変更を単独でレビューするため
- `applies-to: version-updates` を明示する。省略時の既定と同じだが、セキュリティ更新がまとまらないことを設定上わかるようにする
- `docker` はタグがSemVerとして解釈できる場合だけグループに入る。`latest` のようなタグは個別PRになる

#### Lint系の除外（必須）

Lint系はバージョンが上がると新しいルールが入り、既存のコードがCIのlintで落ちる。
グループに入れたままだと、落ちる1つのせいで他の更新まで巻き込んでPR全体がマージできなくなる。
`exclude-patterns` で外し、個別PRにする。グループから外れた依存はDependabotが個別にPRを立てる。

対象は、更新でCIのチェックが落ちうるもの。

| 種類 | 例 |
|------|-----|
| linter | `eslint*`, `stylelint*`, `pylint*`, `flake8*`, `ruff*`, `rubocop*`, `golangci-lint*`, `clippy*` |
| formatter | `prettier*`, `black*`, `isort*`, `gofumpt*` |
| 型チェッカー | `typescript`, `mypy*`, `pyright*` |

- マニフェストを読み、実在する依存だけを `exclude-patterns` に書く。使っていないものを推測で足さない
- 依存が `patterns` と `exclude-patterns` の両方に一致した場合は除外が優先される
- テストフレームワークは外さない。バージョンが上がってもテストが落ちるのは実際の非互換なので、まとめて直す方がよい
- `github-actions`・`docker`・`terraform` には該当するものが無いので `exclude-patterns` を書かない
- `pre-commit` はフック全体がLint系なので、除外するとグループが空になる。`exclude-patterns` を書かない

#### クールダウン設定（必須）

全エコシステムに `cooldown` を置く。公開直後の改ざんされたバージョンを自動で取り込まないための待機期間なので、ユーザーに要否を確認せず必ず入れる。

| エコシステム | 設定するキー |
|-------------|-------------|
| SemVer対応（`npm`, `pip`, `bundler`, `gomod`, `maven`, `gradle`, `composer`, `cargo`） | `default-days`, `semver-major-days`, `semver-minor-days`, `semver-patch-days` |
| `github-actions`, `docker`, `terraform`, `pre-commit` | `default-days` のみ |

```yaml
cooldown:
  default-days: 7
  semver-major-days: 30
  semver-minor-days: 7
  semver-patch-days: 3
```

- `semver-*-days` はSemVer対応のエコシステムにしか効かない。`github-actions`・`docker`・`terraform`・`pre-commit` に書いても無視されるので置かない
- グルーピングの `update-types` とは別系統で、そちらはこの3つでも効く。片方の可否をもう片方に当てはめない
- クールダウンはバージョン更新にのみ適用され、セキュリティ更新には適用されない
- 緊急のセキュリティ修正が待たされる点をユーザーに伝える

参考: https://docs.github.com/en/code-security/dependabot/working-with-dependabot/dependabot-options-reference#cooldown

#### 共通設定
- `schedule.interval`: 手順2で決定した値
- `directory`: マニフェストファイルが存在するディレクトリ（ルートなら `"/"`）

### 5. 可変な参照の固定（必須）

バージョンを指す記述は、必ず不変の1点を指すようにする。
`latest` や移動するタグのような可変な参照は、エコシステムやファイルの種類を問わず使わない。

固定しない害は3つある。

- 参照先が不変でないため、レビューしたものと実際に動くものが一致しない
- Dependabotの更新対象から外れるため、古い版に留まったまま更新PRも出ない
- 固定していない参照は検査のあとも差し替わりうるため、手順4のクールダウンが実際に取得されるものの古さを保証できない

対象は手順1で検出したエコシステムに限らない。リポジトリ内でバージョンを指定している箇所をすべて見る。

| 対象 | 可変な例 | 固定した形 |
|------|---------|-----------|
| ワークフローの `uses:` | `@v4`, `@main` | フルレングスのコミットSHA + `# <タグ>` |
| ワークフローの `runs-on:` | `ubuntu-latest` | `ubuntu-24.04` |
| setup系アクションのバージョン入力 | `node-version: latest` | `.node-version` などのファイルを読ませるか、具体的なバージョン |
| Dockerイメージ | `node:latest`, `node:24` | `node:24.10.0-bookworm@sha256:<ダイジェスト>` |
| マニフェストの依存 | `"pkg": "latest"`, `"pkg": "*"`, gitのブランチ指定 | 上限のあるバージョン指定。ロックファイルが無ければ具体的なバージョン |
| Terraformのprovider / module | 制約なし, `ref=main` | `version = "5.31.0"`, `ref=v1.2.3` |
| pre-commitの `rev` | `main` | コミットSHA + `# frozen: <バージョン>` |
| ランタイムのバージョン指定 | `.tool-versions` の `latest` | 具体的なバージョン |

固定するとDependabotが更新を拾える形になるが、`runs-on:` のようにDependabotが扱わない箇所もある。
その場合は固定した上で、自分で更新する必要があることをユーザーに伝える。

上の害のうち2番目は、ロックファイルを持つエコシステムのマニフェストには当てはまらない。
`"lodash": "*"` のままでもDependabotはロックファイル側を更新するPRを出す。害は1番目だけになる。

#### GitHub Actions

`.github/workflows/` 配下の `uses:` をフルレングスのコミットSHAへ固定する。

```yaml
- uses: actions/checkout@93cb6efe18208431cddfb8368fd83d5badbf9bfd # v5.0.1
```

- SHAは `gh api repos/<owner>/<repo>/commits/<タグ>` で取得する。フォークではなく本体のリポジトリから取ることを確認する
- 上の例のSHAをそのまま書き写さない。タグとSHAがずれるとDependabotが更新済みと誤認し、そのバージョンの更新PRが出なくなる。必ずその時点のタグを解決し直す
- 末尾に `# <タグ>` のコメントを残す。Dependabotはこのコメントを読んで更新の要否を判断し、更新時にSHAとコメントの両方を書き換える。コメントが無くタグにも紐づかないSHAの場合、Dependabotは最新リリースではなく最新コミットへ更新する
- 同一リポジトリ内のローカルアクション（`./.github/actions/...`）と `docker://` は対象外。Dependabotが扱うのはリポジトリ構文のみ

参考: https://docs.github.com/en/actions/reference/security/secure-use

#### Docker

`Dockerfile` と `docker-compose.yml` / `docker-compose.yaml` の `FROM` / `image` を、具体的なバージョンタグとダイジェストで固定する。

```dockerfile
FROM node:24.10.0-bookworm@sha256:<ダイジェスト>
```

- `latest`、`stable`、`edge` のような可変タグを使わない。DependabotがDockerのタグとして更新できるのはSemVer・日付・ビルド番号の形式で、`latest` はどれにも当たらないため更新されない
- `node:24` のようにメジャーだけのタグも避ける。同じ記述が別のパッチ版を指す
- ダイジェストまで併記すると参照先が不変になる。Dependabotはダイジェスト付きの参照も更新できる
- ダイジェストは `docker buildx imagetools inspect <イメージ>:<タグ> --format '{{.Manifest}}'` の先頭に出る `Digest:` を使う。値を推測で書かない
- `Manifests:` の下に並ぶダイジェストは使わない。あちらはプラットフォームごとのものなので、書くと別アーキの環境で違うイメージを掴む
- `docker manifest inspect` は使わない。マルチアーキのイメージではインデックスのダイジェストが出ず、それらしい値が返るぶん誤りに気づけない
- dockerが使えない環境ではタグの固定までを行い、ダイジェストが未設定であることを報告する。推測値を書くくらいならタグ止まりの方がよい

参考: https://github.com/dependabot/dependabot-core/blob/main/docker/README.md

#### pre-commit

`.pre-commit-config.yaml` の `rev` をコミットSHAへ固定し、`# frozen: <バージョン>` のコメントを付ける。

```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: 971923581912ef60a6b70dbf0c3e9a39563c9d47  # frozen: v0.14.14
    hooks:
      - id: ruff
```

- Dependabotはこのコメントを読んで更新の要否を判断し、更新時に `rev` とコメントの両方を書き換える。GitHub Actionsの `# <タグ>` と同じ仕組み
- コメントにバージョンの接頭辞（`v1` など）を書くと、その範囲の最新タグへ更新される
- SHAは `gh api repos/<owner>/<repo>/commits/<タグ>` で取得する

参考: https://docs.github.com/en/code-security/dependabot/ecosystems-supported-by-dependabot/supported-ecosystems-and-repositories

#### マニフェストの依存

対象は、解決先が毎回変わりうる指定に限る。

- `latest`、`*`、`x` のような、上限の無い指定
- gitのブランチを指す指定（`main`、`master`、`HEAD`）
- Pythonの `requirements.txt` などで制約を書いていないもの

`^5.1.0` や `~> 2.0` のようなレンジは対象外。書き換えない。
上限があり、解決結果はロックファイルで固定されるため、同じ記述が別のコードを指す状態にはならない。

- ロックファイルがあるなら、上限のあるレンジへ直す。完全固定はしない。解決の固定はロックファイル側に任せる
- ロックファイルが無いエコシステムでは、マニフェストに具体的なバージョンを書く
- gitのブランチ指定は、タグかコミットSHAへ直す（`#v1.2.3`、`#<SHA>`）
- 公開するライブラリでは完全固定しない。利用側で重複インストールや解決不能を招く

**ロックファイルの再生成は必ず報告する。**

ロックファイルは解決バージョンだけでなく、マニフェストに書かれたレンジの文字列そのものを記録している。
pnpm-lock.yaml の `specifier`、yarn.lock のディスクリプタのキー、package-lock.json の `packages[""]` がそれにあたる。
そのためマニフェストを書き換えると、解決バージョンが同じままでもロックファイルと食い違い、
`npm ci`・`pnpm install --frozen-lockfile`・`yarn install --immutable` が落ちる。

このスキルは依存のインストールもロックファイルの更新も行わない。
書き換えたら、再生成が必要であることと実行すべきコマンドを必ずユーザーに伝える。伝えずに終わらない。

- 新しいレンジは、ロックファイルに記録済みの解決バージョンを含むものにする。再生成したときの差分が最小になる
- gitのブランチ指定の書き換えも同じ。ロックファイルには解決済みのコミットとディスクリプタの両方が入るため、再生成が要る

### 6. 出力
- 新規の場合は `.github/dependabot.yml` に書き出す。`.github/` ディレクトリが存在しない場合は作成する
- 既存ファイルがある場合は手順3の方針で追記する。再生成で既存のキーを落とさない
- 追加・変更した内容の概要と、固定したアクションの一覧をユーザーに表示する

## 生成例

完成形は [examples.md](examples.md) を参照する。

## 絶対に守るべきルール
- 検出されたエコシステムのみ設定に含める（推測で追加しない）
- 検出した全エコシステムに `<エコシステム名>-minor-and-patch` グループと `cooldown` を必ず置く
- そのグループは `patterns` を `"*"` にし、`update-types` を `minor` と `patch` に限定する
- Lint系は `exclude-patterns` でグループから外す。マニフェストに実在するものだけを書く
- `github-actions`・`docker`・`terraform` の `cooldown` に `semver-*-days` を書かない
- 既存の `.github/dependabot.yml` がある場合は手順3の方針で追記する。作り直して既存のキーを落とさない
- 検出したのに `updates` エントリが無いエコシステムは必ず追加する
- 可変な参照を残さない。`latest`・`*`・移動するタグ・`main` は、エコシステムやファイルの種類を問わず使わない
