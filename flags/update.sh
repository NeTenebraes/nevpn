#!/bin/bash
# Update Module

check_for_updates() {
	local force_check=$1
	local timestamp_file="$CONFIG_DIR/.last_update_check"
	local check_interval=86400
	local current_time
	current_time=$(date +%s)
	local last_check_time=0
	if [ -f "$timestamp_file" ]; then last_check_time=$(cat "$timestamp_file"); fi
	local time_diff=$((current_time - last_check_time))
	if [[ "$force_check" == "force" || "$time_diff" -gt "$check_interval" ]]; then
		if [[ "$force_check" == "force" ]]; then echo -e "\n🔄 ${YELLOW}Forcing update check against GitHub...${NC}"; else echo -e "\n🔄 ${YELLOW}Checking for updates (last check was more than 24h ago)...${NC}"; fi
		cd "$CONFIG_DIR" || return
		if ! git fetch; then
			echo -e "❌ ${RED}Update check failed: Could not connect to remote repository.${NC}"
			cd - >/dev/null
			return 1
		fi
		local LOCAL_HASH
		LOCAL_HASH=$(git rev-parse HEAD)
		local REMOTE_HASH
		REMOTE_HASH=$(git rev-parse origin/main)
		echo "$current_time" >"$timestamp_file"
		if [ "$LOCAL_HASH" != "$REMOTE_HASH" ]; then
			local LATEST_COMMIT_MSG
			LATEST_COMMIT_MSG=$(git log -2 --pretty=%B origin/main)
			local CHANGELOG_URL="https://github.com/NeTenebraes/nevpn/commits/main"
			echo -e "💡 ${GREEN}An update for nevpn is available!${NC}"
			echo -e "\n${YELLOW}Latest change:${NC}"
			echo -e "--------------------------------------------------\n${LATEST_COMMIT_MSG}\n--------------------------------------------------"
			echo -e "View all changes here: ${CHANGELOG_URL}\n"
			read -p "Do you want to update now? (Y/N): " choice
			case "$choice" in y | Y)
				run_update
				return 0
				;;
			*) echo -e "${YELLOW}Okay, you can update later by running 'nevpn -Up'.${NC}" ;; esac
		else echo -e "✅ ${GREEN}Your script is already up to date.${NC}"; fi
		cd - >/dev/null
	fi
}

run_update() {
	echo -e "${GREEN}Updating NeVPN & Proxy Manager...${NC}"
	cd "$CONFIG_DIR" || return
	echo -e "\n${YELLOW}Step 1: Fetching latest version from GitHub...${NC}"
	if ! git fetch --all; then
		echo -e "❌ ${RED}Error: Could not fetch updates from GitHub. Please check your internet connection.${NC}"
		return 1
	fi
	echo -e "${YELLOW}Step 2: Forcing local files to match the latest version...${NC}"
	echo "         (Note: Any local modifications to the script files will be overwritten!)"
	if ! git reset --hard origin/main; then
		echo -e "❌ ${RED}Error: Could not reset the local repository. Please check file permissions.${NC}"
		return 1
	fi
	echo -e "${GREEN}Files updated successfully.${NC}"
	echo -e "\n${YELLOW}Step 3: Re-running installer to apply changes...${NC}"
	if [ -f "install.sh" ]; then
		bash install.sh
		local shell_config_file=""
		if [ -n "$BASH_VERSION" ]; then shell_config_file="$HOME/.bashrc"; elif [ -n "$ZSH_VERSION" ]; then shell_config_file="$HOME/.zshrc"; fi
		if [ -n "$shell_config_file" ] && [ -f "$shell_config_file" ]; then
			echo -e "\n${GREEN}Applying changes to the current terminal session...${NC}"
			source "$shell_config_file"
			echo -e "✅ ${GREEN}Update complete! The new version is ready to use.${NC}"
		else echo -e "\n${GREEN}✅ Update complete! Please restart your terminal to use the new version.${NC}"; fi
	else echo -e "❌ ${RED}Error: install.sh not found. Cannot complete the update.${NC}"; fi
}
