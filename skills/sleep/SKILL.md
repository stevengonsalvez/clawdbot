---
name: sleep
description: Cognitive maintenance cycle for agents. Runs during inactivity to perform system health checks, memory consolidation, and self-improvement. Produces a sleep report with proposed changes.
homepage: https://github.com/moltbot/moltbot
metadata: {"moltbot":{"emoji":"🌙","requires":{"bins":["jq"],"env":[]}}}
---

# Sleep & Improve Skill

Scheduled cognitive maintenance that runs during user inactivity to maintain and improve agent health.

## When to Use

- **Automatic**: Cron triggers during sleep window (default 03:00-06:00)
- **Manual**: User requests sleep cycle or system maintenance
- **Keywords**: "run sleep cycle", "cognitive maintenance", "memory consolidation"

## Phases

### 1. Shallow Sleep (System Health)
Quick system checks that don't require heavy processing:
- Config validation against schema
- Integration health (channel connections, API keys)
- Update availability check (report only)
- Log anomaly detection (error spikes, failures)
- Session health (stuck/orphaned sessions)
- Resource cleanup (temp files, old media)

### 2. Deep Sleep (Memory Consolidation)
Memory file analysis and optimization:
- Scan `memory/*.md` for verbose/redundant/stale entries
- Compress verbose entries into concise facts
- Deduplicate near-identical entries
- Flag stale entries (>30-60 days, no recent refs)
- Promote recurring patterns to `MEMORY.md` core
- Extract forgotten todos from session transcripts

### 3. Self-Improvement (Learning Loop)
Extract learnings from recent interactions:
- Mine user corrections ("no, do X not Y")
- Identify success patterns (what worked well)
- Extract implicit preferences not yet recorded
- Propose SOUL.md/TOOLS.md additions
- Feed to reflect skill for permanent encoding

## Usage

### Via OpenProse (recommended)
```bash
prose run ~/d/git/clawdbot/skills/sleep/sleep-cycle.prose
```

### Via Cron (automatic)
```json
{
  "name": "sleep-cycle",
  "schedule": {"kind": "cron", "expr": "0 3 * * *", "tz": "Europe/London"},
  "payload": {"kind": "agentTurn", "message": "Run sleep cycle - it's the scheduled maintenance window"},
  "sessionTarget": "isolated"
}
```

### Manual Trigger
Just ask: "Run a sleep cycle" or "Do cognitive maintenance"

## Configuration

Environment variables (optional):
- `SLEEP_WINDOW_START`: Start hour (default: 3)
- `SLEEP_WINDOW_END`: End hour (default: 6)
- `SLEEP_STALE_DAYS`: Days before memory is considered stale (default: 60)
- `SLEEP_DRY_RUN`: Set to "true" to preview without changes

## Output

Sleep reports are saved to: `memory/sleep-reports/YYYY-MM-DD.md`

Reports include:
- System health status
- Memory consolidation summary
- Extracted learnings
- Proposed changes (require user approval)
- Recommendations

## Safety Rails

- **Never auto-delete**: All deletions require user approval
- **Never auto-update**: Updates are reported, not applied
- **Never modify SOUL.md directly**: Proposals only
- **Dry-run available**: Preview all changes first
- **Rate limited**: Max 1 deep sleep per 24 hours

## Files

| File | Purpose |
|------|---------|
| `sleep-cycle.prose` | Main orchestration workflow |
| `lib/shallow-sleep.sh` | System health checks |
| `lib/deep-sleep.sh` | Memory consolidation |
| `lib/self-improve.sh` | Learning extraction |
| `lib/memory-utils.sh` | Memory file utilities |
| `templates/sleep-report.md` | Report template |
