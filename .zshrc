export PS1="[%n] %~ $"

alias code="code-insiders"

# git worktreeで新しいブランチを作成し、そのディレクトリに移動する
gwt() {
  local branch_name="$1"
  local repo_root
  local worktree_base
  local worktree_path

  repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ -z "$repo_root" ]]; then
    echo "Error: Not in a git repository" >&2
    return 1
  fi

  # ブランチ名が指定されていない場合は自動生成
  if [[ -z "$branch_name" ]]; then
    branch_name="wt-$(date +%Y%m%d-%H%M%S)"
  fi

  # VSCodeと同じ形式: リポジトリ名.worktrees/ブランチ名
  worktree_base="${repo_root}.worktrees"
  worktree_path="${worktree_base}/${branch_name}"

  # worktreesディレクトリがなければ作成
  mkdir -p "$worktree_base"

  # worktreeを作成
  if git worktree add -b "$branch_name" "$worktree_path" 2>/dev/null; then
    echo "Created worktree at: $worktree_path"
    echo "Branch: $branch_name"
    cd "$worktree_path"
  elif git worktree add "$worktree_path" "$branch_name" 2>/dev/null; then
    # 既存のブランチを使用する場合
    echo "Created worktree at: $worktree_path"
    echo "Branch: $branch_name (existing)"
    cd "$worktree_path"
  else
    echo "Error: Failed to create worktree" >&2
    return 1
  fi
}

# マージ済みブランチとworktreeを一括削除する
gb-clean() {
  local base
  local deleted_count=0

  if [[ -z "$(git rev-parse --show-toplevel 2>/dev/null)" ]]; then
    echo "Error: Not in a git repository" >&2
    return 1
  fi

  # ベースブランチを特定
  if [[ -n "$1" ]]; then
    base="$1"
  elif git show-ref --verify --quiet refs/heads/main; then
    base="main"
  elif git show-ref --verify --quiet refs/heads/master; then
    base="master"
  else
    echo "Error: Could not find main or master branch" >&2
    return 1
  fi

  # リモートの最新情報を取得
  git fetch --prune 2>/dev/null

  # worktree内にいる場合はメインworktreeに移動
  local main_worktree
  main_worktree=$(git worktree list --porcelain | awk '/^worktree /{print substr($0,10); exit}')
  if [[ "$(git rev-parse --show-toplevel)" != "$main_worktree" ]]; then
    echo "Switching to main worktree: $main_worktree"
    cd "$main_worktree"
  fi

  # ベースブランチにチェックアウト
  git checkout "$base" || return 1

  # worktreeで使用中のブランチとパスのマップを構築
  local -A worktree_map
  local wt_path wt_branch
  while read -r line; do
    if [[ "$line" == worktree\ * ]]; then
      wt_path="${line#worktree }"
    elif [[ "$line" == branch\ * ]]; then
      wt_branch="${line#branch refs/heads/}"
      worktree_map[$wt_branch]="$wt_path"
    fi
  done < <(git worktree list --porcelain)

  # マージ済みブランチを削除（worktreeがあれば先に削除）
  while read -r b; do
    if [[ -n "${worktree_map[$b]}" ]]; then
      echo "Removing worktree: ${worktree_map[$b]} (branch: $b)"
      if ! git worktree remove "${worktree_map[$b]}"; then
        echo "Warning: Could not remove worktree ${worktree_map[$b]}, skipping branch $b" >&2
        continue
      fi
    fi
    git branch -d "$b" && ((deleted_count++))
  done < <(git branch --merged "$base" --format='%(refname:short)' \
             | grep -Ev '^(develop|main|master|production)$')

  echo "Done. Cleaned up $deleted_count merged branch(es)."
}

# 現在のworktreeからメインのworktreeに移動する
gwt-root() {
  local git_common_dir
  local main_worktree

  git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
  if [[ -z "$git_common_dir" ]]; then
    echo "Error: Not in a git repository" >&2
    return 1
  fi

  # git-common-dirはメインworktreeの.gitを指す
  # 相対パスの場合があるのでabsolute pathに変換
  main_worktree=$(cd "$git_common_dir"/.. && pwd)

  if [[ "$(git rev-parse --show-toplevel)" == "$main_worktree" ]]; then
    echo "Already in the main worktree: $main_worktree"
    return 0
  fi

  echo "Switching to main worktree: $main_worktree"
  cd "$main_worktree"
}

