#!/bin/bash
#
# NeVPN & Proxy Manager
# Main entry point script.
# This script loads all modules and handles user commands.

# --- GLOBAL CONFIGURATION & CONSTANTS ---
export CONFIG_DIR="$HOME/.nevpn"
export CONFIG_FILE="$CONFIG_DIR/proxy_config.conf"
export OPENVPN_DIR="$CONFIG_DIR/openvpn_configs"
export WIREGUARD_DIR="$CONFIG_DIR/wireguard_configs"

# TERMINAL COLORS
export GREEN="\033[0;32m"
export YELLOW="\033[0;33m"
export RED="\033[0;31m"
export NC="\033[0m"

# --- LOAD MODULES ---
# Source all function files from the 'flags' directory.
source "$CONFIG_DIR/flags/help.sh"
source "$CONFIG_DIR/flags/proxy.sh"
source "$CONFIG_DIR/flags/vpn.sh"
source "$CONFIG_DIR/flags/status.sh"
source "$CONFIG_DIR/flags/update.sh"

# --- MAIN COMMAND HANDLER ---
nevpn_handler() {
	# On normal execution, run the periodic check (will skip if it's not time)
	if [[ "$1" != "-Up" && "$1" != "" && "$1" != "-h" && "$1" != "--help" ]]; then
		check_for_updates
	fi

	# Handle the user's command
	case "$1" in
	-S)
		show_status
		;;
	-Pon)
		proxy_on
		;;
	-Poff)
		proxy_off
		;;
	-Von)
		connect_vpn
		;;
	-Voff)
		disconnect_vpn
		;;
	-Up)
		check_for_updates "force"
		;;
	"-h" | "--help")
		nevpn_help
		;;
	"")
		echo -e "${RED}Error: a flag is required.${NC} Use '-h' or '--help' for usage information."
		return 1
		;;
	*)
		echo -e "\n${RED}Error: Invalid argument '$1'.${NC} Use '-h' or '--help' for usage information."
		return 1
		;;
	esac
}
