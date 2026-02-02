#!/usr/bin/env bash
# Self-Improve - Learning Extraction
# Mine session transcripts for corrections and preferences

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Inputs
WORKSPACE="${1:-$HOME/d/popabot}"
AGENT_ID="${2:-main}"
DAYS_BACK="${3:-7}"
RESULTS_FILE="${4:-/tmp/self-improve-results.json}"

echo -e "${BLUE}🚀 Starting Self-Improvement (Learning Extraction)${NC}"
echo ""
echo "Workspace: $WORKSPACE"
echo "Agent: $AGENT_ID"
echo "Looking back: $DAYS_BACK days"
echo ""

# Expand paths
WORKSPACE=$(eval echo "$WORKSPACE")
SESSIONS_DIR="$HOME/.clawdbot/agents/$AGENT_ID/sessions"

# Initialize results
cat > "$RESULTS_FILE" << 'EOF'
{
  "timestamp": "",
  "agent": "",
  "sessions_analyzed": 0,
  "corrections": [],
  "preferences": [],
  "success_patterns": [],
  "proposals": {
    "tools_md": [],
    "soul_md": [],
    "memory": []
  }
}
EOF

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jq --arg ts "$TIMESTAMP" --arg a "$AGENT_ID" '.timestamp = $ts | .agent = $a' "$RESULTS_FILE" > "${RESULTS_FILE}.tmp" && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"

# -----------------------------------------------------------------------------
# 1. Find Recent Session Transcripts
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[1/4]${NC} Finding recent sessions..."

if [ ! -d "$SESSIONS_DIR" ]; then
  echo -e "  ${YELLOW}ℹ${NC} Sessions directory not found: $SESSIONS_DIR"
  exit 0
fi

# Find session files modified in the last N days
RECENT_SESSIONS=$(find "$SESSIONS_DIR" -name "*.jsonl" -mtime -$DAYS_BACK -type f 2>/dev/null || true)
SESSION_COUNT=$(echo "$RECENT_SESSIONS" | grep -c "." || echo "0")

echo -e "  Found $SESSION_COUNT recent sessions"
jq --argjson c "$SESSION_COUNT" '.sessions_analyzed = $c' "$RESULTS_FILE" > "${RESULTS_FILE}.tmp" && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"

if [ "$SESSION_COUNT" -eq 0 ]; then
  echo -e "  ${YELLOW}ℹ${NC} No recent sessions to analyze"
  exit 0
fi

# -----------------------------------------------------------------------------
# 2. Mine for Corrections
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[2/4]${NC} Mining for user corrections..."

TEMP_CORRECTIONS="/tmp/corrections-$$"
> "$TEMP_CORRECTIONS"

# Patterns that indicate corrections
CORRECTION_PATTERNS=(
  "no,.*instead"
  "no,.*not"
  "that's wrong"
  "that's not right"
  "I said"
  "I meant"
  "I told you"
  "use.*instead"
  "don't.*use"
  "wrong"
  "incorrect"
  "fix"
  "actually"
)

while IFS= read -r session_file; do
  [ -z "$session_file" ] && continue
  
  SESSION_NAME=$(basename "$session_file" .jsonl)
  
  # Extract user messages and look for correction patterns
  for pattern in "${CORRECTION_PATTERNS[@]}"; do
    # Look in user messages for correction indicators
    MATCHES=$(jq -r 'select(.role == "user") | .content // ""' "$session_file" 2>/dev/null | grep -i "$pattern" || true)
    
    if [ -n "$MATCHES" ]; then
      echo "$SESSION_NAME|$pattern|$MATCHES" >> "$TEMP_CORRECTIONS"
    fi
  done
done <<< "$RECENT_SESSIONS"

CORRECTION_COUNT=$(wc -l < "$TEMP_CORRECTIONS" | tr -d ' ')

if [ "$CORRECTION_COUNT" -gt 0 ]; then
  echo -e "  ${YELLOW}Found $CORRECTION_COUNT potential corrections${NC}"
  
  # Add top corrections to results (limit to 10)
  head -10 "$TEMP_CORRECTIONS" | while IFS='|' read -r session pattern match; do
    # Truncate match for JSON
    MATCH_SHORT=$(echo "$match" | head -c 200)
    jq --arg s "$session" --arg p "$pattern" --arg m "$MATCH_SHORT" \
      '.corrections += [{"session": $s, "pattern": $p, "context": $m}]' \
      "$RESULTS_FILE" > "${RESULTS_FILE}.tmp" && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"
  done
else
  echo -e "  ${GREEN}✓${NC} No corrections found"
fi

rm -f "$TEMP_CORRECTIONS"

# -----------------------------------------------------------------------------
# 3. Extract Preferences
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[3/4]${NC} Extracting implicit preferences..."

TEMP_PREFS="/tmp/preferences-$$"
> "$TEMP_PREFS"

