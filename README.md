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

- [serena](https://github.com/oraios/serena)
- Gemini
- Playwright
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
- Visual Studio Code

## development

- docker-compose
- Docker Desktop for Mac
- Git
- Go
- Homebrew
- Postman
- Claude Code
- gh
