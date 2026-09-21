#!/bin/bash

# 自動レビューが見るワークツリーの状態表を作る
# Stop と SessionStart の両方から読み込まれる。二重に持つと、判定の土台がずれる
# 単体では実行せず、呼び出し側が標準入力の内容を変数へ入れてから読み込む
# 読み込みはトップレベルに置くこと。git管理外でここから抜けるため、部分シェルでは呼び出し元へ届かない
# エラー時の振る舞いは呼び出し側の設定に従う

TAB=$'\t'

# セッションごとに状態を記録する（リポジトリは汚さない）
# 記録するのは変更のあるパスと、その時点の内容の目印
# この記録は hook だけが読み書きするため一時ディレクトリでよい
# レビュー範囲は記録ではなく依頼文へ載せて渡すので、外部と置き場所を共有しない
STATE_DIR="${TMPDIR:-/tmp}/claude-auto-review"
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' | tr -cd 'A-Za-z0-9._-')
if [[ -z "$SESSION_ID" ]]; then
  SESSION_ID="unknown"
fi

# hook 入力の作業ディレクトリへ移動（取得できなければ現在地のまま）
HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
if [[ -n "$HOOK_CWD" && -d "$HOOK_CWD" ]]; then
  cd "$HOOK_CWD"
fi

# git 管理外では何もしない
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

# リポジトリのルートへ揃える
# 差分の列挙はルート基準のパスを返すが、未追跡ファイルの列挙とファイルの存在判定は現在地基準になる
# サブディレクトリで起動していると両者が噛み合わず、変更を取りこぼす
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [[ -n "$REPO_ROOT" && -d "$REPO_ROOT" ]]; then
  cd "$REPO_ROOT"
fi

HEAD_EXISTS=false
if git rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
  HEAD_EXISTS=true
fi

# 目印を作る手段そのものが使えないか
# ファイル個別の「読めない」と混ぜると、すべてが同じ値で固定され変更が黙って落ち続ける
# 試すのは実際に使う呼び出しの形。標準入力だけ試すと、ファイル引数で落ちる実装を取り逃がす
HASH_USABLE=true
HASH_PROBE="${STATE_DIR}/.probe"
if ! { mkdir -p "$STATE_DIR" && : >"$HASH_PROBE" && shasum -- "$HASH_PROBE" >/dev/null 2>&1; }; then
  HASH_USABLE=false
fi
rm -f "$HASH_PROBE"

# 変更のあるパスを列挙する
list_changed_paths() {
  if [[ "$HEAD_EXISTS" == "true" ]]; then
    # 名前の付け替えは検出させない。片側のパスしか挙がらないと記録と突き合わせられない
    git diff HEAD --name-only --no-renames -z 2>/dev/null || true
  else
    # 最初のコミットがまだ無いリポジトリでは、記録済みのものがそのまま変更にあたる
    git ls-files --cached -z 2>/dev/null || true
  fi
  # 未追跡ファイルは差分に現れないため、別に挙げる
  git ls-files --others --exclude-standard -z 2>/dev/null || true
}

# パスごとの内容の目印を作る
# 先頭がハイフンのパスをオプションと解釈させないため、区切りを必ず置く
mark_for() {
  local target=$1 sum=""
  if [[ -f "$target" ]]; then
    sum=$(shasum -- "$target" 2>/dev/null) || sum=""
  elif [[ -e "$target" || -L "$target" ]]; then
    # 中身を直接読めないもの（入れ子のリポジトリ、ディレクトリを指すリンク）
    # 差分から目印を作れるのは最初のコミットがある場合だけ
    if [[ "$HEAD_EXISTS" == "true" ]]; then
      sum=$(git diff HEAD -- "$target" 2>/dev/null | shasum 2>/dev/null) || sum=""
    fi
  else
    # 消えたファイル。目印が無いこと自体が変化になる
    printf 'gone'
    return
  fi
  if [[ -z "$sum" ]]; then
    # 読めないので中身の変化までは追えない
    # 消えた場合と同じ値にすると、変化しない値のまま状態の移り変わりも拾えなくなる
    printf 'unknown'
    return
  fi
  # 実行ビットだけが変わった場合も拾えるよう、目印に混ぜる
  printf '%s%s' "${sum%% *}" "$([[ -x "$target" ]] && printf 'x')"
}

# レビュー範囲を絞れるか。絞れないときは未コミットの変更すべてを対象にする
SCOPE_USABLE=$HASH_USABLE

RECORDS=""
# ループをパイプラインへ入れない。部分シェルになると絞り込みの可否が外へ伝わらない
while IFS= read -r -d '' changed_path; do
  case "$changed_path" in
  *"$TAB"* | *$'\n'*)
    # 1行1ファイルで記録するため、改行やタブを含む名前は一覧へ出せない
    # 記録には残して変化を追えるようにし、範囲の提示だけ諦める
    SCOPE_USABLE=false
    RECORDS="${RECORDS}$(mark_for "$changed_path")${TAB}$(printf '%s' "$changed_path" | tr '\n\t' '??')"$'\n'
    continue
    ;;
  esac
  RECORDS="${RECORDS}$(mark_for "$changed_path")${TAB}${changed_path}"$'\n'
done < <(list_changed_paths)
RECORDS=$(printf '%s' "$RECORDS" | LC_ALL=C sort -u)

# 状態表をそのまま書き出す。空でも書く。読む側は「無い」と「空」を区別する
write_state() {
  local target=$1
  mkdir -p "$STATE_DIR"
  if [[ -n "$RECORDS" ]]; then
    printf '%s\n' "$RECORDS" >"$target"
  else
    : >"$target"
  fi
}
