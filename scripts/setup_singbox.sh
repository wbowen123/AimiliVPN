#!/usr/bin/env bash
# ==============================================================================
# AimiliVPN Sing-box 核心配置与双节点订阅生成脚本
# 架构：
#   - 入站：443 端口 VLESS + Reality (xtls-rprx-vision)
#   - 节点 1 (直连)：走 VPS 物理网卡 (Direct 出口，原生千兆极速)
#   - 节点 2 (住宅)：分流至 127.0.0.1:8500 (AimiliVPN SOCKS5 网桥，家宽出口)
#   - 订阅：输出 Base64 格式并提供 18443 HTTPS 订阅访问
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${VPNGATE_DATA_DIR:-$ROOT_DIR/vpngate_data}"
SUB_DIR="/var/lib/aimilivpn/subscriptions"
WWW_SUB_DIR="/var/www/aimilivpn-sub"
SB_CONFIG_DIR="/etc/sing-box"
SB_CONFIG_FILE="$SB_CONFIG_DIR/config.json"
SB_BIN="/usr/local/bin/sing-box"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
PLAIN='\033[0m'

if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}错误: 必须以 root 权限运行此脚本。${PLAIN}" >&2
    exit 1
fi

mkdir -p "$DATA_DIR" "$SUB_DIR" "$WWW_SUB_DIR" "$SB_CONFIG_DIR"

echo -e "${BLUE}==========================================================${PLAIN}"
echo -e "${BLUE}      正在部署 Sing-box 高速代理与双节点分流引擎...${PLAIN}"
echo -e "${BLUE}==========================================================${PLAIN}"

# 1. 架构检测
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64) SB_ARCH="amd64" ;;
    aarch64|arm64) SB_ARCH="arm64" ;;
    *) echo -e "${RED}不支持的 CPU 架构: ${ARCH}${PLAIN}"; exit 1 ;;
esac

# 2. 安装/更新 Sing-box
install_singbox_bin() {
    local target_ver="1.11.4"
    if [ -x "$SB_BIN" ]; then
        local cur_ver
        cur_ver=$("$SB_BIN" version 2>/dev/null | awk '/sing-box version/ {print $3}' || echo "")
        if [ -n "$cur_ver" ]; then
            echo -e "${GREEN}  -> 检测到已安装 Sing-box (${cur_ver})${PLAIN}"
            return 0
        fi
    fi

    echo -e "${YELLOW}  -> 正在获取 Sing-box v${target_ver} (${SB_ARCH})...${PLAIN}"
    local mirrors=(
        "$download_url"
        "https://ghfast.top/${download_url}"
        "https://mirror.ghproxy.com/${download_url}"
    )
    local downloaded=0
    for m in "${mirrors[@]}"; do
        if curl -fsSL --connect-timeout 8 --max-time 60 "$m" -o "$tmp_tar" 2>/dev/null; then
            downloaded=1
            break
        fi
        echo -e "${YELLOW}  -> 直连或镜像源超时，尝试下一个加速源...${PLAIN}"
    done
    if [ "$downloaded" != "1" ]; then
        echo -e "${RED}错误: Sing-box 下载失败，请检查网络连接！${PLAIN}"
        exit 1
    fi

    tar -xzf "$tmp_tar" -C "$tmp_dir"
    local extracted_bin
    extracted_bin=$(find "$tmp_dir" -type f -name sing-box | head -n 1)
    if [ -z "$extracted_bin" ]; then
        echo -e "${RED}错误: 解压 Sing-box 失败。${PLAIN}"
        exit 1
    fi

    install -m 755 "$extracted_bin" "$SB_BIN"
    rm -rf "$tmp_dir" "$tmp_tar"
    echo -e "${GREEN}  -> Sing-box 安装成功: $($SB_BIN version | head -n 1)${PLAIN}"
}

install_singbox_bin

# 3. 读取代理配置与公网 IP
PROXY_ENV_FILE="/etc/default/aimilivpn"
LOCAL_PROXY_PORT="8500"
LOCAL_PROXY_USER="socks5"
LOCAL_PROXY_PASS="ilovestudy"

