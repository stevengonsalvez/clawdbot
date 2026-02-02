#!/usr/bin/env bash
# Deep Sleep - Memory Consolidation
# Analyze and consolidate memory files

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Inputs
WORKSPACE="${1:-$HOME/d/popabot}"
STALE_DAYS="${2:-60}"
DRY_RUN="${3:-false}"
RESULTS_FILE="${4:-/tmp/deep-sleep-results.json}"

echo -e "${BLUE}🧠 Starting Deep Sleep (Memory Consolidation)${NC}"
echo ""
echo "Workspace: $WORKSPACE"
echo "Stale threshold: $STALE_DAYS days"
echo "Dry run: $DRY_RUN"
echo ""

# Expand home directory
WORKSPACE=$(eval echo "$WORKSPACE")
MEMORY_DIR="$WORKSPACE/memory"
MEMORY_MD="$WORKSPACE/MEMORY.md"

# Initialize results
cat > "$RESULTS_FILE" << 'EOF'
{
  "timestamp": "",
  "workspace": "",
  "scan": {
    "files_found": 0,
    "total_size_kb": 0,
    "large_files": [],
    "stale_files": []
  },
  "analysis": {
    "verbose_entries": [],
    "duplicates": [],
    "stale_entries": [],
    "promote_candidates": []
  },
  "proposals": []
}
EOF

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jq --arg ts "$TIMESTAMP" --arg ws "$WORKSPACE" '.timestamp = $ts | .workspace = $ws' "$RESULTS_FILE" > "${RESULTS_FILE}.tmp" && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"

# -----------------------------------------------------------------------------
# 1. Scan Memory Files
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[1/4]${NC} Scanning memory files..."

if [ ! -d "$MEMORY_DIR" ]; then
  echo -e "  ${YELLOW}ℹ${NC} No memory directory found at $MEMORY_DIR"
  echo -e "  Creating memory directory..."
  mkdir -p "$MEMORY_DIR"
fi

