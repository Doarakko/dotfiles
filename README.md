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
- `codex-reviewer` runs `codex exec review --uncommitted` for a second opinion from a different model. Install it with `brew install --cask codex` and sign in with `codex login`; without a login every run fails with a 401. The hook checks both that the CLI is on `PATH` and that `codex login status` succeeds, and asks for the Claude review alone otherwise, so the flow still works without codex. `codex login status` ignores key-based auth, so `CODEX_API_KEY`, `CODEX_ACCESS_TOKEN`, and `OPENAI_API_KEY` count as signed in too.
- Passing that check does not guarantee the review runs. A login expires while still reporting as signed in, a plan may not cover codex, and a sandbox that denies writes to `~/.codex` or blocks the network stops codex before it starts. A codex that cannot authenticate may also hang on retries instead of returning the 401. When codex fails for one of those reasons, `codex-reviewer` writes the reason to `/tmp/claude/codex-review-cooldown` and the hook stops asking for a codex review for the next 6 hours, so a broken setup costs one skipped review instead of one per turn. Running `codex login` again ends the wait immediately, because the stored credentials (`~/.codex/auth.json`, or `$CODEX_HOME/auth.json` when that is set) come out newer than the marker — any other write to that file, such as an automatic token refresh, releases the wait the same way. Set `CLAUDE_CODEX_COOLDOWN_SECONDS` to change the window and `CLAUDE_CODEX_COOLDOWN_FILE` to move the marker.
- While the wait is on, the hook says nothing about codex. The reason was reported when the review was skipped, and `cat /tmp/claude/codex-review-cooldown` shows it again.
- The wait is global. The marker lives outside any repository, so one broken setup silences codex reviews in every project until the window passes. Someone signed in through `CODEX_API_KEY`, `CODEX_ACCESS_TOKEN`, or `OPENAI_API_KEY` has no `~/.codex/auth.json` to refresh either, so fixing a bad key does not cut the wait short the way `codex login` does; delete the marker to resume at once.
- Running codex under the Bash sandbox needs two grants in `.claude/settings.json`, because a sandboxed codex writes sqlite state and logs to `~/.codex` and talks to ChatGPT: `sandbox.filesystem.allowWrite` must include `~/.codex`, and `sandbox.network.allowedDomains` must include `chatgpt.com` and `*.openai.com`. Without the write grant codex dies at startup with `failed to initialize in-process app-server client: Operation not permitted`, before it ever checks credentials. This repository's settings carry both.
- That write grant is narrowed by `sandbox.filesystem.denyWrite` on `~/.codex/config.toml`, `~/.codex/plugins`, `~/.codex/rules`, `~/.codex/skills`, `~/.codex/vendor_imports`, and `~/.codex/.tmp/bundled-marketplaces`. Each one decides what codex later runs outside the sandbox: `notify` and `mcp_servers.<name>.command` in the config, plugin executables, the execpolicy `.rules` files that pre-approve commands (`prefix_rule(pattern=[...], decision="allow")`), and the skills and bundled marketplace sources codex loads. A sandboxed command able to edit any of them would be handing itself unsandboxed execution on the user's next codex run. A deny holds inside a wider allow, so codex keeps the sqlite state, logs, and caches it actually writes.
- codex writes `config.toml` itself at runtime (model-migration notices, per-project `trust_level`), so denying it is a trade-off, not a free win. A sandboxed `codex exec` still starts and reaches its session banner with every deny in place, which is as far as it gets here without a login; the full review path is unverified.
- These settings are this repository's own project settings. They are not part of what the plugin installs, so a checkout that runs codex reviews under a sandbox elsewhere needs the same grants in its own settings.
- The hook stays silent when there is nothing to review: a clean working tree, a directory outside git, or a tree unchanged since the last review. Files ignored by git are not counted as changes.
- It fires at most once per turn. `stop_hook_active` in the hook input guards against looping.
- Turns that trigger a review send the completion notification twice, once before the review and once when the turn actually ends.
- `hooks/auto-review.test.sh` covers which reviewers the hook asks for in each codex state, using a stub on `PATH` instead of the real CLI. Run it after changing the hook.
- To turn it off, remove the `auto-review.sh` entry from `hooks.Stop` in `.claude-plugin/plugin.json`, or set `"disableAllHooks": true` in your settings to disable every hook.

