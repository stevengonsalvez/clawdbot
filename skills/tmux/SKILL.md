---
name: tmux
description: Remote-control tmux sessions for interactive CLIs by sending keystrokes and scraping pane output.
metadata:
  { "openclaw": { "emoji": "🧵", "os": ["darwin", "linux"], "requires": { "bins": ["tmux"] } } }
---

# tmux Session Control

Control tmux sessions by sending keystrokes and reading output. Essential for managing Claude Code sessions.

## When to Use

✅ **USE this skill when:**

- Monitoring Claude/Codex sessions in tmux
- Sending input to interactive terminal applications
- Scraping output from long-running processes in tmux
- Navigating tmux panes/windows programmatically
- Checking on background work in existing sessions

## When NOT to Use

❌ **DON'T use this skill when:**

- Running one-off shell commands → use `exec` tool directly
- Starting new background processes → use `exec` with `background:true`
- Non-interactive scripts → use `exec` tool
- The process isn't in tmux
- You need to create a new tmux session → use `exec` with `tmux new-session`

## Example Sessions

| Session                 | Purpose                     |
| ----------------------- | --------------------------- |
| `shared`                | Primary interactive session |
| `worker-2` - `worker-8` | Parallel worker sessions    |

## Common Commands

### List Sessions

```bash
tmux list-sessions
tmux ls
```

### Capture Output

```bash
# Last 20 lines of pane
tmux capture-pane -t shared -p | tail -20

# Entire scrollback
tmux capture-pane -t shared -p -S -

# Specific pane in window
tmux capture-pane -t shared:0.0 -p
```

### Send Keys

```bash
# Send text (doesn't press Enter)
tmux send-keys -t shared "hello"

# Send text + Enter
tmux send-keys -t shared "y" Enter

# Send special keys
tmux send-keys -t shared Enter
tmux send-keys -t shared Escape
tmux send-keys -t shared C-c          # Ctrl+C
tmux send-keys -t shared C-d          # Ctrl+D (EOF)
tmux send-keys -t shared C-z          # Ctrl+Z (suspend)
```

### Window/Pane Navigation

```bash
# Select window
tmux select-window -t shared:0

# Select pane
tmux select-pane -t shared:0.1

# List windows
tmux list-windows -t shared
```

### Session Management

```bash
# Create new session
tmux new-session -d -s newsession

# Kill session
tmux kill-session -t sessionname

# Rename session
tmux rename-session -t old new
```

## Sending Input Safely

For interactive TUIs (Claude Code, Codex, etc.), split text and Enter into separate sends to avoid paste/multiline edge cases:

```bash
tmux send-keys -t shared -l -- "Please apply the patch in src/foo.ts"
sleep 0.1
tmux send-keys -t shared Enter
```

## Claude Code Session Patterns

### Check if Session Needs Input

```bash
# Look for prompts
tmux capture-pane -t worker-3 -p | tail -10 | grep -E "❯|Yes.*No|proceed|permission"
```

### Approve Claude Code Prompt

```bash
# Send 'y' and Enter
tmux send-keys -t worker-3 'y' Enter

# Or select numbered option
tmux send-keys -t worker-3 '2' Enter
```

### Check All Sessions Status

```bash
for s in shared worker-2 worker-3 worker-4 worker-5 worker-6 worker-7 worker-8; do
  echo "=== $s ==="
  tmux capture-pane -t $s -p 2>/dev/null | tail -5
done
```

### Send Task to Session

```bash
tmux send-keys -t worker-4 "Fix the bug in auth.js" Enter
```

---

## Session Naming Convention (Recommended)

Use a consistent naming pattern so sessions are self-documenting and parseable:

```
{tool}-{scope}-{id}[-{desc}]
```

| Segment | Values                                       | Example         |
| ------- | -------------------------------------------- | --------------- |
| `tool`  | `cc` (Claude Code), `codex`, `pi`            | `cc`            |
| `scope` | `issue`, `fix`, `pr`, `feature`, `task`      | `issue`         |
| `id`    | Issue number, PR number, or short identifier | `174`           |
| `desc`  | Optional short slug                          | `auth-refactor` |

**Examples:** `cc-issue-174-auth-refactor`, `codex-fix-1520`, `cc-pr-186`

---

## Steering Protocol

### Monitor (every 2–3 min while session is active)

```bash
tmux capture-pane -t "${SESSION}" -p | tail -50
```

| Signal                      | Action                     |
| --------------------------- | -------------------------- |
| Model is generating code    | Let it work                |
| "I'll now..." planning text | Verify approach is correct |
| Error/stack trace repeating | Intervene (steer)          |
| Idle / waiting for input    | Check if stuck or done     |
| "I've completed..." summary | Move to verify phase       |
| Session has exited          | Check output / PR status   |

