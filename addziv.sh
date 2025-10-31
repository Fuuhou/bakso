#!/bin/bash
# ==============================================
# 🔐 ZIVPN Account Creator (Official Format Compatible)
# ==============================================

# -------------------------------
# 🎨 Warna ANSI
# -------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -------------------------------
# 📂 File & Direktori
# -------------------------------
CONFIG_FILE="/etc/zivpn/config.json"
BACKUP_DIR="/etc/zivpn/backup"
ACCOUNT_LIST="/etc/zivpn/accounts.json"
mkdir -p "$BACKUP_DIR" /etc/zivpn

# -------------------------------
# 🤖 Telegram Bot Config
# -------------------------------
BOT_TOKEN="BOT_TOKEN"
CHAT_ID="CHAT_ID"

# -------------------------------
# 🌍 Informasi VPS
# -------------------------------
IP=$(cat /etc/ipvps 2>/dev/null || echo "Unknown")
CITY=$(cat /etc/cityvps 2>/dev/null || echo "Unknown")
ISP=$(cat /etc/ispvps 2>/dev/null || echo "Unknown")

# -------------------------------
# 🔧 Utility Functions
# -------------------------------
generate_password() {
    LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c8
}

validate_username() {
    [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]]
}

validate_days() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -gt 0 ]
}

# -------------------------------
# 🧑 Input Section
# -------------------------------
clear
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}   🔐 ZIVPN Account Creator${NC}"
echo -e "${BLUE}======================================${NC}"

read -p "👤 Masukkan username baru: " username
if [ -z "$username" ] || ! validate_username "$username"; then
    echo -e "${RED}❌ Username tidak valid.${NC}"
    exit 1
fi

read -p "🔑 Masukkan password (Enter = auto generate): " password
if [ -z "$password" ]; then
    password=$(generate_password)
    echo -e "${YELLOW}⚡ Password otomatis dibuat:${NC} ${GREEN}$password${NC}"
fi

read -p "📅 Masukkan masa aktif (hari): " days
if ! validate_days "$days"; then
    echo -e "${RED}❌ Masa aktif tidak valid (harus angka > 0).${NC}"
    exit 1
fi

expired_date=$(date -d "+$days days" +"%Y-%m-%d")

# -------------------------------
# 🧱 JSON Configuration (official format)
# -------------------------------
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}⚠️  File config.json tidak ditemukan, membuat default...${NC}"
    echo '{"config": []}' > "$CONFIG_FILE"
fi

# Backup sebelum edit
cp "$CONFIG_FILE" "$BACKUP_DIR/config.json.$(date +%s).bak"

# Format resmi: "username:password"
user_entry="${username}:${password}"

# Tambahkan user ke config.json jika belum ada
if jq -e --arg entry "$user_entry" '.config[] | select(. == $entry)' "$CONFIG_FILE" >/dev/null; then
    echo -e "${YELLOW}⚠️  Username sudah ada di config.json!${NC}"
else
    tmpfile=$(mktemp)
    if jq --arg entry "$user_entry" '.config += [$entry]' "$CONFIG_FILE" > "$tmpfile"; then
        mv "$tmpfile" "$CONFIG_FILE"
        echo -e "${GREEN}✅ Akun berhasil ditambahkan ke $CONFIG_FILE${NC}"
    else
        echo -e "${RED}❌ Gagal memperbarui config.json (format JSON tidak valid).${NC}"
        rm -f "$tmpfile"
        exit 1
    fi
fi

# -------------------------------
# 🗂️ Save Account Info (accounts.json)
# -------------------------------
if [ ! -f "$ACCOUNT_LIST" ]; then
    echo '{"accounts": []}' > "$ACCOUNT_LIST"
fi

if jq -e --arg user "$username" '.accounts[] | select(.username==$user)' "$ACCOUNT_LIST" >/dev/null; then
    echo -e "${YELLOW}⚠️  Username '$username' sudah ada di $ACCOUNT_LIST, lewati penambahan.${NC}"
else
    tmpfile=$(mktemp)
    if jq --arg user "$username" \
          --arg pass "$password" \
          --arg exp "$expired_date" \
          '.accounts += [{"username":$user,"password":$pass,"expired":$exp}]' \
          "$ACCOUNT_LIST" > "$tmpfile"; then
        mv "$tmpfile" "$ACCOUNT_LIST"
        echo -e "${GREEN}✅ Akun '$username' berhasil ditambahkan ke $ACCOUNT_LIST${NC}"
    else
        echo -e "${RED}❌ Gagal menulis ke $ACCOUNT_LIST${NC}"
        rm -f "$tmpfile"
        exit 1
    fi
fi

# -------------------------------
# 📤 Telegram Notification
# -------------------------------
account_info="───────────────────────────────────────
🆕 ZIVPN Account Created
───────────────────────────────────────
🌐 IP       : $IP
🏙️ Kota     : $CITY
🏢 ISP      : $ISP

👤 User     : $username
🔑 Password : $password
📆 Expired  : $expired_date
───────────────────────────────────────
"

echo -e "\n${GREEN}$account_info${NC}"

if [[ "$BOT_TOKEN" != "BOT_TOKEN" && "$CHAT_ID" != "CHAT_ID" ]]; then
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d parse_mode="Markdown" \
        -d text="$account_info" >/dev/null
    echo -e "${GREEN}📨 Akun otomatis dikirim ke Telegram.${NC}"
else
    echo -e "${YELLOW}ℹ️ BOT_TOKEN/CHAT_ID belum diatur, skip Telegram.${NC}"
fi

echo -e "${GREEN}🎉 Selesai!${NC}"