Codex reviews pull requests as well. `/pr-zero` posts an `@codex review` comment after opening the PR, and `/pr-fix` picks up the findings that `chatgpt-codex-connector` posts. This needs the repository to be configured at <https://chatgpt.com/codex/settings/code-review>; without it the comment goes unanswered.

GitHub Copilot reviews pull requests too. `/pr-zero` passes `--reviewer @copilot` to `gh pr create`, so Copilot code review is requested the moment the draft PR opens, and `/pr-fix` picks up what it reports. Requesting Copilot from the CLI needs `gh` 2.88.0 or later; older versions cannot resolve `@copilot` and the command fails, so `/pr-zero` checks whether the PR was created before retrying without the flag.

The review effort level cannot be passed on the command line. To get **Balanced** reviews, set it per repository in Settings > Copilot > Code review > Review effort level; an organization can hold a default that a repository setting overrides. GitHub documents that default for automatic reviews only, so if a manually requested review still comes back as Lite, pick Balanced from the Reviewers section in the PR. The effort level each run used is shown in Copilot's PR overview comment. For reviews that are always Balanced without touching the PR, enable a ruleset with "Automatically request Copilot code review" and "Review draft pull requests" instead.

`AGENTS.md` holds the review rules Codex follows, both locally and on GitHub. It mirrors `CLAUDE.md`, so update both together.

#### PR creation

PRs go through `/pr-zero`, which creates a branch, commits, opens a draft PR, and asks Copilot and Codex to review it. Two mechanisms route PR creation into that workflow instead of leaving it to an ad-hoc `gh pr create`.

- `when_to_use` in the command's frontmatter lets Claude load the workflow on its own when you ask for a PR, so you do not have to type `/pr-zero`.
- A `PreToolUse` hook (`hooks/pr-create-guard.sh`) catches `gh pr create` as a backstop. Hooks cannot start a skill themselves, so the hook works on the command instead: it denies a PR that is not a draft and asks for the workflow to be followed, and lets a draft through with a reminder attached as context. Denying only the non-draft form is what keeps the hook from blocking `/pr-zero` itself, since step 6 of the workflow always passes `--draft`.
- The hook splits the command into real shell tokens (`hooks/pr-create-guard.py`, using `shlex`) rather than matching text. Quoting rules are too intricate for a regex, and three earlier regex versions each let a different quoting form through. Tokenizing collapses a quoted string into a single token, so a `gh pr create` written inside one is never mistaken for the command, and a `-d` sitting in a PR title or heredoc body is never mistaken for a flag.
- Only the flags belonging to that one invocation are read. Anything after `;`, `&&`, `||`, `|`, `&`, or a newline belongs to the next command, so `gh pr create --fill && docker run -d nginx` is still denied, and so is a `gh pr create` whose next line happens to carry a `-d` or `-w`. A newline is whitespace to a shell lexer by default, so the script asks for it as punctuation instead, and a backslash line continuation is folded back first so that one invocation split across lines stays one invocation. Two forms still hide the next command from the guard: a trailing `#` comment, which swallows the newline with it, and a separator glued to a subshell such as `;(`. When a line contains more than one `gh pr create`, the first one is the one that runs and the one that is judged.
- An `if` filter on the handler skips the script for commands that clearly have nothing to do with PRs. It is a best-effort prefilter that fails open, so the script repeats the check rather than trusting it.
- `--web` and `-w` are left alone: they hand the PR off to the browser form, where draft is chosen outside the hook's reach. `--help` and `--dry-run` are left alone because they do not open a PR.
- `--draft=false` counts as a non-draft PR and is denied, the same as passing no draft flag at all. Draft is recognized in the forms `gh` accepts, including `-d`, `-dt`, `-de`, `--draft=true`, and `--draft=t`.
- The hook fails open. A missing `python3`, an unparsable command, or malformed input all leave the command alone rather than blocking it.
- `hooks/pr-create-guard.test.sh` holds the decision table. Run it after changing the guard.
- To turn it off, remove the `pr-create-guard.sh` entry from `hooks.PreToolUse` in `.claude-plugin/plugin.json`, or set `"disableAllHooks": true` in your settings to disable every hook.

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
