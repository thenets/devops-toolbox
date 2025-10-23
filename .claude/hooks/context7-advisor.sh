#!/bin/bash
# Context7 Advisor Hook for Claude Code
# Suggests using Context7 MCP for technical documentation during Spec Kit commands and technical issues

# Read JSON input from stdin
INPUT=$(cat)

# Parse the hook event and relevant fields
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // empty')
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')

# Function to return JSON with additional context
suggest_context7() {
    local suggestion=$1
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "$HOOK_EVENT",
    "additionalContext": "$suggestion"
  }
}
EOF
    exit 0
}

# Handle PreToolUse events (detect SlashCommand usage)
if [ "$HOOK_EVENT" = "PreToolUse" ] && [ "$TOOL_NAME" = "SlashCommand" ]; then
    # Extract the command from tool_input
    COMMAND=$(echo "$TOOL_INPUT" | jq -r '.command // empty')

    # Check if it's a Spec Kit command
    if echo "$COMMAND" | grep -qE "^/(plan|tasks|task|implement|specify|clarify|analyze)"; then
        CMD_NAME=$(echo "$COMMAND" | sed 's|^/\([a-z]*\).*|\1|')
        suggest_context7 "📚 Spec Kit Command Detected: /$CMD_NAME

Consider consulting Context7 MCP for technical documentation:
• Use mcp__context7__resolve-library-id to find relevant libraries/frameworks
• Use mcp__context7__get-library-docs to get implementation examples and best practices

This can help ensure your $CMD_NAME aligns with current library versions and patterns."
    fi
fi

# Handle UserPromptSubmit events (detect technical keywords)
if [ "$HOOK_EVENT" = "UserPromptSubmit" ] && [ -n "$PROMPT" ]; then
    # Convert prompt to lowercase for case-insensitive matching
    PROMPT_LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

    # Technical issue keywords
    if echo "$PROMPT_LOWER" | grep -qE "(error|issue|problem|bug|fail|broken|not working|doesn't work|how to|how do i|implementation|configure|setup)"; then
        # Check for library/framework mentions
        if echo "$PROMPT_LOWER" | grep -qE "(fastapi|pydantic|sqlmodel|asyncio|pytest|websocket|redis|postgres|docker|kubernetes|react|typescript|python|javascript|async|await)"; then
            # Extract potential library name (first matching keyword)
            LIBRARY=$(echo "$PROMPT_LOWER" | grep -oE "(fastapi|pydantic|sqlmodel|asyncio|pytest|websocket|redis|postgres|docker|kubernetes|react|typescript|python|javascript)" | head -1)

            suggest_context7 "💡 Technical Issue Detected

You mentioned '$LIBRARY' with what appears to be a technical challenge.

Consider using Context7 MCP for up-to-date documentation:
1. Resolve library ID: mcp__context7__resolve-library-id with libraryName='$LIBRARY'
2. Get documentation: mcp__context7__get-library-docs with the resolved ID
3. Focus on specific topics using the 'topic' parameter

This can provide current best practices, examples, and solutions for common issues."
        else
            # Generic technical issue without specific library
            suggest_context7 "💡 Technical Challenge Detected

Consider using Context7 MCP to consult relevant documentation:
• Identify the library/framework involved
• Use mcp__context7__resolve-library-id to find the right documentation
• Use mcp__context7__get-library-docs to get specific guidance

This can help you find solutions faster with current, accurate information."
        fi
    fi

    # Check for "implement" or "create" with library mentions (proactive suggestion)
    if echo "$PROMPT_LOWER" | grep -qE "(implement|create|build|add|setup|configure)"; then
        if echo "$PROMPT_LOWER" | grep -qE "(api|endpoint|websocket|database|authentication|authorization|test|service|client|server)"; then
            suggest_context7 "🔧 Implementation Task Detected

Before implementing, consider consulting Context7 MCP for:
• Current best practices and patterns
• Working code examples
• Common pitfalls to avoid

Use mcp__context7__resolve-library-id and mcp__context7__get-library-docs to access comprehensive, up-to-date documentation."
        fi
    fi
fi

# Default: allow operation without additional context
exit 0
