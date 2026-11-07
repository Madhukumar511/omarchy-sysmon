#!/usr/bin/env bash
# ==============================================================================
# Omarchy Hardware Monitor (omarchy-sysmon) One-Line Installer
# Repository: https://github.com/Madhukumar511/omarchy-sysmon
# ==============================================================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  󰍛 Installing Omarchy Hardware Monitor (atomic.sysmon)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 1. Dependency checks
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}[ERROR] python3 is required but not installed.${NC}"
    exit 1
fi

if ! command -v git &> /dev/null; then
    echo -e "${RED}[ERROR] git is required but not installed.${NC}"
    exit 1
fi

PLUGIN_DIR="$HOME/.config/omarchy/plugins/atomic.sysmon"
REPO_URL="https://github.com/Madhukumar511/omarchy-sysmon.git"

# 2. Clone or update repository
if [ -d "$PLUGIN_DIR/.git" ]; then
    echo -e "${BLUE}[1/4] Updating existing repository in $PLUGIN_DIR...${NC}"
    git -C "$PLUGIN_DIR" pull --quiet origin main || true
elif [ -d "$PLUGIN_DIR" ]; then
    echo -e "${BLUE}[1/4] Plugin directory exists, backing up and cloning latest...${NC}"
    mv "$PLUGIN_DIR" "${PLUGIN_DIR}.bak.$(date +%s)"
    git clone --quiet "$REPO_URL" "$PLUGIN_DIR"
else
    echo -e "${BLUE}[1/4] Cloning repository to $PLUGIN_DIR...${NC}"
    mkdir -p "$HOME/.config/omarchy/plugins"
    git clone --quiet "$REPO_URL" "$PLUGIN_DIR"
fi

chmod +x "$PLUGIN_DIR/scripts/get_stats.py" "$PLUGIN_DIR/install.sh" 2>/dev/null || true

# 3. Register widget in ~/.config/omarchy/shell.json
SHELL_CONFIG="$HOME/.config/omarchy/shell.json"
echo -e "${BLUE}[2/4] Registering widget in Omarchy bar layout...${NC}"

python3 - << 'EOF'
import json, os, sys

shell_path = os.path.expanduser("~/.config/omarchy/shell.json")
if not os.path.exists(shell_path):
    print("Warning: ~/.config/omarchy/shell.json not found. You may need to add 'atomic.sysmon' manually.")
    sys.exit(0)

try:
    with open(shell_path, "r") as f:
        data = json.load(f)

    layout = data.setdefault("bar", {}).setdefault("layout", {})
    
    # Check if already registered
    found = False
    for section_name, items in layout.items():
        if isinstance(items, list):
            for item in items:
                if isinstance(item, dict) and item.get("id") == "atomic.sysmon":
                    found = True
                    break
        if found:
            break

    if not found:
        # Preferred target: centerEnd (alongside elsewhen, weather), fallback to right
        target_section = "centerEnd" if "centerEnd" in layout else ("right" if "right" in layout else None)
        if target_section and isinstance(layout[target_section], list):
            layout[target_section].append({"id": "atomic.sysmon"})
            with open(shell_path, "w") as f:
                json.dump(data, f, indent=2)
            print("Successfully added 'atomic.sysmon' to layout." + target_section)
        else:
            print("Could not auto-detect bar section. Please add {\"id\": \"atomic.sysmon\"} manually to shell.json.")
    else:
        print("Widget is already present in your bar layout.")
except Exception as e:
    print(f"Notice: Failed to update shell.json automatically ({e}). Please add 'atomic.sysmon' manually.")
EOF

# 4. Clean cache
echo -e "${BLUE}[3/4] Initializing hardware cache and deltas...${NC}"
python3 "$PLUGIN_DIR/scripts/get_stats.py" > /dev/null 2>&1 || true

# 5. Restart Omarchy Shell
echo -e "${BLUE}[4/4] Restarting Omarchy shell to apply changes...${NC}"
if command -v omarchy &> /dev/null; then
    omarchy restart shell || true
elif command -v quickshell &> /dev/null; then
    pkill -f quickshell || true
fi

echo ""
echo -e "${GREEN}✓ Successfully installed Omarchy Hardware Monitor!${NC}"
echo -e "• Click the widget on your bar to view the telemetry dashboard."
echo -e "• Right-click or scroll on the widget to switch metric view modes."
echo -e "• Run ${YELLOW}omarchy-shell atomic.sysmon toggle${NC} via keybindings."
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
