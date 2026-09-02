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
- A `PreToolUse` hook (`hooks/pr-create-guard.sh`) catches `gh pr create` as a backstop. Hooks cannot start a skill themselves, so the hook works on the command instead: it denies a PR that is not a draft and asks for the workflow to be followed, and lets a draft through with a reminder attached as context. Denying only the non-draft form is what keeps the hook from blocking `/pr-zero` itself, since step 8 of the workflow always passes `--draft`.
- The hook splits the command into real shell tokens (`hooks/pr-create-guard.py`, using `shlex`) rather than matching text. Quoting rules are too intricate for a regex, and three earlier regex versions each let a different quoting form through. Tokenizing collapses a quoted string into a single token, so a `gh pr create` written inside one is never mistaken for the command, and a `-d` sitting in a PR title or heredoc body is never mistaken for a flag.
- Symbols produced inside a command substitution are not read as flags. A shell expands `$(echo --web)` into one word the flag parser never sees as `--web`, but the lexer hands the text back token by token, so the guard skips everything between the parens. Without that, a substitution whose text happened to contain `--web` or `-w` made a non-draft PR look exempt and slip through — a hole that predates the media work and is covered by the decision table now.
- Only the flags belonging to that one invocation are read. Anything after `;`, `&&`, `||`, `|`, `&`, or a newline belongs to the next command, so `gh pr create --fill && docker run -d nginx` is still denied, and so is a `gh pr create` whose next line happens to carry a `-d` or `-w`. A newline is whitespace to a shell lexer by default, so the script asks for it as punctuation instead, and a backslash line continuation is folded back first so that one invocation split across lines stays one invocation. One form still hides the next command from the guard: a separator glued to a subshell such as `;(`. A trailing `#` comment used to hide one too, since the lexer read `#` as the start of a comment and swallowed the newline with it. Comments are now cut out before the lexer runs, by a pass that tracks quoting and only treats `#` as a comment where a word can begin, so an unquoted `--attach shot.png#login error` keeps its argument while a real comment still ends at the newline. It tracks quoting, backslash escapes and a stack of open parens, so an escaped space keeps its word together and a `)` that closes `$(...)`, `<(...)` or `>(...)` stays inside the word while one that closes a subshell begins a new one — which is what bash does, checked against it case by case. When that pass leaves something the lexer cannot read, the command is parsed again with the lexer's own comment handling rather than waved through. When a line contains more than one `gh pr create`, the first one is the one that runs and the one that is judged.
- An `if` filter on the handler skips the script for commands that clearly have nothing to do with PRs. It is a best-effort prefilter that fails open, so the script repeats the check rather than trusting it.
- `--web` and `-w` are left alone: they hand the PR off to the browser form, where draft is chosen outside the hook's reach. `--help` and `--dry-run` are left alone because they do not open a PR.
- `--draft=false` counts as a non-draft PR and is denied, the same as passing no draft flag at all. Draft is recognized in the forms `gh` accepts, including `-d`, `-dt`, `-de`, `--draft=true`, and `--draft=t`.
- The hook fails open. A missing `python3`, an unparsable command, or malformed input all leave the command alone rather than blocking it.
- A draft PR is denied once more when this branch has E2E media waiting and the command carries no `--attach`, so evidence that was captured does not get left behind. Only media the workflow could actually attach counts — PNG and WebM under the size limit — because denying over something that cannot be attached would deny every retry. The check is skipped for the same reason when `gh` is older than 2.99.0.
- `hooks/pr-create-guard.test.sh` holds the decision table. Run it after changing the guard. The attachment cases need `gh` 2.99.0 or newer and are skipped below that.
- To turn it off, remove the `pr-create-guard.sh` entry from `hooks.PreToolUse` in `.claude-plugin/plugin.json`, or set `"disableAllHooks": true` in your settings to disable every hook.

#### E2E capture

`/pr-zero` captures what a change looks like and attaches it to the PR. Step 5 of the workflow looks at the changed files, and only when something that reaches the screen changed does it check that the app answers and hand off to `doarakko-config:e2e-check`, which drives Playwright and leaves screenshots and a short video behind. Step 7 embeds them in the body and step 8 uploads them with `--attach`.

- `--attach` needs `gh` 2.99.0 or newer (`brew upgrade gh`). Below that the PR is still created, without the media, and the workflow says so.
- In 2.99.0 the flag exists on `gh pr create` alone, not on `gh pr edit` or `gh pr comment`, so media cannot be added to a PR after it opens. The release note lists the other commands, but the installed CLI does not carry the flag there.
- When some uploads succeed and others fail, the PR is created with the ones that made it and `gh` exits non-zero while still printing the PR URL. The workflow treats a printed URL as created and does not open a second PR.
- `--attach` is rejected alongside `--dry-run`, so a dry run cannot preview the upload. Check the command's shape without the attachments, or open the draft PR and look at it.
- Media lands in `/tmp/claude/e2e/<repo>/<branch>`, which `CLAUDE_E2E_OUTPUT_ROOT` moves. The path is fixed rather than under `$TMPDIR` because the guard hook and the sandboxed Bash tool see different values for `$TMPDIR`, the same reason `auto-review.sh` keeps its cooldown marker at a fixed path.
- `playwright-cli` resolves a relative `--filename` against the directory the command ran in, so the skill always passes an absolute path. `PLAYWRIGHT_MCP_OUTPUT_DIR` looks like it should decide this, but it is only consulted when no filename is given, and a relative name would drop the media straight into the working tree.
- Files are named `NN-what-it-shows.png` and `NN-what-it-shows.webm`. The leading number orders them in the body and the rest, without the extension, becomes the alt text an image is embedded with, so the naming is the record and nothing has to be kept in sync alongside it. Video renders as a player and carries no alt text.
- Anything the upload would reject on size is dropped first. GitHub's limit is 10 MB, and the workflow keeps just under it so the guard never asks for a file the upload step would skip. GitHub allows 100 MB of video on paid plans, but there is no way to tell which plan a repository is on, so the lower limit is the one that applies. Video is always WebM, which GitHub plays.
- Claude never starts the app. If nothing answers on the URL, capture is skipped and the PR is created anyway.
- Running this in another repository needs `Bash(playwright-cli *)` and `Bash(curl -s -o /dev/null *)` allowed there. `.claude/settings.json` here is this repository's own project settings and is not distributed with the plugin, so adding them here does nothing for the repositories where E2E actually runs. The skill's `allowed-tools` covers the turn it is invoked in, which is what carries across projects.
- If the reachability check fails with a permission error rather than a connection error, the sandbox is in the way: allow `localhost` and `127.0.0.1` in that repository's `sandbox.network.allowedDomains`, or use `/sandbox`.
- The PR body is written to `/tmp/claude/pr-body/<repo>-<branch>.md`, under the same fixed root and for the same reasons: `$TMPDIR` resolves differently for different callers, and a single fixed name would be fought over by two workflows running at once.
- Media outlives the run it came from, so step 5 empties the directory when it decides not to capture. When stale media does reach the guard, the denial says the directory can be cleared instead of attached.
- To turn capture off, leave the app down or skip step 5 of the workflow.

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
