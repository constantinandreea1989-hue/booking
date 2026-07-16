#!/bin/bash
# ============================================================
# Booking Page Auto-Sync
# Reads "Apple - Andreea" calendar, updates busy slots, pushes to GitHub Pages
# Runs every 30 min via launchd
# ============================================================

REPO_DIR="$HOME/Documents/EnterpriseAssistant/booking-pages"
CALENDAR_NAME="Apple - Andreea"
HTML_FILE="$REPO_DIR/index.html"

cd "$REPO_DIR" || exit 1

# Pull latest
git pull --quiet origin main 2>/dev/null

# Read busy slots from Calendar for next 30 days
BUSY_JSON=$(icalBuddy -ic "$CALENDAR_NAME" -df "%Y-%m-%d" -tf "%H:%M" -nrd -nc -b "" -npn -ea -iep "datetime" eventsFrom:today to:today+30 2>/dev/null | grep -E "^[0-9]{4}-" | while IFS= read -r line; do
    date=$(echo "$line" | grep -oE "^[0-9]{4}-[0-9]{2}-[0-9]{2}")
    start=$(echo "$line" | grep -oE "at [0-9]{2}:[0-9]{2}" | head -1 | sed 's/at //')
    end=$(echo "$line" | grep -oE "\- [0-9]{2}:[0-9]{2}$" | sed 's/- //')
    if [ -n "$date" ] && [ -n "$start" ] && [ -n "$end" ]; then
        echo "        \"${date}T${start}|${date}T${end}\","
    fi
done | sort -u)

# Remove trailing comma from last line
BUSY_JSON=$(echo "$BUSY_JSON" | sed '$ s/,$//')

# Update the busySlots array in the HTML file
python3 << PYEOF
import re

html_file = "$HTML_FILE"
busy_lines = """$BUSY_JSON"""

with open(html_file, 'r') as f:
    content = f.read()

# Replace busySlots array content
pattern = r'(busySlots:\s*\[)[^]]*(\])'
new_slots = busy_lines.strip()
replacement = r'\g<1>\n' + new_slots + '\n    \g<2>'
content = re.sub(pattern, replacement, content, flags=re.DOTALL)

with open(html_file, 'w') as f:
    f.write(content)

print(f"Updated busy slots ({len(busy_lines.strip().splitlines())} entries)")
PYEOF

# Push if changes exist
cd "$REPO_DIR"
git add -A
if git diff --cached --quiet; then
    echo "$(date): No changes"
else
    git commit -m "Auto-sync $(date '+%H:%M')" --quiet
    git push origin main --quiet 2>&1
    echo "$(date): Pushed update"
fi
