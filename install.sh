#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- CONFIGURATION ---
REPO_URL="https://github.com/NeTenebraes/nevpn.git"
INSTALL_DIR="$HOME/.nevpn"

# --- TERMINAL COLORS ---
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
NC="\033[0m"

# --- UNINSTALL FUNCTION ---
uninstall() {
    # ... (la función de desinstalación no cambia) ...
    echo -e "${YELLOW}Uninstalling NeVPN & Proxy Manager...${NC}"; if [ -d "$INSTALL_DIR" ]; then rm -rf "$INSTALL_DIR"; echo "Removed directory: $INSTALL_DIR"; fi; for shell_config in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_profile"; do if [ -f "$shell_config" ]; then sed -i.bak "/# NeVPN & Proxy Manager command/,/}/d" "$shell_config"; sed -i.bak "/# Load .bashrc if it exists/,/fi/d" "$shell_config"; echo "Cleaned up: $shell_config"; fi; done; echo "You may be asked for your password to clean up system files..."; sudo find /etc/wireguard -type l -lname "$INSTALL_DIR/wireguard_configs/*" -exec rm {} \; &>/dev/null || true; echo "Cleanup of system links attempted."; echo -e "\n${GREEN}✅ Uninstallation complete.${NC}"; echo "Please restart your terminal for changes to take full effect."; exit 0
}

