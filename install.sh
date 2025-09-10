#!/bin/bash

# --- CONFIGURATION ---
REPO_URL="https://github.com/NeTenebraes/nevpn.git"
INSTALL_DIR="$HOME/.nevpn"

# --- TERMINAL COLORS ---
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
NC="\033[0m"

echo -e "${GREEN}Installing NeVPN & Proxy Manager...${NC}"

# Step 1: Check dependencies
echo -e "\n${YELLOW}Step 1: Checking for dependencies...${NC}"
command -v git >/dev/null 2>&1 || {
	echo -e "${RED}Error: 'git' is not installed. Please install it to continue.${NC}" >&2
	exit 1
}
echo "Dependencies found."

# Step 2: Clone or update the repository
echo -e "\n${YELLOW}Step 2: Cloning repository into $INSTALL_DIR...${NC}"
if [ -d "$INSTALL_DIR" ]; then
	echo "Existing installation found. Pulling latest changes..."
	(cd "$INSTALL_DIR" && git pull)
else
	git clone "$REPO_URL" "$INSTALL_DIR" || {
		echo -e "${RED}Error: Could not clone repository.${NC}" >&2
		exit 1
	}
fi

# Step 3: Create configuration directories
echo -e "\n${YELLOW}Step 3: Creating configuration directories...${NC}"
mkdir -p "$INSTALL_DIR/openvpn_configs"
mkdir -p "$INSTALL_DIR/wireguard_configs"
echo "Configuration directories are ready."

# Step 4: Setup the 'nevpn' command function
echo -e "\n${YELLOW}Step 4: Setting up the 'nevpn' command...${NC}"
SHELL_CONFIG=""
if [ -n "$BASH_VERSION" ]; then
	SHELL_CONFIG="$HOME/.bashrc"
elif [ -n "$ZSH_VERSION" ]; then
	SHELL_CONFIG="$HOME/.zshrc"
fi

if [ -n "$SHELL_CONFIG" ]; then
	# Remove any old configuration to prevent duplicates
	sed -i.bak "/# NeVPN & Proxy Manager command/,/}/d" "$SHELL_CONFIG"

	# Add the new dispatcher function to the shell config file
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
	echo "Command 'nevpn' has been added to $SHELL_CONFIG."
fi

# --- FINAL INSTRUCTIONS ---
echo -e "\n${GREEN}🎉 Installation complete! 🎉${NC}"
echo -e "\nTo start using the command, please restart your terminal or run:"
echo -e "   ${YELLOW}source $SHELL_CONFIG${NC}"
echo -e "\nThen, just type ${GREEN}nevpn${NC} to see the usage instructions."