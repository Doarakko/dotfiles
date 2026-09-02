"""Claude Code PR作成ガード Hook の判定本体。

シェルの語分割はクォートやエスケープの規則が複雑で、正規表現では正しく扱えない。
shlex で実際にトークンへ分解し、コマンド位置に現れた PR 作成呼び出しだけを見る。
"""

import json
import os
import re
import shlex
import subprocess
import sys

# 括弧は含めない。コマンド置換の括弧は呼び出しの引数を終わらせないため
SEPARATOR_CHARS = {";", "&", "|", "\n"}

# 改行を記号として切り出す。既定では空白と同じ扱いになり、次の行のフラグまで
# 同じ呼び出しの引数として読んでしまう
PUNCTUATION = "();<>|&\n"

# 値を取らない短縮フラグ。結合して書けるため、まとめて解釈する必要がある
BOOLEAN_SHORTS = {"d", "e", "f", "w"}
# 値を取る短縮フラグ。以降は値になるので、そこで解釈を打ち切る
VALUE_SHORTS = {"a", "B", "b", "F", "H", "l", "m", "p", "R", "r", "T", "t"}

# この記号のうしろに置かれた注釈記号は、語の先頭に現れたものとして扱う
WORD_BREAKS = " \t\r\n;&|()<>"

TRUTHY = {"", "true", "t", "1"}
FALSY = {"false", "f", "0"}

# E2E の動作確認が残したスクリーンショットと動画の置き場所
DEFAULT_MEDIA_ROOT = "/tmp/claude/e2e"
MEDIA_SUFFIXES = (".png", ".webm")  # 手順が選ぶのと同じ、大文字小文字を区別する綴り

# 添付できる大きさの上限。PR作成の手順が選び出す条件より厳しくしてある。
# 数えたのに手順側で選ばれないものがあると、応えようのない差し戻しになる
MEDIA_SIZE_LIMIT = 9999 * 1024

# 添付を受け付ける最初の版
ATTACH_SUPPORTED_FROM = (2, 99, 0)


def strip_comments(command):
    """語の先頭に現れた注釈だけを、その行の終わりまで取り除く。

    シェルが注釈と見なすのは語の先頭に置かれた記号だけで、語の途中にある
    ものは文字として扱われる。添付の代替テキストはこの区切り記号を語の途中で
    使うため、字句解析器の既定にまかせると引数の読み取りが途中で終わる。
    クォートやエスケープの内側も注釈にはならないので、状態を追いながら判定する。
    """
    kept = []
    # 開いたままの括弧の種類。置換を閉じた括弧のうしろは語が続く
    parens = []
    quote = ""
    inside_word = False
    index = 0
    while index < len(command):
        char = command[index]
        if quote:
            kept.append(char)
            if char == "\\" and quote == '"' and index + 1 < len(command):
                index += 1
                kept.append(command[index])
            elif char == quote:
                quote = ""
            index += 1
            inside_word = False
            continue
        if char == "\\" and index + 1 < len(command):
            # 行継続は入力の段階で消える。手前の状態をそのまま引き継ぐ
            if command[index + 1] == "\n":
                index += 2
                continue
            kept.append(char)
            index += 1
            kept.append(command[index])
            index += 1
            # エスケープされた文字は必ず語の一部で、区切りにはならない
            inside_word = True
            continue
        if char in "'\"":
            quote = char
            kept.append(char)
            index += 1
            inside_word = False
            continue
        if char == "$" and index + 1 < len(command) and command[index + 1] == "(":
            parens.append("substitution")
            kept.append(char)
            kept.append("(")
            index += 2
            inside_word = False
            continue
        if char == "(":
            # 入出力を渡す形の置換も、閉じたあとに語が続く
            redirected = bool(kept) and kept[-1] in "<>"
            parens.append("substitution" if redirected else "group")
            kept.append(char)
            index += 1
            inside_word = False
            continue
        if char == ")":
            inside_word = bool(parens) and parens.pop() == "substitution"
            kept.append(char)
            index += 1
            continue
        if char == "#" and not inside_word and (not kept or kept[-1] in WORD_BREAKS):
            while index < len(command) and command[index] != "\n":
                index += 1
            continue
        kept.append(char)
        index += 1
        inside_word = False
    return "".join(kept)


