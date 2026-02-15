# dotfiles

## Usage

```bash
mkdir -p ~/src
cd ~/src
git clone https://github.com/Doarakko/dotfiles.git
```

### Claude Code

#### Original Plugin

##### Install

```bash
claude plugin marketplace add ~/src/dotfiles
claude plugin install doarakko-config@doarakko-config
```

##### Update

```bash
claude-plugin-update
```

After install/update, restart Claude Code to apply changes.

#### LSP Plugin

```bash
claude plugin install gopls-lsp@claude-plugins-official
claude plugin install typescript-lsp@claude-plugins-official
claude plugin install pyright-lsp@claude-plugins-official
```

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
