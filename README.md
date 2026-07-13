# bash-helpers

Styleguide: https://google.github.io/styleguide/shellguide.html

## Claude Code files

Claude Code files are grouped by feature. Inside each feature, paths mirror the
user-level `~/.claude/` directory:

```text
ai/claude/
├── bash-scripting/
│   └── skills/
├── context7-advisor/
│   ├── hooks/
│   └── settings.local.json
├── red-green/
│   ├── skills/
│   └── workflows/
└── update-pr/
    └── commands/
```

Sync every feature into the user-level Claude Code directory:

```bash
# Preview changes
make sync-claude-dry-run

# Sync to ~/.claude/
make sync-claude
```

The sync rejects duplicate destination paths across features, updates managed
files, and does not delete unrelated files already in `~/.claude/`. To use
another destination, set `CLAUDE_DIR`:

```bash
make sync-claude CLAUDE_DIR=/path/to/claude-config
```


## Claude MCP tools

```bash
# Check if you have `npx` available
which npx

# Tivaly search tools
# https://www.tavily.com/
claude mcp add tavily-mcp -e TAVILY_API_KEY=tvly-dev-YOUR_API_KEY -s user -- npx -y tavily-mcp@latest

# Content7 documentation search
# https://github.com/upstash/context7
claude mcp add context7 -- npx -y @upstash/context7-mcp --api-key YOUR_API_KEY
```
