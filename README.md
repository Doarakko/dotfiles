# dotfiles

Shell configuration plus a Claude Code plugin (`doarakko-config`) holding commands, skills, agents, and hooks.

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

## Commands

| | |
| --- | --- |
| `/pr-create` | Branch, commit, open a draft PR, request Copilot and Codex review |
| `/pr-fix` | Apply PR review comments and fix CI failures |
| `/pr-review` | Review a PR in detail |
| `/ci-fix` | Fix CI failures on the current branch's PR |
| `/review-diff` | Review uncommitted local changes |
| `/test-create` | Generate tests for changed files |
| `/commit` | Commit and push — user-invoked only |
| `/decision-save` | Write the session's technical decisions to a file |
| `/plan-view` | Publish a plan file as an HTML page you can open in a browser |

Defined in `commands/`.

## Skills

| | |
| --- | --- |
| `e2e-check` | Drive Playwright CLI to verify behaviour and capture screenshots |
| `security-review` | Review code for vulnerabilities |
| `test-review` | Review test quality |
| `coding-style-guide-review` | Check compliance with project conventions |
| `pr-compliance-review` | Check an implementation against the PR description and linked issues |
| `docs-update` | Update documentation to match code changes |
| `dependabot-setting` | Generate `.github/dependabot.yml` |
| `project-setup` | Audit dependency automation and CI/CD on an unfamiliar project |
| `review-followup` | Shared post-review confirmation flow — invoked by the review commands, not by you |
| `report-artifact` | Publish a review result or a plan as an HTML page on claude.ai |

Defined in `skills/<name>/SKILL.md`.

## Agents

| | |
| --- | --- |
| `code-reviewer` | Review code, read-only. Loads the review skills above |
| `codex-reviewer` | Second opinion from a different model via the codex CLI, read-only |
| `test-generator` | Generate tests from source |

Defined in `agents/`.

## Hooks

| Event | Behaviour |
| --- | --- |
| `PreToolUse` | Routes `gh pr create` through `/pr-create`, denying non-draft PRs (`hooks/pr-create-guard.sh`) |
| `PostToolUse` | Runs `make lint` after edits when the Makefile has that target |
| `Stop` | Reviews uncommitted changes before the turn ends (`hooks/auto-review.sh`) |

Wired in `.claude-plugin/plugin.json`. The decision tables live in `hooks/*.test.sh`, which `.github/workflows/test.yml` runs on pushes to master and on pull requests — read those for the exact behaviour. The same workflow runs `scripts/validate-definitions.sh`, which checks every command, skill, and agent for a closed frontmatter block, for permission specifiers Claude Code accepts but never consults (`Write(path)`, `Glob(path)`, and friends — use `Edit(path)`), and for `doarakko-config:` references that point at nothing. Set `"disableAllHooks": true` in your settings to turn all hooks off, or remove the individual entry from `plugin.json`.

## External setup

None of this can be inferred from the code.

- **codex** — run `codex login`; without it every review fails with a 401. PR review additionally needs the repository registered at <https://chatgpt.com/codex/settings/code-review>. When codex is unusable the review falls back to Claude alone and pauses codex for 6 hours; `cat /tmp/claude/codex-review-cooldown` shows why. Signing in through `CODEX_API_KEY` / `CODEX_ACCESS_TOKEN` / `OPENAI_API_KEY` counts as signed in but leaves no `~/.codex/auth.json` to refresh, so `codex login` does not end that wait — delete the marker instead.
- **codex under the Bash sandbox** — `sandbox.filesystem.allowWrite` must include `~/.codex` and `sandbox.network.allowedDomains` must include `chatgpt.com` and `*.openai.com`. Without the write grant codex dies at startup with `failed to initialize in-process app-server client: Operation not permitted`, before it ever checks credentials. `.claude/settings.json` here carries both, but it is this repository's own project settings and is not distributed with the plugin.
- **gh** — 2.88.0 or newer to request `@copilot`, 2.99.0 or newer for `--attach` (E2E media on PRs). `--attach` exists only on `gh pr create`, not on `gh pr edit` or `gh pr comment`, so media cannot be added after the PR opens, and it cannot be combined with `--dry-run`.
- **Copilot review effort** — cannot be passed from the CLI. Set it per repository under Settings > Copilot > Code review > Review effort level, or enable a ruleset with "Automatically request Copilot code review".
- **Artifacts** — `/pr-review`, `/review-diff`, and `/plan-view` publish their output as an HTML page on claude.ai through the built-in `Artifact` tool.

  Publishing needs a Pro, Max, Team, or Enterprise plan, a session signed in with `/login`, and the Anthropic API as the model provider. Bedrock, Vertex, and Foundry sessions cannot publish; neither can an organization with CMEK, HIPAA, or Zero Data Retention enabled; and on Enterprise an Owner has to enable artifacts for the organization. Where publishing is unavailable the commands keep the local HTML file under `/tmp/claude/report` and print the path instead.

  A published page is stored on Anthropic infrastructure, so review pages carry your diff — keep secrets out of them. The page is invisible to other members until you share it from its header, but not invisible to your organization: on Team and Enterprise, Owners can list and read artifact content through the Compliance API, and every publish, share, and delete lands in the org audit log as a `claude_artifact_*` event. The commands deliberately leave `Artifact` out of their `allowed-tools`, so a page asks before it is first published. That prompt is the only one you get: once you approve a page, later republishes of it go through without asking, and in auto mode a classifier approves even the first publish.

  Set `CLAUDE_CODE_ARTIFACT_AUTO_OPEN=0` to stop the browser opening on publish, `"enableArtifact": false` or `CLAUDE_CODE_DISABLE_ARTIFACT=1` to turn the whole thing off, or put `Artifact` in `permissions.deny`.
- **E2E in other repositories** — needs `Bash(playwright-cli *)` and `Bash(curl -s -o /dev/null *)` allowed there. `.claude/settings.json` here is this repository's own project settings and is not distributed with the plugin.

## Conventions

`AGENTS.md` is the single source for this repository's rules. `CLAUDE.md` imports it with `@AGENTS.md`, so edit `AGENTS.md` and leave `CLAUDE.md` alone.

Shell naming: `cc*` touches Claude Code alone, `ai*` touches the whole toolchain.

## development

- docker-compose
- Docker Desktop for Mac
- Git
- Homebrew
- Postman
- Visual Studio Code
- Claude Code
- Codex
- gh
- [Playwright CLI](https://github.com/microsoft/playwright-cli)
- cmux
