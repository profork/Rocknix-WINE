#!/bin/bash
# setup_wine_port.sh
#
# This script automates the setup for a generic Wine port for a game.
# It:
#   - Prompts for the game title and executable name.
#   - Optionally asks if the executable is in a subfolder (relative to the data folder).
#   - Prompts the user to choose a graphics compatibility package (DXVK, vkd3d, or none).
#   - Optionally fetches the winetricks list and lets the user select additional winetricks packages.
#   - Creates the directory structure and sets up a dedicated 64-bit Wine bottle (prefix).
#   - Leaves Gecko and Mono uninstalled so that Wine auto-installs them on first launch;
#       however, if missing, manual installation of the 64-bit versions will be attempted.
#   - Installs the chosen graphics dependency and any additional winetricks packages during setup.
#   - Generates a launch script in __PORTS_BASE__ that sets up the environment and launches the game.
#
# When the launch script is executed, Wine will auto-install any missing components
# (including Gecko and Mono) without user intervention.
#
# Requirements: dialog, curl, winetricks, wine64, box64, and GPTOKEYB.
#
# Base folders and executable locations
PORTS_BASE="/storage/roms/ports"
BASE_WINE_PREFIX="/storage/.wine64-setup"
GPTOKEYB="/usr/bin/gptokeyb"  # Adjust this path as needed

# ---------------------------
# Utility Functions
# ---------------------------
msgbox() {
    dialog --title "$1" --msgbox "$2" 10 60
}

yesno() {
    dialog --title "$1" --yesno "$2" 10 60
    return $?
}

# ---------------------------
# Pre-Setup Dependency Check
# ---------------------------
for cmd in wine64 box64 "${GPTOKEYB}"; do
    if ! command -v "$cmd" &>/dev/null; then
        msgbox "Error" "Missing dependency: $cmd is not installed. Install it before proceeding."
        exit 1
    fi
done

msgbox "Game Port Setup" "This script will create the directory structure and 64-bit Wine bottle for your game port."
yesno "Proceed?" "This will create folders and files under ${PORTS_BASE} and set up a dedicated Wine bottle. Continue?"
if [ $? -ne 0 ]; then
    clear
    echo "Setup cancelled."
    exit 1
fi

# ---------------------------
# User Input: Game Title, Executable, and Subfolder
# ---------------------------
TMPFILE=$(mktemp)
dialog --inputbox "Enter the game title (e.g. ExampleGame):" 8 60 2> "$TMPFILE"
GAME_TITLE=$(sed -e 's/^[ \t]*//;s/[ \t]*$//' "$TMPFILE")
[ -z "$GAME_TITLE" ] && { clear; echo "No game title provided. Exiting."; rm -f "$TMPFILE"; exit 1; }
rm -f "$TMPFILE"
# Create a folder-friendly name (lowercase, no spaces)
GAME_FOLDER=$(echo "$GAME_TITLE" | tr '[:upper:]' '[:lower:]' | tr -d ' ')

BASE_WINE_PREFIX="/storage/.wine64-setup"
WINE_PREFIX="${BASE_WINE_PREFIX}/${GAME_FOLDER}"

DEFAULT_EXE="${GAME_TITLE}.exe"
TMPFILE=$(mktemp)
dialog --inputbox "Enter the game executable (with extension):" 8 60 "$DEFAULT_EXE" 2> "$TMPFILE"
EXE_NAME=$(sed -e 's/^[ \t]*//;s/[ \t]*$//' "$TMPFILE")
[ -z "$EXE_NAME" ] && EXE_NAME="$DEFAULT_EXE"
rm -f "$TMPFILE"

yesno "Executable Location" "Is your game executable in a subfolder (relative to 'data')?"
if [ $? -eq 0 ]; then
    TMPFILE=$(mktemp)
    dialog --inputbox "Enter the relative subfolder path (e.g. bin64):" 8 60 2> "$TMPFILE"
    SUBFOLDER=$(sed -e 's/^[ \t]*//;s/[ \t]*$//' "$TMPFILE")
    rm -f "$TMPFILE"