def tokenize(command, strip=True):
    """コマンドをトークンへ分解する。

    既定では注釈を先に取り除く。字句解析器に注釈を任せると、代替テキストを
    添えた添付指定で引数の読み取りが語の途中で終わるため。
    取り除きに失敗したときのために、字句解析器へ任せる読み方も残してある。
    """
    if strip:
        command = strip_comments(command)
    # 行継続はシェルと同じく畳む。畳まないと改行が区切りとして残り、
    # 1つの呼び出しを複数行に分けて書いただけのコマンドを取り違える
    command = re.sub(r"(?<!\\)\\\n", " ", command)
    lexer = shlex.shlex(command, posix=True, punctuation_chars=PUNCTUATION)
    lexer.whitespace_split = True
    lexer.whitespace = " \t\r"
    lexer.commenters = "" if strip else "#"
    return list(lexer)


def is_separator(token):
    """区切り記号だけでできたトークンかどうかを返す。

    記号は連続すると1トークンにまとめられるため、`&&` や改行を伴う `&\n` の
    ような組み合わせも区切りとして扱う必要がある。
    """
    return bool(token) and all(char in SEPARATOR_CHARS for char in token)


def is_only(token, char):
    """その記号だけでできたトークンかどうかを返す。"""
    return bool(token) and all(letter == char for letter in token)


def pr_create_arguments(tokens):
    """コマンド位置の gh pr create を探し、その呼び出しの引数だけを返す。

    クォートされた文字列は 1 トークンに畳まれるため、文字列リテラルの中に
    書かれた gh pr create が 3 連続トークンとして現れることはない。

    置換の中身は展開されて1つの語になるため、そこに現れた記号は引数として
    読まない。読むと、置換が生む文字列の中の文字列をフラグと取り違える。
    """
    for i in range(len(tokens) - 2):
        if tokens[i : i + 3] != ["gh", "pr", "create"]:
            continue
        arguments = []
        depth = 0
        for token in tokens[i + 3 :]:
            if is_separator(token):
                break
            if is_only(token, "("):
                depth += len(token)
                continue
            if is_only(token, ")"):
                depth = max(0, depth - len(token))
                continue
            if depth:
                continue
            arguments.append(token)
        return arguments
    return None


def parse_short_group(token):
    """結合短縮フラグを解釈し、含まれるブール短縮フラグの集合を返す。"""
    found = set()
    for char in token[1:]:
        if char in BOOLEAN_SHORTS:
            found.add(char)
            continue
        if char in VALUE_SHORTS:
            break
        break
    return found


def classify(arguments):
    """(ドラフトか, ガード対象外か, 添付があるか) を返す。"""
    is_draft = False
    exempt = False
    attaches = False

    for token in arguments:
        name, _, value = token.partition("=")

        if name in ("--help", "--dry-run"):
            exempt = True
        elif name == "--web":
            exempt = True
        elif name == "--attach":
            attaches = True
        elif name == "--draft" or name == "-d":
            if value.lower() in FALSY:
                is_draft = False
            elif value.lower() in TRUTHY:
                is_draft = True
        elif name.startswith("-") and not name.startswith("--") and len(name) > 1:
            shorts = parse_short_group(name)
            if "w" in shorts:
                exempt = True
            if "d" in shorts:
                is_draft = True

    return is_draft, exempt, attaches


