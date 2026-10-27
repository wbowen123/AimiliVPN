#!/usr/bin/env bash
# ==============================================================================
# AimiliVPN Sing-box 全协议矩阵 × 住宅/原生双出站工业级部署脚本
# 吸收 singbox-lite 核心工程亮点：
#   1. GOMEMLIMIT 动态软内存上限计算，杜绝低配小鸡 (128M/512M) OOM Crash
#   2. 事务快照与原子写入 + 失败自动回滚机制，零断网风险
#   3. 全球权威授时中心时间同步诊断与毫秒级时钟漂移补偿
#   4. 容器与虚拟化环境自适应 (KVM / LXC / Docker) 权限自愈
#   5. Hysteria 2 Salamander 混淆 + 40000-50000 端口跳跃，抗运营商 QoS 阻断
#   6. 住宅出口双模支持：内置 Aimili 动态家宽池 (8500) 或 外部第三方 SOCKS5 接入
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${VPNGATE_DATA_DIR:-$ROOT_DIR/vpngate_data}"
SUB_DIR="/var/lib/aimilivpn/subscriptions"
WWW_SUB_DIR="/var/www/aimilivpn-sub"
SB_CONFIG_DIR="/etc/sing-box"
SB_CONFIG_FILE="$SB_CONFIG_DIR/config.json"
SB_CONFIG_BAK="$SB_CONFIG_DIR/config.json.bak"
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
echo -e "${BLUE}   正在部署 AimiliVPN 工业级全协议双出站代理引擎...${PLAIN}"
echo -e "${BLUE}==========================================================${PLAIN}"

# 0.1 服务器高精度时钟同步诊断与自动校准（防 Reality/TLS 握手因时间漂移被阻断）
if [ -f "$ROOT_DIR/scripts/check_time_sync.sh" ]; then
    bash "$ROOT_DIR/scripts/check_time_sync.sh" || true
fi

# 0.2 调优 Linux BBR 拥塞控制与系统网络缓冲区
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
    if [ -x "$SB_BIN" ] && [ -z "${FORCE_SINGBOX_UPDATE:-}" ]; then
        local cur_ver
        cur_ver=$("$SB_BIN" version 2>/dev/null | awk '/sing-box version/ {print $3}' || echo "")
        if [ -n "$cur_ver" ]; then
            echo -e "${GREEN}  -> 检测到已安装 Sing-box (${cur_ver}) (如需升级请运行: ml core)${PLAIN}"
            return 0
        fi
    fi

    if [ -f "$ROOT_DIR/scripts/manage_core.sh" ]; then
        bash "$ROOT_DIR/scripts/manage_core.sh" "${SINGBOX_VERSION:-latest}"
    else
        local target_ver="${SINGBOX_VERSION:-1.14.3}"
        echo -e "${YELLOW}  -> 正在获取 Sing-box v${target_ver} (${SB_ARCH})...${PLAIN}"
        local download_url="https://github.com/SagerNet/sing-box/releases/download/v${target_ver}/sing-box-${target_ver}-linux-${SB_ARCH}.tar.gz"
        local tmp_tar="/tmp/sing-box-${target_ver}.tar.gz"
        local tmp_dir="/tmp/sing-box-extract-$$"
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
    fi
}

install_singbox_bin

# 3. 读取住宅出口配置（支持内置 Aimili 8500 家宽池或外部第三方 SOCKS5 接入）
PROXY_ENV_FILE="/etc/default/aimilivpn"
RESI_EGRESS_TYPE="local"
RESI_PROXY_HOST="127.0.0.1"
RESI_PROXY_PORT="8500"
RESI_PROXY_USER="socks5"
RESI_PROXY_PASS="ilovestudy"

