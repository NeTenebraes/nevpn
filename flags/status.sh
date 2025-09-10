#!/bin/bash
# Status Module

show_status() {
	echo -e "\n${GREEN}--- Current Status ---${NC}"
	local vpn_active=false
	echo -e "${YELLOW}VPN Status:${NC}"
	openvpn_pids=$(pgrep openvpn)
	if [ -n "$openvpn_pids" ]; then
		vpn_active=true
		for pid in $openvpn_pids; do
			local config_file
			config_file=$(ps -p "$pid" -o cmd= | grep -oP -- '--config \K[^\s]+')
			echo -e "  - ${GREEN}CONNECTED${NC} (OpenVPN)"
			echo -e "    └─ Using config: ${YELLOW}$config_file${NC}"
		done
	fi
	active_wg_interfaces=$(sudo wg show interfaces 2>/dev/null)
	if [ -n "$active_wg_interfaces" ]; then
		vpn_active=true
		for interface in $active_wg_interfaces; do
			local symlink_path="/etc/wireguard/$interface.conf"
			local original_config="<unknown>"
			if [ -L "$symlink_path" ]; then
				original_config=$(readlink -f "$symlink_path")
			fi
			echo -e "  - ${GREEN}CONNECTED${NC} (WireGuard)"
			echo -e "    ├─ Interface: ${YELLOW}$interface${NC}"
			echo -e "    └─ Using config: ${YELLOW}$original_config${NC}"
		done
	fi
	if [ "$vpn_active" = false ]; then
		echo -e "  - ${RED}DISCONNECTED${NC}"
	fi
	echo -e "\n${YELLOW}Proxy Status:${NC}"
	if [ -n "$http_proxy" ]; then
		local proxy_ip
		proxy_ip=$(echo "$http_proxy" | sed -E 's_.*//([^:]+):.*_\1_')
		local proxy_port
		proxy_port=$(echo "$http_proxy" | sed -E 's_.*:([0-9]+).*_\1_')
		echo -e "  - ${GREEN}ACTIVE${NC}"
		echo -e "    ├─ IP:   ${YELLOW}$proxy_ip${NC}"
		echo -e "    └─ Port: ${YELLOW}$proxy_port${NC}"
	else
		echo -e "  - ${RED}INACTIVE${NC}"
	fi
	echo -e "\n${YELLOW}Public IP Information:${NC}"
	curl ipinfo.io
	echo "--------------------------"
}
