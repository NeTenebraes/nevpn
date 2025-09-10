#!/bin/bash
# VPN Functions Module

connect_vpn() {
	if pgrep -x openvpn >/dev/null || [ -n "$(sudo wg show interfaces 2>/dev/null)" ]; then
		echo -e "${YELLOW}An active VPN connection was detected. Please use 'nevpn -Voff' first.${NC}"
		return 1
	fi
	echo "Select the VPN type:"
	select vpn_type in "WireGuard" "OpenVPN" "Cancel"; do case $vpn_type in WireGuard)
		config_files=("$WIREGUARD_DIR"/*.conf)
		if [ ${#config_files[@]} -eq 0 ] || [ ! -f "${config_files[0]}" ]; then
			echo -e "${RED}No WireGuard configuration files (.conf) found in '$WIREGUARD_DIR'.${NC}"
			return 1
		fi
		echo "Select a WireGuard configuration:"
		select wg_config in "${config_files[@]}"; do if [ -n "$wg_config" ]; then
			local base_name
			base_name=$(basename "$wg_config" .conf)
			local safe_iface_name
			safe_iface_name=$(echo "$base_name" | sed -e 's/[^a-zA-Z0-9_-]/-/g' | cut -c1-15)
			local symlink_path="/etc/wireguard/$safe_iface_name.conf"
			echo -e "${YELLOW}Preparing secure interface '$safe_iface_name'...${NC}"
			sudo ln -sf "$wg_config" "$symlink_path"
			echo -e "${YELLOW}Attempting to connect with '$wg_config'...${NC}"
			if sudo wg-quick up "$safe_iface_name"; then echo -e "${GREEN}WireGuard connected successfully as '$safe_iface_name'.${NC}"; else
				echo -e "${RED}Connection failed. Cleaning up...${NC}"
				sudo rm -f "$symlink_path"
			fi
			break
		else echo "Invalid selection."; fi; done
		break
		;;
	OpenVPN)
		config_files=("$OPENVPN_DIR"/*.ovpn)
		if [ ${#config_files[@]} -eq 0 ] || [ ! -f "${config_files[0]}" ]; then
			echo -e "${RED}No OpenVPN configuration files (.ovpn) found in '$OPENVPN_DIR'.${NC}"
			return 1
		fi
		echo "Select an OpenVPN configuration:"
		select ovpn_config in "${config_files[@]}"; do if [ -n "$ovpn_config" ]; then
			echo -e "${YELLOW}Connecting with $ovpn_config in the background...${NC}"
			sudo openvpn --config "$ovpn_config" --daemon
			sleep 3
			echo -e "${GREEN}OpenVPN connected successfully.${NC}"
			break
		else echo "Invalid selection."; fi; done
		break
		;;
	"Cancel")
		echo "Operation canceled."
		break
		;;
	*) echo "Invalid option. Please choose 1, 2, or 3." ;; esac done
}

disconnect_vpn() {
	echo -e "${YELLOW}Attempting to disconnect all VPN connections...${NC}"
	if pgrep -x openvpn >/dev/null; then
		sudo killall openvpn
		echo -e "${GREEN}OpenVPN connections stopped.${NC}"
	fi
	active_wg_interfaces=$(sudo wg show interfaces 2>/dev/null)
	if [ -n "$active_wg_interfaces" ]; then
		for interface in $active_wg_interfaces; do
			echo "Bringing down interface: $interface..."
			local symlink_path="/etc/wireguard/$interface.conf"
			if sudo wg-quick down "$interface"; then echo "Interface '$interface' is down."; else
				echo -e "${YELLOW} 'wg-quick down' failed, attempting forceful removal...${NC}"
				sudo ip link delete dev "$interface"
			fi
			if [ -L "$symlink_path" ]; then
				echo "Cleaning up temporary configuration for '$interface'..."
				sudo rm -f "$symlink_path"
			fi
		done
		echo -e "${GREEN}All WireGuard connections stopped.${NC}"
	fi
	echo -e "\n${GREEN}✅ Disconnection process complete.${NC}"
}
