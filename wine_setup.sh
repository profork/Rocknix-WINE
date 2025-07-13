#!/bin/bash 
# setup_wine_port.sh
#
# This script automates the setup for a generic Wine port for a game.
# It:
#   - Prompts the user to either create a new game/Wine prefix or modify an existing one.
#   - Offers an option to use a dedicated Wine prefix (less potential conflicts) or a general shared prefix (less bloat).
#   - For new installs, prompts for the game title, the executable filename (specifically the game-launching exe; do not include any folder), and a subfolder (if applicable).
#   - Prompts for a graphics compatibility package with the choice to install latest dxvk or legacy dxvk2041 (due to performance regressions), vkd3d, or none.
#   - Offers options for DXVK HUD (default off), async mode, and separate yes/no prompts for ESYNC and FSYNC.
#   - Provides a single radiolist for the Pulse Audio option:
#         * "nopulse" – Do not use Pulse Audio.
#         * "pulse60" – Use winetricks sound=pulse with 60 ms latency.
#         * "pulse90" – Use winetricks sound=pulse with 90 ms latency.
#   - Prompts for installing common VC++ runtimes and DirectX9 (d3dx9_43).
#   - Optionally asks if the user wants to manually assign keyboard button mappings (for controls like back, start, a, b, etc.).
#       - If skipped, a default GPTK file with empty mappings is created.
#   - Then asks if the user wants to install additional winetricks packages.
#   - Creates the directory structure and sets up (or modifies) a dedicated/shared 64-bit Wine prefix.
#   - Generates a launch script that sets up the environment and launches the game.
#
# Requirements: dialog, curl, winetricks, wine, box64.
#
# Base folders and executable locations
PORTS_BASE="/storage/roms/windows"
# Default dedicated Wine prefixes go here:
BASE_WINE_PREFIX="/storage/.wine-setup"
# General (shared) Wine prefix location:
GENERAL_WINE_PREFIX="/storage/.wine-shared"
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
for cmd in wine box64 "${GPTOKEYB}"; do
    if ! command -v "$cmd" &>/dev/null; then
        msgbox "Error" "Missing dependency: $cmd is not installed. Install it before proceeding."
        exit 1
    fi
done

msgbox "Game Port Setup" "This script will create or modify a Wine prefix for your game port."
yesno "Proceed?" "This will create folders and files under ${PORTS_BASE} and set up a dedicated/shared Wine prefix. Continue?"
if [ $? -ne 0 ]; then
    clear
    echo "Setup cancelled."
    exit 1
fi

# ---------------------------
# Choose New or Modify Mode
# ---------------------------
MODE=$(dialog --stdout --radiolist "Select mode:" 10 60 2 \
    "new" "Create a new game/Wine prefix" on \
    "modify" "Modify an existing Wine prefix" off)

