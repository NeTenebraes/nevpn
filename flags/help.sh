#!/bin/bash
# Help Module

nevpn_help() {
	echo -e 	"${GREEN}NeVPN & Proxy Manager - Usage:${NC}"
	echo 		"usage: 'nevpn [Argument]'"
	echo		"-------------------------------------------------"
	echo -e 	"${YELLOW}[Arguments]:${NC}"
	echo 		"  -h, --help       Shows this help menu."
	echo 		"  -Up              Check for updates and install if available."
	echo 		"  -S               Show useful conection Status."
	echo 		"  -Pon             Turn Proxy ON."
	echo 		"  -Poff            Turn Proxy OFF."
	echo 		"  -Von             Turn VPN ON."
	echo 		"  -Voff            Turn VPN OFF."

}