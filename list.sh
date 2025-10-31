#!/bin/bash
# ==============================================
# 📋 ZIVPN Account List Viewer (with Colors)
# ==============================================

ACCOUNTS_FILE="/etc/zivpn/accounts.json"
DATE_NOW=$(date +%Y-%m-%d)
EPOCH_NOW=$(date +%s)

# Warna
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[1;34m'
NC='\033[0m'

# ==============================================
# Fungsi Bantuan
# ==============================================
banner() {
    clear
    echo -e "${BLUE}==============================================${NC}"
    echo -e "${CYAN}       📋  ZIVPN ACCOUNT LIST VIEWER${NC}"
    echo -e "${BLUE}==============================================${NC}"
}

line() {
    echo -e "${BLUE}----------------------------------------------${NC}"
}

calc_days_left() {
    local exp_date=$1
    local exp_epoch
    exp_epoch=$(date -d "$exp_date" +%s 2>/dev/null || echo 0)
    echo $(( (exp_epoch - EPOCH_NOW) / 86400 ))
}

status_color() {
    local days_left=$1
    if (( days_left < 0 )); then
        echo -e "${RED}Expired${NC}"
    elif (( days_left <= 3 )); then
        echo -e "${YELLOW}Expiring Soon${NC}"
    else
        echo -e "${GREEN}Active${NC}"
    fi
}

username_color() {
    local name=$1
    local days_left=$2
    if (( days_left < 0 )); then
        echo -e "${RED}$name${NC}"
    elif (( days_left <= 3 )); then
        echo -e "${YELLOW}$name${NC}"
    else
        echo -e "${GREEN}$name${NC}"
    fi
}

expired_color() {
    local date=$1
    local days_left=$2
    if (( days_left < 0 )); then
        echo -e "${RED}$date${NC}"
    elif (( days_left <= 3 )); then
        echo -e "${YELLOW}$date${NC}"
    else
        echo -e "${GREEN}$date${NC}"
    fi
}

# ==============================================
# Validasi File
# ==============================================
banner
if [ ! -f "$ACCOUNTS_FILE" ]; then
    echo -e "${RED}❌ File $ACCOUNTS_FILE tidak ditemukan.${NC}"
    exit 1
fi

total_users=$(jq '.accounts | length' "$ACCOUNTS_FILE")
if [ "$total_users" -eq 0 ]; then
    echo -e "${YELLOW}⚠️  Tidak ada akun ditemukan.${NC}"
    exit 0
fi

# ==============================================
# Menampilkan Data Akun
# ==============================================
printf "${CYAN}📅 Tanggal Saat Ini: %s${NC}\n" "$DATE_NOW"
line
printf "${YELLOW}Total Akun: ${NC}%s\n" "$total_users"
line

printf "%-4s %-20s %-15s %-15s %-10s %-12s\n" \
"No" "Username" "Password" "Expired" "Sisa(H)" "Status"
echo -e "${BLUE}--------------------------------------------------------------------------------${NC}"

i=1
jq -c '.accounts[]' "$ACCOUNTS_FILE" | while read -r acc; do
    username=$(echo "$acc" | jq -r '.username')
    password=$(echo "$acc" | jq -r '.password')
    expired=$(echo "$acc" | jq -r '.expired')

    days_left=$(calc_days_left "$expired")
    status=$(status_color "$days_left")
    uname_colored=$(username_color "$username" "$days_left")
    exp_colored=$(expired_color "$expired" "$days_left")

    if (( days_left < 0 )); then
        days_display="0"
    else
        days_display="$days_left"
    fi

    printf "%-4s %-20b %-15s %-15b %-10s %b\n" \
    "$i." "$uname_colored" "$password" "$exp_colored" "$days_display" "$status"

    ((i++))
done

echo -e "${BLUE}--------------------------------------------------------------------------------${NC}"
printf "${CYAN}Total akun terdaftar: %s${NC}\n" "$total_users"
echo ""
