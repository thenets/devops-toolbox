# Adversary review → validation panel

This document is a **pointer**. Steps 6–8 (CLI gate, optional Grok, evaluation
ledger, consensus-gap remediation) live in:

**[validation-panel.md](validation-panel.md)**

The runner script is still named `scripts/run_adversary_review.sh` (dual Opus+GPT
by default; `--with-grok` when the bug is complex). Use that path from the skill
body and worksheet; do not maintain a second copy of the rules here.
