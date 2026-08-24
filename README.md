# dotfiles

## Usage

```bash
mkdir -p ~/src
cd ~/src
git clone https://github.com/Doarakko/dotfiles.git
```

Add `source ~/src/dotfiles/.zshrc` to your `~/.zshrc` to load the configuration.

Keep `~/.zshrc` limited to machine-specific settings (PATH entries, version managers, tool shell integrations) plus that one `source` line. Never copy the contents of this repository's `.zshrc` into `~/.zshrc` — the copy goes stale and changes made here stop taking effect.

### Claude Code

install

```bash
ccpi
```

update

```bash
ccpu
```

Both register the marketplaces listed in `CLAUDE_MARKETPLACES` first, then process every plugin in `CLAUDE_PLUGINS` (defined in `.zshrc`). Add or remove plugins in those arrays only — `ccpi` and `ccpu` share them.

After install/update, restart Claude Code to apply changes.

#### Auto review

A `Stop` hook (`hooks/auto-review.sh`) reviews uncommitted changes before Claude finishes a turn.

- When the working tree has changes that have not been reviewed yet, Claude runs the `code-reviewer` and `codex-reviewer` subagents in parallel, merges their findings, fixes Critical / High ones, and reports Medium / Low ones without changing the code.
- `codex-reviewer` runs `codex exec review --uncommitted` for a second opinion from a different model. Install it with `brew install --cask codex`. The hook detects whether the CLI is on `PATH` and asks for the Claude review alone when it is missing, so the flow still works without codex.
- The hook stays silent when there is nothing to review: a clean working tree, a directory outside git, or a tree unchanged since the last review. Files ignored by git are not counted as changes.
- It fires at most once per turn. `stop_hook_active` in the hook input guards against looping.
- Turns that trigger a review send the completion notification twice, once before the review and once when the turn actually ends.
- To turn it off, remove the `auto-review.sh` entry from `hooks.Stop` in `.claude-plugin/plugin.json`, or set `"disableAllHooks": true` in your settings to disable every hook.

Codex reviews pull requests as well. `/pr-zero` posts an `@codex review` comment after opening the PR, and `/pr-fix` picks up the findings that `chatgpt-codex-connector` posts. This needs the repository to be configured at <https://chatgpt.com/codex/settings/code-review>; without it the comment goes unanswered.

`AGENTS.md` holds the review rules Codex follows, both locally and on GitHub. It mirrors `CLAUDE.md`, so update both together.

#### MCP Server

- [context7](https://github.com/upstash/context7)
- Figma
- [Chrome DevTools](https://github.com/ChromeDevTools/chrome-devtools-mcp)

## application

- 1Password7
- Raycast
- Google Chrome
- LINE
- Slack
- Todoist

## development

- docker-compose
- Docker Desktop for Mac
- Git
- Homebrew
- Postman
- Visual Studio Code
- Claude Code
- gh
- [Playwright CLI](https://github.com/microsoft/playwright-cli)
