# dotfiles

Shell configuration plus a Claude Code plugin (`doarakko-config`) holding skills, agents, and hooks.

## Setup

```bash
mkdir -p ~/src && cd ~/src
git clone https://github.com/Doarakko/dotfiles.git
```

Add `source ~/src/dotfiles/.zshrc` to `~/.zshrc`, then run `aii`.

Keep `~/.zshrc` to machine-specific settings — PATH entries, version managers, tool shell integrations — plus that one `source` line. Never copy this repository's `.zshrc` into it; the copy goes stale and changes made here stop taking effect.

## AI toolchain

```bash
aii   # install
aiu   # update
```

Add or remove tools in these `.zshrc` arrays:

| Array | Channel |
| --- | --- |
| `AI_BREW_CASKS` | `brew --cask` |
| `AI_BREW_FORMULAE` | `brew` |
| `AI_NPM_PACKAGES` | `npm install -g` |
| `CLAUDE_MARKETPLACES` / `CLAUDE_PLUGINS` | `claude plugin` |

Restart Claude Code after `aiu`. It replaces plugins and can replace the `claude-code` cask itself, and a running session keeps the binary it started with.

npm packages land under the node version asdf selects, so re-run `aii` after switching node.

## Skills

All of them live in `skills/<name>/SKILL.md`.

### Workflows you start

| | |
| --- | --- |
| `/pr-create` | Branch, commit, open a draft PR, request Codex review, and Copilot review on organization-owned repositories |
| `/pr-fix` | Apply PR review comments and fix CI failures |
| `/pr-review` | Review a PR in detail |
| `/ci-fix` | Fix CI failures on the current branch's PR |
| `/review-diff` | Review uncommitted local changes |
| `/auto-review-mode` | Switch how far the Stop hook goes in this session — `off`, `review`, `fix`, or `auto`. User-invoked only |
| `/commit` | Commit and push — user-invoked only |

### Used while you work

Claude picks these up on its own when the task calls for them, and the workflows above invoke several of them.

| | |
| --- | --- |
| `e2e-check` | Drive Playwright CLI to verify behaviour and capture screenshots |
| `vulnerability-review` | Review code for vulnerabilities. Not named `security-review`, because that name resolves to Claude Code's built-in command when an agent preloads it. Reports only findings with a concrete attack path and lists the classes it deliberately leaves out (missing rate limiting, DoS, non-credential config values, and so on) |
| `silent-failure-review` | Find failures that are swallowed without anyone noticing — empty catches, unexplained fallbacks, defaults that hide an error — while respecting a project's documented reasons to swallow |
| `test-review` | Review test quality. Rates each missing or weak test 1–10 and reports 5 and above |
| `comment-review` | Check that comments still match the code and explain why rather than restate what |
| `coding-style-guide-review` | Check compliance with project conventions |
| `pr-compliance-review` | Check an implementation against the PR description and linked issues |
| `test-implementation` | Add tests in the same turn as the implementation |
| `docs-update` | Update documentation to match code changes |
| `decision-save` | Record a technical decision — options compared, what was chosen, and why — once it is settled. Writes into the repository's existing decision records — the location its docs name, `.adr-dir`, or a directory such as `docs/adr/` — following their numbering and template, and falls back to `docs/decisions/`. Commits the record on its own, leaving anything else you have staged out of it, and never pushes |
| `dependabot-setting` | Generate `.github/dependabot.yml` and pin mutable references |
| `project-setup` | Audit dependency automation, runtime pinning, and CI/CD — build, lint, test, deploy, and per-PR preview. Triggers on an unfamiliar project, a newly created repository, and the first push or PR in a repository |
| `review-followup` | Shared post-review confirmation flow — invoked by the review skills, not by you |
| `report-artifact` | Publish a review result as an HTML page on claude.ai |

## Agents

| | |
| --- | --- |
| `code-reviewer` | Review code, read-only. Loads the review skills above and reports only findings it rates at 80 or more out of 100 for confidence |
| `finding-verifier` | Try to disprove Critical and High findings against the cited code, read-only. Used by `/review-diff` and `/pr-review` |
| `codex-reviewer` | Second opinion from a different model via the codex CLI, read-only |
| `test-generator` | Generate tests for one file. `test-implementation` fans out to it for 3+ files |

Defined in `agents/`.

## Hooks

| Event | Behaviour |
| --- | --- |
| `PreToolUse` | Routes `gh pr create` through `/pr-create`, denying non-draft PRs (`hooks/pr-create-guard.sh`) |
| `PostToolUse` | Runs `make lint` after edits when the Makefile has that target |
| `Stop` | Reviews uncommitted changes before the turn ends, scoping every review after the first to the files that changed since the last one (`hooks/auto-review.sh`) |

