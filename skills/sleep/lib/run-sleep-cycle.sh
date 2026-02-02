#!/usr/bin/env bash
# Run Sleep Cycle - Main Orchestrator
# Runs all sleep phases and generates the final report

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Parse arguments
WORKSPACE="${1:-$HOME/d/popabot}"
AGENT_ID="${2:-main}"
DRY_RUN="${3:-false}"
SKIP_DEEP="${4:-false}"
SKIP_IMPROVE="${5:-false}"
STALE_DAYS="${6:-60}"
DAYS_BACK="${7:-7}"

# Expand workspace
WORKSPACE=$(eval echo "$WORKSPACE")

# Output directories
REPORT_DIR="$WORKSPACE/memory/sleep-reports"
mkdir -p "$REPORT_DIR"

# Temp files
TIMESTAMP=$(date +"%Y-%m-%d")
TIME_FULL=$(date +"%H:%M:%S %Z")
SHALLOW_RESULTS="/tmp/shallow-sleep-$$.json"
DEEP_RESULTS="/tmp/deep-sleep-$$.json"
IMPROVE_RESULTS="/tmp/self-improve-$$.json"
REPORT_FILE="$REPORT_DIR/$TIMESTAMP.md"

# Cleanup on exit
cleanup() {
  rm -f "$SHALLOW_RESULTS" "$DEEP_RESULTS" "$IMPROVE_RESULTS"
}
trap cleanup EXIT

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}           ${BLUE}🌙 SLEEP CYCLE — Cognitive Maintenance${NC}           ${CYAN}║${NC}"
echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║${NC} Workspace: $WORKSPACE"
echo -e "${CYAN}║${NC} Agent:     $AGENT_ID"
echo -e "${CYAN}║${NC} Dry Run:   $DRY_RUN"
echo -e "${CYAN}║${NC} Report:    $REPORT_FILE"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

START_TIME=$(date +%s)

# =============================================================================
# PHASE 1: SHALLOW SLEEP
# =============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}PHASE 1: Shallow Sleep (System Health)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

bash "$SCRIPT_DIR/shallow-sleep.sh" "$SHALLOW_RESULTS" 2>&1 | sed 's/^/  /'

echo ""