# ブランチ名を指定してチェックアウトする。worktreeがあればそこにcdする
gco() {
  local branch_name="$1"

  if [[ -z "$branch_name" ]]; then
    echo "Usage: gco <branch-name>" >&2
    return 1
  fi

  # worktreeを探す
  local worktree_path
  worktree_path=$(git worktree list --porcelain | awk -v branch="refs/heads/$branch_name" '
    /^worktree / { path = substr($0, 10) }
    $0 == "branch " branch { print path; exit }
  ')

  if [[ -n "$worktree_path" ]]; then
    echo "Switching to worktree: $worktree_path (branch: $branch_name)"
    cd "$worktree_path"
  else
    git checkout "$branch_name"
  fi
}

# Claude Code
export EDITOR="code-insiders"

# 命名: 直接叩く操作のうち、ccで始まるものはClaude Codeだけを対象にし、
# aiで始まるものはAI開発ツールチェーン全体を対象にする。補助関数はこの区別の外
alias cc='claude'
alias ccw='claude --worktree'
alias ccu='brew upgrade claude-code'

# 登録するマーケットプレイス（導入と更新で共有）
CLAUDE_MARKETPLACES=(
  ~/src/dotfiles
  anthropics/skills
  anthropics/claude-plugins-official
)

# インストールするプラグイン（導入と更新で共有）
CLAUDE_PLUGINS=(
  doarakko-config@doarakko-config
  example-skills@anthropic-agent-skills
  context7@claude-plugins-official
  claude-md-management@claude-plugins-official
  gopls-lsp@claude-plugins-official
  typescript-lsp@claude-plugins-official
  pyright-lsp@claude-plugins-official
  feature-dev@claude-plugins-official
)

# Homebrewから入れるAI開発ツール（導入と更新で共有）
AI_BREW_CASKS=(
  claude-code
  codex
)

# PRの作成・CI確認に要るため、AIワークフローの一部として一緒に更新する
AI_BREW_FORMULAE=(
  gh
)

# npmから入れるAI開発ツール（導入と更新で共有）
# asdfが管理するnode配下へ入るので、nodeを切り替えたら入れ直しが要る
AI_NPM_PACKAGES=(
  @google/gemini-cli
  @playwright/cli
)

# 失敗した対象をまとめて報告する。1件転んでも残りを進めたいので終了コードは最後に決める
ai-tools-report() {
  if (( $# == 0 )); then
    print -r -- "すべて完了した"
    return 0
  fi
  print -r -- "失敗した対象: $*"
  return 1
}

# マーケットプレイスを登録する（登録済みの場合は何もしない）
cc-marketplace-add() {
  local marketplace
  for marketplace in "${CLAUDE_MARKETPLACES[@]}"; do
    claude plugin marketplace add "$marketplace" || return 1
  done
}

# AI開発ツールとClaude Codeプラグインをまとめて導入する
aii() {
  local failed=()
  local cask formula pkg plugin

  for cask in "${AI_BREW_CASKS[@]}"; do
    brew list --cask "$cask" >/dev/null 2>&1 && continue
    brew install --cask "$cask" || failed+=("$cask")
  done

  for formula in "${AI_BREW_FORMULAE[@]}"; do
    brew list --formula "$formula" >/dev/null 2>&1 && continue
    brew install "$formula" || failed+=("$formula")
  done

  # 導入済みは飛ばす。ここで最新化まで走ると更新側と区別が付かなくなる
  for pkg in "${AI_NPM_PACKAGES[@]}"; do
    npm ls -g --depth=0 "$pkg" >/dev/null 2>&1 && continue
    npm install -g "${pkg}@latest" || failed+=("$pkg")
  done

  cc-marketplace-add || failed+=("marketplace")

  for plugin in "${CLAUDE_PLUGINS[@]}"; do
    claude plugin install "$plugin" || failed+=("$plugin")
  done

  ai-tools-report "${failed[@]}"
}

# AI開発ツールとClaude Codeプラグインをまとめて最新化する
aiu() {
  local failed=()
  local cask formula pkg plugin

  # 未導入のものへupgradeを投げると失敗するため、その場合は導入に回す
  for cask in "${AI_BREW_CASKS[@]}"; do
    if brew list --cask "$cask" >/dev/null 2>&1; then
      brew upgrade --cask "$cask" || failed+=("$cask")
    else
      brew install --cask "$cask" || failed+=("$cask")
    fi
  done

  for formula in "${AI_BREW_FORMULAE[@]}"; do
    if brew list --formula "$formula" >/dev/null 2>&1; then
      brew upgrade "$formula" || failed+=("$formula")
    else
      brew install "$formula" || failed+=("$formula")
    fi
  done

  for pkg in "${AI_NPM_PACKAGES[@]}"; do
    npm install -g "${pkg}@latest" || failed+=("$pkg")
  done

  # マーケットプレイス未登録だとinstallが失敗するため先に登録する
  cc-marketplace-add || failed+=("marketplace")
  # 更新が落ちるとプラグインは古いカタログのまま入る。後段がたまたま成功しても
  # 「完了」と報告しないよう、ここでも失敗を数える
  claude plugin marketplace update || failed+=("marketplace-update")

  # 導入は未導入を埋めるだけの前処理として先に置く。導入済みなら何もせず成功するため、
  # 後段に回すと更新が転んでも成功が返り、古いまま「完了」と報告してしまう
  # 成否は更新の戻り値だけで決める
  for plugin in "${CLAUDE_PLUGINS[@]}"; do
    claude plugin install "$plugin" >/dev/null 2>&1
    claude plugin update "$plugin" || failed+=("$plugin")
  done

  ai-tools-report "${failed[@]}"
}