else
    SUBFOLDER=""
fi
EXE_PATH="${SUBFOLDER:+${SUBFOLDER}/}${EXE_NAME}"

# ---------------------------
# Graphics Dependency Selection
# ---------------------------
CHOICE=$(dialog --stdout --radiolist "Select graphics compatibility package:" 10 60 3 \
    "dxvk" "Install DXVK (DirectX to Vulkan)" on \
    "vkd3d" "Install vkd3d (DirectX 12 to Vulkan)" off \
    "none" "Install neither" off)
[ -z "$CHOICE" ] && CHOICE="none"

# ---------------------------
# Additional Winetricks Packages (Optional)
# ---------------------------
yesno "Additional Winetricks" "Do you want to install additional winetricks packages (fetched from the official list)?"
if [ $? -eq 0 ]; then
    WT_URL="https://raw.githubusercontent.com/Winetricks/winetricks/master/files/verbs/all.txt"
    WT_TEMP=$(mktemp)
    curl -sL "$WT_URL" -o "$WT_TEMP"
    if [ ! -s "$WT_TEMP" ]; then
        msgbox "Error" "Failed to fetch winetricks list."
        ADDITIONAL_WT=""
    else
        WT_PARSED=$(mktemp)
        # Remove section headers and blank lines.
        grep -v '^=====' "$WT_TEMP" | grep -v '^[[:space:]]*$' > "$WT_PARSED"
        ADD_OPTIONS=()
        while IFS= read -r line; do
            pkg=$(echo "$line" | awk '{print $1}')
            desc=$(echo "$line" | cut -d' ' -f2-)
            ADD_OPTIONS+=("$pkg" "$desc" "off")
        done < "$WT_PARSED"
        ADD_SELECTION=$(dialog --stdout --checklist "Select additional winetricks packages:" 20 70 10 "${ADD_OPTIONS[@]}")
        ADDITIONAL_WT=$(echo $ADD_SELECTION | tr -d '"')
        rm -f "$WT_PARSED" "$WT_TEMP"
    fi
else
    ADDITIONAL_WT=""
fi

# ---------------------------
# Set Directory Paths Based on Game Folder
# ---------------------------
GAME_DIR="${PORTS_BASE}/${GAME_FOLDER}"
GPTK_FILE="${GAME_DIR}/${GAME_FOLDER}.gptk"
LAUNCH_SCRIPT="${PORTS_BASE}/${GAME_FOLDER}.sh"

# ---------------------------
# Create Directories and GPTK File
# ---------------------------
msgbox "Creating Directories" "Creating ${GAME_DIR} (with subfolders data and config)."
mkdir -p "${GAME_DIR}/data" "${GAME_DIR}/config"
mkdir -p /storage/.wine64-setup

cat > "${GPTK_FILE}" << 'EOF'
back = \"
start = \"
a = \"
b = \"
x = \"
y = \"
l1 = \"
l2 = \"
r1 = \"
r2 = \"
up = \"
down = \"
left = \"
right = \"
left_analog_up = \"
left_analog_down = \"
left_analog_left = \"
left_analog_right = \"
right_analog_up = \"
right_analog_down = \"
right_analog_left = \"
right_analog_right = \"
EOF

# ---------------------------
# Initialize Wine Bottle
# ---------------------------
# Always create a 64-bit prefix.
if [ ! -d "${WINE_PREFIX}/drive_c" ]; then
    msgbox "Initializing Wine Bottle" "Creating 64-bit Wine prefix at ${WINE_PREFIX}."
    WINEPREFIX="${WINE_PREFIX}" wine64 wineboot --init
    if [ ! -d "${WINE_PREFIX}/drive_c" ]; then
        msgbox "Error" "Failed to initialize Wine prefix. Setup aborted."
        exit 1
    fi
fi

# Do not install wine-gecko/mono here; let Wine auto-install them on first launch.
# However, if desired, you could verify or force install the 64-bit versions manually.
# (The following multiarch block is now removed since we only support 64-bit.)

