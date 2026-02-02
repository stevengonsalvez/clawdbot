#!/usr/bin/env bash
# Shallow Sleep - System Health Checks
# Quick checks that don't require heavy processing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Optional common utilities (not required)
[ -f "${SCRIPT_DIR}/common.sh" ] && source "${SCRIPT_DIR}/common.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Output file for results
RESULTS_FILE="${1:-/tmp/shallow-sleep-results.json}"

echo -e "${BLUE}🌙 Starting Shallow Sleep (System Health)${NC}"
echo ""

# Initialize results
cat > "$RESULTS_FILE" << 'EOF'
{
  "timestamp": "",
  "config": { "valid": null, "issues": [] },
  "integrations": {},
  "updates": { "available": false, "details": "" },
  "anomalies": { "detected": false, "error_count": 0, "details": [] },
  "sessions": { "active": 0, "stale": 0, "details": [] },
  "cleanup": { "temp_cleaned": 0, "media_archived": 0 }
}
EOF

# Update timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jq --arg ts "$TIMESTAMP" '.timestamp = $ts' "$RESULTS_FILE" > "${RESULTS_FILE}.tmp" && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"

# -----------------------------------------------------------------------------
# 1. Config Validation
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[1/6]${NC} Checking configuration..."

if command -v moltbot &> /dev/null; then
  GATEWAY_STATUS=$(moltbot status --json 2>/dev/null | jq -r '.gateway.status // "unknown"' 2>/dev/null || echo "error")
  
  if [ "$GATEWAY_STATUS" = "running" ]; then
    echo -e "  ${GREEN}✓${NC} Gateway running, config valid"
    jq '.config.valid = true' "$RESULTS_FILE" > "${RESULTS_FILE}.tmp" && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"
  else
    echo -e "  ${YELLOW}⚠${NC} Gateway status: $GATEWAY_STATUS"
    jq --arg s "$GATEWAY_STATUS" '.config.valid = false | .config.issues += ["Gateway status: " + $s]' "$RESULTS_FILE" > "${RESULTS_FILE}.tmp" && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"
  fi
else
  echo -e "  ${YELLOW}⚠${NC} moltbot command not found"
  jq '.config.valid = false | .config.issues += ["moltbot not in PATH"]' "$RESULTS_FILE" > "${RESULTS_FILE}.tmp" && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"
fi

# -----------------------------------------------------------------------------
# 2. Integration Health
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[2/6]${NC} Checking integrations..."

if command -v moltbot &> /dev/null; then
  STATUS_JSON=$(moltbot status --json 2>/dev/null || echo '{}')
  
  # WhatsApp
  WA_STATUS=$(echo "$STATUS_JSON" | jq -r '.channels.whatsapp.status // "not_configured"' 2>/dev/null)
  echo -e "  WhatsApp: $WA_STATUS"
  jq --arg s "$WA_STATUS" '.integrations.whatsapp = $s' "$RESULTS_FILE" > "${RESULTS_FILE}.tmp" && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"
  
  # Telegram
  TG_STATUS=$(echo "$STATUS_JSON" | jq -r '.channels.telegram.status // "not_configured"' 2>/dev/null)
  echo -e "  Telegram: $TG_STATUS"
  jq --arg s "$TG_STATUS" '.integrations.telegram = $s' "$RESULTS_FILE" > "${RESULTS_FILE}.tmp" && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"
  
  # Discord
  DC_STATUS=$(echo "$STATUS_JSON" | jq -r '.channels.discord.status // "not_configured"' 2>/dev/null)
  echo -e "  Discord: $DC_STATUS"
  jq --arg s "$DC_STATUS" '.integrations.discord = $s' "$RESULTS_FILE" > "${RESULTS_FILE}.tmp" && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"
fi

# -----------------------------------------------------------------------------
# 3. Update Check
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[3/6]${NC} Checking for updates..."

if command -v moltbot &> /dev/null; then
  CURRENT_VERSION=$(moltbot --version 2>/dev/null | head -1 || echo "unknown")
  echo -e "  Current: $CURRENT_VERSION"
  jq --arg v "$CURRENT_VERSION" '.updates.details = "Current version: " + $v' "$RESULTS_FILE" > "${RESULTS_FILE}.tmp" && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"
fi

# -----------------------------------------------------------------------------
# 4. Log Anomaly Detection
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[4/6]${NC} Scanning logs for anomalies..."

LOG_DIR="$HOME/.clawdbot/logs"
ERROR_COUNT=0

