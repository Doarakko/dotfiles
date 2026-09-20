---
name: project-setup
description: 初めて触るプロジェクトやセットアップ時に、依存更新の自動化・クールダウン・CI/CDが設定されているか確認して整備するときに使用
allowed-tools: Read, Write, Edit, Glob, Grep, Skill, Bash(ls *), Bash(git remote *), Bash(git log *), Bash(gh workflow list *), Bash(gh run list *), Bash(gh api repos/*), Bash(mkdir *)
---

# プロジェクト基本設定

初めて触るプロジェクトで、依存更新の自動化・パッケージマネージャのクールダウン・ランタイムのバージョン固定・CIの自動化が入っているかを確認し、足りないものを整備する。

先に4つの観点すべてを調査してから、まとめて結果を出す。1つ直すたびに報告しない。

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
- `git remote get-url origin` でホスティング先を確認する。GitHub でない場合は手順2と、手順5のうちGitHub ActionsとGitHub APIに関する項目をスキップし、その旨を報告する
- 可変な参照の固定はホスティング先に関係なく実行する。Dockerイメージやマニフェストの `latest` はGitHubと無関係なため、手順5ごと飛ばさない
- ビルド・Lint・テストの実行コマンドを集める（`package.json` の `scripts`、`Makefile`、`Taskfile.yml`、`justfile`、`tox.ini`、`noxfile.py`、`pyproject.toml` など）。手順5で使う

### 2. 依存更新の自動化を確認

以下を探す。

- Dependabot: `.github/dependabot.yml`, `.github/dependabot.yaml`
- Renovate: `renovate.json`, `renovate.json5`, `.renovaterc`, `.renovaterc.json`, `.github/renovate.json`, `package.json` の `renovate` キー

判定と対応。

| 状態 | 対応 |
|------|------|
| どちらもない | `Skill` で `dependabot-setting` を呼び、`.github/dependabot.yml` を生成する |
| Dependabot あり | `Skill` で `dependabot-setting` を呼ぶ。エコシステムの漏れ・グルーピング・クールダウンの過不足の判定も含め、既存ファイルの扱いは同スキルの「既存設定の確認」の方針に従う |
| Renovate あり・`minimumReleaseAge` なし | `minimumReleaseAge` を追記する |
| 両方ある | PRが二重に立つので、どちらに寄せるかユーザーに確認する |

Dependabotの設定内容の基準（対象エコシステム・グルーピング・クールダウンの値・アクションのSHA固定）は
`dependabot-setting` スキルに一本化している。このファイルへ基準を書き写さない。二重管理になって片方だけ古くなる。

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

### 4. npmのランタイムバージョン固定を確認（必須）

npm を使うプロジェクトでは `.npmrc` に `engine-strict=true` を必ず入れる。入っていなければ追記する。

```ini
engine-strict=true
```

既定の `false` では、宣言したランタイムと非互換のパッケージでも警告だけで入る。
`true` にすると、現在のNode.jsと非互換を宣言しているパッケージのインストールを拒否するため、
手元とCIでランタイムがずれたまま進むことがなくなる。

- `package.json` に `engines.node` が無ければ、`.node-version` / `.nvmrc` / CIの `setup-node` で使っているバージョンに合わせて追加する。宣言が無いと固定するものが無い
- 自分のプロジェクトだけでなく依存の `engines` 宣言でも失敗するようになる。既存プロジェクトへ入れる場合はインストールが通らなくなる可能性をユーザーに伝える
- `--force` で上書きできる

### 5. CIの自動化を確認

`.github/workflows/` 配下のファイルを読み、以下が自動化されているかを判定する。

| 項目 | 見るところ |
|------|-----------|
| build | ビルドコマンドを実行するジョブがあるか。ビルド工程のない言語なら対象外 |
| lint | Lint・フォーマット・型チェックを実行するジョブがあるか |
| test | テストを実行するジョブがあるか |
| deploy | デプロイするジョブがあるか。ライブラリなら公開（publish/release）で読み替える |
| preview | PRごとにプレビュー環境へデプロイしているか。CLIやライブラリなど公開先がURLでないものは対象外 |

ジョブ名ではなく `run` で実行しているコマンドを見て判定する。名前が `ci` でも中身がテストだけのことがある。

あわせて次を確認する。

- build・lint・test が `on: pull_request` で走るか。`push` だけだとPRで結果が出ない
- 手順1で集めた実行コマンドのうち、CIから呼ばれていないものがないか
- `gh workflow list` と `gh run list --limit 10` で、定義があるだけで実際は走っていない・失敗し続けているワークフローがないか
- プレビューが用意されているか。次の順で見て、いずれかが当たれば「あり」とする
  1. `.github/workflows/` に `on: pull_request` で走りデプロイを実行しているジョブがあるか。`vercel`、`netlify deploy`、`wrangler pages deploy`、`firebase hosting:channel:deploy` などを `run` と `uses` の中身で判定する。`aws s3 sync` とGitHub Pagesへのデプロイは本番の更新であることが多いため、PR番号やブランチ名を出力先のパス・サブドメインへ含めているときだけプレビューとみなす
  2. ワークフローが無くても、ホスティング側のGit連携（Vercel・Netlify・Cloudflare PagesのGitHub App）がプレビューを作っていることがある。手順1で確認したリモートのowner/repoを使い、`gh api repos/<owner>/<repo>/deployments -X GET -F per_page=100 --jq '[.[].environment] | unique'` を実行し、`Preview` を含む環境名（`Preview – <プロジェクト名>` のように接尾辞が付く）があれば連携ありとして扱い、ワークフローを追加しない（`-F` を付けると既定でPOSTになるため `-X GET` が要る）
  3. `vercel.json`・`netlify.toml`・`wrangler.toml`・`firebase.json` の有無も手掛かりにする

  2番で何も返らないことを「プレビュー無し」の根拠にしない。デプロイの記録に出るのは実質Vercelで、NetlifyとCloudflare PagesはPRのチェック（commit status / check run）側に出ることが多い。1番と3番で決まらなければユーザーに確認する。
- `latest`・`*`・移動するタグ・`main` のような可変な参照が残っていないか。`uses:`・`runs-on:`・Dockerイメージ・マニフェストの依存など、バージョンを指定している箇所をすべて見る。残っていれば `Skill` で `dependabot-setting` を呼び、「可変な参照の固定」を実行させる。SHAやダイジェストの解決はそちらの手順で行うので、このスキルでは書き換えない

不足している場合の対応。

- **build・lint・test**: 手順1で集めた実際の実行コマンドを使ってワークフローを追加する。プロジェクトに存在しないコマンドを書かない
- **deploy・preview**: デプロイ先とその認証情報は推測できないため、生成せずまずユーザーに確認する。追加すると決まったときだけ、後述の「ワークフローを追加するときは以下に従う」に従って書く

可変な参照の固定は、固定した対象ごとに行を分けて報告する。手順5の対象はワークフローに限らないため、
まとめて1行にすると何が直って何が残ったか分からない。Dependabotが更新を拾わない対象は、その旨も併記する。

ワークフローを追加するときは以下に従う。

- 既存のワークフローがある場合は新規ファイルを作らず、ジョブを足せないか先に検討する
- `permissions` は最小限にする（読むだけなら `contents: read`）
- 同一ブランチの多重実行を止めるため `concurrency` に `cancel-in-progress: true` を入れる
- ランタイムのバージョンはプロジェクトの指定（`.node-version`、`.python-version`、`go.mod`、`engines` など）に合わせる
- `uses:` は `Skill` で `dependabot-setting` を呼び、「可変な参照の固定」でコミットSHAへ固定させる。既存ワークフローがタグ指定のままでも、そちらに揃えない

ユーザーの確認を得てプレビュー用のワークフローを追加する場合は、あわせて以下に従う。

- `pull_request_target` を使わない。secretsと書き込み権限を持った状態で走るため、PRのコードをチェックアウトして実行すると秘密情報を奪われる
- ワークフローでプレビューを作る場合、forkからのPRには `secrets` が渡らずプレビューが出ない。その前提をユーザーに伝える。ホスティング側のGit連携はGitHub Actionsを経由しないため、こちらは当てはまらない
- PRがクローズされたときにプレビューを片付ける処理も用意する。別のワークフローとして作る。同じワークフローに入れるなら `on` の `types` を `[opened, synchronize, reopened, closed]` と明示し、ジョブ側の `if: github.event.action == 'closed'` で分ける。`types` を書くと既定の `opened`・`synchronize`・`reopened` が上書きされるため、`[closed]` だけにするとプレビューそのものが作られなくなる

### 6. 報告

調査結果を表で出し、変更したファイルと残っている対応を分けて示す。対象外だった項目は行を消さず、状態を `対象外` として残す。

```
| 項目 | 状態 | 対応 |
|------|------|------|
| 依存更新の自動化 | なし | .github/dependabot.yml を生成 |
| クールダウン（Dependabot） | なし | 生成した設定に含めた |
| クールダウン（pnpm） | なし | pnpm-workspace.yaml に追記 |
| マイナー/パッチのグルーピング | なし | dependabot-setting の基準で追記 |
| engine-strict | なし | .npmrc に追記 |
| 可変な参照の固定（uses） | タグ指定 | SHAへ固定 |
| 可変な参照の固定（runs-on） | ubuntu-latest | ubuntu-24.04 へ固定。Dependabotの対象外なので手動で追う |
| 可変な参照の固定（Dockerイメージ） | latest | バージョンタグとダイジェストへ固定 |
| 可変な参照の固定（マニフェスト） | `"*"` が2件 | 上限のあるレンジへ。ロックファイルの再生成が必要 |
| 可変な参照の固定（Terraform） | 制約なし | version を明示 |
| build | あり | - |
| lint | あり（pushのみ） | pull_request を追加 |
| test | なし | .github/workflows/test.yml を追加 |
| deploy | なし | デプロイ先の確認待ち |
| preview | あり | Vercelの連携で作成済み |
```

## 絶対に守るべきルール

- 変更するのはプロジェクト配下のファイルだけ。`~/.npmrc`、`~/.bundle/config`、`~/.config/pip/pip.conf` などユーザー全体の設定は変更しない
- 既存の設定値を勝手に書き換えない。値が入っている項目は現状を報告するだけにする。例外は可変な参照（`latest`、`*`、移動するタグ、`main`）で、これらは固定した値へ書き換える
- 依存のインストールやロックファイルの更新を実行しない。設定ファイルを書くところまでにする
- 検出したパッケージマネージャ・エコシステムの設定だけを追加する。使っていないものを推測で足さない
- クールダウンのオプションは変化が速い。表にないパッケージマネージャや、値が効かない場合は公式ドキュメントを確認してから書く
- クールダウン・`engine-strict`・可変な参照の固定は必須。要否をユーザーに確認せず入れる。`latest` はエコシステムやファイルの種類を問わず残さない
- Dependabotの設定を作る・直すときは必ず `dependabot-setting` スキルを呼ぶ。基準をこのファイルに複製しない
