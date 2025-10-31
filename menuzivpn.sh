#!/usr/bin/env bash

set -eo pipefail
set -u

# Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
GRAY='\033[1;37m'
WHITE='\033[1;37m'
RESET='\033[0m'

# Initialize variables
IP="N/A"
distribution="Unknown"
Network="Unknown"
PORTS=""

# Function to get system info
get_system_info() {
    # Get WAN IP
    IP=$(curl -4 -s icanhazip.com 2>/dev/null || echo "N/A")
    echo "$IP" > /etc/ipvps 2>/dev/null || true
    
    # Get city and ISP info
    curl -s ipinfo.io/city 2>/dev/null >> /etc/cityvps 2>/dev/null || true
    curl -s ipinfo.io/org 2>/dev/null | cut -d " " -f 2-10 >> /etc/ispvps 2>/dev/null || true
    
    # Get distribution
    distribution=$(lsb_release -ds 2>/dev/null || cat /etc/*release 2>/dev/null | head -n1 || uname -om 2>/dev/null)
    
    # Get network interface
    Network=$(ip -4 route ls 2>/dev/null | grep default | grep -Po '(?<=dev )(\S+)' | head -1 || echo "Unknown")
    
    # Get ports
    PORTS=$(netstat -tunlp 2>/dev/null | grep zivpn | awk '
      BEGIN { ports = "" }
      $4 ~ /:::/ {
        port = substr($4, 4)
        ports = ports (ports == "" ? "" : " ") port
      }
      END { print ports }
    ' 2>/dev/null || echo "")
}

# Helper func: prompt yes/no
confirm_action() {
    local prompt="$1"
    local yn
    echo -e "$prompt"
    while [[ ! $yn =~ ^[sSyYNn]$ ]]; do
        read -p "[S/N]: " yn
        tput cuu1 >&2 && tput dl1 >&2
    done
    [[ $yn =~ ^[sSyY]$ ]]
}

# Helper func: check if service exists
service_exists() {
    local service_name="$1"
    systemctl list-units --full -all 2>/dev/null | grep -Fq "$service_name.service" 2>/dev/null && return 0 || return 1
}

# Helper func: systemctl wrapper
manage_service() {
    local action="$1"
    local service="$2"
    if service_exists "$service"; then
        echo -e "${YELLOW}Service $service found. $action...${RESET}"
        sudo systemctl "$action" "$service.service" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            echo -e "${GREEN}SUCCESS: $service $action${RESET}"
        else
            echo -e "${RED}FAILED: $service $action${RESET}"
        fi
    else
        echo -e "${YELLOW}Service $service not found. Skipping.${RESET}"
    fi
}

installv1() {
    if confirm_action "This option will install ZIVPN version 2 AMD, UDP port range 6000:19999 redirected to 5667. Continue?"; then
        echo -e "${YELLOW}INSTALLING..${RESET}"
        bash <(curl -fsSL https://raw.githubusercontent.com/powermx/zivpn/main/ziv2.sh)
    fi
}

installv2() {
    if confirm_action "This option will install ZIVPN version 2 ARM, UDP port range 6000:19999 redirected to 5667. Continue?"; then
        echo -e "${YELLOW}INSTALLING..${RESET}"
        bash <(curl -fsSL https://raw.githubusercontent.com/powermx/zivpn/main/ziv3.sh)
    fi
}

uninstall() {
    if confirm_action "This option will uninstall ZIVPN server. Continue?"; then
        echo -e "${YELLOW}UNINSTALLING..${RESET}"
        bash <(curl -fsSL https://raw.githubusercontent.com/powermx/zivpn/main/uninstall.sh)
    fi
}

# Service management
startzivpn() {
    if confirm_action "Start ZiVPN server?"; then
        manage_service "start" "zivpn"
        manage_service "start" "zivpn_backfill"
        echo -e "${YELLOW}DONE!${RESET}"
    fi
}

stopzivpn() {
    if confirm_action "Stop ZiVPN server?"; then
        manage_service "stop" "zivpn"
        manage_service "stop" "zivpn_backfill"
        echo -e "${YELLOW}DONE!${RESET}"
    fi
}

restartzivpn() {
    if confirm_action "Restart ZiVPN server?"; then
        manage_service "restart" "zivpn"
        manage_service "restart" "zivpn_backfill"
        echo -e "${YELLOW}DONE!${RESET}"
    fi
}

# Menu
main_menu() {
    clear
    get_system_info
    echo -e "${GRAY}[${RED}-${GRAY}]${RED} ────────────── /// ─────────────── ${RESET}"
    echo -e "${YELLOW}   【          ${RED}ZIVPN            ${YELLOW}】 ${RESET}"
    echo -e "${YELLOW} › ${WHITE}Linux Dist:${GREEN} $distribution ${RESET}"
    echo -e "${YELLOW} › ${WHITE}IP:${GREEN} $IP ${RESET}"
    echo -e "${YELLOW} › ${WHITE}Network:${GREEN} $Network ${RESET}"
    echo -e "${YELLOW} › ${WHITE}Running:${GREEN} $PORTS ${RESET}"
    echo -e "${GRAY}[${RED}-${GRAY}]${RED} ────────────── /// ─────────────── ${RESET}"
    echo ""
}

# Main menu options
main_menu_options=(
    "INSTALL ZIVPN — AMD (5667)"
    "INSTALL ZIVPN — ARM (5667)"
    "UNINSTALL ZIVPN"
    "START ZIVPN"
    "STOP ZIVPN"
    "RESTART ZIVPN"
    "EXIT"
)

# Main loop
while true; do
    if [ $(id -u) -ne 0 ]; then
        echo -e "${RED}Run the script as root user${RESET}"
        exit 1
    fi

    PS3="Δ CHOOSE AN OPTION: "
    main_menu
    select option in "${main_menu_options[@]}"; do
        case $REPLY in
            1)  installv1; break ;;
            2)  installv2; break ;;
            3)  uninstall; break ;;
            4)  startzivpn; break ;;
            5)  stopzivpn; break ;;
            6)  restartzivpn; break ;;
            7)  echo -e "${GREEN}Goodbye!${RESET}"; exit 0 ;;
            *)  echo -e "${RED}Invalid option. Try again.${RESET}" ;;
        esac
    done
    
    echo ""
    read -p "Press Enter to continue..."
done