if [ -d "$LOG_DIR" ]; then
  # Count errors in last 24 hours
  ERROR_COUNT=$(find "$LOG_DIR" -name "*.log" -mtime -1 -exec grep -c -i "error" {} + 2>/dev/null | awk -F: '{sum+=$2} END {print sum+0}')
  
  echo -e "  Errors in last 24h: $ERROR_COUNT"
  
  if [ "$ERROR_COUNT" -gt 50 ]; then
    echo -e "  ${YELLOW}⚠${NC} High error rate detected"
    jq --argjson c "$ERROR_COUNT" '.anomalies.detected = true | .anomalies.error_count = $c | .anomalies.details += ["High error rate: " + ($c | tostring) + " errors in 24h"]' "$RESULTS_FILE" > "${RESULTS_FILE}.tmp" && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"
  else
    echo -e "  ${GREEN}✓${NC} Error rate normal"
    jq --argjson c "$ERROR_COUNT" '.anomalies.error_count = $c' "$RESULTS_FILE" > "${RESULTS_FILE}.tmp" && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"
  fi
else
  echo -e "  ${YELLOW}ℹ${NC} Log directory not found"
fi

# -----------------------------------------------------------------------------
# 5. Session Health
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[5/6]${NC} Checking session health..."

SESSIONS_DIR="$HOME/.clawdbot/agents"
ACTIVE_SESSIONS=0
STALE_SESSIONS=0

if [ -d "$SESSIONS_DIR" ]; then
  # Count session files modified in last hour (active)
  ACTIVE_SESSIONS=$(find "$SESSIONS_DIR" -name "*.jsonl" -mmin -60 2>/dev/null | wc -l | tr -d ' ')
  
  # Count session files not modified in 7+ days (stale)
  STALE_SESSIONS=$(find "$SESSIONS_DIR" -name "*.jsonl" -mtime +7 2>/dev/null | wc -l | tr -d ' ')
  
  echo -e "  Active sessions (last hour): $ACTIVE_SESSIONS"
  echo -e "  Stale sessions (>7 days): $STALE_SESSIONS"
  
  jq --argjson a "$ACTIVE_SESSIONS" --argjson s "$STALE_SESSIONS" '.sessions.active = $a | .sessions.stale = $s' "$RESULTS_FILE" > "${RESULTS_FILE}.tmp" && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"
fi

# -----------------------------------------------------------------------------
# 6. Resource Cleanup
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[6/6]${NC} Cleaning up resources..."

TEMP_CLEANED=0
MEDIA_ARCHIVED=0

# Clean old temp files (>7 days) - TTS artifacts etc
OLD_TEMPS=$(find /tmp -maxdepth 2 \( -name "tts-*" -o -name "voice-*.mp3" -o -name "voice-*.ogg" \) -mtime +7 2>/dev/null | wc -l | tr -d ' ')
if [ "$OLD_TEMPS" -gt 0 ]; then
  find /tmp -maxdepth 2 \( -name "tts-*" -o -name "voice-*.mp3" -o -name "voice-*.ogg" \) -mtime +7 -delete 2>/dev/null || true
  TEMP_CLEANED=$OLD_TEMPS
  echo -e "  Cleaned $TEMP_CLEANED old temp files"
fi

# Archive old inbound media (>30 days)
MEDIA_DIR="$HOME/.clawdbot/media/inbound"
if [ -d "$MEDIA_DIR" ]; then
  OLD_MEDIA=$(find "$MEDIA_DIR" -type f -mtime +30 2>/dev/null | wc -l | tr -d ' ')
  
  if [ "$OLD_MEDIA" -gt 0 ]; then
    ARCHIVE_DIR="$HOME/.clawdbot/media/archive/$(date +%Y-%m)"
    mkdir -p "$ARCHIVE_DIR"
    find "$MEDIA_DIR" -type f -mtime +30 -exec mv {} "$ARCHIVE_DIR/" \; 2>/dev/null || true
    MEDIA_ARCHIVED=$OLD_MEDIA
    echo -e "  Archived $MEDIA_ARCHIVED old media files"
  fi
fi

jq --argjson t "$TEMP_CLEANED" --argjson m "$MEDIA_ARCHIVED" '.cleanup.temp_cleaned = $t | .cleanup.media_archived = $m' "$RESULTS_FILE" > "${RESULTS_FILE}.tmp" && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo -e "${GREEN}✓ Shallow sleep complete${NC}"
echo -e "  Results saved to: $RESULTS_FILE"

# Output summary
cat "$RESULTS_FILE" | jq '.'
