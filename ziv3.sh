#!/bin/bash
set -e

echo "Updating server..."
sudo apt-get update && sudo apt-get upgrade -y

# Stop service if it exists
systemctl stop zivpn.service 2>/dev/null || true

echo "Downloading UDP Service..."
wget -q https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-arm64 -O /usr/local/bin/zivpn
chmod +x /usr/local/bin/zivpn

mkdir -p /etc/zivpn
wget -q https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json -O /etc/zivpn/config.json

echo "Generating cert files..."
openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
  -subj "/C=US/ST=California/L=Los Angeles/O=Example Corp/OU=IT Department/CN=zivpn" \
  -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt"

sysctl -w net.core.rmem_max=16777216 >/dev/null
sysctl -w net.core.wmem_max=16777216 >/dev/null

cat <<EOF > /etc/systemd/system/zivpn.service
[Unit]
Description=zivpn VPN Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

echo "ZIVPN UDP Passwords"
read -p "Enter passwords separated by commas (default: zi): " input_config

if [ -n "$input_config" ]; then
    IFS=',' read -r -a config <<< "$input_config"
    if [ ${#config[@]} -eq 1 ]; then
        config+=("${config[0]}")
    fi
else
    config=("zi")
fi

new_config_str="\"config\": [$(printf "\"%s\"," "${config[@]}" | sed 's/,$//')]"
sed -i -E "s/\"config\":.*

\[.*\]

/${new_config_str}/" /etc/zivpn/config.json

systemctl daemon-reload
systemctl enable zivpn.service
systemctl restart zivpn.service

# Networking rules
IFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination 127.0.0.1:5667

if command -v ufw >/dev/null; then
    ufw allow 6000:19999/udp || true
    ufw allow 5667/udp || true
fi

echo "ZIVPN Installed"
