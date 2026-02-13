# Project: Lobster

*Auto-updated by nightly consolidation. Last updated: 2026-02-13T03:00:00Z*

## Description

Always-on AI assistant built on Claude Code, processing messages from Telegram and other channels. Runs as a persistent session on a Debian cloud VM.

## Repository

https://github.com/SiderealPress/Lobster

## Status

Active development -- major milestone reached with sync epic completion.

## Key Components

- MCP inbox server (`src/mcp/inbox_server.py`)
- HTTP MCP bridge (`src/mcp/inbox_server_http.py`)
- Local bridge convenience tools (`src/mcp/lobster_bridge_local.py`)
- Memory system (`src/mcp/memory/`) -- SQLite + FTS5 + sqlite-vec event store
- Canonical memory (`memory/canonical/`) -- synthesized knowledge files
- Nightly consolidation pipeline (`scripts/nightly-consolidation.sh`)
- Canonical push script (`scripts/push-canonical.sh`)
- Telegram bot (`lobster_bot.py`)
- Reliability layer (`reliability.py`)
- Calendar integration (`calendar_integration.py`)
- Scheduled tasks system
- Brain dumps processing
- Self-update system with compatibility scanning
- Distributed git hooks with pre-push PII/security scanner

### macOS Components (new)
- lobster-sync daemon (`macos/lobster-sync`) -- zero-disruption git backup using `write-tree`/`commit-tree`
- launchd plist (`macos/com.lobster.sync.plist`)
- Installer/uninstaller scripts (`macos/install-lobster-local.sh`, `macos/uninstall-lobster-local.sh`)
- Sync config (`config/sync-repos.json`)

## Recent Work

### Sync Epic (#30) -- COMPLETED 2026-02-13
All 5 layers merged to main (~6,437 lines, 153 tests):
- **Layer 1** (PR #40): lobster-sync core script -- zero-disruption git plumbing
- **Layer 2** (PR #41): Nightly consolidation pipeline + canonical memory
- **Layer 3** (PR #43): Bridge convenience tools (get_priorities, get_project_context, etc.)
- **Layer 4** (PR #44): macOS integration (launchd, CLI wrapper, installer)
- **Layer 5** (PR #45): VPS-side integration (sync awareness, canonical push)

### Previous Work
- Three-layer memory system (PR #26) -- SQLite + FTS5 + sqlite-vec
- HTTP MCP bridge (PR #32) -- remote Claude Code access
- Self-update system with compatibility scanning (PR #29)
- Distributed git hooks with pre-push PII/security scanner (PR #28)
- Reliability improvements (atomic writes, circuit breakers)
- Google Calendar integration
- Headless browser fetch capability
- Slack integration

## Next Steps

- Monitor nightly consolidation quality and refine prompts
- Automate canonical push after consolidation
- Close epic issues #30 and #25 on GitHub
- Phase 2 memory: add vector embeddings (Ollama + nomic-embed-text)
- Expand messaging channels (SMS/Signal)

## Blockers

*No current blockers.*