# =============================================================================
# PHASE 2: DEEP SLEEP
# =============================================================================
if [ "$SKIP_DEEP" != "true" ]; then
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}PHASE 2: Deep Sleep (Memory Consolidation)${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  
  bash "$SCRIPT_DIR/deep-sleep.sh" "$WORKSPACE" "$STALE_DAYS" "$DRY_RUN" "$DEEP_RESULTS" 2>&1 | sed 's/^/  /'
  
  echo ""
else
  echo -e "${YELLOW}⏭  Skipping deep sleep phase${NC}"
  echo '{"skipped": true}' > "$DEEP_RESULTS"
fi

# =============================================================================
# PHASE 3: SELF-IMPROVEMENT
# =============================================================================
if [ "$SKIP_IMPROVE" != "true" ]; then
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}PHASE 3: Self-Improvement (Learning Extraction)${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  
  bash "$SCRIPT_DIR/self-improve.sh" "$WORKSPACE" "$AGENT_ID" "$DAYS_BACK" "$IMPROVE_RESULTS" 2>&1 | sed 's/^/  /'
  
  echo ""
else
  echo -e "${YELLOW}⏭  Skipping self-improvement phase${NC}"
  echo '{"skipped": true}' > "$IMPROVE_RESULTS"
fi

# =============================================================================
# PHASE 4: GENERATE REPORT
# =============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}PHASE 4: Generate Report${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Build the report
cat > "$REPORT_FILE" << EOF
# Sleep Report — $TIMESTAMP

> 🌙 Cognitive maintenance cycle completed at $TIME_FULL

---

## System Health (Shallow Sleep)

EOF

# Add shallow sleep results
if [ -f "$SHALLOW_RESULTS" ]; then
  CONFIG_VALID=$(jq -r '.config.valid // "unknown"' "$SHALLOW_RESULTS")
  WA_STATUS=$(jq -r '.integrations.whatsapp // "not_configured"' "$SHALLOW_RESULTS")
  TG_STATUS=$(jq -r '.integrations.telegram // "not_configured"' "$SHALLOW_RESULTS")
  DC_STATUS=$(jq -r '.integrations.discord // "not_configured"' "$SHALLOW_RESULTS")
  ANOMALY=$(jq -r '.anomalies.detected // false' "$SHALLOW_RESULTS")
  ERROR_COUNT=$(jq -r '.anomalies.error_count // 0' "$SHALLOW_RESULTS")
  ACTIVE=$(jq -r '.sessions.active // 0' "$SHALLOW_RESULTS")
  STALE=$(jq -r '.sessions.stale // 0' "$SHALLOW_RESULTS")
  TEMP_CLEANED=$(jq -r '.cleanup.temp_cleaned // 0' "$SHALLOW_RESULTS")
  MEDIA_ARCHIVED=$(jq -r '.cleanup.media_archived // 0' "$SHALLOW_RESULTS")
  
  cat >> "$REPORT_FILE" << EOF
| Check | Status | Details |
|-------|--------|---------|
| Config | $([ "$CONFIG_VALID" = "true" ] && echo "✅" || echo "⚠️") | Valid: $CONFIG_VALID |
| WhatsApp | $([ "$WA_STATUS" = "connected" ] && echo "✅" || echo "⚠️") | $WA_STATUS |
| Telegram | $([ "$TG_STATUS" = "connected" ] && echo "✅" || echo "⚠️") | $TG_STATUS |
| Discord | $([ "$DC_STATUS" = "connected" ] && echo "✅" || echo "⚠️") | $DC_STATUS |
| Anomalies | $([ "$ANOMALY" = "false" ] && echo "✅" || echo "⚠️") | Errors (24h): $ERROR_COUNT |
| Sessions | ✅ | Active: $ACTIVE, Stale: $STALE |
| Cleanup | ✅ | Temp: $TEMP_CLEANED, Media archived: $MEDIA_ARCHIVED |

EOF
fi

# Add deep sleep results
cat >> "$REPORT_FILE" << EOF
---

## Memory Consolidation (Deep Sleep)

EOF

if [ -f "$DEEP_RESULTS" ] && [ "$(jq -r '.skipped // false' "$DEEP_RESULTS")" != "true" ]; then
  FILE_COUNT=$(jq -r '.scan.files_found // 0' "$DEEP_RESULTS")
  TOTAL_SIZE=$(jq -r '.scan.total_size_kb // 0' "$DEEP_RESULTS")
  LARGE_COUNT=$(jq -r '.scan.large_files | length' "$DEEP_RESULTS")
  STALE_COUNT=$(jq -r '.scan.stale_files | length' "$DEEP_RESULTS")
  
  cat >> "$REPORT_FILE" << EOF
- **Files scanned**: $FILE_COUNT
- **Total size**: ${TOTAL_SIZE}KB
- **Large files**: $LARGE_COUNT
- **Stale files**: $STALE_COUNT

### Large Files (>10KB)
EOF
  
  jq -r '.scan.large_files[] | "- \(.file) (\(.size))"' "$DEEP_RESULTS" >> "$REPORT_FILE" 2>/dev/null || echo "- (none)" >> "$REPORT_FILE"
  
  echo "" >> "$REPORT_FILE"
  echo "### Stale Files (>$STALE_DAYS days)" >> "$REPORT_FILE"
  jq -r '.scan.stale_files[] | "- \(.file) (modified: \(.modified))"' "$DEEP_RESULTS" >> "$REPORT_FILE" 2>/dev/null || echo "- (none)" >> "$REPORT_FILE"
  
else
  echo "*Skipped*" >> "$REPORT_FILE"
fi

# Add self-improvement results
cat >> "$REPORT_FILE" << EOF

---

## Self-Improvement

EOF

if [ -f "$IMPROVE_RESULTS" ] && [ "$(jq -r '.skipped // false' "$IMPROVE_RESULTS")" != "true" ]; then
  SESSIONS_ANALYZED=$(jq -r '.sessions_analyzed // 0' "$IMPROVE_RESULTS")
  CORRECTIONS_COUNT=$(jq -r '.corrections | length' "$IMPROVE_RESULTS")
  PREFS_COUNT=$(jq -r '.preferences | length' "$IMPROVE_RESULTS")
  
  cat >> "$REPORT_FILE" << EOF
- **Sessions analyzed**: $SESSIONS_ANALYZED (last $DAYS_BACK days)
- **Corrections found**: $CORRECTIONS_COUNT
- **Preferences extracted**: $PREFS_COUNT

### Corrections Found
EOF
  
  jq -r '.corrections[:5][] | "- **\(.pattern)** in \(.session): \"\(.context | .[0:100])...\""' "$IMPROVE_RESULTS" >> "$REPORT_FILE" 2>/dev/null || echo "- (none)" >> "$REPORT_FILE"
  
  echo "" >> "$REPORT_FILE"
  echo "### Preferences Extracted" >> "$REPORT_FILE"
  jq -r '.preferences[:5][] | "- **\(.pattern)**: \"\(.context | .[0:100])...\""' "$IMPROVE_RESULTS" >> "$REPORT_FILE" 2>/dev/null || echo "- (none)" >> "$REPORT_FILE"
  
else
  echo "*Skipped*" >> "$REPORT_FILE"
fi

# Add recommendations and footer
cat >> "$REPORT_FILE" << EOF

---

## Recommendations

EOF

# Generate recommendations based on findings
if [ -f "$SHALLOW_RESULTS" ]; then
  ERROR_COUNT=$(jq -r '.anomalies.error_count // 0' "$SHALLOW_RESULTS")
  if [ "$ERROR_COUNT" -gt 50 ]; then
    echo "- ⚠️ **High error rate detected** ($ERROR_COUNT errors in 24h) - investigate logs" >> "$REPORT_FILE"
  fi
  
  STALE_SESSIONS=$(jq -r '.sessions.stale // 0' "$SHALLOW_RESULTS")
  if [ "$STALE_SESSIONS" -gt 5 ]; then
    echo "- 🧹 Consider archiving $STALE_SESSIONS stale sessions" >> "$REPORT_FILE"
  fi
fi

if [ -f "$DEEP_RESULTS" ]; then
  LARGE_COUNT=$(jq -r '.scan.large_files | length' "$DEEP_RESULTS")
  if [ "$LARGE_COUNT" -gt 0 ]; then
    echo "- 📝 Review $LARGE_COUNT large memory files for compression opportunities" >> "$REPORT_FILE"
  fi
fi

if [ -f "$IMPROVE_RESULTS" ]; then
  CORRECTIONS=$(jq -r '.corrections | length' "$IMPROVE_RESULTS")
  if [ "$CORRECTIONS" -gt 0 ]; then
    echo "- 📚 Review $CORRECTIONS corrections and add learnings to TOOLS.md/MEMORY.md" >> "$REPORT_FILE"
  fi
fi

echo "" >> "$REPORT_FILE"
echo "---" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "*Generated by Sleep & Improve Skill v1.0*" >> "$REPORT_FILE"
echo "*Sleep cycle duration: ${DURATION}s*" >> "$REPORT_FILE"

# =============================================================================
# COMPLETION
# =============================================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}           ${GREEN}✓ SLEEP CYCLE COMPLETE${NC}                            ${GREEN}║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC} Duration: ${DURATION}s"
echo -e "${GREEN}║${NC} Report:   $REPORT_FILE"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Output the report path for callers
echo "REPORT_FILE=$REPORT_FILE"
