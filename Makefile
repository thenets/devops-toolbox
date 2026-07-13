ROOT_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
CLAUDE_SOURCE := $(ROOT_DIR)ai/claude/
CLAUDE_DIR ?= $(HOME)/.claude
RSYNC ?= rsync
RSYNC_FLAGS := --archive --itemize-changes --exclude=.DS_Store

.PHONY: help sync-claude sync-claude-dry-run check-rsync check-claude-features

help:
	@echo "Available targets:"
	@echo "  sync-claude          Sync ai/claude/ into $(CLAUDE_DIR)/"
	@echo "  sync-claude-dry-run  Preview the files that would be synced"

check-rsync:
	@command -v "$(RSYNC)" >/dev/null 2>&1 || { \
		echo "Error: rsync is required but was not found." >&2; \
		exit 1; \
	}

check-claude-features:
	@duplicates=$$(cd "$(CLAUDE_SOURCE)" && \
		find . -mindepth 2 \( -type f -o -type l \) ! -name .DS_Store | \
		sed 's|^\./[^/]*/||' | LC_ALL=C sort | uniq -d); \
	if [ -n "$$duplicates" ]; then \
		echo "Error: multiple Claude features provide the same destination path:" >&2; \
		echo "$$duplicates" >&2; \
		exit 1; \
	fi

sync-claude: check-rsync check-claude-features
	@mkdir -p "$(CLAUDE_DIR)"
	@set -e; \
	find "$(CLAUDE_SOURCE)" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort | \
	while IFS= read -r feature; do \
		echo "Syncing $${feature##*/}"; \
		$(RSYNC) $(RSYNC_FLAGS) "$$feature/" "$(CLAUDE_DIR)/"; \
	done

sync-claude-dry-run: check-rsync check-claude-features
	@mkdir -p "$(CLAUDE_DIR)"
	@set -e; \
	find "$(CLAUDE_SOURCE)" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort | \
	while IFS= read -r feature; do \
		echo "Previewing $${feature##*/}"; \
		$(RSYNC) $(RSYNC_FLAGS) --dry-run "$$feature/" "$(CLAUDE_DIR)/"; \
	done
