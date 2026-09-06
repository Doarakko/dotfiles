---
name: project-setup
description: 初めて触るプロジェクトやセットアップ時に、依存更新の自動化・クールダウン・CI/CDが設定されているか確認して整備するときに使用
allowed-tools: Read, Write, Edit, Glob, Grep, Skill, Bash(ls *), Bash(git remote *), Bash(git log *), Bash(gh workflow list *), Bash(gh run list *), Bash(mkdir *)
---

# プロジェクト基本設定

初めて触るプロジェクトで、依存更新の自動化・パッケージマネージャのクールダウン・CIの自動化が入っているかを確認し、足りないものを整備する。

先に3つの観点すべてを調査してから、まとめて結果を出す。1つ直すたびに報告しない。

## 手順

### 1. プロジェクトの把握

マニフェストとロックファイルを `Glob` で探し、言語とパッケージマネージャを特定する。

| ロックファイル | パッケージマネージャ |
|----------------|---------------------|
| `package-lock.json` | npm |
| `pnpm-lock.yaml` | pnpm |
| `yarn.lock` | yarn |
| `bun.lock`, `bun.lockb` | bun |
| `uv.lock` | uv |
| `poetry.lock` | poetry |
| `requirements*.txt`（ロックなし） | pip |
| `Gemfile.lock` | bundler |
| `Cargo.lock` | cargo |
| `go.sum` | go |
| `composer.lock` | composer |

- ロックファイルがない場合は `packageManager` フィールドやCIの実行コマンドから判定する
- モノレポならワークスペースのディレクトリを列挙し、どこにマニフェストがあるかを控える
- `git remote get-url origin` でホスティング先を確認する。GitHub でない場合は手順2・4をスキップし、その旨を報告する
- ビルド・Lint・テストの実行コマンドを集める（`package.json` の `scripts`、`Makefile`、`Taskfile.yml`、`justfile`、`tox.ini`、`noxfile.py`、`pyproject.toml` など）。手順4で使う

### 2. 依存更新の自動化を確認

以下を探す。

- Dependabot: `.github/dependabot.yml`, `.github/dependabot.yaml`
- Renovate: `renovate.json`, `renovate.json5`, `.renovaterc`, `.renovaterc.json`, `.github/renovate.json`, `package.json` の `renovate` キー

判定と対応。

| 状態 | 対応 |
|------|------|
| どちらもない | `dependabot-setting` スキルで `.github/dependabot.yml` を生成する |
| Dependabot あり・`cooldown` なし | `dependabot-setting` スキルの基準に合わせて `cooldown` を追記する |
| Dependabot あり・エコシステムに漏れがある | 手順1で検出したエコシステムを追記する |
| Renovate あり・`minimumReleaseAge` なし | `minimumReleaseAge` を追記する |
| 両方ある | PRが二重に立つので、どちらに寄せるかユーザーに確認する |

Renovate に追記する場合は最上位に置く。特定パッケージだけ緩めたいときは `packageRules` で上書きする。

```json
{
  "extends": ["config:recommended"],
  "minimumReleaseAge": "7 days"
}
```

### 3. パッケージマネージャのクールダウンを確認

手順1で特定したパッケージマネージャの設定ファイルを読み、クールダウンが入っているか確認する。
入っていなければ追記する。既存の値がある場合は上書きしない。

Dependabot / Renovate のクールダウンは自動更新PRにしか効かない。手元やCIでの `install` を守るのはこちらなので、両方入れる。

| パッケージマネージャ | ファイル | キー | 単位 | 7日相当 | 必要バージョン |
|---------------------|----------|------|------|---------|---------------|
| npm | `.npmrc` | `min-release-age` | 日 | `7` | npm 11.10.0 |
| pnpm | `pnpm-workspace.yaml`（pnpm 10 は `.npmrc`） | `minimumReleaseAge` | 分 | `10080` | pnpm 10.16 |
| yarn | `.yarnrc.yml` | `npmMinimalAgeGate` | 分 | `10080` | Yarn 4.10.0 |
| bun | `bunfig.toml` | `install.minimumReleaseAge` | 秒 | `604800` | Bun 1.3.0 |
| uv | `pyproject.toml` の `[tool.uv]` または `uv.toml` | `exclude-newer` | 期間文字列 | `"7 days"` | uv 0.9.17 |
| poetry | `pyproject.toml` の `[tool.poetry.solver]` | `min-release-age` | 日 | `7` | - |
| pip | `pip.conf` の `[install]` | `uploaded-prior-to` | ISO 8601 期間 | `P7D` | pip 26.1 |
| bundler | `.bundle/config` | `BUNDLE_COOLDOWN` | 日 | `"7"` | Bundler 4.0.13 |