# ---------------------------
# Install the Selected Graphics Compatibility Package
# ---------------------------
if [ "$CHOICE" != "none" ]; then
    WINEPREFIX="${WINE_PREFIX}" winetricks -q "$CHOICE"
    if [ "$CHOICE" = "dxvk" ]; then
        if [ ! -f "$WINE_PREFIX/drive_c/windows/system32/dxgi.dll" ]; then
            msgbox "Error" "DXVK installation failed or dxgi.dll is missing. Game may not work properly."
        fi
    fi
fi

# Install additional winetricks packages if selected.
if [ -n "$ADDITIONAL_WT" ]; then
    for pkg in $ADDITIONAL_WT; do
         WINEPREFIX="${WINE_PREFIX}" winetricks -q "$pkg"
    done
fi

# ---------------------------
# Generate the Launch Script (No dependency installation here)
# ---------------------------
cat > "${LAUNCH_SCRIPT}" << 'EOF'
#!/bin/bash

# Determine PortMaster control folder
if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

# Source control files if available
source "${controlfolder}/control.txt"
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

# Variables
GAMEDIR="__PORTS_BASE__/__GAME_FOLDER__"
WINEPREFIX="__WINE_PREFIX__"

# Ensure the game directory exists.
if [ ! -d "$GAMEDIR" ]; then
  echo "Error: Game directory missing ($GAMEDIR). Please check your installation."
  exit 1
fi

# Change to game directory and prepare logging.
cd "$GAMEDIR"
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1
\$ESUDO chmod +x -R "$GAMEDIR"/*

# Environment variable exports.
export SDL_GAMECONTROLLERCONFIG="\$sdl_controllerconfig"
export WINEPREFIX="__WINE_PREFIX__"
export WINEDEBUG=-all
export DXVK_HUD=1

# Check if pm_message exists.
if ! type pm_message &>/dev/null; then
    echo "Warning: pm_message function is missing. Skipping dependency message."
else
    pm_message "Checking for and installing dependencies..."
fi

# Config Setup: create config directory and bind to the Wine save folder.
mkdir -p "$GAMEDIR/config"
if [ "$(type -t bind_directories)" = "function" ]; then
    bind_directories "$WINEPREFIX/drive_c/users/root/AppData/LocalLow/Andrew Shouldice/Secret Legend" "$GAMEDIR/config"
else
    echo "Warning: bind_directories function is missing. Skipping config binding."
fi

# Check that box64, wine64, and GPTOKEYB exist before launching.
if ! command -v box64 &>/dev/null || ! command -v wine64 &>/dev/null; then
  echo "Error: box64 or wine64 is missing. Install them before running the game."
  exit 1
fi
if ! command -v __GPTOKEYB__ &>/dev/null; then
  echo "Error: GPTOKEYB is missing. Install it before running the game."
  exit 1
fi

# Launch the game:
# First, launch GPToKeyB for controller mapping.
__GPTOKEYB__ "__EXE_NAME__" -c "./__GAME_FOLDER__.gptk" &
# Then launch the game executable from the data folder using box64/wine64.
box64 wine64 "$GAMEDIR/data/__EXE_PATH__"
EOF

# Replace placeholders in the launch script.
sed -i "s|__PORTS_BASE__|${PORTS_BASE}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__WINE_PREFIX__|${WINE_PREFIX}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__GAME_FOLDER__|${GAME_FOLDER}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__EXE_PATH__|\"${EXE_PATH}\"|g" "${LAUNCH_SCRIPT}"
sed -i "s|__GPTOKEYB__|${GPTOKEYB}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__EXE_NAME__|${EXE_NAME}|g" "${LAUNCH_SCRIPT}"

chmod +x "${LAUNCH_SCRIPT}"

msgbox "Setup Complete" "Setup complete.
Files created:
- Launch Script: ${LAUNCH_SCRIPT}
- Game Folder: ${GAME_DIR} (with subfolders data and config)
- GPTK File: ${GPTK_FILE}

Please copy your game data into the 'data' folder before launching."
clear
echo "Setup complete. Run: ${LAUNCH_SCRIPT}"