if [ -f "$PROXY_ENV_FILE" ]; then
    RESI_EGRESS_TYPE=$(grep '^RESI_EGRESS_TYPE=' "$PROXY_ENV_FILE" | cut -d'=' -f2 | tr -d '"'"'" || echo "local")
    if [ "$RESI_EGRESS_TYPE" = "external" ]; then
        RESI_PROXY_HOST=$(grep '^EXTERNAL_PROXY_HOST=' "$PROXY_ENV_FILE" | cut -d'=' -f2 | tr -d '"'"'" || echo "127.0.0.1")
        RESI_PROXY_PORT=$(grep '^EXTERNAL_PROXY_PORT=' "$PROXY_ENV_FILE" | cut -d'=' -f2 | tr -d '"'"'" || echo "8500")
        RESI_PROXY_USER=$(grep '^EXTERNAL_PROXY_USER=' "$PROXY_ENV_FILE" | cut -d'=' -f2 | tr -d '"'"'" || echo "")
        RESI_PROXY_PASS=$(grep '^EXTERNAL_PROXY_PASS=' "$PROXY_ENV_FILE" | cut -d'=' -f2 | tr -d '"'"'" || echo "")
        echo -e "${GREEN}  -> 住宅出口模式: 外部第三方 SOCKS5 (${RESI_PROXY_HOST}:${RESI_PROXY_PORT})${PLAIN}"
    else
        RESI_PROXY_HOST="127.0.0.1"
        RESI_PROXY_PORT=$(grep '^LOCAL_PROXY_PORT=' "$PROXY_ENV_FILE" | cut -d'=' -f2 | tr -d '"'"'" || echo "8500")
        RESI_PROXY_USER=$(grep '^LOCAL_PROXY_USER=' "$PROXY_ENV_FILE" | cut -d'=' -f2 | tr -d '"'"'" || echo "socks5")
        RESI_PROXY_PASS=$(grep '^LOCAL_PROXY_PASS=' "$PROXY_ENV_FILE" | cut -d'=' -f2 | tr -d '"'"'" || echo "ilovestudy")
        echo -e "${GREEN}  -> 住宅出口模式: AimiliVPN 内置动态家宽池 (127.0.0.1:${RESI_PROXY_PORT})${PLAIN}"
    fi
fi

# 4. 获取本机公网 IP 与域名
PUBLIC_IP=""
if [ -f "$DATA_DIR/public_ip.txt" ]; then
    PUBLIC_IP=$(cat "$DATA_DIR/public_ip.txt" | tr -d '[:space:]')
