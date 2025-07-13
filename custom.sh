#!/bin/bash
# Rocknix Combined Builds Downloader
# Downloads custom Wine/Proton builds to /storage/winecustom/

# Base directory for custom builds
INSTALL_DIR="/storage/winecustom/"
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
download_vanilla() {
    # Vanilla builds from the Kron4ek/Wine-Builds repository
    local REPO_URL="https://api.github.com/repos/Kron4ek/Wine-Builds/releases?per_page=300"
    echo "Fetching Vanilla release information..."
    local release_data
    release_data=$(curl -s "$REPO_URL")
    if [[ $? -ne 0 || -z "$release_data" ]]; then
        echo "Failed to fetch Vanilla release data."
        exit 1
    fi

    local menu_cmd=(dialog --separate-output --checklist "Select Vanilla Wine builds to download:" 22 76 16)
    local options=()
    local i=1

    while IFS= read -r line; do
        local name tag description
        name=$(echo "$line" | jq -r '.name')
        tag=$(echo "$line" | jq -r '.tag_name')
        description="${name} - ${tag}"
        options+=("$i" "$description" off)
        ((i++))
    done < <(echo "$release_data" | jq -c '.[]')

    local choices
    choices=$("${menu_cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
    clear

    for choice in $choices; do
        local version url version_dir
        version=$(echo "$release_data" | jq -r ".[$choice-1].tag_name")
        url=$(echo "$release_data" | jq -r ".[$choice-1].assets[] | select(.name | endswith(\"amd64.tar.xz\")).browser_download_url" | head -n1)

        version_dir="${INSTALL_DIR}wine-${version}"
        mkdir -p "$version_dir"
        cd "$version_dir" || { echo "Failed to change directory."; exit 1; }

        echo "Downloading Vanilla Wine ${version} from $url"
        wget -q --tries=10 --no-check-certificate --no-cache --no-cookies --show-progress -O "${version_dir}/wine-${version}.tar.xz" "$url"

        if [ -f "${version_dir}/wine-${version}.tar.xz" ]; then
            echo "Unpacking Vanilla Wine ${version}..."
            tar --strip-components=1 -xf "${version_dir}/wine-${version}.tar.xz"
            rm "wine-${version}.tar.xz"
            echo "Installation of Vanilla Wine ${version} complete."
        else
            echo "Failed to download Vanilla Wine ${version}."
        fi
        cd - >/dev/null
    done

    echo "All selected Vanilla builds have been processed."
}

###############################
# Function: Wine-TKG Builds  #
###############################
download_wine_tkg() {
    local REPO_URL="https://api.github.com/repos/Kron4ek/Wine-Builds/releases?per_page=300"
    echo "Fetching Wine TKG-Staging release information..."
    local release_data
    release_data=$(curl -s "$REPO_URL")
    if [[ $? -ne 0 || -z "$release_data" ]]; then
        echo "Failed to fetch Wine TKG-Staging release data."
        exit 1
    fi

    local menu_cmd=(dialog --separate-output --checklist "Select Wine TKG-Staging versions to download:" 22 76 16)
    local options=()
    local i=1

    while IFS= read -r line; do
        local name tag description tkg_staging_assets
        name=$(echo "$line" | jq -r '.name')
        tag=$(echo "$line" | jq -r '.tag_name')
        description="${name} - ${tag}"
        tkg_staging_assets=$(echo "$line" | jq -c '.assets[] | select(.name | contains("staging-tkg"))')
        if [ -n "$tkg_staging_assets" ]; then
            options+=("$i" "$description" off)
            ((i++))
        fi
    done < <(echo "$release_data" | jq -c '.[]')

    local choices
    choices=$("${menu_cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
    clear

    for choice in $choices; do
        local version url output_folder
        version=$(echo "$release_data" | jq -r ".[$choice-1].tag_name")
        url=$(echo "$release_data" | jq -r ".[$choice-1].assets[] | select(.name | contains(\"staging-tkg\") and endswith(\"amd64.tar.xz\")).browser_download_url" | head -n1)

        if [[ -z "$url" ]]; then
            echo "No compatible download found for Wine TKG-Staging ${version}."
            continue
        fi

        output_folder="${INSTALL_DIR}wine-${version}-staging-tkg"
        mkdir -p "$output_folder"
        cd "$output_folder" || { echo "Failed to change directory."; exit 1; }

        echo "Downloading Wine TKG-Staging ${version} from $url"
        wget -q --tries=10 --no-check-certificate --no-cache --no-cookies --show-progress -O "${output_folder}/wine-${version}-staging-tkg.tar.xz" "$url"

        if [ -f "${output_folder}/wine-${version}-staging-tkg.tar.xz" ]; then
            echo "Unpacking Wine TKG-Staging ${version}..."
            tar --strip-components=1 -xf "${output_folder}/wine-${version}-staging-tkg.tar.xz"
            rm "wine-${version}-staging-tkg.tar.xz"
            echo "Installation of Wine TKG-Staging ${version} complete."
        else
            echo "Failed to download Wine TKG-Staging ${version}."
        fi
        cd - >/dev/null
    done

    echo "All selected Wine TKG-Staging versions have been processed."
}

###############################
# Function: Wine-GE Builds   #
###############################
download_wine_ge() {
    dialog --msgbox "Note: Testing has shown Wine-GE versions above 8.15 appear broken on Batocera." 7 60

    local REPO_URL="https://api.github.com/repos/GloriousEggroll/wine-ge-custom/releases?per_page=100"
    echo "Fetching Wine-GE release information..."
    local release_data
    release_data=$(curl -s "$REPO_URL")
    if [[ $? -ne 0 || -z "$release_data" ]]; then
        echo "Failed to fetch Wine-GE release data."
        exit 1
    fi

    local menu_cmd=(dialog --separate-output --checklist "Select Wine-GE versions to download:" 22 76 16)
    local options=()
    local i=1

    while IFS= read -r line; do
        local name tag description
        name=$(echo "$line" | jq -r '.name')
        tag=$(echo "$line" | jq -r '.tag_name')
        description="${name} - ${tag}"
        options+=("$i" "$description" off)
        ((i++))
    done < <(echo "$release_data" | jq -c '.[]')

    local choices
    choices=$("${menu_cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
    clear

    for choice in $choices; do
        local version url version_dir
        version=$(echo "$release_data" | jq -r ".[$choice-1].tag_name")
        url=$(echo "$release_data" | jq -r ".[$choice-1].assets[] | select(.name | endswith(\"x86_64.tar.xz\")).browser_download_url" | head -n1)

        if [[ -z "$url" ]]; then
            echo "No compatible download found for Wine-GE ${version}."
            continue
        fi

        version_dir="${INSTALL_DIR}wine-${version}"
        mkdir -p "$version_dir"
        cd "$version_dir" || { echo "Failed to change directory."; exit 1; }

        echo "Downloading Wine-GE ${version} from $url"
        wget -q --tries=10 --no-check-certificate --no-cache --no-cookies --show-progress -O "${version_dir}/wine-${version}.tar.xz" "$url"

        if [ -f "${version_dir}/wine-${version}.tar.xz" ]; then
            echo "Unpacking Wine-GE ${version}..."
            tar --strip-components=1 -xf "${version_dir}/wine-${version}.tar.xz"
            rm "wine-${version}.tar.xz"
            echo "Installation of Wine-GE ${version} complete."
        else
            echo "Failed to download Wine-GE ${version}."
        fi
        cd - >/dev/null
    done

    echo "All selected Wine-GE versions have been processed."
}

###############################
# Function: Proton-GE Builds #
###############################
download_proton_ge() {
    local REPO_URL="https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases?per_page=100"
    echo "Fetching Proton-GE release information..."
    local release_data
    release_data=$(curl -s "$REPO_URL")
    if [[ $? -ne 0 || -z "$release_data" ]]; then
        echo "Failed to fetch Proton-GE release data."
        exit 1
    fi

    local menu_cmd=(dialog --separate-output --checklist "Select Proton-GE versions to download:" 22 76 16)
    local options=()
    local i=1

    while IFS= read -r line; do
        local name tag description
        name=$(echo "$line" | jq -r '.name')
        tag=$(echo "$line" | jq -r '.tag_name')
        description="${name} - ${tag}"
        options+=("$i" "$description" off)
        ((i++))
    done < <(echo "$release_data" | jq -c '.[]')

    local choices
    choices=$("${menu_cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
    clear

    for choice in $choices; do
        local version url version_dir
        version=$(echo "$release_data" | jq -r ".[$choice-1].tag_name")
        url=$(echo "$release_data" | jq -r ".[$choice-1].assets[] | select(.name | endswith(\".tar.gz\")).browser_download_url" | head -n1)

        if [[ -z "$url" ]]; then
            echo "No compatible download found for Proton-GE ${version}."
            continue
        fi

        version_dir="${INSTALL_DIR}proton-${version}"
        mkdir -p "$version_dir"
        cd "$version_dir" || { echo "Failed to change directory."; exit 1; }

        echo "Downloading Proton-GE ${version} from $url"
        wget -q --tries=10 --no-check-certificate --no-cache --no-cookies --show-progress -O "${version_dir}/proton-${version}.tar.gz" "$url"

        if [ -f "${version_dir}/proton-${version}.tar.gz" ]; then
            echo "Unpacking Proton-GE ${version}..."
            tar -xzf "${version_dir}/proton-${version}.tar.gz" --strip-components=1
            if [ "$(ls -A "$version_dir")" ]; then
                echo "Unpacking successful."
                rm "proton-${version}.tar.gz"
                if [ -d "${version_dir}/files" ]; then
                    echo "Moving files from 'files' folder to parent directory..."
                    mv "${version_dir}/files/"* "${version_dir}/"
                    rmdir "${version_dir}/files"
                    echo "'files' folder processed and deleted."
                fi
            else
                echo "Unpacking failed, directory is empty."
            fi
            echo "Installation of Proton-GE ${version} complete."
        else
            echo "Failed to download Proton-GE ${version}."
        fi
        cd - >/dev/null
    done

    echo "All selected Proton-GE versions have been processed."
}

###############################
# Main Menu Function          #
###############################
main_menu() {
    local menu_cmd=(dialog --clear --title "Rocknix Wine Downloader" --menu "Select a build category to download:" 15 60 5)
    local options=(1 "Standard (Vanilla) Builds" 2 "Wine-TKG-Staging Builds" 3 "Exit")
    local choice
    choice=$("${menu_cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
    clear
    case $choice in
        1) download_vanilla ;;
        2) download_wine_tkg ;;
        #3) download_wine_ge ;;
        #4) download_proton_ge ;;
        3) echo "Exiting." && exit 0 ;;
        *) echo "Invalid selection. Exiting." && exit 1 ;;
    esac
}

# Main loop
while true; do
    main_menu
    echo "Returning to main menu..."
done