### Steer (when intervention is needed)

```bash
# Correct course
tmux send-keys -t "${SESSION}" \
  "STOP. You're going the wrong direction. <specific correction>" Enter

# Unstick
tmux send-keys -t "${SESSION}" \
  "You seem stuck. Try: <specific suggestion>" Enter

# Add context
tmux send-keys -t "${SESSION}" \
  "Additional context: <file path, pattern, constraint>" Enter

# Abort
tmux send-keys -t "${SESSION}" "/exit" Enter
```

### Steering Rules

1. **Be specific.** "Fix the types" is bad. "Change `costTotal` to `v.optional(v.float64())`" is good.
2. **Don't over-steer.** Interruptions reset context. If on track, let it work.
3. **One correction at a time.** Multiple simultaneous corrections confuse the model.
4. **Stuck 3+ times on same issue?** Kill session, rethink approach, respawn with better prompt.

---

## Completion Detection

Look for these patterns in `capture-pane` output:

```bash
OUTPUT=$(tmux capture-pane -t "$SESSION" -p | tail -30)

# Completion signals
echo "$OUTPUT" | grep -qE "I've completed|changes have been|PR.*created|committed.*pushed" && echo "DONE"

# Error signals
echo "$OUTPUT" | grep -qE "Error:|FATAL|panic|OOM|killed|context.*exhausted" && echo "ERROR"

# Stuck signals (same error 3+ times)
echo "$OUTPUT" | sort | uniq -c | sort -rn | head -1 | awk '$1 >= 3 {print "STUCK"}'
```

---

## Full Lifecycle: Spawn → Monitor → Steer → Verify → Cleanup

```bash
ISSUE=174; DESC="auth-refactor"; WORKTREE=/tmp/worktree-${ISSUE}

# 1. Worktree
git fetch origin main
git worktree add -b "feat/issue-${ISSUE}" "$WORKTREE" origin/main

# 2. Spawn
tmux new-session -d -s "cc-issue-${ISSUE}-${DESC}" -c "$WORKTREE" \
  'claude --dangerously-skip-permissions'
tmux send-keys -t "cc-issue-${ISSUE}-${DESC}" \
  "<task with full context>" Enter

# 3. Monitor
tmux capture-pane -t "cc-issue-${ISSUE}-${DESC}" -p | tail -50

# 4. Verify
gh pr list --head "feat/issue-${ISSUE}"

# 5. Cleanup
git worktree remove "$WORKTREE" --force
tmux kill-session -t "cc-issue-${ISSUE}-${DESC}" 2>/dev/null
```

---

## Session Health Check

Periodically check for stale sessions:

```bash
for s in $(tmux list-sessions -F '#{session_name}' 2>/dev/null); do
  LAST_ACTIVITY=$(tmux display -t "$s" -p '#{session_activity}')
  IDLE_SECS=$(( $(date +%s) - LAST_ACTIVITY ))
  if [ $IDLE_SECS -gt 3600 ]; then
    echo "⚠️ $s idle for ${IDLE_SECS}s — consider cleanup"
  fi
done
```

---

## OpenClaw Enhancement (optional — activates when running inside OpenClaw)

> These features only apply when running as an OpenClaw agent (detected via `~/.openclaw/` or agent workspace). Skip this section if using tmux standalone.

### Inbox Linkage

Link tmux sessions to inbox items using `lib/tmux-inbox.sh`:

```bash
source ~/d/git/mission-control/lib/tmux-inbox.sh

# Start: creates tmux session + records state
tmux_inbox_start "$INBOX_ID" "claude-code" "my-task" "$WORKTREE" "$ISSUE_NUM"

# Check: captures output, detects completion/errors
tmux_inbox_check "$INBOX_ID" "$AGENT_WORKSPACE"

# Complete: marks inbox done, records result
tmux_inbox_complete "$INBOX_ID" "$AGENT_WORKSPACE" "PR #188 created"

# Cleanup: kills session + removes worktree
tmux_inbox_cleanup "$INBOX_ID" "$AGENT_WORKSPACE"
```

### Dashboard Integration

The `sync-tmux.ts` cron (every 5 min) parses session names → extracts issue refs → syncs to the mission-control dashboard. **Session name is the contract** — name it wrong, it won't link.

### Heartbeat Health Check

On heartbeat, use the `tmux-monitor` skill to auto-check session health and report stale/stuck sessions via inbox.

---

## Notes

- Use `capture-pane -p` to print to stdout (essential for scripting)
- `-S -` captures entire scrollback history
- Target format: `session:window.pane` (e.g., `shared:0.0`)
- Sessions persist across SSH disconnects
