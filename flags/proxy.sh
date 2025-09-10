#!/bin/bash
# Proxy Functions Module

manage_proxy() {
	if [ -f "$CONFIG_FILE" ] && [ -s "$CONFIG_FILE" ]; then
		local LAST_IP
		LAST_IP=$(grep '^LAST_IP=' "$CONFIG_FILE" | cut -d'=' -f2)
		local LAST_PORT
		LAST_PORT=$(grep '^LAST_PORT=' "$CONFIG_FILE" | cut -d'=' -f2)
		if [ -n "$LAST_IP" ] && [ -n "$LAST_PORT" ]; then
			echo -e "${YELLOW}Last saved config: IP=${LAST_IP} Port=${LAST_PORT}${NC}"
			read -p "Use this configuration? (y/n): " choice
			if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
				PROXY_IP=$LAST_IP
				PROXY_PORT=$LAST_PORT
				return
			fi
		fi
	fi
	read -p "Enter the new proxy IP: " PROXY_IP
	read -p "Enter the new proxy port: " PROXY_PORT
	if [ -n "$PROXY_IP" ] && [ -n "$PROXY_PORT" ]; then
		echo "LAST_IP=${PROXY_IP}" >"$CONFIG_FILE"
		echo "LAST_PORT=${PROXY_PORT}" >>"$CONFIG_FILE"
	fi
}

proxy_on() {
	manage_proxy
	if [ -n "$PROXY_IP" ] && [ -n "$PROXY_PORT" ]; then
		PROXY_URL="http://${PROXY_IP}:${PROXY_PORT}"
		export http_proxy="$PROXY_URL" https_proxy="$PROXY_URL" ftp_proxy="$PROXY_URL"
		export no_proxy="localhost,127.0.0.1"
		export HTTP_PROXY="$PROXY_URL" HTTPS_PROXY="$PROXY_URL" FTP_PROXY="$PROXY_URL"
		export NO_PROXY="localhost,127.0.0.1"
		echo -e "${GREEN}✅ Proxy Activated: ${PROXY_URL}${NC}"
	else
		echo -e "${RED}Operation canceled.${NC}"
	fi
}

proxy_off() {
	unset http_proxy https_proxy ftp_proxy no_proxy
	unset HTTP_PROXY HTTPS_PROXY FTP_PROXY NO_PROXY
	echo -e "${RED}❌ Proxy Deactivated.${NC}"
}
