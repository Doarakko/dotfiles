---
name: report-artifact
description: レビュー結果やプランをHTMLページとして公開し、ブラウザで見られるようにするときに使用
allowed-tools: Skill, Edit(//tmp/claude/report/**), Edit(//private/tmp/claude/report/**), Read, Bash(mkdir *), Bash(git rev-parse *)
---

# HTMLページ公開手順

レビュー結果やプランを、ターミナルのmarkdownではなくHTMLページとして公開する。公開先はArtifact（claude.ai上の非公開URL）で、ブラウザで開き、必要ならページ上のShareから共有できる。

## 1. 種別を決める

呼び出し元から渡された種別で、ページの骨組みとファイル名が決まる。

| 種別 | 呼び出し元 |
| --- | --- |
| `pr-review` | `/pr-review` |
| `review-diff` | `/review-diff` |
| `plan` | `/plan-view` |
| `review` | 単体のレビュー系スキル（`security-review` / `test-review` / `coding-style-guide-review` / `pr-compliance-review`）を使ったあと |

どの種別もHTMLで書き出す。`.md`も公開できるが、その場合は題名がファイル名で固定され、体裁も選べない。

### `/artifact-pr-review` との使い分け

Claude Codeには`/artifact-pr-review`という組み込みのPRレビューページ機能がある。PRを自力で取得してpayload JSONを書き、専用テンプレートで公開する別系統の手順で、GitHubへのリンクや判定ピルが付く。

このスキルはそれを呼ばない。理由は3つ。ページの同一性が`/artifact-pr-review <PR番号>`の起動引数で決まるため、呼び出し元が受け取ったPR番号を渡さないと別のPRに解決される。payloadはレビュー時のheadのSHAを持ち公開時に照合されるため、修正後の再公開が通らない。そして公開が拒否されたときに、このスキルのフォールバック（手順6）が効かなくなる。

組み込みのページが欲しいときは、ユーザーが`/artifact-pr-review <PR番号>`を直接実行する。セッションでそれが使えることに気づいたら、選択肢として一度伝えるだけにとどめる。

## 2. 設計スキルを先に起動する

ページを書き始める前に `artifact-design` スキルを起動し、その配色・タイポグラフィ・ダーク/ライト両対応の指針に従う。

## 3. ページを組み立てる

### レビュー系（`pr-review` / `review-diff` / `review`）

- **ヘッダー**: 対象（PR番号とURL、またはローカル差分の範囲）、ブランチ、レビュアーの内訳。実際に走ったものだけを並べる（`/pr-review`は`code-reviewer`のみ、`/review-diff`は`code-reviewer`と`codex-reviewer`と自動チェックツール）
- **サマリー**: Critical / High / Medium / Low の件数
- **指摘一覧**: 重大度バッジ、`file:line`、由来ラベル（codex由来は`[codex]`）、説明、改善提案。該当diffの抜粋は`<details>`で畳む
- **自動チェック結果**: ESLint / Ruff / golangci-lint 等の出力の要点
- **次のステップ**

指摘の並びは重大度順。重複をまとめた指摘は、まとめた旨と由来を両方載せる。

### プラン（`plan`）

- **ヘッダー**: プラン名、元ファイル名、更新日時。`~/.claude/plans`配下のプランはファイル名だけを出す。絶対パスにはユーザー名が入る
- **本文**: プランの見出し構造をそのまま残す。長いプランは冒頭に見出しへのアンカーリンクを置く
- **実行手順・検証手順**: チェックリストとして読める形にする
- コードブロックとパスは等幅で、横スクロールは各ブロック内に閉じ込める

内容は書き換えない。見出し・箇条書き・コードブロックの区別をHTMLの階層へ移すだけにする。

## 4. ファイルを書き出す

`mkdir -p /tmp/claude/report` を先に実行し、`/tmp/claude/report/` の下に書く。ファイル名は種別ではなく**レビュー対象**で決める。

| 種別 | ファイル名 |
| --- | --- |
| `pr-review` | `<repo>-pr<PR番号>-review.html` |
| `review-diff` | `<repo>-<branch>-review-diff.html` |
| `plan` | `plan-<拡張子を除いたプランファイル名>.html` |
| `review` | `<repo>-<branch>-<観点>-review.html`（観点は`security` / `test` / `quality` / `guidelines` / `pr-compliance`） |

`<repo>`と`<branch>`は次で取る。ほかのコマンドを使うと`allowed-tools`に無く、許可プロンプトが出る。

- `<repo>`: `git rev-parse --show-toplevel` の末尾セグメント。ただし`pr-review`は別リポジトリのPRを指定できるので、`gh pr view`で取得済みのPR情報から取る
- `<branch>`: `git rev-parse --abbrev-ref HEAD`

`pr-review`をブランチで名付けないのは、`/pr-review <番号>`がPRをチェックアウトせずに動くため。同じセッションで別のPRをレビューすると同じファイル名になり、先に共有したページが別PRの内容へ差し替わる。

- リポジトリ内には書き出さない
- `$TMPDIR`は使わない。hookとBashで指す先が異なる
- 対象ごとにパスを固定するのは、同じ対象を再レビューしたときに新しいURLを増やさず、同じURLへ更新させるため。同一セッションでは同じファイルパスへの再公開が同じURLの更新になり、別のパスにすると別のページが増える

## 5. 公開する

`Artifact`にファイルパスを渡す。

- **題名はHTMLの`<title>`タグで決める**。短い名詞句にし、`PR 123 Review`、`OAuth Migration Plan` のように対象を特定できる名前にする。説明をコロンやダッシュで足さない。`title`パラメータは`<title>`が無いときだけ使われ、タグを上書きしない
- `description`: 1文。ギャラリーのカードに出る
- `favicon`: レビュー系は🔍、プランは🗺️
- `<title>`と`favicon`は、同じ対象を更新する限り変えない

**`Artifact`を`allowed-tools`へ足して事前承認しないこと。** 差分をAnthropic側へ上げる操作なので、何を上げるかをユーザーが見て判断する余地を残す。

ただしプロンプトが出るのは、そのページを初めて公開するときだけ。一度承認された後の再公開は確認なしで通り、auto modeのセッションでは初回も分類器判断になって人に出ない。つまり再公開の中身は自分で見張ること。

公開後、URLをターミナルにも出す。別セッションから同じページを更新するときは、そのURLを`url`に渡す。URLが分からなければ`Artifact`の`action: "list"`で一覧から探すか、ユーザーに`/artifacts`で開いてもらう。`url`を渡さずに公開すると、既存ページの更新ではなく別のページが増える。

## 6. 公開できないとき

Artifactが使えないセッション（`enableArtifact: false`、APIキーやゲートウェイ経由の認証、Bedrock / Vertex / Foundry、組織側で無効）では公開に失敗する。このとき、

- 手順4で書き出したファイルはそのまま残っているので、作り直さずにパスを提示し、`open <パス>` で見られることを案内する
- レビューやプラン表示そのものは止めない。呼び出し元の残りの手順（`review-followup`等）へそのまま進む
- ユーザーが公開を断った場合も同じ扱いにする

## 7. 公開する内容の制約

- 秘匿情報を載せない。トークン、`.env`の中身、社外秘の識別子は、指摘の対象であっても値そのものは伏せる
- パスはリポジトリ相対で書く。絶対パスにはユーザー名が入る
- 画像をdata URIで埋め込まない。diffは該当箇所の抜粋だけにする
