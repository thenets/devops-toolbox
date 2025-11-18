# bash-helpers

Styleguide: https://google.github.io/styleguide/shellguide.html


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