# Patterns that indicate preferences
PREF_PATTERNS=(
  "I prefer"
  "I like"
  "I want"
  "I always"
  "I never"
  "please.*always"
  "please.*don't"
  "make sure"
  "remember to"
  "from now on"
)

while IFS= read -r session_file; do
  [ -z "$session_file" ] && continue
  
  SESSION_NAME=$(basename "$session_file" .jsonl)
  
  for pattern in "${PREF_PATTERNS[@]}"; do
    MATCHES=$(jq -r 'select(.role == "user") | .content // ""' "$session_file" 2>/dev/null | grep -i "$pattern" || true)
    
    if [ -n "$MATCHES" ]; then
      echo "$SESSION_NAME|$pattern|$MATCHES" >> "$TEMP_PREFS"
    fi
  done
done <<< "$RECENT_SESSIONS"

PREF_COUNT=$(wc -l < "$TEMP_PREFS" | tr -d ' ')

if [ "$PREF_COUNT" -gt 0 ]; then
  echo -e "  ${YELLOW}Found $PREF_COUNT potential preferences${NC}"
  
  head -10 "$TEMP_PREFS" | while IFS='|' read -r session pattern match; do
    MATCH_SHORT=$(echo "$match" | head -c 200)
    jq --arg s "$session" --arg p "$pattern" --arg m "$MATCH_SHORT" \
      '.preferences += [{"session": $s, "pattern": $p, "context": $m}]' \
      "$RESULTS_FILE" > "${RESULTS_FILE}.tmp" && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"
  done
else
  echo -e "  ${GREEN}✓${NC} No new preferences found"
fi

rm -f "$TEMP_PREFS"

# -----------------------------------------------------------------------------
# 4. Identify Success Patterns
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[4/4]${NC} Identifying success patterns..."

# Look for positive feedback indicators
SUCCESS_PATTERNS=(
  "perfect"
  "great"
  "thanks"
  "awesome"
  "exactly"
  "that's right"
  "works"
  "love it"
  "nice"
)

TEMP_SUCCESS="/tmp/success-$$"
> "$TEMP_SUCCESS"

while IFS= read -r session_file; do
  [ -z "$session_file" ] && continue
  
  SESSION_NAME=$(basename "$session_file" .jsonl)
  
  for pattern in "${SUCCESS_PATTERNS[@]}"; do
    # Count positive feedback
    COUNT=$(jq -r 'select(.role == "user") | .content // ""' "$session_file" 2>/dev/null | grep -ci "$pattern" || echo "0")
    
    if [ "$COUNT" -gt 0 ]; then
      echo "$SESSION_NAME|$pattern|$COUNT" >> "$TEMP_SUCCESS"
    fi
  done
done <<< "$RECENT_SESSIONS"

SUCCESS_COUNT=$(wc -l < "$TEMP_SUCCESS" | tr -d ' ')

if [ "$SUCCESS_COUNT" -gt 0 ]; then
  echo -e "  ${GREEN}Found positive feedback in sessions${NC}"
  
  # Aggregate by pattern
  sort -t'|' -k2 "$TEMP_SUCCESS" | head -5 | while IFS='|' read -r session pattern count; do
    jq --arg p "$pattern" --argjson c "$count" \
      '.success_patterns += [{"indicator": $p, "occurrences": $c}]' \
      "$RESULTS_FILE" > "${RESULTS_FILE}.tmp" && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"
  done
fi

rm -f "$TEMP_SUCCESS"

# -----------------------------------------------------------------------------
# Generate Proposals
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}Generating proposals...${NC}"

# Based on corrections, suggest TOOLS.md additions
CORRECTION_COUNT=$(jq '.corrections | length' "$RESULTS_FILE")
if [ "$CORRECTION_COUNT" -gt 0 ]; then
  jq '.proposals.tools_md += ["Review corrections and add tool usage notes to prevent recurrence"]' "$RESULTS_FILE" > "${RESULTS_FILE}.tmp" && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"
fi

# Based on preferences, suggest MEMORY additions
PREF_COUNT=$(jq '.preferences | length' "$RESULTS_FILE")
if [ "$PREF_COUNT" -gt 0 ]; then
  jq '.proposals.memory += ["Review preferences and add to MEMORY.md core facts"]' "$RESULTS_FILE" > "${RESULTS_FILE}.tmp" && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo -e "${GREEN}✓ Self-improvement analysis complete${NC}"
echo ""
echo "Summary:"
echo "  - Sessions analyzed: $(jq '.sessions_analyzed' "$RESULTS_FILE")"
echo "  - Corrections found: $(jq '.corrections | length' "$RESULTS_FILE")"
echo "  - Preferences found: $(jq '.preferences | length' "$RESULTS_FILE")"
echo "  - Success patterns: $(jq '.success_patterns | length' "$RESULTS_FILE")"
echo ""
echo -e "  Results saved to: $RESULTS_FILE"

cat "$RESULTS_FILE" | jq '.'
