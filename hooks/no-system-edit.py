#!/usr/bin/env python3
"""Block edits to system files (CLAUDE.md, hooks, services, src/).

Four-tier architecture:
  Tier 1 (System): repo root — CLAUDE.md, src/, hooks/, services/ — read-only, git-managed
  Tier 2 (User config): user/ — gitignored, editable
  Tier 3 (Secrets): ~/lobster-config/ — external, editable
  Tier 4 (Workspace): lobster-workspace/ — gitignored, CWD for CC, fully writable

CWD for Claude Code sessions is lobster-workspace/, so:
  - CLAUDE.md is found by walking UP from lobster-workspace/ → repo root
  - .claude/agents/ at CWD = lobster-workspace/.claude/agents/ (user agents, writable)
  - ~/.claude/agents/ = system agents (installed there by install.sh)

This hook protects Tier 1 paths only.
"""
import json, sys

# Paths that are read-only at runtime (Tier 1 — system layer)
PROTECTED_PATTERNS = [
    "/lobster/CLAUDE.md",
    "/lobster/hooks/",
    "/lobster/.githooks/",
    "/lobster/services/",
    "/lobster/src/",
]

# Paths that are explicitly allowed (override any protected pattern matches)
# lobster-workspace/ is the runtime CWD and is fully writable.
ALLOWED_PREFIXES = [
    "/lobster/lobster-workspace/",
]


def is_allowed(path: str) -> bool:
    return any(path.startswith(p) or p in path for p in ALLOWED_PREFIXES)


def is_protected(path: str) -> bool:
    return any(pattern in path for pattern in PROTECTED_PATTERNS)


def main():
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)

    tool_input = data.get("tool_input", {})
    file_path = tool_input.get("file_path", "")

    # Check Write/Edit targets
    if file_path:
        if not is_allowed(file_path) and is_protected(file_path):
            print(json.dumps({
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": (
                        f"Cannot edit system file: {file_path}. "
                        "System files (CLAUDE.md, hooks/, services/, src/) are read-only "
                        "and git-managed. "
                        "For user agents, edit lobster-workspace/.claude/agents/*.agent.md. "
                        "For personal context, edit user/agents/base.agent.md."
                    ),
                }
            }))
            sys.exit(0)

    # Check Bash commands targeting system files
    command = tool_input.get("command", "")
    if command:
        # Only block write operations, not reads
        write_ops = ["rm ", "mv ", "cp ", "> ", ">> ", "tee ", "sed -i", "chmod ", "chown "]
        if any(op in command for op in write_ops):
            if not is_allowed(command) and is_protected(command):
                print(json.dumps({
                    "hookSpecificOutput": {
                        "hookEventName": "PreToolUse",
                        "permissionDecision": "deny",
                        "permissionDecisionReason": (
                            "Cannot modify system files via bash. "
                            "System files (CLAUDE.md, hooks/, services/, src/) are "
                            "read-only and git-managed."
                        ),
                    }
                }))
                sys.exit(0)

    sys.exit(0)


if __name__ == "__main__":
    main()
