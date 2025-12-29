# About Me

- Name: YK
- GitHub: ykdojo
- Current year: 2025

# Behavior

When I paste large content with no instructions, just summarize it.

# Safety

**NEVER use `--dangerously-skip-permissions` on the host machine.**

For risky operations, use a Docker container. Inside containers, YOLO mode and `--dangerously-skip-permissions` are fine.

Run `npx cc-safe <directory>` to scan Claude Code settings for security issues.

## Containers

| Container | Purpose |
|-----------|---------|
| `peaceful_lovelace` | Main container for risky operations (has `gh` CLI installed) |
| `eager_moser` | Secondary/backup |
| `delfina` | Daft CI/GitHub Actions flaky test debugging |

For `gh` API calls, use the container: `docker exec peaceful_lovelace gh api <endpoint>`

## Tmux

For interactive Gemini or Claude Code sessions:

```bash
tmux new-session -d -s <name> '<command>'
tmux send-keys -t <name> '<input>' Enter  # don't forget Enter!
tmux capture-pane -t <name> -p
```

Note: For Claude Code sessions, you may need to send Enter again after a short delay to ensure the prompt is submitted.

## Long-running Jobs

If you need to wait for a long-running job, use sleep commands with manual exponential backoff: wait 1 minute, then 2 minutes, then 4 minutes, and so on.

# GitHub

Use `gh` CLI for GitHub URLs (PRs, issues, etc.) since WebFetch often fails with 404/auth errors.

# Python

Use Python 3.12 whenever Python 3 or Python is needed.

# Browser Automation

**ALWAYS use DOM-based interaction. NEVER use coordinates.**

- Use `read_page` to get element refs
- Use `find` to locate elements by description
- Click/interact using `ref` parameter - NEVER coordinates
- Screenshots only for visual context, not for finding click targets