Wired in `.claude-plugin/plugin.json`. The reviewed point is recorded per session under the temporary directory, never in git — your index and your partial staging stay untouched. Whenever that record cannot be trusted (first review of a session, a corrupted or missing record, a path that will not fit on one line, more changed files than `CLAUDE_AUTO_REVIEW_MAX_SCOPE_FILES`, default 40) the review falls back to the whole uncommitted diff rather than silently dropping anything. The decision tables live in `hooks/*.test.sh`, which `.github/workflows/test.yml` runs on pushes to master and on pull requests — read those for the exact behaviour. The same workflow runs `scripts/validate-definitions.sh`, which checks every skill and agent for a closed frontmatter block, for permission specifiers Claude Code accepts but never consults (`Write(path)`, `Glob(path)`, and friends — use `Edit(path)`), and for `doarakko-config:` references that point at nothing. Set `"disableAllHooks": true` in your settings to turn all hooks off, or remove the individual entry from `plugin.json`.

How far the `Stop` hook goes is decided per turn, in this order:

1. Permission mode `plan` — do nothing. Nothing is being edited, and a review request would only get in the way of the plan
2. Whatever `/auto-review-mode` wrote for this session
3. Otherwise the permission mode decides

| Permission mode | Default behaviour |
| --- | --- |
| `default` (shown as Manual) | Review only — findings are listed, nothing is edited |
| `acceptEdits` / `auto` / `dontAsk` / `bypassPermissions` | Review, then fix Critical and High findings in the same turn |
| An unknown value, or no value at all | Review and fix |

An unreadable setting is ignored rather than obeyed, and an unknown permission mode reviews and fixes rather than falling silent — staying quiet would leave unreviewed changes that nobody hears about again. A missing `permission_mode` lands in the same row so that a build which stops sending the field behaves exactly as this hook did before the setting existed. `off` and `plan` leave the reviewed point unrecorded, so whatever changed while the hook was held back is still waiting when you switch back.

The setting lives in `/tmp/claude/auto-review-mode/<session>` (`CLAUDE_AUTO_REVIEW_MODE_DIR` moves it, which is how the test suite keeps off the real one) and is scoped to one session — a new session always starts from the default, so you cannot forget that you turned it off. `/auto-review-mode` is user-invoked only: the hook exists to stop unreviewed changes from slipping through, so the side being reviewed does not get to switch it off.

Turning it `off` does not take reviewing away. `/review-diff` is a skill, not the hook, so it never reads the setting — it reviews the same points more deeply, and adds a lint run, an HTML page, and a prompt asking which findings to fix. What it does not inherit is the scoping: it always reads the whole uncommitted diff unless you name a path, and it leaves the reviewed point untouched, so ending a turn right after one sends the same diff through the hook a second time. Switch to `off` first when you want to drive the review yourself. For a pull request, `/pr-review` is the one to reach for.

## Manual review

`/review-diff` and `/pr-review` split `code-reviewer` into groups and start them in parallel, so one reviewer is not spread across every point at once. Which groups run depends on the kinds of files that changed.

| Group | Points | Runs when |
| --- | --- | --- |
| Safety | `security`, `errors` | Code changed — scripts, config, CI definitions, and Markdown that Claude Code runs (skill and agent definitions) count as code |
| Readability | `quality`, `comments`, `guidelines` | Always. A docs-only change gets `guidelines` alone |
| Tests | `test` | Code or tests changed |
| Requirements | `pr-compliance` | Always, `/pr-review` only |

`/review-diff` adds `codex-reviewer` alongside them. After the findings are merged, the Critical and High ones go to `finding-verifier` in one batch, and whatever it disproves with a cited `file:line` moves to a separate "refuted" list with the reason. Medium and Low are not verified — there are too many to be worth the cost — and are marked as such. If the verifier fails, nothing is dropped.

The `Stop` hook does none of this. It starts a single `code-reviewer` with every point, because it runs on every turn and the extra agents would multiply the cost of each one.

## External setup

None of this can be inferred from the code.

