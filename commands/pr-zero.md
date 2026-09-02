---
description: 新規ブランチ作成からPR作成までを一連で実行する
when_to_use: PR・プルリクエストの作成を依頼されたとき、変更をPRにまとめるとき、`gh pr create`を実行しようとしたときに使用
argument-hint: [--from-main]
allowed-tools: Skill, Read, Write, Bash(git add *), Bash(git commit *), Bash(git push *), Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git branch *), Bash(git stash *), Bash(git checkout *), Bash(git rev-parse *), Bash(gh pr create *), Bash(gh pr view *), Bash(gh pr comment *), Bash(gh auth refresh *), Bash(gh --version*), Bash(cat *), Bash(ls *), Bash(find *), Bash(mkdir *), Bash(echo *), Bash(printf *), Bash(basename *), Bash(tr *), Bash(test *), Bash(curl -s -o /dev/null *), Bash(playwright-cli *)
---

# PRゼロからワークフロー

新規ブランチ作成からPR作成までを一連で実行する。

## 使用方法
```
/pr-zero [--from-main]
```
- `--from-main`: メインブランチから新規ブランチ作成
- 省略時: 現在のブランチから新規ブランチ作成

## 現在の状態（自動取得）
- ブランチ: !`git branch --show-current`
- ステータス: !`git status --short`
- 差分統計: !`git diff --stat`

## オプション
指定されたオプション: $ARGUMENTS（省略時は現在のブランチから作成）

## 重要ルール
**既存ブランチには絶対にpushしない。必ず新規ブランチを作成する。**

## 手順
1. 新規ブランチ作成（Conventional Branch形式）
   - 例: `feature/admin-user-role-edit-invite-form`
2. 上記の自動取得データを元に変更確認
3. コミット分割・作成（Conventional Commits形式）
4. `git push -u origin <branch>` でプッシュ
5. 画面に出る変更を含むなら動作確認の様子を撮る
   - `git diff --name-only <メインブランチ>...HEAD` で変更ファイルを一覧する
   - 次のいずれかに当たるファイルがあれば画面に出る変更とみなす
     - 画面を描画する拡張子: `.tsx` `.jsx` `.vue` `.svelte` `.astro` `.html` `.erb` `.blade.php` `.templ` `.hbs` `.ejs`
     - 見た目を決める拡張子: `.css` `.scss` `.sass` `.less`
     - 画面をまとめる場所: `components` `pages` `views` `templates` `layouts` `screens` `public` `assets` `static` を含むパス
   - 当たらなければこのステップを飛ばす（hookのシェルスクリプト、CI設定、ドキュメント、サーバー内部のロジックなど）
   - 当たる場合は、READMEから動作確認用のURLを読み取り `curl -s -o /dev/null -w "%{http_code}" <URL>` で疎通を確認する
     - 応答が無い、または5xxならスキップし、アプリが起動していないため撮影を省略した旨を報告してPR作成へ進む
     - 疎通したら `doarakko-config:e2e-check` の手順で撮影し、成果物ディレクトリを作る
   - `playwright-cli` が無い、撮影に失敗した、のいずれでもスキップして理由を報告する。ここでユーザーに確認を求めて止まらない
   - アプリのビルドや再起動はしない。動いているものがこのブランチのコードとは限らないため、古い画面が写っていればその旨も報告する
   - 撮影しない・できないと判断した場合は、成果物ディレクトリを空にしてから次へ進む。同じブランチで前に撮ったものが残っていると、PR作成ガードが添付を求めて止める:
     ```bash
     TOP=$(git rev-parse --show-toplevel) && BRANCH=$(git branch --show-current) && [ -n "$BRANCH" ] &&
       find "${CLAUDE_E2E_OUTPUT_ROOT:-/tmp/claude/e2e}/$(basename "$TOP")/$(printf '%s' "$BRANCH" | tr '/' '-')" -maxdepth 1 -type f -delete 2>/dev/null || true
     ```
     一度も撮っていなければディレクトリが無い。それは失敗ではないので終了コードも潰す
     gitが答えられないときは削除しない。パスが潰れると別のブランチの成果物まで消える
