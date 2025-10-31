#!/bin/bash

set -eo pipefail

# Update server
echo -e "Updating server"
sudo apt-get update && sudo apt-get upgrade -y

# Stop service gracefully
echo -e "Stopping zivpn service"
systemctl stop zivpn.service 2>/dev/null || true

# Download binary and validate
echo -e "Downloading UDP Service"
if ! wget 'https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64' -O /tmp/udp-zivpn-linux-amd64 2>/dev/null; then
    echo "Error: Failed to download UDP binary" >&2
    exit 1
fi
mv /tmp/udp-zivpn-linux-amd64 /usr/local/bin/zivpn
chmod +x /usr/local/bin/zivpn

# Download config and validate
echo -e "Downloading config.json"
if ! wget 'https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json' -O /tmp/config.json 2>/dev/null; then
    echo "Error: Failed to download config.json" >&2
    exit 1
fi
mkdir -p /etc/zivpn
mv /tmp/config.json /etc/zivpn/config.json

# Generate certs
echo "Generating cert files:"
openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=US/ST=California/L=Los Angeles/O=Example Corp/OU=IT Department/CN=zivpn" -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt"

# Optimize buffer
echo -e "Optimizing system buffers"
sysctl -w net.core.rmem_max=16777216 2>/dev/null || true
sysctl -w net.core.wmem_max=16777216 2>/dev/null || true

# Create systemd service
cat <<'EOF' > /etc/systemd/system/zivpn.service
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

echo -e "ZIVPN UDP Passwords"
read -p "Enter passwords separated by commas, example: passwd1,passwd2 (Press enter for Default 'zi'): " input_config

# Handle user input and config
if [ -n "$input_config" ]; then
    IFS=',' read -r -a config <<< "$input_config"
else
    config=("zi")
fi

# Convert array to config string
new_config_str="\"config\": [$(printf "\"%s\"," "${config[@]}" | sed 's/,$//')]"

# Update config.json
if ! sed -i -E "s/\"config\": ?\[[[:space:]]*\"zi\"[[:space:]]*\]/${new_config_str}/g" /etc/zivpn/config.json; then
    echo "Error: Failed to update config.json" >&2
    exit 1
fi

# Reload and enable/start service
echo -e "Enabling and starting service"
systemctl daemon-reload
systemctl enable zivpn.service
if ! systemctl start zivpn.service; then
    echo "Error: Failed to start zivpn.service" >&2
    exit 1
fi

# Setup iptables DNAT
Network=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
iptables -t nat -A PREROUTING -i "$Network" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
ufw allow 6000:19999/udp
ufw allow 5667/udp

# Cleanup
rm -f zi2.* 2>/dev/null

echo -e "ZIVPN Installed"
