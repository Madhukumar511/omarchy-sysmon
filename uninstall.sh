#!/usr/bin/env bash
# ==============================================================================
# Omarchy Hardware Monitor (omarchy-sysmon) Uninstaller
# ==============================================================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

PLUGIN_DIR="$HOME/.config/omarchy/plugins/atomic.sysmon"
SHELL_CONFIG="$HOME/.config/omarchy/shell.json"

echo -e "${BLUE}Removing Omarchy Hardware Monitor...${NC}"

# 1. Remove from shell.json
python3 - << 'EOF'
import json, os

shell_path = os.path.expanduser("~/.config/omarchy/shell.json")
if os.path.exists(shell_path):
    try:
        with open(shell_path, "r") as f:
            data = json.load(f)

        layout = data.get("bar", {}).get("layout", {})
        changed = False
        for section_name, items in layout.items():
            if isinstance(items, list):
                new_items = [item for item in items if not (isinstance(item, dict) and item.get("id") == "atomic.sysmon")]
                if len(new_items) != len(items):
                    layout[section_name] = new_items
                    changed = True

        if changed:
            with open(shell_path, "w") as f:
                json.dump(data, f, indent=2)
            print("Removed atomic.sysmon from shell.json")
    except Exception as e:
        print(f"Notice: {e}")
EOF

# 2. Remove files
rm -rf "$PLUGIN_DIR" /tmp/.omarchy_sysmon_state.json

# 3. Restart shell
if command -v omarchy &> /dev/null; then
    omarchy restart shell || true
fi

echo -e "${GREEN}✓ Successfully uninstalled Omarchy Hardware Monitor.${NC}"