6. PRテンプレート確認（`.github/PULL_REQUEST_TEMPLATE.md`等）
7. PR本文を `/tmp/claude/pr-body/<リポジトリ名>-<ブランチ名のスラッシュを - に置換>.md` に書き出す
   - 先に `mkdir -p /tmp/claude/pr-body` する。ディレクトリが無いと書き込みに失敗する
   - 対象リポジトリ内には置かない。差分に混ざる
   - `$TMPDIR` は使わない。書き手と読み手で指す先が変わるうえ、名前が固定だと並行して動いた別のセッションと取り合う
   - 撮影した場合は、上限に収まるファイルだけを選ぶ:
     `find <成果物ディレクトリ> -maxdepth 1 -type f -size -10000k \( -name '*.png' -o -name '*.webm' \) | sort`
   - ファイル名から先頭の `NN-` と拡張子を除き、ハイフンを空白に置き換えたものを代替テキストにする
   - 動作確認セクションを設け、各ファイルを `![代替テキスト](<絶対パス>)` の形で並べる
   - `gh` はこの参照をアップロード先のURLへ置換する。本文に書いた位置にそのまま入る
8. `gh pr create --draft --reviewer @copilot --title <タイトル> --body-file <本文ファイル>` でドラフトPR作成とCopilotへのレビュー依頼
   - 撮影した場合は、選んだファイルごとに `--attach '<絶対パス>'` を並べて渡す。本文に参照を書いてあればその位置がアップロード先のURLに書き換わり、本文に書いた代替テキストがそのまま使われるため `#代替テキスト` は不要
   - 動画はプレイヤーとして表示され、代替テキストを持たない
   - 添付は1コマンドあたり50ファイルまで。超えるなら主要な導線に絞る
   - `--attach` は `gh` 2.99.0以降の `gh pr create` にしかない。`gh pr edit` や `gh pr comment` には無いため、PRを作ったあとから添付を足すことはできない。`gh --version` で確認し、2.99.0未満なら `--attach` と本文の画像参照を外して作成し、添付できなかった旨を必ず報告する
   - 一部の添付だけが失敗した場合、成功した分を伴ってPRは作成される。終了コードは非0になるが標準出力にPRのURLが出るので、**URLが出ていればPRを作り直さない**。添付の一部が失敗した旨を報告する
   - `@copilot` の指定には `gh` 2.88.0以降が必要。それ未満やCopilot code reviewが使えないリポジトリではコマンドが失敗する
   - 失敗したら `gh pr view --json url,number` でPRが作成済みかを先に確認する
     - 未作成なら失敗の原因になったオプションを外して作り直す
     - 作成済みならPRはそのままにして、依頼や添付だけが失敗した旨を報告する（重複してPRを作らない）
   - どちらの場合もCopilotへのレビュー依頼や添付が失敗したことを必ず報告する
   - レビューのeffort levelはコマンドから指定できない。Balancedにするにはリポジトリの Settings > Copilot > Code review での設定が必要
9. `gh pr comment <PR番号> --body "@codex review"` でCodexのレビューを起動
   - リポジトリでCodexのGitHub連携が有効でない場合は無反応になる。その場合は連携が未設定である旨を報告する
   - CodexとCopilotから返ってきたレビューは `/pr-fix` で取得・修正する

## エラーハンドリング
- 認証エラー時は手動PR作成URLを提供
- `gh auth refresh -s repo,read:org` で再認証案内

## 絶対に守るべきルール
- 関係のない変更はコミットに含めない
- 関係のない変更を消さない
- `git checkout`、`git restore`、`git reset`、`git stash` は使わない（ブランチ作成時の明示的stashは除く）