# --- INTERACTIVE DEPENDENCY INSTALLER ---
install_dependencies() {
    # ... (la función de dependencias no cambia) ...
    echo -e "\n${YELLOW}Step 1: Checking for required dependencies...${NC}"; local required_cmds=("git" "curl" "openvpn" "wg"); local missing_deps=(); for cmd in "${required_cmds[@]}"; do if ! command -v "$cmd" &>/dev/null; then missing_deps+=("$cmd"); fi; done; if [ ${#missing_deps[@]} -eq 0 ]; then echo "✅ All dependencies are already installed."; return 0; fi; echo -e "⚠️ The following dependencies are missing: ${RED}${missing_deps[*]}${NC}"; local install_command=""; local packages_to_install=""; echo -e "\nPlease select your package manager to attempt automatic installation:"; PS3="Choose an option: "; select pm in "apt (Debian/Ubuntu)" "pacman (Arch Linux)" "dnf (Fedora/CentOS)" "Skip / I will install them manually"; do case $pm in "apt (Debian/Ubuntu)") for dep in "${missing_deps[@]}"; do packages_to_install+=" $(case "$dep" in "wg") echo "wireguard-tools";; *) echo "$dep";; esac)"; done; install_command="sudo apt-get update && sudo apt-get install -y$packages_to_install"; break;; "pacman (Arch Linux)") for dep in "${missing_deps[@]}"; do packages_to_install+=" $(case "$dep" in "wg") echo "wireguard-tools";; *) echo "$dep";; esac)"; done; install_command="sudo pacman -Syu --noconfirm$packages_to_install"; break;; "dnf (Fedora/CentOS)") for dep in "${missing_deps[@]}"; do packages_to_install+=" $(case "$dep" in "wg") echo "wireguard-tools";; *) echo "$dep";; esac)"; done; install_command="sudo dnf install -y$packages_to_install"; break;; "Skip / I will install them manually") echo -e "${YELLOW}Skipping automatic installation. Please install the missing packages and run the script again.${NC}"; exit 1;; *) echo "Invalid option. Please try again.";; esac; done; if [ -n "$install_command" ]; then echo -e "\n${YELLOW}The following command will be executed to install the packages:${NC}"; echo -e "    $install_command"; read -p "Do you want to run this command now? (y/n): " choice; if [[ "$choice" == "y" || "$choice" == "Y" ]]; then eval "$install_command"; else echo "${RED}Installation aborted by user.${NC}"; exit 1; fi; fi; echo -e "\n${YELLOW}Verifying installation...${NC}"; for cmd in "${missing_deps[@]}"; do if ! command -v "$cmd" &>/dev/null; then echo -e "❌ ${RED}Error: Dependency '$cmd' could not be installed. Please install it manually and try again.${NC}" >&2; exit 1; fi; done; echo "✅ All dependencies are now successfully installed."
}


# --- SCRIPT EXECUTION ---
if [[ "$1" == "--uninstall" ]]; then
    uninstall
fi

echo -e "${GREEN}Installing NeVPN & Proxy Manager...${NC}"

# Step 1: Check and install dependencies
install_dependencies

# Steps 2 & 3 (Cloning and creating directories, no changes)
echo -e "\n${YELLOW}Step 2: Cloning/updating repository in $INSTALL_DIR...${NC}"; if [ -d "$INSTALL_DIR" ]; then echo "Existing installation found. Forcing update to the latest version..."; cd "$INSTALL_DIR"; git fetch --all; git reset --hard origin/main; cd - >/dev/null; else git clone "$REPO_URL" "$INSTALL_DIR"; fi; echo "✅ Repository is up to date."
echo -e "\n${YELLOW}Step 3: Verifying configuration directories...${NC}"; mkdir -p "$INSTALL_DIR/flags"; mkdir -p "$INSTALL_DIR/openvpn_configs"; mkdir -p "$INSTALL_DIR/wireguard_configs"; echo "✅ Directories are ready."


# --- Step 4: Setup the 'nevpn' command (NOW MORE ROBUST) ---
echo -e "\n${YELLOW}Step 4: Setting up the 'nevpn' command...${NC}"
SHELL_CONFIG=""
if [ -n "$BASH_VERSION" ]; then
	SHELL_CONFIG="$HOME/.bashrc"
elif [ -n "$ZSH_VERSION" ]; then
	SHELL_CONFIG="$HOME/.zshrc"
fi

if [ -n "$SHELL_CONFIG" ]; then
    # --- NEW: BASH_PROFILE FIX ---
    # If using bash and .bash_profile exists, ensure it sources .bashrc
    # This makes the install compatible with more Linux distributions (like Arch)
    if [[ "$SHELL_CONFIG" == "$HOME/.bashrc" && -f "$HOME/.bash_profile" ]]; then
        if ! grep -q 'source ~/.bashrc' "$HOME/.bash_profile"; then
            echo -e "${YELLOW}Found ~/.bash_profile. Adding a line to source ~/.bashrc to ensure 'nevpn' is always available...${NC}"
            echo -e '\n# Load .bashrc if it exists for interactive shells\nif [ -f ~/.bashrc ]; then\n    source ~/.bashrc\nfi' >> "$HOME/.bash_profile"
        fi
    fi
    # --- END OF FIX ---

    if ! [ -w "$SHELL_CONFIG" ]; then
        echo -e "❌ ${RED}Error: Cannot write to '$SHELL_CONFIG'. Please check permissions.${NC}" >&2
        exit 1
    fi
    
	sed -i.bak "/# NeVPN & Proxy Manager command/,/}/d" "$SHELL_CONFIG"

	cat >>"$SHELL_CONFIG" <<'EOF'

# NeVPN & Proxy Manager command
nevpn() {
    # Source the function library to make them available in the current shell
    if [ -f "$HOME/.nevpn/nevpn.sh" ]; then
        source "$HOME/.nevpn/nevpn.sh"
    else
        echo "Error: nevpn library not found at $HOME/.nevpn/nevpn.sh"
        return 1
    fi
    # Pass all arguments to the main handler function
    nevpn_handler "$@"
}
EOF
	echo "✅ Command 'nevpn' has been added to '$SHELL_CONFIG'."
else
    echo "⚠️ ${YELLOW}Could not detect .bashrc or .zshrc. Please add the 'nevpn' function manually.${NC}"
fi

# --- FINAL INSTRUCTIONS ---
echo -e "\n${GREEN}🎉 Installation complete! 🎉${NC}"
echo -e "\nTo start using the command, please restart your terminal or run:"
echo -e "   ${YELLOW}source $SHELL_CONFIG${NC}"
echo -e "\nThen, just type ${GREEN}nevpn -h${NC} to see the usage instructions."