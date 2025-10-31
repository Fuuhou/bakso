#!/bin/bash
# ==============================================
# 🧹 ZIVPN Manual Account Remover (with Colors)
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
ACCOUNTS_FILE="/etc/zivpn/accounts.json"
BACKUP_DIR="/etc/zivpn/backup"
mkdir -p "$BACKUP_DIR" /etc/zivpn

# -------------------------------
# 🤖 Telegram Bot Config
# -------------------------------
BOT_TOKEN="BOT_TOKEN"
CHAT_ID="CHAT_ID"

# -------------------------------
# 🔧 Utility Functions
# -------------------------------
list_users() {
    jq -r '.accounts[] | "\(.username)\t|\tExpired: \(.expired)"' "$ACCOUNTS_FILE" 2>/dev/null
}

backup_files() {
    cp "$CONFIG_FILE"   "$BACKUP_DIR/config.json.$(date +%s).bak"   2>/dev/null
    cp "$ACCOUNTS_FILE" "$BACKUP_DIR/accounts.json.$(date +%s).bak" 2>/dev/null
}

send_telegram() {
    local msg="$1"
    if [[ "$BOT_TOKEN" != "BOT_TOKEN" && "$CHAT_ID" != "CHAT_ID" ]]; then
        curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
            -d chat_id="$CHAT_ID" \
            -d parse_mode="Markdown" \
            -d text="$msg" >/dev/null
        echo -e "${GREEN}📨 Notifikasi Telegram terkirim.${NC}"
    else
        echo -e "${YELLOW}ℹ️ BOT_TOKEN/CHAT_ID belum diatur, skip Telegram.${NC}"
    fi
}

# -------------------------------
# 🧑 UI Section
# -------------------------------
clear
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}   🧹 ZIVPN Manual Account Remover${NC}"
echo -e "${BLUE}======================================${NC}"

# Validasi file
if [ ! -f "$ACCOUNTS_FILE" ]; then
    echo -e "${RED}❌ File $ACCOUNTS_FILE tidak ditemukan.${NC}"
    exit 1
fi
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}❌ File $CONFIG_FILE tidak ditemukan.${NC}"
    exit 1
fi

# Tampilkan daftar akun
echo ""
echo -e "${YELLOW}📋 Daftar Akun yang Tersimpan:${NC}"
echo "──────────────────────────────"
list_users || { echo -e "${YELLOW}⚠️ Tidak ada akun ditemukan.${NC}"; exit 0; }
echo "──────────────────────────────"
echo ""

read -p "🗑️  Masukkan username yang ingin dihapus: " username
[ -z "$username" ] && { echo -e "${RED}❌ Username tidak boleh kosong.${NC}"; exit 1; }

# Cek apakah user ada di accounts.json
if ! jq -e --arg user "$username" '.accounts[] | select(.username==$user)' "$ACCOUNTS_FILE" >/dev/null; then
    echo -e "${RED}❌ Username '$username' tidak ditemukan di accounts.json.${NC}"
    exit 1
fi

# Ambil password & expired date
password=$(jq -r --arg user "$username" '.accounts[] | select(.username==$user) | .password' "$ACCOUNTS_FILE")
expired=$(jq -r --arg user "$username" '.accounts[] | select(.username==$user) | .expired' "$ACCOUNTS_FILE")

# Konfirmasi
echo ""
echo "--------------------------------------"
echo -e "👤 Username : ${YELLOW}$username${NC}"
echo -e "🔑 Password : ${YELLOW}$password${NC}"
echo -e "📆 Expired  : ${YELLOW}$expired${NC}"
echo "--------------------------------------"
read -p "Yakin ingin menghapus akun ini? (y/n): " confirm
[[ "$confirm" != "y" && "$confirm" != "Y" ]] && { echo -e "${YELLOW}❌ Dibatalkan.${NC}"; exit 0; }

# -------------------------------
# 🧹 Eksekusi penghapusan
# -------------------------------
backup_files

# Hapus dari accounts.json
tmp_acc=$(mktemp)
jq --arg user "$username" 'del(.accounts[] | select(.username==$user))' "$ACCOUNTS_FILE" > "$tmp_acc" \
    && mv "$tmp_acc" "$ACCOUNTS_FILE"

# Hapus dari config.json (format resmi user:pass)
tmp_conf=$(mktemp)
jq --arg entry "${username}:${password}" '.config |= map(select(. != $entry))' "$CONFIG_FILE" > "$tmp_conf" \
    && mv "$tmp_conf" "$CONFIG_FILE"

# -------------------------------
# 📤 Telegram & Output
# -------------------------------
msg="🧹 ZIVPN Account Removed
───────────────────────────────
👤 User : $username
🔑 Password : $password
📆 Expired : $expired
───────────────────────────────
🕒 $(date +'%Y-%m-%d %H:%M:%S')
"

echo ""
echo -e "${GREEN}✅ Akun '$username' berhasil dihapus!${NC}"
send_telegram "$msg"

echo ""
echo -e "${GREEN}🎉 Proses selesai!${NC}"