# Count files
FILE_COUNT=$(find "$MEMORY_DIR" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
echo -e "  Memory files: $FILE_COUNT"

# Total size
if [ -d "$MEMORY_DIR" ]; then
  TOTAL_SIZE=$(du -sk "$MEMORY_DIR" 2>/dev/null | cut -f1 || echo "0")
else
  TOTAL_SIZE=0
fi
echo -e "  Total size: ${TOTAL_SIZE}KB"

jq --argjson fc "$FILE_COUNT" --argjson ts "$TOTAL_SIZE" '.scan.files_found = $fc | .scan.total_size_kb = $ts' "$RESULTS_FILE" > "${RESULTS_FILE}.tmp" && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"

# Find large files (>10KB)
echo ""
echo "  Large files (>10KB):"
LARGE_FILES=$(find "$MEMORY_DIR" -name "*.md" -size +10k -type f 2>/dev/null || true)
if [ -n "$LARGE_FILES" ]; then
  while IFS= read -r file; do
    SIZE=$(ls -lh "$file" 2>/dev/null | awk '{print $5}')
    BASENAME=$(basename "$file")
    echo "    - $BASENAME ($SIZE)"
    jq --arg f "$BASENAME" --arg s "$SIZE" '.scan.large_files += [{"file": $f, "size": $s}]' "$RESULTS_FILE" > "${RESULTS_FILE}.tmp" && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"
  done <<< "$LARGE_FILES"
else
  echo "    (none)"
fi

# Find stale files
echo ""
echo "  Files older than $STALE_DAYS days:"
STALE_FILES=$(find "$MEMORY_DIR" -name "*.md" -mtime +$STALE_DAYS -type f 2>/dev/null || true)
if [ -n "$STALE_FILES" ]; then
  STALE_COUNT=0
  while IFS= read -r file; do
    BASENAME=$(basename "$file")
    MOD_DATE=$(stat -f "%Sm" -t "%Y-%m-%d" "$file" 2>/dev/null || stat -c "%y" "$file" 2>/dev/null | cut -d' ' -f1)
    echo "    - $BASENAME (modified: $MOD_DATE)"
    jq --arg f "$BASENAME" --arg d "$MOD_DATE" '.scan.stale_files += [{"file": $f, "modified": $d}]' "$RESULTS_FILE" > "${RESULTS_FILE}.tmp" && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"
    STALE_COUNT=$((STALE_COUNT + 1))
    [ "$STALE_COUNT" -ge 10 ] && echo "    ... (truncated)" && break
  done <<< "$STALE_FILES"
else
  echo "    (none)"
fi

# -----------------------------------------------------------------------------
# 2. Analyze MEMORY.md
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[2/4]${NC} Analyzing MEMORY.md..."

if [ -f "$MEMORY_MD" ]; then
  # Count sections
  SECTION_COUNT=$(grep -c "^##" "$MEMORY_MD" 2>/dev/null || echo "0")
  echo -e "  Sections: $SECTION_COUNT"
  
  # Count bullet points (facts)
  FACT_COUNT=$(grep -c "^- " "$MEMORY_MD" 2>/dev/null || echo "0")
  echo -e "  Facts/entries: $FACT_COUNT"
  
  # Line count
  LINE_COUNT=$(wc -l < "$MEMORY_MD" | tr -d ' ')
  echo -e "  Total lines: $LINE_COUNT"
  
  # Check for very long entries (potential verbose)
  LONG_LINES=$(awk 'length > 200' "$MEMORY_MD" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$LONG_LINES" -gt 0 ]; then
    echo -e "  ${YELLOW}⚠${NC} Found $LONG_LINES lines >200 chars (potential verbose entries)"
    jq --argjson c "$LONG_LINES" '.analysis.verbose_entries += [{"file": "MEMORY.md", "count": $c, "note": "Lines over 200 chars"}]' "$RESULTS_FILE" > "${RESULTS_FILE}.tmp" && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"
  fi
else
  echo -e "  ${YELLOW}ℹ${NC} MEMORY.md not found"
fi

# -----------------------------------------------------------------------------
# 3. Check for Duplicates
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[3/4]${NC} Checking for duplicates..."

# Combine all memory files and look for similar lines
ALL_MEMORY=$(find "$WORKSPACE" -maxdepth 2 -name "*.md" \( -path "*/memory/*" -o -name "MEMORY.md" \) -type f 2>/dev/null)

if [ -n "$ALL_MEMORY" ]; then
  # Extract all fact-like lines (starting with -)
  TEMP_FACTS="/tmp/sleep-facts-$$"
  while IFS= read -r file; do
    grep "^- " "$file" 2>/dev/null | while read -r line; do
      echo "$file|$line"
    done
  done <<< "$ALL_MEMORY" > "$TEMP_FACTS"
  
  # Look for exact duplicates
  DUPE_COUNT=$(cut -d'|' -f2 "$TEMP_FACTS" | sort | uniq -d | wc -l | tr -d ' ')
  
  if [ "$DUPE_COUNT" -gt 0 ]; then
    echo -e "  ${YELLOW}⚠${NC} Found $DUPE_COUNT duplicate entries"
    jq --argjson c "$DUPE_COUNT" '.analysis.duplicates += [{"count": $c, "note": "Exact duplicate bullet points"}]' "$RESULTS_FILE" > "${RESULTS_FILE}.tmp" && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"
  else
    echo -e "  ${GREEN}✓${NC} No exact duplicates found"
  fi
  
  rm -f "$TEMP_FACTS"
else
  echo -e "  ${YELLOW}ℹ${NC} No memory files to check"
fi

# -----------------------------------------------------------------------------
# 4. Identify Promotion Candidates
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[4/4]${NC} Identifying promotion candidates..."

# Look for patterns in daily logs that might be worth promoting
DAILY_LOGS=$(find "$MEMORY_DIR" -name "2*.md" -type f -mtime -30 2>/dev/null | head -10)

if [ -n "$DAILY_LOGS" ]; then
  # Look for repeated terms across multiple days
  echo "  Analyzing recent daily logs for patterns..."
  
  # This is a simple heuristic - a full implementation would use embeddings
  # For now, just flag files with similar topics
  RECENT_COUNT=$(echo "$DAILY_LOGS" | wc -l | tr -d ' ')
  echo -e "  Recent logs (30 days): $RECENT_COUNT"
  
  NOTE="Review recent $RECENT_COUNT daily logs for recurring patterns"
  jq --arg n "$NOTE" '.analysis.promote_candidates += [{"note": $n}]' "$RESULTS_FILE" > "${RESULTS_FILE}.tmp" && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"
else
  echo -e "  ${YELLOW}ℹ${NC} No recent daily logs found"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo -e "${GREEN}✓ Deep sleep scan complete${NC}"
echo -e "  Results saved to: $RESULTS_FILE"

# Generate proposals summary
echo ""
echo "Proposals:"
echo "  - Review $(jq '.scan.large_files | length' "$RESULTS_FILE") large files for compression"
echo "  - Review $(jq '.scan.stale_files | length' "$RESULTS_FILE") stale files"
echo "  - Merge $(jq '.analysis.duplicates[0].count // 0' "$RESULTS_FILE") duplicate entries"

cat "$RESULTS_FILE" | jq '.'
