#!/bin/bash
# =========================================================
# 🧹 Auto-Remove Expired ZIVPN Accounts (JSON Edition)
# =========================================================

CONFIG_FILE="/etc/zivpn/config.json"
ACCOUNTS_FILE="/etc/zivpn/accounts.json"
BACKUP_DIR="/etc/zivpn/backup"
RECAP_FILE="/var/log/zivpn-monthly-recap.json"
LOG_FILE="/var/log/zivpn-autoremove.log"

BOT_TOKEN="BOT_TOKEN"
CHAT_ID="CHAT_ID"

TODAY=$(date +"%Y-%m-%d")
TODAY_EPOCH=$(date +%s)
MONTH=$(date +"%Y-%m")
LAST_MONTH=$(date -d "-1 month" +"%Y-%m")
NOW=$(date +"%Y-%m-%d %H:%M:%S")

mkdir -p "$BACKUP_DIR" /var/log

echo "[$NOW] === Auto-Remove ZIVPN Started ===" >> "$LOG_FILE"

# =========================================================
# 🧩 Validasi file utama
# =========================================================
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[$NOW] config.json tidak ditemukan." >> "$LOG_FILE"
    exit 0
fi
if [ ! -f "$ACCOUNTS_FILE" ]; then
    echo "[$NOW] accounts.json tidak ditemukan." >> "$LOG_FILE"
    exit 0
fi
[ ! -f "$RECAP_FILE" ] && echo '{"months":{}}' > "$RECAP_FILE"

# Backup config & account sebelum edit
cp "$CONFIG_FILE" "$BACKUP_DIR/config.json.$(date +%s).bak"
cp "$ACCOUNTS_FILE" "$BACKUP_DIR/accounts.json.$(date +%s).bak"

# Bersihkan recap & log lama
if jq -e --arg m "$LAST_MONTH" '.months[$m]' "$RECAP_FILE" >/dev/null 2>&1; then
    echo "[$NOW] Menghapus rekap bulan sebelumnya ($LAST_MONTH)" >> "$LOG_FILE"
    tmp_recap=$(mktemp)
    jq --arg m "$LAST_MONTH" 'del(.months[$m])' "$RECAP_FILE" > "$tmp_recap" && mv "$tmp_recap" "$RECAP_FILE"
fi
find "$BACKUP_DIR" -type f -mtime +40 -delete
find /var/log -type f -name "zivpn-autoremove.log*" -mtime +60 -delete

# =========================================================
# 🔍 Deteksi akun expired (berdasarkan accounts.json)
# =========================================================
expired_users=()
declare -A expired_info

while IFS= read -r acc; do
    user=$(echo "$acc" | jq -r '.username')
    pass=$(echo "$acc" | jq -r '.password')
    exp=$(echo "$acc" | jq -r '.expired')
    [ -z "$user" ] && continue

    exp_epoch=$(date -d "$exp" +%s 2>/dev/null || echo 0)
    if [ "$TODAY_EPOCH" -ge "$exp_epoch" ]; then
        expired_users+=("$user")
        expired_info["$user"]="$exp|$pass"
        echo "[$NOW] ❌ $user expired on $exp" >> "$LOG_FILE"
    fi
done < <(jq -c '.accounts[]' "$ACCOUNTS_FILE")

# =========================================================
# 🧹 Hapus akun expired dari accounts.json & config.json
# =========================================================
if [ "${#expired_users[@]}" -gt 0 ]; then
    # --- Update accounts.json ---
    tmp_accounts=$(mktemp)
    jq --argjson expired "$(printf '%s\n' "${expired_users[@]}" | jq -R . | jq -s .)" \
       'del(.accounts[] | select(.username as $u | $expired | index($u)))' \
       "$ACCOUNTS_FILE" > "$tmp_accounts" && mv "$tmp_accounts" "$ACCOUNTS_FILE"

    # --- Update config.json (hapus user:pass resmi) ---
    tmp_config=$(mktemp)
    newjq='.config |= map(select('
    for u in "${expired_users[@]}"; do
        pass=$(echo "${expired_info[$u]}" | cut -d"|" -f2)
        newjq+=". != \"${u}:${pass}\" and "
    done
    newjq=${newjq::-5}  # hapus " and "
    newjq+="))"

    jq "$newjq" "$CONFIG_FILE" > "$tmp_config" && mv "$tmp_config" "$CONFIG_FILE"

    echo "[$NOW] ${#expired_users[@]} akun dihapus." >> "$LOG_FILE"
else
    echo "[$NOW] Tidak ada akun expired." >> "$LOG_FILE"
fi

# =========================================================
# 📊 Update rekap bulanan
# =========================================================
active_count=$(jq '.accounts | length' "$ACCOUNTS_FILE")
expired_count_today=${#expired_users[@]}
total_created=$(jq '.accounts | length' "$ACCOUNTS_FILE")

tmp_recap=$(mktemp)
jq --arg month "$MONTH" \
   --argjson active "$active_count" \
   --argjson expired_today "$expired_count_today" \
   --argjson total_created "$total_created" \
   --arg today "$TODAY" '
   if .months[$month] == null then .months[$month] = {} else . end
   | .months[$month].last_update = $today
   | .months[$month].active = $active
   | .months[$month].expired += $expired_today
   | .months[$month].created = $total_created
   ' "$RECAP_FILE" > "$tmp_recap" 2>/dev/null || echo "{}" > "$tmp_recap"
mv "$tmp_recap" "$RECAP_FILE"

# =========================================================
# 📤 Kirim laporan Telegram
# =========================================================
if [[ "$BOT_TOKEN" != "BOT_TOKEN" && "$CHAT_ID" != "CHAT_ID" ]]; then
    month_data=$(jq -r --arg month "$MONTH" '.months[$month]' "$RECAP_FILE")
    month_expired=$(echo "$month_data" | jq -r '.expired // 0')
    month_created=$(echo "$month_data" | jq -r '.created // 0')
    month_active=$(echo "$month_data" | jq -r '.active // 0')
    last_update=$(echo "$month_data" | jq -r '.last_update // "-"')

    msg="📊 *ZIVPN Monthly Recap - $MONTH*\n───────────────────────────────\n"
    msg+="📅 *Tanggal Laporan:* $TODAY\n"
    msg+="👥 *Total Akun Aktif:* $month_active\n"
    msg+="💀 *Total Expired Bulan Ini:* $month_expired\n"
    msg+="🆕 *Total Akun Dibuat:* $month_created\n"
    msg+="───────────────────────────────\n🕒 *Update Terakhir:* $last_update\n"

    if [ "$expired_count_today" -gt 0 ]; then
        msg+="\n🧹 *Akun Dihapus Hari Ini:*\n"
        for u in "${expired_users[@]}"; do
            exp=$(echo "${expired_info[$u]}" | cut -d"|" -f1)
            msg+="• $u (Expired $exp)\n"
        done
    fi

    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d parse_mode="Markdown" \
        -d text="$msg" >/dev/null

    echo "[$NOW] Telegram report sent." >> "$LOG_FILE"
else
    echo "[$NOW] BOT_TOKEN/CHAT_ID belum diatur, skip Telegram." >> "$LOG_FILE"
fi

echo "[$NOW] === Auto-Remove ZIVPN Selesai ===" >> "$LOG_FILE"