- **codex** — run `codex login`; without it every review fails with a 401. PR review additionally needs the repository registered at <https://chatgpt.com/codex/settings/code-review>. When codex is unusable the review falls back to Claude alone and pauses codex for 6 hours; `cat /tmp/claude/codex-review-cooldown` shows why. Signing in through `CODEX_API_KEY` / `CODEX_ACCESS_TOKEN` / `OPENAI_API_KEY` counts as signed in but leaves no `~/.codex/auth.json` to refresh, so `codex login` does not end that wait — delete the marker instead.
- **security-guidance** — installed by `aii` from the official marketplace. It warns on known-dangerous patterns as files are edited and reviews each `git commit` and `git push` in the background. `.zshrc` exports `ENABLE_STOP_REVIEW=0` to turn off its end-of-turn review, which would run at the same moment as this plugin's `Stop` hook. That reaches only sessions started from zsh — a session launched from an IDE extension or a GUI does not inherit it and runs both reviews; put `ENABLE_STOP_REVIEW` in the `env` of `~/.claude/settings.json` to cover those too. Its reviews call the newest Opus through your own API path, so they cost tokens on top of the session — on the Anthropic API they do not show in Claude Code's cost figures; `grep 'Review usage' ~/.claude/security/log.txt` shows the estimate. It needs Python 3.8 or newer, and on its first session it builds a virtualenv under `~/.claude/security/` for the commit reviewer. Set `SECURITY_GUIDANCE_DISABLE=1` to turn it off entirely.
- **claude-security** — installed by `aii` from the official marketplace. `/claude-security` runs a multi-agent vulnerability scan of the whole repository or of a diff inside the session, verifies every finding before reporting it, and can turn the confirmed findings into patch files. It is on-demand, not automatic: its hooks only print a banner, report usage after its own scripts, and suggest a scan after `git push` or `gh pr create`, so it does not overlap with this plugin's `Stop` hook. Each scan asks once to confirm its time and token cost, writes its report into a `CLAUDE-SECURITY-<timestamp>/` directory with its own `.gitignore`, and is not a substitute for `/vulnerability-review`, which is the cheaper diff-level check this plugin runs on every review.
- **gh** — 2.88.0 or newer to request `@copilot`, 2.99.0 or newer for `--attach` (E2E media on PRs). `--attach` exists only on `gh pr create`, not on `gh pr edit` or `gh pr comment`, so media cannot be added after the PR opens, and it cannot be combined with `--dry-run`.
- **Copilot review on personal repositories** — `/pr-create` requests `@copilot` only when `gh repo view --json isInOrganization` reports an organization-owned repository, and skips the request when the owner is a personal account or the check fails. A review is billed to the seat of the account that requested it, so on a company Copilot Business or Enterprise seat a personal-repository review spends the company's AI credits and leaves the repository and user name in its usage report.
- **Copilot review effort** — cannot be passed from the CLI. Set it per repository under Settings > Copilot > Code review > Review effort level, or enable a ruleset with "Automatically request Copilot code review".
- **Artifacts** — `/pr-review` and `/review-diff` publish their output as an HTML page on claude.ai through the built-in `Artifact` tool.

  Publishing needs a Pro, Max, Team, or Enterprise plan, a session signed in with `/login`, and the Anthropic API as the model provider. Bedrock, Vertex, and Foundry sessions cannot publish; neither can an organization with CMEK, HIPAA, or Zero Data Retention enabled; and on Enterprise an Owner has to enable artifacts for the organization. Where publishing is unavailable the skills keep the local HTML file under `/tmp/claude/report` and print the path instead.

  A published page is stored on Anthropic infrastructure, so review pages carry your diff — keep secrets out of them. The page is invisible to other members until you share it from its header, but not invisible to your organization: on Team and Enterprise, Owners can list and read artifact content through the Compliance API, and every publish, share, and delete lands in the org audit log as a `claude_artifact_*` event. The skills deliberately leave `Artifact` out of their `allowed-tools`, so a page asks before it is first published. That prompt is the only one you get: once you approve a page, later republishes of it go through without asking, and in auto mode a classifier approves even the first publish.

  Set `CLAUDE_CODE_ARTIFACT_AUTO_OPEN=0` to stop the browser opening on publish, `"enableArtifact": false` or `CLAUDE_CODE_DISABLE_ARTIFACT=1` to turn the whole thing off, or put `Artifact` in `permissions.deny`.
- **E2E in other repositories** — needs `Bash(playwright-cli *)` and `Bash(curl -s -o /dev/null *)` allowed there. `.claude/settings.json` here is this repository's own project settings and is not distributed with the plugin.

## Conventions

`AGENTS.md` is the single source for this repository's rules. `CLAUDE.md` imports it with `@AGENTS.md`, so edit `AGENTS.md` and leave `CLAUDE.md` alone.

Shell naming: `cc*` touches Claude Code alone, `ai*` touches the whole toolchain.