if [ -f "$PROXY_ENV_FILE" ]; then
    LOCAL_PROXY_PORT=$(grep '^LOCAL_PROXY_PORT=' "$PROXY_ENV_FILE" | cut -d'=' -f2 | tr -d '"'"'" || echo "8500")
    LOCAL_PROXY_USER=$(grep '^LOCAL_PROXY_USER=' "$PROXY_ENV_FILE" | cut -d'=' -f2 | tr -d '"'"'" || echo "socks5")
    LOCAL_PROXY_PASS=$(grep '^LOCAL_PROXY_PASS=' "$PROXY_ENV_FILE" | cut -d'=' -f2 | tr -d '"'"'" || echo "ilovestudy")
fi

PUBLIC_IP=""
if [ -f "$DATA_DIR/public_ip.txt" ]; then
    PUBLIC_IP=$(cat "$DATA_DIR/public_ip.txt" | tr -d '[:space:]')
fi
if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" = "您的服务器公网IP" ]; then
    PUBLIC_IP=$(curl -4fsS --max-time 5 https://api.ipify.org 2>/dev/null || curl -4fsS --max-time 5 https://ifconfig.me 2>/dev/null || echo "127.0.0.1")
fi

# 4. 生成或保留 Reality 密钥与 UUID
KEY_FILE="$DATA_DIR/singbox_keys.json"
REALITY_KEYPAIR=""
PRIVATE_KEY=""
PUBLIC_KEY=""
DIRECT_UUID=""
RESI_UUID=""
SHORT_ID=""

CAMOUFLAGE_DOMAIN="${1:-${JIUHEYI_REALITY_DOMAIN:-gateway.icloud.com}}"
[ -z "$CAMOUFLAGE_DOMAIN" ] && CAMOUFLAGE_DOMAIN="gateway.icloud.com"

if [ -f "$KEY_FILE" ]; then
    PRIVATE_KEY=$(python3 -c "import json; print(json.load(open('$KEY_FILE')).get('private_key',''))" 2>/dev/null || true)
    PUBLIC_KEY=$(python3 -c "import json; print(json.load(open('$KEY_FILE')).get('public_key',''))" 2>/dev/null || true)
    DIRECT_UUID=$(python3 -c "import json; print(json.load(open('$KEY_FILE')).get('direct_uuid',''))" 2>/dev/null || true)
    RESI_UUID=$(python3 -c "import json; print(json.load(open('$KEY_FILE')).get('resi_uuid',''))" 2>/dev/null || true)
    SHORT_ID=$(python3 -c "import json; print(json.load(open('$KEY_FILE')).get('short_id',''))" 2>/dev/null || true)
fi

if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    REALITY_KEYPAIR=$("$SB_BIN" generate reality-keypair)
    PRIVATE_KEY=$(printf '%s\n' "$REALITY_KEYPAIR" | awk '/PrivateKey:/ {print $2}')
    PUBLIC_KEY=$(printf '%s\n' "$REALITY_KEYPAIR" | awk '/PublicKey:/ {print $2}')
fi

[ -z "$DIRECT_UUID" ] && DIRECT_UUID=$("$SB_BIN" generate uuid)
[ -z "$RESI_UUID" ] && RESI_UUID=$("$SB_BIN" generate uuid)
[ -z "$SHORT_ID" ] && SHORT_ID=$("$SB_BIN" generate rand --hex 8)

cat > "$KEY_FILE" <<EOF
{
  "private_key": "$PRIVATE_KEY",
  "public_key": "$PUBLIC_KEY",
  "direct_uuid": "$DIRECT_UUID",
  "resi_uuid": "$RESI_UUID",
  "short_id": "$SHORT_ID",
  "sni": "$CAMOUFLAGE_DOMAIN"
}
EOF
chmod 600 "$KEY_FILE"

# 5. 生成 Sing-box 核心配置文件
echo -e "${YELLOW}  -> 正在生成 Sing-box 双出站核心配置 (/etc/sing-box/config.json)...${PLAIN}"
cat > "$SB_CONFIG_FILE" <<EOF
{
  "log": {
    "level": "warn",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": 443,
      "sniff": true,
      "sniff_override_destination": false,
      "users": [
        {
          "name": "direct-user",
          "uuid": "${DIRECT_UUID}",
          "flow": "xtls-rprx-vision"
        },
        {
          "name": "residential-user",
          "uuid": "${RESI_UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${CAMOUFLAGE_DOMAIN}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${CAMOUFLAGE_DOMAIN}",
            "server_port": 443
          },
          "private_key": "${PRIVATE_KEY}",
          "short_id": [
            "${SHORT_ID}"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct-out"
    },
    {
      "type": "socks",
      "tag": "resi-out",
      "server": "127.0.0.1",
      "server_port": ${LOCAL_PROXY_PORT},
      "version": "5",
      "username": "${LOCAL_PROXY_USER}",
      "password": "${LOCAL_PROXY_PASS}"
    }
  ],
  "route": {
    "rules": [
      {
        "ip_is_private": true,
        "outbound": "direct-out"
      },
      {
        "auth_user": ["residential-user"],
        "outbound": "resi-out"
      },
      {
        "auth_user": ["direct-user"],
        "outbound": "direct-out"
      }
    ],
    "final": "direct-out"
  }
}
EOF

"$SB_BIN" check -c "$SB_CONFIG_FILE"
echo -e "${GREEN}  -> Sing-box 配置文件语法校验通过${PLAIN}"

# 6. 配置 systemd 服务
cat > /etc/systemd/system/sing-box.service <<'EOF'
[Unit]
Description=Sing-box Service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target aimilivpn.service
Wants=network.target

[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=3s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sing-box.service
systemctl restart sing-box.service
sleep 1
if ! systemctl is-active --quiet sing-box.service; then
    echo -e "${RED}警告: Sing-box 服务未能正常启动，可能是 443 端口被占用。查看日志: journalctl -u sing-box -e${PLAIN}"
else
    echo -e "${GREEN}  -> Sing-box 服务已成功启动 (端口 443 / Reality)${PLAIN}"
fi

# 7. 生成客户端链接与订阅文件
url_encode() {
    python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$1" 2>/dev/null || echo "$1"
}

NODE_NAME_DIRECT="🚀 [VPS-直连] 高速原生"
NODE_NAME_RESI="🏠 [VPS-住宅] Aimili穿透"

ENCODED_DIRECT=$(url_encode "$NODE_NAME_DIRECT")
ENCODED_RESI=$(url_encode "$NODE_NAME_RESI")

URL_DIRECT="vless://${DIRECT_UUID}@${PUBLIC_IP}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${CAMOUFLAGE_DOMAIN}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#${ENCODED_DIRECT}"
URL_RESI="vless://${RESI_UUID}@${PUBLIC_IP}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${CAMOUFLAGE_DOMAIN}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#${ENCODED_RESI}"

# 写入纯文本节点链接文件
cat > "$DATA_DIR/singbox_links.txt" <<EOF
# AimiliVPN + Sing-box 双节点链接
# 节点 1：原生 VPS IP 直连（千兆高速）
${URL_DIRECT}

# 节点 2：穿透 AimiliVPN 8500 住宅 IP
${URL_RESI}
EOF

# 写入 Base64 订阅文件
SUB_CONTENT=$(printf '%s\n%s\n' "$URL_DIRECT" "$URL_RESI" | base64 | tr -d '\n\r')
echo "$SUB_CONTENT" > "$WWW_SUB_DIR/sub.txt"
echo "$SUB_CONTENT" > "$SUB_DIR/sub.txt"
chmod 644 "$WWW_SUB_DIR/sub.txt"

# 同时也提供明文 nodes.txt 供部分特定客户端读取
cp -f "$DATA_DIR/singbox_links.txt" "$WWW_SUB_DIR/nodes.txt" 2>/dev/null || true
chmod 644 "$WWW_SUB_DIR/nodes.txt" 2>/dev/null || true

# 8. 写入汇总数据
cat > "$DATA_DIR/singbox_nodes.json" <<EOF
{
  "public_ip": "${PUBLIC_IP}",
  "port": 443,
  "camouflage_domain": "${CAMOUFLAGE_DOMAIN}",
  "public_key": "${PUBLIC_KEY}",
  "short_id": "${SHORT_ID}",
  "direct_uuid": "${DIRECT_UUID}",
  "resi_uuid": "${RESI_UUID}",
  "direct_url": "${URL_DIRECT}",
  "resi_url": "${URL_RESI}"
}
EOF

# 9. 重新载入 Nginx 订阅配置
if command -v nginx >/dev/null 2>&1; then
    if nginx -t >/dev/null 2>&1; then
        systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1 || true
        echo -e "${GREEN}  -> Nginx 订阅入口 (18443 & /sub/) 已就绪${PLAIN}"
    fi
fi

echo -e "\n${GREEN}Sing-box 双节点与订阅生成完成！${PLAIN}"
