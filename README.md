# dotfiles

## Usage

```bash
mkdir -p ~/src
cd ~/src
git clone https://github.com/Doarakko/dotfiles.git
cd dotfiles
```

### Claude Code

#### Plugin

##### Install

```bash
claude plugin marketplace add ~/src/dotfiles
claude plugin install doarakko-config@doarakko-config
```

##### Update

```bash
claude plugin marketplace update && claude plugin uninstall doarakko-config@doarakko-config && claude plugin install doarakko-config@doarakko-config
```

After install/update, restart Claude Code to apply changes.

### MCP Server

- Figma
- [Chrome DevTools](https://github.com/ChromeDevTools/chrome-devtools-mcp)
- [context7](https://github.com/upstash/context7)

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