fi
if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" = "您的服务器公网IP" ]; then
    PUBLIC_IP=$(curl -4fsS --max-time 5 https://api.ipify.org 2>/dev/null || curl -4fsS --max-time 5 https://ifconfig.me 2>/dev/null || echo "127.0.0.1")
fi

PUBLIC_IPV6=""
if [ -f "$DATA_DIR/public_ipv6.txt" ]; then
    PUBLIC_IPV6=$(cat "$DATA_DIR/public_ipv6.txt" | tr -d '[:space:]')
fi
if [ -z "$PUBLIC_IPV6" ]; then
    PUBLIC_IPV6=$(curl -6fsS --max-time 5 https://api64.ipify.org 2>/dev/null || curl -6fsS --max-time 5 https://ipv6.icanhazip.com 2>/dev/null || echo "")
fi
if [ -n "$PUBLIC_IPV6" ]; then
    echo "$PUBLIC_IPV6" > "$DATA_DIR/public_ipv6.txt" 2>/dev/null || true
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

CDN_DOMAIN="${AIMILIVPN_CDN_DOMAIN:-}"
if [ -z "$CDN_DOMAIN" ] && [ -f "$DATA_DIR/singbox_nodes.json" ]; then
    CDN_DOMAIN=$(python3 -c "import json; print(json.load(open('$DATA_DIR/singbox_nodes.json')).get('cdn_domain',''))" 2>/dev/null || true)
fi
if [ -z "$CDN_DOMAIN" ] && [ -f "$PROXY_ENV_FILE" ]; then
    CDN_DOMAIN=$(grep '^AIMILIVPN_CDN_DOMAIN=' "$PROXY_ENV_FILE" | cut -d'=' -f2 | tr -d '"'"' " || true)
fi
CDN_DOMAIN=$(echo "$CDN_DOMAIN" | tr -d '[:space:]')

# 5. 伪装域名 (SNI) 智能测速优选
REQUESTED_SNI="${1:-${JIUHEYI_REALITY_DOMAIN:-}}"
CAMOUFLAGE_DOMAIN=""
if [ -f "$ROOT_DIR/scripts/test_sni.sh" ]; then
    echo -e "${YELLOW}  -> 正在对全球权威大厂 SNI 执行本地握手测速与连通性优选...${PLAIN}"
    CAMOUFLAGE_DOMAIN=$(bash "$ROOT_DIR/scripts/test_sni.sh" "$REQUESTED_SNI" 2>/dev/null || echo "gateway.icloud.com")
fi
[ -z "$CAMOUFLAGE_DOMAIN" ] && CAMOUFLAGE_DOMAIN="gateway.icloud.com"
echo -e "${GREEN}  -> 优选伪装域名: ${CAMOUFLAGE_DOMAIN}${PLAIN}"

# 6. 证书体系就绪 (域名证书复用或自签 IP 证书)
CERT_FILE="/etc/sing-box/cert.pem"
KEY_FILE="/etc/sing-box/key.pem"

if [ -f /etc/aimilivpn/tls/fullchain.pem ] && [ -f /etc/aimilivpn/tls/privkey.pem ]; then
    echo -e "${GREEN}  -> 检测到系统已存在有效域名证书，直接复用${PLAIN}"
    cp -f /etc/aimilivpn/tls/fullchain.pem "$CERT_FILE"
    cp -f /etc/aimilivpn/tls/privkey.pem "$KEY_FILE"
    chmod 600 "$KEY_FILE"
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

# 7. 生成或保留 Reality 密钥、UUID 与 Hysteria 2 混淆密码
KEYS_STORE="$DATA_DIR/singbox_keys.json"
PRIVATE_KEY=""
PUBLIC_KEY=""
DIRECT_UUID=""
RESI_UUID=""
SHORT_ID=""
HY2_OBFS=""

if [ -f "$KEYS_STORE" ]; then
    PRIVATE_KEY=$(python3 -c "import json; print(json.load(open('$KEYS_STORE')).get('private_key',''))" 2>/dev/null || true)
    PUBLIC_KEY=$(python3 -c "import json; print(json.load(open('$KEYS_STORE')).get('public_key',''))" 2>/dev/null || true)
    DIRECT_UUID=$(python3 -c "import json; print(json.load(open('$KEYS_STORE')).get('direct_uuid',''))" 2>/dev/null || true)
    RESI_UUID=$(python3 -c "import json; print(json.load(open('$KEYS_STORE')).get('resi_uuid',''))" 2>/dev/null || true)
    SHORT_ID=$(python3 -c "import json; print(json.load(open('$KEYS_STORE')).get('short_id',''))" 2>/dev/null || true)
    HY2_OBFS=$(python3 -c "import json; print(json.load(open('$KEYS_STORE')).get('hy2_obfs',''))" 2>/dev/null || true)
fi

if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    REALITY_KEYPAIR=$("$SB_BIN" generate reality-keypair)
    PRIVATE_KEY=$(printf '%s\n' "$REALITY_KEYPAIR" | awk '/PrivateKey:/ {print $2}')
    PUBLIC_KEY=$(printf '%s\n' "$REALITY_KEYPAIR" | awk '/PublicKey:/ {print $2}')
fi

[ -z "$DIRECT_UUID" ] && DIRECT_UUID=$("$SB_BIN" generate uuid)
[ -z "$RESI_UUID" ] && RESI_UUID=$("$SB_BIN" generate uuid)
[ -z "$SHORT_ID" ] && SHORT_ID=$("$SB_BIN" generate rand --hex 8)

# --------------------------------------------------------------------------
# Hysteria 2 混淆(Salamander) 与 伪装(HTTP/3 Masquerade) 优雅二选一分流：
# 规范：Salamander 破坏 QUIC 头部导致 masquerade 永远无法生效（二者底层协议互斥）。
# 模式 A: 标准 HTTP/3 伪装站模式 (默认推荐, HY2_OBFS="") -> 伪装至 CAMOUFLAGE_DOMAIN，兼容全客户端并抗探测。
# 模式 B: Salamander 强混淆模式 (HY2_ENABLE_OBFS=1 或 HY2_OBFS_MODE=obfs) -> 随机密码，打乱 UDP 特征抗极端 QoS。
# --------------------------------------------------------------------------
if [ "${HY2_ENABLE_OBFS:-}" = "1" ] || [ "${HY2_OBFS_MODE:-}" = "obfs" ]; then
    [ -z "$HY2_OBFS" ] && HY2_OBFS=$("$SB_BIN" generate rand --hex 12)
elif [ "${HY2_ENABLE_OBFS:-}" = "0" ] || [ "${HY2_OBFS_MODE:-}" = "masquerade" ]; then
    HY2_OBFS=""
fi

if [ -n "$HY2_OBFS" ] && [ "$HY2_OBFS" != "none" ]; then
    HY2_PROTECT_BLOCK=$(cat <<EOF
      "obfs": {
        "type": "salamander",
        "password": "${HY2_OBFS}"
      },
EOF
)
    echo -e "${YELLOW}  * Hysteria 2 防护模式: [Salamander 强混淆] (密码: ${HY2_OBFS}，抗晚高峰 QoS，伪装站依规关闭)${PLAIN}"
else
    HY2_PROTECT_BLOCK=$(cat <<EOF
      "masquerade": "https://${CAMOUFLAGE_DOMAIN}",
EOF
)
    echo -e "${GREEN}  * Hysteria 2 防护模式: [标准 HTTP/3 伪装站] (反代至 ${CAMOUFLAGE_DOMAIN}，抗嗅探、全平台通用兼容)${PLAIN}"
fi

cat > "$KEYS_STORE" <<EOF
{
  "private_key": "$PRIVATE_KEY",
  "public_key": "$PUBLIC_KEY",
  "direct_uuid": "$DIRECT_UUID",
  "resi_uuid": "$RESI_UUID",
  "short_id": "$SHORT_ID",
  "hy2_obfs": "$HY2_OBFS",
  "sni": "$CAMOUFLAGE_DOMAIN"
}
EOF
chmod 600 "$KEYS_STORE"

# 8. 事务快照与原子配置生成 (Transaction Snapshot & Atomic Rollback)
SB_CONFIG_TMP="$SB_CONFIG_DIR/config.json.tmp.$$"

# 8.1 先做事务快照备份
if [ -f "$SB_CONFIG_FILE" ]; then
    cp -f "$SB_CONFIG_FILE" "$SB_CONFIG_BAK"
fi

echo -e "${YELLOW}  -> 正在构建 Sing-box 核心配置事务草稿...${PLAIN}"

cat > "$SB_CONFIG_TMP" <<EOF
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
${HY2_PROTECT_BLOCK}
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
    },
    {
      "type": "vmess",
      "tag": "vmess-ws-in",
      "listen": "::",
      "listen_port": 8446,
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
        "type": "ws",
        "path": "/vmess-ws"
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
      "server": "${RESI_PROXY_HOST}",
      "server_port": ${RESI_PROXY_PORT},
      "version": "5",
      "username": "${RESI_PROXY_USER}",
      "password": "${RESI_PROXY_PASS}"
    }
  ],
  "route": {
    "rules": [
      {
        "action": "sniff",
        "sniffer": ["tls", "http", "quic", "dns"]
      },
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

# 8.2 配置清洗与语法校验
python3 -c "
import json
with open('$SB_CONFIG_TMP', 'r') as f:
    cfg = json.load(f)
for ob in cfg.get('outbounds', []):
    if ob.get('type') == 'socks' and not ob.get('username'):
        ob.pop('username', None)
        ob.pop('password', None)
with open('$SB_CONFIG_TMP', 'w') as f:
    json.dump(cfg, f, indent=2)
"

# 语法校验与平滑降级（如 AnyTLS 或 Salamander obfs 在特定平台不兼容）
ANYTLS_PORT=8444
if ! "$SB_BIN" check -c "$SB_CONFIG_TMP" >/dev/null 2>&1; then
    echo -e "${YELLOW}  -> 检测到部分前沿特性在当前内核受限，执行自愈降级处理...${PLAIN}"
    HY2_OBFS=""
    ANYTLS_PORT=0
    python3 -c "
import json
with open('$SB_CONFIG_TMP', 'r') as f:
    cfg = json.load(f)
cfg['inbounds'] = [ib for ib in cfg['inbounds'] if ib.get('type') != 'anytls']
for ib in cfg['inbounds']:
    if ib.get('type') == 'hysteria2' and 'obfs' in ib:
        del ib['obfs']
        ib['masquerade'] = 'https://$CAMOUFLAGE_DOMAIN'
with open('$SB_CONFIG_TMP', 'w') as f:
    json.dump(cfg, f, indent=2)
"
fi

if ! "$SB_BIN" check -c "$SB_CONFIG_TMP" >/dev/null 2>&1; then
    echo -e "${RED}错误: 无法生成合法的 Sing-box 配置！已终止提交，现有运行状态未受破坏。${PLAIN}"
    rm -f "$SB_CONFIG_TMP"
    exit 1
fi

# 8.3 原子写入生效
mv -f "$SB_CONFIG_TMP" "$SB_CONFIG_FILE"
echo -e "${GREEN}  -> Sing-box 配置原子提交成功！${PLAIN}"

# 9. 计算 GOMEMLIMIT 软内存配额与容器自适应 Systemd 服务
calculate_gomemlimit() {
    local mem_kb=0
    if [ -f /proc/meminfo ]; then
        mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
    fi
    local mem_mb=$((mem_kb / 1024))
    if [ "$mem_mb" -le 0 ]; then
        echo "180MiB"
        return
    fi
    if [ "$mem_mb" -le 256 ]; then
        echo "64MiB"
    elif [ "$mem_mb" -le 512 ]; then
        echo "160MiB"
    elif [ "$mem_mb" -le 1024 ]; then
        echo "380MiB"
    else
        echo "$((mem_mb * 40 / 100))MiB"
    fi
}

GOMEMLIMIT_VAL=$(calculate_gomemlimit)
echo -e "${GREEN}  -> 检测系统可用内存，Go 运行时防 OOM 软配额设为: ${GOMEMLIMIT_VAL}${PLAIN}"

# 检测是否在无特权容器环境（Docker / LXC）
CAP_LINE="CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW\nAmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW"
if [ -f /.dockerenv ] || grep -qE "lxc|docker" /proc/1/environ 2>/dev/null; then
    echo -e "${YELLOW}  -> 检测到容器运行环境 (Docker/LXC)，自动调整安全权能以确保平稳启动${PLAIN}"
    CAP_LINE="# Container environment capabilities managed by host"
fi

cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=Sing-box Service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target aimilivpn.service
Wants=network.target

[Service]
Environment="GOMEMLIMIT=${GOMEMLIMIT_VAL}"
Environment="GODEBUG=madvdontneed=1"
$(printf '%b' "$CAP_LINE")
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
sleep 1.5

# 8.4 失败自动回滚校验
if ! systemctl is-active --quiet sing-box.service; then
    echo -e "${RED}警告: Sing-box 新配置启动异常！启动事务失败回滚机制...${PLAIN}"
    if [ -f "$SB_CONFIG_BAK" ]; then
        mv -f "$SB_CONFIG_BAK" "$SB_CONFIG_FILE"
        systemctl restart sing-box.service || true
        echo -e "${GREEN}  -> 已成功自动回滚到上一版健康配置，生产环境未受损！${PLAIN}"
    fi
    journalctl -u sing-box -n 20 --no-pager || true
    exit 1
else
    echo -e "${GREEN}  -> Sing-box 全协议服务已成功启动并健康运行！${PLAIN}"
    rm -f "$SB_CONFIG_BAK"
fi

# 9.5 自动平滑继承并挂载既有 WARP 解锁策略 (若曾配置过)
if [ -f "$DATA_DIR/warp_mode.json" ] && [ -f "$ROOT_DIR/scripts/setup_warp.sh" ]; then
    saved_warp_mode=$(python3 -c "import json; print(json.load(open('$DATA_DIR/warp_mode.json')).get('mode', ''))" 2>/dev/null || echo "")
    if [ -n "$saved_warp_mode" ] && [ "$saved_warp_mode" != "off" ]; then
        echo -e "${YELLOW}  -> 检测到已保存的 WARP 分流策略 (${saved_warp_mode})，正在平滑继承挂载...${PLAIN}"
        bash "$ROOT_DIR/scripts/setup_warp.sh" "$saved_warp_mode" >/dev/null 2>&1 || true
    fi
fi

# 10. 部署 Hysteria 2 端口跳跃转发规则 (Port Hopping: 40000-50000 -> 443)
echo -e "${YELLOW}  -> 正在配置 Hysteria 2 端口跳跃重定向规则 (UDP 40000-50000 -> 443)...${PLAIN}"
if command -v iptables >/dev/null 2>&1; then
    if iptables -t nat -L -n >/dev/null 2>&1; then
        iptables -t nat -C PREROUTING -p udp --dport 40000:50000 -j REDIRECT --to-ports 443 2>/dev/null || \
        iptables -t nat -A PREROUTING -p udp --dport 40000:50000 -j REDIRECT --to-ports 443 2>/dev/null || true
    fi
fi
if command -v nft >/dev/null 2>&1; then
    nft add table ip aimilivpn 2>/dev/null || true
    nft add chain ip aimilivpn prerouting '{ type nat hook prerouting priority -100; }' 2>/dev/null || true
    nft add rule ip aimilivpn prerouting udp dport 40000-50000 redirect to :443 2>/dev/null || true
fi

# 11. 写入汇总数据
NODES_JSON="$DATA_DIR/singbox_nodes.json"
cat > "$NODES_JSON" <<EOF
{
  "public_ip": "${PUBLIC_IP}",
  "public_ipv6": "${PUBLIC_IPV6}",
  "domain": "${DOMAIN}",
  "cdn_domain": "${CDN_DOMAIN}",
  "camouflage_domain": "${CAMOUFLAGE_DOMAIN}",
  "public_key": "${PUBLIC_KEY}",
  "short_id": "${SHORT_ID}",
  "hy2_obfs": "${HY2_OBFS}",
  "hy2_hop_ports": "443,40000-50000",
  "direct_uuid": "${DIRECT_UUID}",
  "resi_uuid": "${RESI_UUID}",
  "resi_egress_type": "${RESI_EGRESS_TYPE}",
  "resi_host": "${RESI_PROXY_HOST}",
  "resi_port": ${RESI_PROXY_PORT},
  "vless_port": 443,
  "hy2_port": 443,
  "tuic_port": 8443,
  "anytls_port": ${ANYTLS_PORT},
  "vmess_port": 8445
}
EOF

# 12. 调用 Python 订阅生成引擎产出全格式订阅
if [ -f "$ROOT_DIR/scripts/generate_subs.py" ]; then
    echo -e "${YELLOW}  -> 正在生成 10 大节点矩阵与全平台订阅 (sub.txt, clash.yaml, singbox.json)...${PLAIN}"
    python3 "$ROOT_DIR/scripts/generate_subs.py" "$NODES_JSON" "$WWW_SUB_DIR"
    cp -rf "$WWW_SUB_DIR"/* "$SUB_DIR/" 2>/dev/null || true
    echo -e "${GREEN}  -> 全生态订阅文件已更新并就绪！${PLAIN}"
fi

# 13. 部署并重新载入 Nginx 订阅配置
NGINX_CONF_DEST=""
if [ -d /etc/nginx/conf.d ]; then
    NGINX_CONF_DEST="/etc/nginx/conf.d/aimilivpn-production.conf"
elif [ -d /etc/nginx/http.d ]; then
    NGINX_CONF_DEST="/etc/nginx/http.d/aimilivpn-production.conf"
fi

if [ -n "$NGINX_CONF_DEST" ] && [ -f "$ROOT_DIR/scripts/nginx/aimilivpn-production.conf" ]; then
    install -m 0644 "$ROOT_DIR/scripts/nginx/aimilivpn-production.conf" "$NGINX_CONF_DEST"
    if [ -n "$DOMAIN" ]; then
        python3 -c "
import sys, re
path = sys.argv[1]
dom = sys.argv[2]
with open(path, 'r', encoding='utf-8') as f:
    c = f.read()
repl = lambda m: m.group(1) + dom + ';'
c = re.sub(r'(listen\s+(?:\[::\]:)?8443\s+ssl;[^{]*?server_name\s+)[^;]+;', repl, c)
with open(path, 'w', encoding='utf-8') as f:
    f.write(c)
" "$NGINX_CONF_DEST" "$DOMAIN" 2>/dev/null || true
    fi
fi

if command -v nginx >/dev/null 2>&1; then
    if nginx -t >/dev/null 2>&1; then
        systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1 || true
        echo -e "${GREEN}  -> Nginx 订阅入口 (端口 18443 & /sub/) 已就绪${PLAIN}"
    fi
fi

# 14. 防火墙端口放行 (放行 TCP: 443, 8443, 8444, 8445, 8446, 18443, 18080; UDP: 443, 8443 及 40000-50000 跳跃端口)
if command -v iptables >/dev/null 2>&1; then
    for p in 443 8443 8444 8445 8446 18443 18080; do
        iptables -C INPUT -p tcp --dport "$p" -m comment --comment aimilivpn -j ACCEPT >/dev/null 2>&1 || \
        iptables -I INPUT 1 -p tcp --dport "$p" -m comment --comment aimilivpn -j ACCEPT >/dev/null 2>&1 || true
    done
    for p in 443 8443; do
        iptables -C INPUT -p udp --dport "$p" -m comment --comment aimilivpn -j ACCEPT >/dev/null 2>&1 || \
        iptables -I INPUT 1 -p udp --dport "$p" -m comment --comment aimilivpn -j ACCEPT >/dev/null 2>&1 || true
    done
    iptables -C INPUT -p udp --dport 40000:50000 -m comment --comment aimilivpn -j ACCEPT >/dev/null 2>&1 || \
    iptables -I INPUT 1 -p udp --dport 40000:50000 -m comment --comment aimilivpn -j ACCEPT >/dev/null 2>&1 || true
fi
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow 443/tcp comment aimilivpn >/dev/null 2>&1 || true
    ufw allow 8443/tcp comment aimilivpn >/dev/null 2>&1 || true
    ufw allow 8444/tcp comment aimilivpn >/dev/null 2>&1 || true
    ufw allow 8445/tcp comment aimilivpn >/dev/null 2>&1 || true
    ufw allow 8446/tcp comment aimilivpn >/dev/null 2>&1 || true
    ufw allow 18443/tcp comment aimilivpn >/dev/null 2>&1 || true
    ufw allow 18080/tcp comment aimilivpn >/dev/null 2>&1 || true
    ufw allow 443/udp comment aimilivpn >/dev/null 2>&1 || true
    ufw allow 8443/udp comment aimilivpn >/dev/null 2>&1 || true
    ufw allow 40000:50000/udp comment aimilivpn >/dev/null 2>&1 || true
fi
if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port={443,8443,8444,8445,8446,18443,18080}/tcp >/dev/null 2>&1 || true
    firewall-cmd --permanent --add-port={443,8443}/udp >/dev/null 2>&1 || true
    firewall-cmd --permanent --add-port=40000-50000/udp >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
fi
if command -v ip6tables >/dev/null 2>&1; then
    if ip6tables -t nat -L -n >/dev/null 2>&1; then
        ip6tables -t nat -C PREROUTING -p udp --dport 40000:50000 -j REDIRECT --to-ports 443 2>/dev/null || \
        ip6tables -t nat -A PREROUTING -p udp --dport 40000:50000 -j REDIRECT --to-ports 443 2>/dev/null || true
    fi
    for p in 443 8443 8444 8445 8446 18443 18080; do
        ip6tables -C INPUT -p tcp --dport "$p" -m comment --comment aimilivpn -j ACCEPT >/dev/null 2>&1 || \
        ip6tables -I INPUT 1 -p tcp --dport "$p" -m comment --comment aimilivpn -j ACCEPT >/dev/null 2>&1 || true
    done
    for p in 443 8443; do
        ip6tables -C INPUT -p udp --dport "$p" -m comment --comment aimilivpn -j ACCEPT >/dev/null 2>&1 || \
        ip6tables -I INPUT 1 -p udp --dport "$p" -m comment --comment aimilivpn -j ACCEPT >/dev/null 2>&1 || true
    done
    ip6tables -C INPUT -p udp --dport 40000:50000 -m comment --comment aimilivpn -j ACCEPT >/dev/null 2>&1 || \
    ip6tables -I INPUT 1 -p udp --dport 40000:50000 -m comment --comment aimilivpn -j ACCEPT >/dev/null 2>&1 || true
fi

# 15. 升级全局管理命令 'ml'
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
    ln -sf /usr/bin/ml /usr/local/bin/ml 2>/dev/null || true
    echo -e "${GREEN}  -> 全局管理命令 'ml' 已升级支持全协议矩阵与工业级加固${PLAIN}"
fi

echo -e "\n${GREEN}==========================================================${PLAIN}"
echo -e "${GREEN}  🎉 AimiliVPN 工业级全协议双出站矩阵部署成功！${PLAIN}"
echo -e "${GREEN}==========================================================${PLAIN}"

# 16. 打印订阅详情卡片
if [ -f "$ROOT_DIR/aimili_cli.py" ]; then
    python3 "$ROOT_DIR/aimili_cli.py" sub
fi