if [ "$MODE" = "modify" ]; then
    if [ ! -d "${BASE_WINE_PREFIX}" ]; then
        msgbox "Error" "Dedicated prefix directory ${BASE_WINE_PREFIX} not found."
        exit 1
    fi

    EXISTING_OPTIONS=()
    for d in "${BASE_WINE_PREFIX}"/*; do
        [ -d "$d" ] || continue
        foldername=$(basename "$d")
        EXISTING_OPTIONS+=("$foldername" "$foldername" "off")
    done

    if [ ${#EXISTING_OPTIONS[@]} -eq 0 ]; then
        msgbox "No Existing Prefixes" "No existing dedicated Wine prefixes were found. Switching to new prefix mode."
        MODE="new"
    else
        SELECTED=$(dialog --stdout --radiolist "Select a Wine prefix to modify:" 15 60 5 "${EXISTING_OPTIONS[@]}")
        if [ -z "$SELECTED" ]; then
            msgbox "Cancelled" "No selection made. Exiting."
            exit 1
        fi
        GAME_FOLDER="$SELECTED"
        WINE_PREFIX="${BASE_WINE_PREFIX}/${GAME_FOLDER}"
    fi
fi

# ---------------------------
# For New Prefix: Ask Game Title and Prefix Mode
# ---------------------------
if [ "$MODE" = "new" ]; then
    TMPFILE=$(mktemp)
    dialog --inputbox "Enter the game title (e.g. ExampleGame):" 8 60 2> "$TMPFILE"
    GAME_TITLE=$(sed -e 's/^[ \t]*//;s/[ \t]*$//' "$TMPFILE")
    [ -z "$GAME_TITLE" ] && { clear; echo "No game title provided. Exiting."; rm -f "$TMPFILE"; exit 1; }
    rm -f "$TMPFILE"
    # Create a folder-friendly name (lowercase, no spaces)
    GAME_FOLDER=$(echo "$GAME_TITLE" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
    
    # Ask if user wants a dedicated prefix or a general (shared) one.
    yesno "Prefix Mode" "Do you want to use a dedicated Wine prefix for this game?\n\nDedicated prefixes reduce conflicts, while a general prefix reduces bloat."
    if [ $? -eq 0 ]; then
        # Use dedicated prefix:
        WINE_PREFIX="${BASE_WINE_PREFIX}/${GAME_FOLDER}"
    else
        # Use general shared prefix:
        WINE_PREFIX="${GENERAL_WINE_PREFIX}"
    fi
fi

# ---------------------------
# Common Prompt: Executable and Subfolder
# ---------------------------
# Clarify: Enter only the executable filename that launches the game (do not include any folder path).
DEFAULT_EXE="${GAME_TITLE}.exe"
TMPFILE=$(mktemp)
dialog --inputbox "Enter the game executable filename (with extension, e.g. game.exe):" 8 60 "$DEFAULT_EXE" 2> "$TMPFILE"
EXE_NAME=$(sed -e 's/^[ \t]*//;s/[ \t]*$//' "$TMPFILE")
[ -z "$EXE_NAME" ] && EXE_NAME="$DEFAULT_EXE"
rm -f "$TMPFILE"

yesno "Executable Location" "Is your game executable located in a subfolder relative to the 'data' folder?\n\n(If 'No', the executable filename will be used directly.)"
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
# Allow user to choose between latest dxvk and dxvk2041 (fixes regressions), vkd3d, or neither.
CHOICE=$(dialog --stdout --radiolist "Select graphics compatibility package:" 15 90 7 \
    "dxvk"     "Install latest DXVK (Newer regressions have shown ~-5FPS)" off \
    "dxvk2041" "Install DXVK 2041 (fixes regression in later builds)" on \
    "vkd3d"    "Install vkd3d (DirectX 12 to Vulkan)" off \
    "none"     "Install neither" off)
[ -z "$CHOICE" ] && CHOICE="none"

# ---------------------------
# DXVK and Wine Environment Options
# ---------------------------
# DXVK HUD selection (default off).
HUD_CHOICE=$(dialog --stdout --radiolist "DXVK HUD:" 10 60 2 \
    "1" "Enable DXVK HUD" off \
    "0" "Disable DXVK HUD" on)
[ -z "$HUD_CHOICE" ] && HUD_CHOICE=0

# Ask for DXVK Async Mode option.
yesno "DXVK Async Mode" "Do you want to enable DXVK/VKD3D async mode? (This may reduce shader stutter)"
if [ $? -eq 0 ]; then
    DXVK_ASYNC=1
else
    DXVK_ASYNC=0
fi

# ---------------------------
# Separate Prompts for ESYNC and FSYNC
# ---------------------------
yesno "ESYNC" "Do you want to enable ESYNC (Wine's eventfd-based synchronization)?"
if [ $? -eq 0 ]; then
    STAGING_SHARED_MEMORY=1
else
    STAGING_SHARED_MEMORY=0
fi

yesno "FSYNC" "Do you want to enable FSYNC (Wine's file descriptor–based synchronization)?"
if [ $? -eq 0 ]; then
    STAGING_WRITECOPY=1
else
    STAGING_WRITECOPY=0
fi

# ---------------------------
# Additional Settings for Unity/Other Games (Optional)
# ---------------------------
UNITY_OPT=0
yesno "Unity/Other Game Optimizations" "Would you like to apply additional optimal settings for Unity games (or similar titles)?\n\nThis will write extra BOX64 environment variable settings to the launcher script."
if [ $? -eq 0 ]; then
    UNITY_OPT=1
    msgbox "Additional Settings" "Extra BOX64 settings will be written to your launcher script."
fi


# ---------------------------
# Pulse Audio Option (ENSURES IT SHOWS)
# ---------------------------
SOUND_OPTION=$(dialog --stdout --radiolist "Pulse Audio Option" 10 90 3 \
    "nopulse" "Do not use Pulse Audio" on \
    "pulse60" "Use winetricks sound=pulse with 60 ms latency" off \
    "pulse90" "Use winetricks sound=pulse with 90 ms latency" off)

# If the user cancels or doesn't select anything, default to "nopulse"
if [ -z "$SOUND_OPTION" ]; then
    SOUND_OPTION="nopulse"
fi



# ---------------------------
# VC++ and DirectX9 Dependencies Prompt
# ---------------------------
yesno "VC++/DirectX Dependencies" "Do you want to install common VC++ runtimes and DirectX9 (d3dx9_43)?\n\nThese include VC++ 2008, 2010, 2012, 2013, and 2015-2022."
if [ $? -eq 0 ]; then
    DEP_OPTIONS=$(dialog --stdout --checklist "Select VC++/DirectX dependencies to install:" 15 60 8 \
        "vcrun2008" "Visual C++ 2008" off \
        "vcrun2010" "Visual C++ 2010" off \
        "vcrun2012" "Visual C++ 2012" off \
        "vcrun2013" "Visual C++ 2013" off \
        "vcrun2022" "Visual C++ 2015-2022" off \
        "d3dx9_43" "DirectX9 (d3dx9_43)" off)
else
    DEP_OPTIONS=""
fi









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
        ADD_SELECTION=$(dialog --stdout --checklist "Select additional winetricks packages:" 30 85 10 "${ADD_OPTIONS[@]}")
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
# Create Directories
# ---------------------------
msgbox "Creating Directories" "Creating ${GAME_DIR} (with subfolders data and config)."
mkdir -p "${GAME_DIR}/data" "${GAME_DIR}/config"
mkdir -p /storage/.wine-setup

# ---------------------------
# Keyboard Mapping: Manual or Default?
# ---------------------------
yesno "Keyboard Mapping" "Do you want to manually assign keyboard button mappings?\n\n(If you choose 'No', default empty mappings will be created.)"
if [ $? -eq 0 ]; then
    # Define the list of controls for which to assign keyboard buttons.
    BUTTONS=("back" "start" "a" "b" "x" "y" "l1" "l2" "r1" "r2" "up" "down" "left" "right" "left_analog_up" "left_analog_down" "left_analog_left" "left_analog_right" "right_analog_up" "right_analog_down" "right_analog_left" "right_analog_right")
    GPTK_CONTENT=""
    for btn in "${BUTTONS[@]}"; do
      TMPFILE=$(mktemp)
      dialog --inputbox "Press keyboard button for the ${btn} button:" 8 60 2> "$TMPFILE"
      KEY_ASSIGN=$(sed -e 's/^[ \t]*//;s/[ \t]*$//' "$TMPFILE")
      rm -f "$TMPFILE"
      GPTK_CONTENT+="${btn} = \"${KEY_ASSIGN}\"\n"
    done
else
    # Create a default GPTK file with empty mappings.
    GPTK_CONTENT="back = \"\"\nstart = \"\"\na = \"\"\nb = \"\"\nx = \"\"\ny = \"\"\nl1 = \"\"\nl2 = \"\"\nr1 = \"\"\nr2 = \"\"\nup = \"\"\ndown = \"\"\nleft = \"\"\nright = \"\"\nleft_analog_up = \"\"\nleft_analog_down = \"\"\nleft_analog_left = \"\"\nleft_analog_right = \"\"\nright_analog_up = \"\"\nright_analog_down = \"\"\nright_analog_left = \"\"\nright_analog_right = \"\""
fi

# Write the control mappings to the GPTK file.
echo -e "$GPTK_CONTENT" > "${GPTK_FILE}"

# ---------------------------
# Initialize or Modify Wine Bottle
# ---------------------------
if [ "$MODE" = "new" ]; then
    if [ ! -d "${WINE_PREFIX}/drive_c" ]; then
        msgbox "Initializing Wine Bottle" "Creating 64-bit Wine prefix at ${WINE_PREFIX}.\n\n(Note: A Wine Mono GUI prompt may appear on the main display.)"
        WINEPREFIX="${WINE_PREFIX}" wine wineboot --init
        if [ ! -d "${WINE_PREFIX}/drive_c" ]; then
            msgbox "Error" "Failed to initialize Wine prefix. Setup aborted."
            exit 1
        fi
    fi
else
    msgbox "Modifying Wine Bottle" "Modifying the existing Wine prefix at ${WINE_PREFIX}.\n\n(Note: A Wine Mono GUI prompt may appear if components are missing.)"
fi

# Do not install wine-gecko/mono here; let Wine auto-install them on first launch.

# ---------------------------
# Install the Selected Graphics Compatibility Package
# ---------------------------
if [ "$CHOICE" != "none" ]; then
    WINEPREFIX="${WINE_PREFIX}" winetricks -q "$CHOICE"
    if [ "$CHOICE" = "dxvk" ] || [ "$CHOICE" = "dxvk2041" ]; then
        if [ ! -f "$WINE_PREFIX/drive_c/windows/system32/dxgi.dll" ]; then
            msgbox "Error" "DXVK installation failed or dxgi.dll is missing. Game may not work properly."
        fi
    fi
fi

# ---------------------------
# Install VC++/DirectX Dependencies if Selected
# ---------------------------
if [ -n "$DEP_OPTIONS" ]; then
    for pkg in $DEP_OPTIONS; do
         WINEPREFIX="${WINE_PREFIX}" winetricks -q "$pkg"
    done
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
chmod +x -R "$GAMEDIR"/*

# Environment variable exports.
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
export WINEPREFIX="__WINE_PREFIX__"
export WINEDEBUG=-all

# Graphics and optimization options.
export DXVK_HUD=__DXVK_HUD__
export DXVK_ASYNC=__DXVK_ASYNC__
export STAGING_SHARED_MEMORY=__STAGING_SHARED_MEMORY__
export STAGING_WRITECOPY=__STAGING_WRITECOPY__
__BOX64_EXTRA_SETTINGS__

# Sound setup
__SOUND_SETUP__

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

# Check that box64, wine, and GPTOKEYB exist before launching.
if ! command -v box64 &>/dev/null || ! command -v wine &>/dev/null; then
  echo "Error: box64 or wine is missing. Install them before running the game."
  exit 1
fi
if ! command -v __GPTOKEYB__ &>/dev/null; then
  echo "Error: GPTOKEYB is missing. Install it before running the game."
  exit 1
fi

# Launch the game:
# First, launch GPToKeyB for controller mapping.
__GPTOKEYB__ "__EXE_NAME__" -c "./__GAME_FOLDER__.gptk" &
# Then launch the game executable from the data folder using box64/wine.
box64 wine "$GAMEDIR/data/__EXE_PATH__"
EOF

# ---------------------------
# Replace Placeholders in the Launch Script
# ---------------------------
sed -i "s|__PORTS_BASE__|${PORTS_BASE}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__WINE_PREFIX__|${WINE_PREFIX}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__GAME_FOLDER__|${GAME_FOLDER}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__EXE_PATH__|\"${EXE_PATH}\"|g" "${LAUNCH_SCRIPT}"
sed -i "s|__GPTOKEYB__|${GPTOKEYB}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__EXE_NAME__|${EXE_NAME}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__DXVK_HUD__|${HUD_CHOICE}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__DXVK_ASYNC__|${DXVK_ASYNC}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__STAGING_SHARED_MEMORY__|${STAGING_SHARED_MEMORY}|g" "${LAUNCH_SCRIPT}"
sed -i "s|__STAGING_WRITECOPY__|${STAGING_WRITECOPY}|g" "${LAUNCH_SCRIPT}"

# ---------------------------
# Remove the grouped placeholder.
# ---------------------------
sed -i "s|__BOX64_EXTRA_SETTINGS__||g" "${LAUNCH_SCRIPT}"

# ---------------------------
# Insert extra BOX64 settings before the game launch.
# ---------------------------
if [ "$UNITY_OPT" -eq 1 ]; then
    sed -i "/# Launch the game:/i \
export BOX64_DYNAREC_SAFEFLAGS=1\n\
export BOX64_DYNAREC_FASTNAN=1\n\
export BOX64_DYNAREC_FASTROUND=1\n\
export BOX64_DYNAREC_X87DOUBLE=0\n\
export BOX64_DYNAREC_BIGBLOCK=3\n\
export BOX64_DYNAREC_STRONGMEM=0\n\
export BOX64_DYNAREC_FORWARD=512\n\
export BOX64_DYNAREC_CALLRET=1\n\
export BOX64_DYNAREC_WAIT=1\n\
export BOX64_AVX=0\n\
export BOX64_MAXCPU=8\n\
export BOX64_UNITYPLAYER=1" "${LAUNCH_SCRIPT}"
fi

# ---------------------------
# Insert Sound Setup Commands
# ---------------------------
SOUND_CMD=""
if [ "$SOUND_OPTION" = "pulse60" ]; then
    SOUND_CMD+="WINEPREFIX=\"${WINE_PREFIX}\" winetricks -q sound=pulse\n"
    SOUND_CMD+="export PULSE_LATENCY_MSEC=60\n"
elif [ "$SOUND_OPTION" = "pulse90" ]; then
    SOUND_CMD+="WINEPREFIX=\"${WINE_PREFIX}\" winetricks -q sound=pulse\n"
    SOUND_CMD+="export PULSE_LATENCY_MSEC=90\n"
fi

if [ -n "$SOUND_CMD" ]; then
    # Use sed to replace the placeholder with the generated commands.
    sed -i "s|__SOUND_SETUP__|${SOUND_CMD}|g" "${LAUNCH_SCRIPT}"
else
    sed -i "s|__SOUND_SETUP__||g" "${LAUNCH_SCRIPT}"
fi

chmod +x "${LAUNCH_SCRIPT}"

msgbox "Setup Complete" "Setup complete.
Files created/modified:
- Launch Script: ${LAUNCH_SCRIPT}
- Game Folder: ${GAME_DIR} (with subfolders data and config)
- GPTK File: ${GPTK_FILE}

Please copy your game data into the 'data' folder before launching."
clear
echo "Setup complete. Run: ${LAUNCH_SCRIPT} after you copy your game over to the data folder"
