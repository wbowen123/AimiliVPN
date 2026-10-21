#!/usr/bin/env bash
# ==============================================================================
# AimiliVPN Sing-box 全协议矩阵与双出站订阅生成引擎
# 架构：
#   - 入站协议：
#       1. VLESS-Reality (TCP 443) -> 极速 Vision 伪装
#       2. Hysteria 2 (UDP 443)    -> 恶劣网络满速推流 / 晚高峰免拥塞
#       3. TUIC v5 (UDP 8443)      -> QUIC 0-RTT 原生 BBR
#       4. AnyTLS (TCP 8444)       -> 动态包长特征混淆 / 会话池
#       5. VMess-xHTTP (TCP 8445)  -> 标准分段 HTTP 流
#   - 出口矩阵：
#       • 直连用户 (direct-user)      -> 走 VPS 原生机房千兆 IP 出口
#       • 住宅用户 (residential-user) -> 分流至 127.0.0.1:8500 (Aimili 家宽住宅出口)
#   - 订阅生态：同时输出 Base64 (sub.txt)、Clash Meta (clash.yaml)、Sing-box (singbox.json)
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
echo -e "${BLUE}   正在部署 AimiliVPN 全协议矩阵 × 住宅/原生双出站系统...${PLAIN}"
echo -e "${BLUE}==========================================================${PLAIN}"

# 0. 调优 Linux BBR 与系统网络栈
if [ -f "$ROOT_DIR/scripts/tune_bbr.sh" ]; then
    bash "$ROOT_DIR/scripts/tune_bbr.sh" || true
fi

# 1. 架构检测
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64) SB_ARCH="amd64" ;;
    aarch64|arm64) SB_ARCH="arm64" ;;
    *) echo -e "${RED}不支持的 CPU 架构: ${ARCH}${PLAIN}"; exit 1 ;;
esac

# 2. 安装/更新 Sing-box 核心
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
    local download_url="https://github.com/SagerNet/sing-box/releases/download/v${target_ver}/sing-box-${target_ver}-linux-${SB_ARCH}.tar.gz"
    local tmp_tar="/tmp/sing-box-${target_ver}.tar.gz"
    local tmp_dir="/tmp/sing-box-extract"
    rm -rf "$tmp_dir" "$tmp_tar"
    mkdir -p "$tmp_dir"

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

# 3. 读取本地住宅代理配置与公网 IP
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

DOMAIN="${AIMILIVPN_DOMAIN:-}"
if [ -z "$DOMAIN" ] && [ -f "$DATA_DIR/ui_auth.json" ]; then
    DOMAIN=$(python3 -c "import json; print(json.load(open('$DATA_DIR/ui_auth.json')).get('web_domain',''))" 2>/dev/null || true)
fi
if [ -z "$DOMAIN" ] && [ -f "$PROXY_ENV_FILE" ]; then
    DOMAIN=$(grep '^AIMILIVPN_DOMAIN=' "$PROXY_ENV_FILE" | cut -d'=' -f2 | tr -d '"'"' " || true)
fi
if [ -z "$DOMAIN" ] && [ -f /etc/aimilivpn/tls/fullchain.pem ] && command -v openssl >/dev/null 2>&1; then
    DOMAIN=$(openssl x509 -in /etc/aimilivpn/tls/fullchain.pem -noout -ext subjectAltName 2>/dev/null | grep -o 'DNS:[^ ,]*' | head -1 | cut -d: -f2 || true)
fi
DOMAIN=$(echo "$DOMAIN" | tr -d '[:space:]')

# 4. 伪装域名 (SNI) 智能优选与握手测速
REQUESTED_SNI="${1:-${JIUHEYI_REALITY_DOMAIN:-}}"
CAMOUFLAGE_DOMAIN=""
if [ -f "$ROOT_DIR/scripts/test_sni.sh" ]; then
    echo -e "${YELLOW}  -> 正在对全球权威大厂 SNI 执行本地握手测速与连通性优选...${PLAIN}"
    CAMOUFLAGE_DOMAIN=$(bash "$ROOT_DIR/scripts/test_sni.sh" "$REQUESTED_SNI" 2>/dev/null || echo "gateway.icloud.com")
