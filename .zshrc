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

alias cc='claude'
alias ccw='claude --worktree'
alias ccu='brew upgrade claude-code'
alias ccpi='claude plugin marketplace add ~/src/dotfiles && claude plugin install doarakko-config@doarakko-config && claude plugin marketplace add hashicorp/agent-skills && claude plugin install terraform-code-generation@hashicorp && claude plugin install terraform-module-generation@hashicorp && claude plugin marketplace add anthropics/skills && claude plugin install example-skills@anthropic-agent-skills && claude plugin marketplace add anthropics/claude-plugins-official && claude plugin install claude-md-management@claude-plugins-official && claude plugin install gopls-lsp@claude-plugins-official && claude plugin install typescript-lsp@claude-plugins-official && claude plugin install pyright-lsp@claude-plugins-official'
alias ccpp='claude plugin marketplace update && claude plugin uninstall doarakko-config@doarakko-config; claude plugin install doarakko-config@doarakko-config && claude plugin uninstall terraform-code-generation@hashicorp; claude plugin install terraform-code-generation@hashicorp && claude plugin uninstall terraform-module-generation@hashicorp; claude plugin install terraform-module-generation@hashicorp && claude plugin uninstall example-skills@anthropic-agent-skills; claude plugin install example-skills@anthropic-agent-skills && claude plugin uninstall claude-md-management@claude-plugins-official; claude plugin install claude-md-management@claude-plugins-official'
