"""Claude Code PR作成ガード Hook の判定本体。

シェルの語分割はクォートやエスケープの規則が複雑で、正規表現では正しく扱えない。
shlex で実際にトークンへ分解し、コマンド位置に現れた PR 作成呼び出しだけを見る。
"""

import json
import re
import shlex
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

TRUTHY = {"", "true", "t", "1"}
FALSY = {"false", "f", "0"}


def tokenize(command):
    # 行継続はシェルと同じく畳む。畳まないと改行が区切りとして残り、
    # 1つの呼び出しを複数行に分けて書いただけのコマンドを取り違える
    command = re.sub(r"(?<!\\)\\\n", " ", command)
    lexer = shlex.shlex(command, posix=True, punctuation_chars=PUNCTUATION)
    lexer.whitespace_split = True
    lexer.whitespace = " \t\r"
    return list(lexer)


def is_separator(token):
    """区切り記号だけでできたトークンかどうかを返す。

    記号は連続すると1トークンにまとめられるため、`&&` や改行を伴う `&\n` の
    ような組み合わせも区切りとして扱う必要がある。
    """
    return bool(token) and all(char in SEPARATOR_CHARS for char in token)


def pr_create_arguments(tokens):
    """コマンド位置の gh pr create を探し、その呼び出しの引数だけを返す。

    クォートされた文字列は 1 トークンに畳まれるため、文字列リテラルの中に
    書かれた gh pr create が 3 連続トークンとして現れることはない。
    """
    for i in range(len(tokens) - 2):
        if tokens[i : i + 3] != ["gh", "pr", "create"]:
            continue
        arguments = []
        for token in tokens[i + 3 :]:
            if is_separator(token):
                break
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
    """(ドラフトか, ガード対象外か) を返す。"""
    is_draft = False
    exempt = False

    for token in arguments:
        name, _, value = token.partition("=")

        if name in ("--help", "--dry-run"):
            exempt = True
        elif name == "--web":
            exempt = True
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

    return is_draft, exempt


def emit(payload):
    json.dump({"hookSpecificOutput": payload}, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


def main():
    try:
        command = json.load(sys.stdin).get("tool_input", {}).get("command", "")
    except (ValueError, AttributeError):
        return
    if not command:
        return

    try:
        tokens = tokenize(command)
    except ValueError:
        # クォートが閉じていないなど、シェルとしても実行できない入力
        return

    arguments = pr_create_arguments(tokens)
    if arguments is None:
        return

    is_draft, exempt = classify(arguments)
    if exempt:
        return

    if is_draft:
        emit({
            "hookEventName": "PreToolUse",
            "additionalContext": (
                "PRを作成しようとしています。doarakko-config:pr-zero スキルの手順に"
                "従ってください。まだ起動していなければ先に起動すること"
                "（起動済みならそのまま進めてよい）。"
            ),
        })
        return

    emit({
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            "PRはドラフトで作成します。doarakko-config:pr-zero スキルを起動し、"
            "その手順に従って作成し直してください。"
        ),
    })


if __name__ == "__main__":
    main()