fi
[ -z "$CAMOUFLAGE_DOMAIN" ] && CAMOUFLAGE_DOMAIN="gateway.icloud.com"
echo -e "${GREEN}  -> 优选伪装域名: ${CAMOUFLAGE_DOMAIN}${PLAIN}"

# 5. 证书体系就绪 (支持真实域名证书与无域名纯 IP 证书自动准备)
CERT_FILE="/etc/sing-box/cert.pem"
KEY_FILE="/etc/sing-box/key.pem"

if [ -f /etc/aimilivpn/tls/fullchain.pem ] && [ -f /etc/aimilivpn/tls/privkey.pem ]; then
    echo -e "${GREEN}  -> 检测到系统已存在有效域名证书，直接复用${PLAIN}"
    cp -f /etc/aimilivpn/tls/fullchain.pem "$CERT_FILE"
    cp -f /etc/aimilivpn/tls/privkey.pem "$KEY_FILE"
elif [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    echo -e "${YELLOW}  -> 未检测到现成域名证书，自动生成自签 ECC P-256 IP/域名通用证书...${PLAIN}"
    if command -v openssl >/dev/null 2>&1; then
        openssl ecparam -name prime256v1 -genkey -noout -out "$KEY_FILE"
        openssl req -new -x509 -days 3650 -key "$KEY_FILE" -out "$CERT_FILE" \
            -subj "/CN=${DOMAIN:-$PUBLIC_IP}" \
            -addext "subjectAltName=DNS:${DOMAIN:-$PUBLIC_IP},DNS:${PUBLIC_IP}.nip.io,IP:${PUBLIC_IP}" 2>/dev/null || \
        openssl req -new -x509 -days 3650 -key "$KEY_FILE" -out "$CERT_FILE" -subj "/CN=${PUBLIC_IP}" 2>/dev/null
        chmod 600 "$KEY_FILE"
    fi
fi

# 6. 生成或保留 Reality 密钥与 UUID 凭据
KEYS_STORE="$DATA_DIR/singbox_keys.json"
PRIVATE_KEY=""
PUBLIC_KEY=""
DIRECT_UUID=""
RESI_UUID=""
SHORT_ID=""

if [ -f "$KEYS_STORE" ]; then
    PRIVATE_KEY=$(python3 -c "import json; print(json.load(open('$KEYS_STORE')).get('private_key',''))" 2>/dev/null || true)
    PUBLIC_KEY=$(python3 -c "import json; print(json.load(open('$KEYS_STORE')).get('public_key',''))" 2>/dev/null || true)
    DIRECT_UUID=$(python3 -c "import json; print(json.load(open('$KEYS_STORE')).get('direct_uuid',''))" 2>/dev/null || true)
    RESI_UUID=$(python3 -c "import json; print(json.load(open('$KEYS_STORE')).get('resi_uuid',''))" 2>/dev/null || true)
    SHORT_ID=$(python3 -c "import json; print(json.load(open('$KEYS_STORE')).get('short_id',''))" 2>/dev/null || true)
fi

if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    REALITY_KEYPAIR=$("$SB_BIN" generate reality-keypair)
    PRIVATE_KEY=$(printf '%s\n' "$REALITY_KEYPAIR" | awk '/PrivateKey:/ {print $2}')
    PUBLIC_KEY=$(printf '%s\n' "$REALITY_KEYPAIR" | awk '/PublicKey:/ {print $2}')
fi

[ -z "$DIRECT_UUID" ] && DIRECT_UUID=$("$SB_BIN" generate uuid)
[ -z "$RESI_UUID" ] && RESI_UUID=$("$SB_BIN" generate uuid)
[ -z "$SHORT_ID" ] && SHORT_ID=$("$SB_BIN" generate rand --hex 8)

cat > "$KEYS_STORE" <<EOF
{
  "private_key": "$PRIVATE_KEY",
  "public_key": "$PUBLIC_KEY",
  "direct_uuid": "$DIRECT_UUID",
  "resi_uuid": "$RESI_UUID",
  "short_id": "$SHORT_ID",
  "sni": "$CAMOUFLAGE_DOMAIN"
}
EOF
chmod 600 "$KEYS_STORE"

# 7. 生成 Sing-box 全协议双出站核心配置文件
echo -e "${YELLOW}  -> 正在生成 Sing-box 全协议核心配置 (/etc/sing-box/config.json)...${PLAIN}"

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
    },
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": 443,
      "users": [
        {
          "name": "direct-user",
          "password": "${DIRECT_UUID}"
        },
        {
          "name": "residential-user",
          "password": "${RESI_UUID}"
        }
      ],
      "masquerade": "https://${CAMOUFLAGE_DOMAIN}",
      "tls": {
        "enabled": true,
        "certificate_path": "${CERT_FILE}",
        "key_path": "${KEY_FILE}",
        "alpn": ["h3"]
      }
    },
    {
      "type": "tuic",
      "tag": "tuic-in",
      "listen": "::",
      "listen_port": 8443,
      "users": [
        {
          "name": "direct-user",
          "uuid": "${DIRECT_UUID}",
          "password": "${SHORT_ID}"
        },
        {
          "name": "residential-user",
          "uuid": "${RESI_UUID}",
          "password": "${SHORT_ID}"
        }
      ],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "certificate_path": "${CERT_FILE}",
        "key_path": "${KEY_FILE}",
        "alpn": ["h3"]
      }
    },
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "::",
      "listen_port": 8444,
      "users": [
        {
          "name": "direct-user",
          "password": "${DIRECT_UUID}"
        },
        {
          "name": "residential-user",
          "password": "${RESI_UUID}"
        }
      ],
      "padding_scheme": "random",
      "tls": {
        "enabled": true,
        "certificate_path": "${CERT_FILE}",
        "key_path": "${KEY_FILE}"
      }
    },
    {
      "type": "vmess",
      "tag": "vmess-in",
      "listen": "::",
      "listen_port": 8445,
      "users": [
        {
          "name": "direct-user",
          "uuid": "${DIRECT_UUID}"
        },
        {
          "name": "residential-user",
          "uuid": "${RESI_UUID}"
        }
      ],
      "transport": {
        "type": "http",
        "path": "/vmess"
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

# 8. 校验 Sing-box 核心配置，如果个别实验性协议在老二进制报错则平滑回退
if ! "$SB_BIN" check -c "$SB_CONFIG_FILE" >/dev/null 2>&1; then
    echo -e "${YELLOW}  -> 检测到 Sing-box 对 AnyTLS 支持受限，调整为四合一主力协议模式...${PLAIN}"
    # 移除 anytls 入站
    python3 -c "
import json
with open('$SB_CONFIG_FILE', 'r') as f:
    cfg = json.load(f)
cfg['inbounds'] = [ib for ib in cfg['inbounds'] if ib.get('type') != 'anytls']
with open('$SB_CONFIG_FILE', 'w') as f:
    json.dump(cfg, f, indent=2)
"
    "$SB_BIN" check -c "$SB_CONFIG_FILE"
fi

echo -e "${GREEN}  -> Sing-box 全协议配置文件校验通过！${PLAIN}"

# 9. 配置与启动 systemd 服务
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
    echo -e "${RED}警告: Sing-box 服务未能正常启动。日志: journalctl -u sing-box -e${PLAIN}"
else
    echo -e "${GREEN}  -> Sing-box 全协议服务已成功启动！${PLAIN}"
fi

# 10. 写入汇总数据
NODES_JSON="$DATA_DIR/singbox_nodes.json"
cat > "$NODES_JSON" <<EOF
{
  "public_ip": "${PUBLIC_IP}",
  "domain": "${DOMAIN}",
  "camouflage_domain": "${CAMOUFLAGE_DOMAIN}",
  "public_key": "${PUBLIC_KEY}",
  "short_id": "${SHORT_ID}",
  "direct_uuid": "${DIRECT_UUID}",
  "resi_uuid": "${RESI_UUID}",
  "vless_port": 443,
  "hy2_port": 443,
  "tuic_port": 8443,
  "anytls_port": 8444,
  "vmess_port": 8445
}
EOF

# 11. 调用 Python 订阅生成引擎产出全格式订阅
if [ -f "$ROOT_DIR/scripts/generate_subs.py" ]; then
    echo -e "${YELLOW}  -> 正在生成 10 大节点矩阵与全平台订阅 (sub.txt, clash.yaml, singbox.json)...${PLAIN}"
    python3 "$ROOT_DIR/scripts/generate_subs.py" "$NODES_JSON" "$WWW_SUB_DIR"
    cp -rf "$WWW_SUB_DIR"/* "$SUB_DIR/" 2>/dev/null || true
    echo -e "${GREEN}  -> 全生态订阅文件已更新并就绪！${PLAIN}"
fi

# 12. 部署并重新载入 Nginx 订阅配置
NGINX_CONF_DEST=""
if [ -d /etc/nginx/conf.d ]; then
    NGINX_CONF_DEST="/etc/nginx/conf.d/aimilivpn-production.conf"
elif [ -d /etc/nginx/http.d ]; then
    NGINX_CONF_DEST="/etc/nginx/http.d/aimilivpn-production.conf"
fi

if [ -n "$NGINX_CONF_DEST" ] && [ -f "$ROOT_DIR/scripts/nginx/aimilivpn-production.conf" ]; then
    install -m 0644 "$ROOT_DIR/scripts/nginx/aimilivpn-production.conf" "$NGINX_CONF_DEST"
    if [ -n "$DOMAIN" ]; then
        sed -i "s/server_name _;/server_name ${DOMAIN};/g" "$NGINX_CONF_DEST"
    fi
fi

if command -v nginx >/dev/null 2>&1; then
    if nginx -t >/dev/null 2>&1; then
        systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1 || true
        echo -e "${GREEN}  -> Nginx 订阅入口 (端口 18443 & /sub/) 已就绪${PLAIN}"
    fi
fi

# 13. 防火墙端口全开 (TCP: 443, 8444, 8445, 18443; UDP: 443, 8443)
if command -v iptables >/dev/null 2>&1; then
    for p in 443 8444 8445 18443; do
        iptables -C INPUT -p tcp --dport "$p" -m comment --comment aimilivpn -j ACCEPT >/dev/null 2>&1 || \
        iptables -I INPUT 1 -p tcp --dport "$p" -m comment --comment aimilivpn -j ACCEPT >/dev/null 2>&1 || true
    done
    for p in 443 8443; do
        iptables -C INPUT -p udp --dport "$p" -m comment --comment aimilivpn -j ACCEPT >/dev/null 2>&1 || \
        iptables -I INPUT 1 -p udp --dport "$p" -m comment --comment aimilivpn -j ACCEPT >/dev/null 2>&1 || true
    done
fi
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow 443/tcp comment aimilivpn >/dev/null 2>&1 || true
    ufw allow 8444/tcp comment aimilivpn >/dev/null 2>&1 || true
    ufw allow 8445/tcp comment aimilivpn >/dev/null 2>&1 || true
    ufw allow 18443/tcp comment aimilivpn >/dev/null 2>&1 || true
    ufw allow 443/udp comment aimilivpn >/dev/null 2>&1 || true
    ufw allow 8443/udp comment aimilivpn >/dev/null 2>&1 || true
fi
if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port={443,8444,8445,18443}/tcp >/dev/null 2>&1 || true
    firewall-cmd --permanent --add-port={443,8443}/udp >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
fi

# 14. 升级全局管理命令 'ml'
if [ -f "$ROOT_DIR/aimili_cli.py" ]; then
    cat > /usr/bin/ml <<'EOF'
#!/usr/bin/env python3
import sys
sys.path.insert(0, "/opt/aimilivpn")
try:
    import aimili_cli
    aimili_cli.main()
except Exception as e:
    sys.stderr.write(f"执行出错: {e}\n")
    raise SystemExit(1)
EOF
    chmod +x /usr/bin/ml
    echo -e "${GREEN}  -> 全局管理命令 'ml' 已升级支持全协议矩阵${PLAIN}"
fi

echo -e "\n${GREEN}==========================================================${PLAIN}"
echo -e "${GREEN}  🎉 AimiliVPN 全协议双出站矩阵与全平台订阅部署成功！${PLAIN}"
echo -e "${GREEN}==========================================================${PLAIN}"

# 15. 打印订阅详情卡片
if [ -f "$ROOT_DIR/aimili_cli.py" ]; then
    python3 "$ROOT_DIR/aimili_cli.py" sub
fi