書き込み例は [cooldown-examples.md](cooldown-examples.md) を参照する。

cargo・go・composer・maven・gradle にはクールダウンの公式オプションがない。この場合は手順2のDependabot / Renovate側だけで担保し、その旨を報告する。

緊急のセキュリティ修正が待たされる点をユーザーに伝える。除外の指定方法はパッケージマネージャごとに異なるため（npm は `min-release-age-exclude`、pnpm は `minimumReleaseAgeExclude`、yarn は `npmPreapprovedPackages`、uv は `exclude-newer-package`）、必要になった時点で公式ドキュメントを確認する。

### 4. CIの自動化を確認

`.github/workflows/` 配下のファイルを読み、以下が自動化されているかを判定する。

| 項目 | 見るところ |
|------|-----------|
| build | ビルドコマンドを実行するジョブがあるか。ビルド工程のない言語なら対象外 |
| lint | Lint・フォーマット・型チェックを実行するジョブがあるか |
| test | テストを実行するジョブがあるか |
| deploy | デプロイするジョブがあるか。ライブラリなら公開（publish/release）で読み替える |

ジョブ名ではなく `run` で実行しているコマンドを見て判定する。名前が `ci` でも中身がテストだけのことがある。

あわせて次を確認する。

- build・lint・test が `on: pull_request` で走るか。`push` だけだとPRで結果が出ない
- 手順1で集めた実行コマンドのうち、CIから呼ばれていないものがないか
- `gh workflow list` と `gh run list --limit 10` で、定義があるだけで実際は走っていない・失敗し続けているワークフローがないか

不足している場合の対応。

- **build・lint・test**: 手順1で集めた実際の実行コマンドを使ってワークフローを追加する。プロジェクトに存在しないコマンドを書かない
- **deploy**: デプロイ先とその認証情報は推測できないため、生成せずユーザーに確認する

ワークフローを追加するときは以下に従う。

- 既存のワークフローがある場合は新規ファイルを作らず、ジョブを足せないか先に検討する
- `permissions` は最小限にする（読むだけなら `contents: read`）
- 同一ブランチの多重実行を止めるため `concurrency` に `cancel-in-progress: true` を入れる
- ランタイムのバージョンはプロジェクトの指定（`.node-version`、`.python-version`、`go.mod`、`engines` など）に合わせる
- アクションのバージョンは既存ワークフローで使っている指定方法に揃える

### 5. 報告

調査結果を表で出し、変更したファイルと残っている対応を分けて示す。

```
| 項目 | 状態 | 対応 |
|------|------|------|
| 依存更新の自動化 | なし | .github/dependabot.yml を生成 |
| クールダウン（Dependabot） | なし | 生成した設定に含めた |
| クールダウン（pnpm） | なし | pnpm-workspace.yaml に追記 |
| build | あり | - |
| lint | あり（pushのみ） | pull_request を追加 |
| test | なし | .github/workflows/test.yml を追加 |
| deploy | なし | デプロイ先の確認待ち |
```

## 絶対に守るべきルール

- 変更するのはプロジェクト配下のファイルだけ。`~/.npmrc`、`~/.bundle/config`、`~/.config/pip/pip.conf` などユーザー全体の設定は変更しない
- 既存の設定値を勝手に書き換えない。値が入っている項目は現状を報告するだけにする
- 依存のインストールやロックファイルの更新を実行しない。設定ファイルを書くところまでにする
- 検出したパッケージマネージャ・エコシステムの設定だけを追加する。使っていないものを推測で足さない
- クールダウンのオプションは変化が速い。表にないパッケージマネージャや、値が効かない場合は公式ドキュメントを確認してから書く