def read_git(directory, *arguments):
    """作業ディレクトリで git に問い合わせる。答えが得られなければ空文字を返す。"""
    try:
        completed = subprocess.run(
            ["git", "-C", directory, *arguments],
            capture_output=True,
            text=True,
            timeout=2,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    if completed.returncode != 0:
        return ""
    return completed.stdout.strip()


def media_directory(cwd):
    """撮影した画像と動画の置き場所を返す。突き止められなければ None を返す。

    置き場所は E2E の動作確認と同じ規則で組み立てる。ブランチ名のスラッシュは
    そのままでは階層になってしまうため、双方で同じ置き換えをする。
    """
    # 数値を渡すとファイル記述子として扱われ、その先で例外になる
    if not isinstance(cwd, str) or not os.path.isdir(cwd):
        return None
    top = read_git(cwd, "rev-parse", "--show-toplevel")
    branch = read_git(cwd, "branch", "--show-current")
    if not top or not branch:
        return None
    root = os.environ.get("CLAUDE_E2E_OUTPUT_ROOT") or DEFAULT_MEDIA_ROOT
    return os.path.join(root, os.path.basename(top), branch.replace("/", "-"))


def has_media(directory):
    """このブランチで撮った、添付できる成果物が残っているかどうかを返す。"""
    if directory is None:
        return False
    try:
        names = os.listdir(directory)
    except OSError:
        return False
    for name in names:
        if not name.endswith(MEDIA_SUFFIXES):
            continue
        path = os.path.join(directory, name)
        try:
            # 手順は通常のファイルしか選ばない。同じ名前のディレクトリを数えると
            # 添付しようのないものを求めて差し戻し続けることになる
            if os.path.isfile(path) and os.path.getsize(path) < MEDIA_SIZE_LIMIT:
                return True
        except OSError:
            continue
    return False


def attach_supported():
    """手元の gh が添付を受け付けるかどうかを返す。分からなければ受け付けない扱い。

    受け付けない版で添付を促すと、応えようのない差し戻しを繰り返すことになる。
    """
    try:
        completed = subprocess.run(
            ["gh", "--version"],
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    if completed.returncode != 0:
        return False
    found = re.search(r"(\d+)\.(\d+)\.(\d+)", completed.stdout)
    if not found:
        return False
    return tuple(int(part) for part in found.groups()) >= ATTACH_SUPPORTED_FROM


def emit(payload):
    json.dump({"hookSpecificOutput": payload}, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


def main():
    try:
        received = json.load(sys.stdin)
        command = received.get("tool_input", {}).get("command", "")
        cwd = received.get("cwd", "")
    except (ValueError, AttributeError):
        return
    if not command:
        return

    try:
        tokens = tokenize(command)
    except ValueError:
        # 注釈の切り出しを誤ると、注釈の中のクォートが本文に残って読めなくなる。
        # 素通りさせないよう、字句解析器に注釈を任せてもう一度読む
        try:
            tokens = tokenize(command, strip=False)
        except ValueError:
            # クォートが閉じていないなど、シェルとしても実行できない入力
            return

    arguments = pr_create_arguments(tokens)
    if arguments is None:
        return

    is_draft, exempt, attaches = classify(arguments)
    if exempt:
        return

    if not is_draft:
        emit({
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": (
                "PRはドラフトで作成します。doarakko-config:pr-zero スキルを起動し、"
                "その手順に従って作成し直してください。"
            ),
        })
        return

    # 撮った成果物は貼られて初めて意味を持つ。撮影自体は強制しない
    if not attaches:
        directory = media_directory(cwd)
        if has_media(directory) and attach_supported():
            emit({
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": (
                    f"動作確認の成果物が {directory} に残っています。"
                    "PR本文に埋め込んだうえで --attach を並べて添付し、"
                    "作成し直してください。この変更と関係のない古い成果物なら、"
                    f"find {directory} -maxdepth 1 -type f -delete "
                    "で消してから作成し直してください。"
                ),
            })
            return

    emit({
        "hookEventName": "PreToolUse",
        "additionalContext": (
            "PRを作成しようとしています。doarakko-config:pr-zero スキルの手順に"
            "従ってください。まだ起動していなければ先に起動すること"
            "（起動済みならそのまま進めてよい）。"
        ),
    })


if __name__ == "__main__":
    main()
