#!/bin/bash
# Rocknix 32-bit Builds Downloader
# Downloads custom 32-bit Vanilla and Wine-TKG-Staging builds to /storage/winecustom32/

# Base directory for custom builds (32-bit)
INSTALL_DIR="/storage/winecustom32/"
mkdir -p "$INSTALL_DIR"

# Check for required commands
for cmd in jq dialog wget curl tar; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: $cmd is not installed."
        exit 1
    fi
done

###############################
# Function: Standard (Vanilla) Builds #
###############################
download_vanilla_32bit() {
    local REPO_URL="https://api.github.com/repos/Kron4ek/Wine-Builds/releases?per_page=300"
    echo "Fetching 32-bit Vanilla release information..."
    local release_data
    release_data=$(curl -s "$REPO_URL")
    if [[ $? -ne 0 || -z "$release_data" ]]; then
        echo "Failed to fetch release data."
        exit 1
    fi

    # Build a dialog checklist
    local menu_cmd=(dialog --separate-output --checklist "Select 32-bit Vanilla Wine builds to download (contains x86):" 22 76 16)
    local options=()
    local i=0

    while IFS= read -r line; do
        local name tag
        name=$(echo "$line" | jq -r '.name')
        tag=$(echo "$line" | jq -r '.tag_name')
        options+=("$i" "${name} - ${tag}" off)
        ((i++))
    done < <(echo "$release_data" | jq -c '.[]')

    local choices
    choices=$("${menu_cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
    clear

    # Download and extract selected releases
    for choice in $choices; do
        local version url version_dir
        version=$(echo "$release_data" | jq -r ".[$choice].tag_name")

        # For 32-bit, we look for x86 in the filename
        url=$(echo "$release_data" | jq -r ".[$choice].assets[] 
               | select(.name | contains(\"x86\"))
               | .browser_download_url" | head -n1)

        if [[ -z "$url" ]]; then
            echo "No compatible 32-bit (x86) Vanilla download found for version ${version}."
            continue
        fi

        version_dir="${INSTALL_DIR}wine-${version}"
        mkdir -p "$version_dir"
        cd "$version_dir" || { echo "Failed to change directory."; exit 1; }

        local filename=$(basename "$url")
        echo "Downloading 32-bit Vanilla Wine ${version} from $url"
        wget -q --tries=10 --no-check-certificate --no-cache --no-cookies --show-progress -O "$filename" "$url"

        if [ -f "$filename" ]; then
            echo "Unpacking 32-bit Vanilla Wine ${version}..."
            tar --strip-components=1 -xf "$filename"
            rm "$filename"
            echo "Installation of 32-bit Vanilla Wine ${version} complete."
        else
            echo "Failed to download 32-bit Vanilla Wine ${version}."
        fi
        cd - >/dev/null
    done

    echo "All selected 32-bit Vanilla builds have been processed."
}

###############################
# Function: Wine-TKG-Staging Builds #
###############################
download_wine_tkg_32bit() {
    local REPO_URL="https://api.github.com/repos/Kron4ek/Wine-Builds/releases?per_page=300"
    echo "Fetching 32-bit Wine TKG-Staging release information..."
    local release_data
    release_data=$(curl -s "$REPO_URL")
    if [[ $? -ne 0 || -z "$release_data" ]]; then
        echo "Failed to fetch release data."
        exit 1
    fi

    local menu_cmd=(dialog --separate-output --checklist "Select 32-bit Wine TKG-Staging builds to download (contains x86, staging-tkg):" 22 76 16)
    local options=()
    local i=0

    while IFS= read -r line; do
        local name tag
        name=$(echo "$line" | jq -r '.name')
        tag=$(echo "$line" | jq -r '.tag_name')

        # Check if there's a staging-tkg-x86 asset
        local tkg_asset
        tkg_asset=$(echo "$line" | jq -r ".assets[] 
                    | select(.name | contains(\"staging-tkg\") and contains(\"x86\")) 
                    | .name" | head -n1)

        # If there's a matching asset, add to the menu
        if [ -n "$tkg_asset" ]; then
            options+=("$i" "${name} - ${tag}" off)
            ((i++))
        fi
    done < <(echo "$release_data" | jq -c '.[]')

    local choices
    choices=$("${menu_cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
    clear

    # Download and extract selected TKG-Staging releases
    for choice in $choices; do
        local version url output_folder
        version=$(echo "$release_data" | jq -r ".[$choice].tag_name")

        url=$(echo "$release_data" | jq -r ".[$choice].assets[]
               | select(.name | contains(\"staging-tkg\") and contains(\"x86\"))
               | .browser_download_url" | head -n1)

        if [[ -z "$url" ]]; then
            echo "No compatible 32-bit Wine TKG-Staging download found for version ${version}."
            continue
        fi

        output_folder="${INSTALL_DIR}wine-${version}-staging-tkg"
        mkdir -p "$output_folder"
        cd "$output_folder" || { echo "Failed to change directory."; exit 1; }

        local filename=$(basename "$url")
        echo "Downloading 32-bit Wine TKG-Staging ${version} from $url"
        wget -q --tries=10 --no-check-certificate --no-cache --no-cookies --show-progress -O "$filename" "$url"

        if [ -f "$filename" ]; then
            echo "Unpacking 32-bit Wine TKG-Staging ${version}..."
            tar --strip-components=1 -xf "$filename"
            rm "$filename"
            echo "Installation of 32-bit Wine TKG-Staging ${version} complete."
        else
            echo "Failed to download 32-bit Wine TKG-Staging ${version}."
        fi
        cd - >/dev/null
    done

    echo "All selected 32-bit Wine TKG-Staging builds have been processed."
}

###############################
# Main Menu Function          #
###############################
main_menu() {
    local menu_cmd=(dialog --clear --title "Rocknix 32-bit Wine Downloader" --menu "Select a build category to download:" 15 60 3)
    local options=(
        1 "Standard (Vanilla) Builds"
        2 "Wine-TKG-Staging Builds"
        3 "Exit"
    )
    local choice
    choice=$("${menu_cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
    clear
    case $choice in
        1) download_vanilla_32bit ;;
        2) download_wine_tkg_32bit ;;
        3) echo "Exiting." && exit 0 ;;
        *) echo "Invalid selection. Exiting." && exit 1 ;;
    esac
}

# Main loop
while true; do
    main_menu
    echo "Returning to main menu..."
done
