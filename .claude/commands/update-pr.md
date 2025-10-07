---
description: Update the current branch's PR description based on file changes
---

Update the PR description for the current branch by:

1. Get the current PR details using `gh pr view --json number,title,body,files,commits`
2. Get the file changes diff using `gh pr diff`
3. Analyze the file changes and commits to understand what was changed and why
4. Generate a comprehensive PR description that includes:
   - Clear description of what changed and why
   - Only the applicable type of change checkboxes (checked) - remove others
   - List of specific changes made
   - Only applicable testing checklist items (checked) - remove others
   - Local verification instructions
   - Only applicable code quality checklist items (checked) - remove others
5. Update the PR description using `gh pr edit --body "$(cat <<'EOF'\n<description>\nEOF\n)"`
6. Preserve the existing `<!-- CHANGED_FILES:START -->` to `<!-- CHANGED_FILES:END -->` section if present

**IMPORTANT**: Never mention AI assistance in the PR description. Use neutral language like "automated changes" or direct technical descriptions.
