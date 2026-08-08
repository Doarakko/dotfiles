# dotfiles

## Usage

```bash
mkdir -p ~/src
cd ~/src
git clone https://github.com/Doarakko/dotfiles.git
```

Add `source ~/src/dotfiles/.zshrc` to your `~/.zshrc` to load the configuration.

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
