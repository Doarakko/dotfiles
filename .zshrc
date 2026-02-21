export PS1="[%n] %~ $"

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

# マージ済みブランチのworktreeを削除する
gwt-clean() {
  local repo_root
  local main_branch
  local worktree_path
  local branch_name
  local deleted_count=0

  repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ -z "$repo_root" ]]; then
    echo "Error: Not in a git repository" >&2
    return 1
  fi

  # メインブランチを特定（main or master）
  if git show-ref --verify --quiet refs/heads/main; then
    main_branch="main"
  elif git show-ref --verify --quiet refs/heads/master; then
    main_branch="master"
  else
    echo "Error: Could not find main or master branch" >&2
    return 1
  fi

  # リモートの最新情報を取得
  git fetch --prune 2>/dev/null

  # worktree一覧を取得して処理（プロセス置換でサブシェルを回避）
  while read -r line; do
    if [[ "$line" == worktree\ * ]]; then
      worktree_path="${line#worktree }"
    elif [[ "$line" == branch\ * ]]; then
      branch_name="${line#branch refs/heads/}"

      # メインブランチ自体はスキップ
      if [[ "$branch_name" == "$main_branch" ]]; then
        continue
      fi

      # メインブランチにマージ済みか確認（+はworktree、*は現在のブランチを示す）
      if git branch --merged "$main_branch" | grep -qE "^[[:space:]*+]*${branch_name}$"; then
        echo "Removing: $worktree_path (branch: $branch_name)"
        git worktree remove "$worktree_path" 2>/dev/null
        git branch -d "$branch_name" 2>/dev/null
        ((deleted_count++))
      fi
    fi
  done < <(git worktree list --porcelain)

  echo "Done. Removed $deleted_count worktree(s)."
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

# Claude Code
alias cc='claude'
alias ccw='claude --worktree'

# Claude Code plugin install
alias claude-plugin-install='claude plugin marketplace add ~/src/dotfiles && claude plugin install doarakko-config@doarakko-config && claude plugin marketplace add hashicorp/agent-skills && claude plugin install terraform-code-generation@hashicorp && claude plugin install terraform-module-generation@hashicorp && claude plugin install gopls-lsp@claude-plugins-official && claude plugin install typescript-lsp@claude-plugins-official && claude plugin install pyright-lsp@claude-plugins-official'

# Claude Code plugin update
alias claude-plugin-update='claude plugin marketplace update && claude plugin uninstall doarakko-config@doarakko-config; claude plugin install doarakko-config@doarakko-config && claude plugin uninstall terraform-code-generation@hashicorp; claude plugin install terraform-code-generation@hashicorp && claude plugin uninstall terraform-module-generation@hashicorp; claude plugin install terraform-module-generation@hashicorp'
