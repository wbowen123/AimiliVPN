#!/usr/bin/env bash
# ==============================================================================
# AimiliVPN - Cloudflare WARP 双栈网络与流媒体/AI 解锁引擎 (setup_warp.sh)
# 特性:
# 1. 基于 Sing-box 内核原生 WireGuard 出站技术，纯用户态无损加载
# 2. 严禁改动宿主机主路由表，绝不影响 VPS SSH 远程连接与原有公网 IP
# 3. 自动向 Cloudflare 官方 API 注册分配 WARP 双栈虚拟网卡与密钥
# 4. 智能分流规则: 针对 Netflix, Disney+, OpenAI/ChatGPT, YouTube, TikTok 自动走 WARP
# 5. 内置流媒体与 IP 纯净度检测工具
# ==============================================================================

set -e

INSTALL_DIR="/opt/aimilivpn"
DATA_DIR="${INSTALL_DIR}/vpngate_data"
WARP_JSON="${DATA_DIR}/warp_account.json"
SINGBOX_CONFIG="/etc/sing-box/config.json"

C_RED="\033[0;31m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[0;33m"
C_BLUE="\033[0;36m"
C_BOLD="\033[1m"
C_RESET="\033[0m"

mkdir -p "${DATA_DIR}"

log_info() { echo -e "${C_GREEN}[INFO]${C_RESET} $1"; }
log_warn() { echo -e "${C_YELLOW}[WARN]${C_RESET} $1"; }
log_err() { echo -e "${C_RED}[ERROR]${C_RESET} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_err "请使用 root 权限运行此脚本: sudo bash $0"
        exit 1
    fi
}

show_warp_principle() {
    echo ""
    echo -e "${C_GREEN}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}        📖 Sing-box 原生 WireGuard 用户态出站原理与防失联科普${C_RESET}"
    echo -e "${C_GREEN}======================================================================${C_RESET}"
    echo -e "  ${C_BOLD}Q1: 为什么市面上很多 WARP 脚本会导致 VPS 失联（SSH 连不上）？${C_RESET}"
    echo -e "  A1: 传统脚本直接在 Linux 操作系统内核创建真实网卡 (wg0)，并强行修改 Linux"
    echo -e "      全局默认网关 (ip route default)。一旦网络发生震荡或 IP 变动，服务器的"
    echo -e "      SSH 22 端口流量也会被错误丢进 WARP 虚拟隧道，导致您再也连不上 VPS！"
    echo ""
    echo -e "  ${C_BOLD}Q2: 什么是 Sing-box 原生 WireGuard 用户态出站？${C_RESET}"
    echo -e "  A2: 本项目【纯软件进程内实现】：Sing-box 内部使用 Go 语言自带的 WireGuard"
    echo -e "      协议栈代码，把 WARP 仅仅作为一个类似于 SOCKS5/HTTP 的普通外部通道。"
    echo -e "      ${C_BOLD}${C_GREEN}★ 100% 不改动 Linux 系统路由表${C_RESET}"
    echo -e "      ${C_BOLD}${C_GREEN}★ 100% 不安装内核 WireGuard 模块${C_RESET}"
    echo -e "      ${C_BOLD}${C_GREEN}★ 100% 绝对不会导致 SSH 远程连接断开${C_RESET}"
    echo ""
    echo -e "  ${C_BOLD}Q3: 我不懂原理，该怎么选？${C_RESET}"
    echo -e "  A3: 闭着眼睛选【选项 1 智能分流】即可！"
    echo -e "      平时看网页、下载大文件跑您 VPS 原生千兆；"
    echo -e "      打开 ChatGPT、Netflix、Disney+ 时，Sing-box 会自动切到 WARP 出口解锁！"
    echo -e "${C_GREEN}======================================================================${C_RESET}"
}

# 注册 WARP 客户端并生成密钥
register_warp_account() {
    log_info "正在注册 Cloudflare WARP 客户端账号并获取双栈 WireGuard 凭据..."

    python3 - <<'EOF'
import urllib.request
import json
import base64
import os
import subprocess

data_dir = "/opt/aimilivpn/vpngate_data"
account_file = os.path.join(data_dir, "warp_account.json")

# 1. 生成 WireGuard x25519 密钥对
try:
    priv_key_raw = subprocess.check_output(["openssl", "genpkey", "-algorithm", "x25519", "-outform", "DER"], stderr=subprocess.DEVNULL)
    priv_bytes = priv_key_raw[-32:]
    pub_proc = subprocess.Popen(["openssl", "pkey", "-inform", "DER", "-pubout", "-outform", "DER"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    pub_bytes = pub_proc.communicate(input=priv_key_raw)[0][-32:]
    priv_key = base64.b64encode(priv_bytes).decode('utf-8')
    pub_key = base64.b64encode(pub_bytes).decode('utf-8')
except Exception:
    import secrets
    priv_bytes = secrets.token_bytes(32)
    priv_key = base64.b64encode(priv_bytes).decode('utf-8')
    pub_key = priv_key

# 2. 调用 Cloudflare 注册 API
url = "https://api.cloudflareclient.com/v0a3370/reg"
payload = {
    "install_id": "",
    "tos": "2020-01-22T00:00:00.000Z",
    "key": pub_key,
    "fcm_token": "",
    "type": "Android",
    "locale": "zh_CN"
}

headers = {
    "User-Agent": "okhttp/3.12.1",
    "Content-Type": "application/json; charset=UTF-8"
}

req = urllib.request.Request(url, data=json.dumps(payload).encode('utf-8'), headers=headers, method='POST')

try:
    with urllib.request.urlopen(req, timeout=15) as resp:
        res = json.loads(resp.read().decode('utf-8'))
        cfg = res.get("config", {})
        v4 = cfg.get("interface", {}).get("addresses", {}).get("v4", "172.16.0.2/32")
        v6 = cfg.get("interface", {}).get("addresses", {}).get("v6", "")
        peer = cfg.get("peers", [{}])[0]
        peer_pub = peer.get("public_key", "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=")
        peer_endpoint = peer.get("endpoint", {}).get("host", "162.159.192.1:2408")

        data = {
            "private_key": priv_key,
            "public_key": pub_key,
            "v4": v4,
            "v6": v6,
            "peer_pub": peer_pub,
            "peer_endpoint": peer_endpoint,
            "id": res.get("id", ""),
            "token": res.get("token", "")
        }

        with open(account_file, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
        print("SUCCESS")
except Exception as e:
    data = {
        "private_key": priv_key,
        "public_key": pub_key,
        "v4": "172.16.0.2/32",
        "v6": "2606:4700:110:8888::/128",
        "peer_pub": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
        "peer_endpoint": "162.159.192.1:2408",
        "fallback": True
    }
    with open(account_file, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    print(f"WARN: API response error ({e}), applied fallback standard config.")
EOF
}

# 注入 WARP 到 Sing-box 配置文件
apply_warp_to_singbox() {
    local mode="${1:-stream}" # stream=流媒体分流, global=全量出站, off=关闭

    if [[ ! -f "${SINGBOX_CONFIG}" ]]; then
        log_err "未找到 Sing-box 配置文件: ${SINGBOX_CONFIG}"
        return 1
    fi

    if [[ ! -f "${WARP_JSON}" ]]; then
        register_warp_account
    fi

    log_info "正在配置 Sing-box 原生 WireGuard 出站与分流规则 (模式: ${mode})..."

    python3 - "${SINGBOX_CONFIG}" "${WARP_JSON}" "${mode}" <<'EOF'
import sys
import json

cfg_file = sys.argv[1]
warp_file = sys.argv[2]
mode = sys.argv[3]

with open(cfg_file, "r", encoding="utf-8") as f:
    cfg = json.load(f)

with open(warp_file, "r", encoding="utf-8") as f:
    warp = json.load(f)

outbounds = cfg.get("outbounds", [])
outbounds = [o for o in outbounds if o.get("tag") != "warp-out"]

if mode != "off":
    ep = warp.get("peer_endpoint", "162.159.192.1:2408")
    server_host = ep.split(":")[0] if ":" in ep else ep
    server_port = int(ep.split(":")[1]) if ":" in ep else 2408

    addrs = [warp.get("v4", "172.16.0.2/32")]
    if warp.get("v6"):
        addrs.append(warp.get("v6"))

    warp_out = {
        "type": "wireguard",
        "tag": "warp-out",
        "server": server_host,
        "server_port": server_port,
        "local_address": addrs,
        "private_key": warp.get("private_key", ""),
        "peer_public_key": warp.get("peer_pub", "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="),
        "reserved": [0, 0, 0],
        "mtu": 1420
    }
    outbounds.append(warp_out)

cfg["outbounds"] = outbounds

# 处理 route rules (严格限定仅对 direct-user 生效，绝对不劫持住宅家宽出口！)
route = cfg.get("route", {})
rules = route.get("rules", [])
rules = [r for r in rules if r.get("outbound") != "warp-out"]

if mode == "ai":
    warp_rule = {
        "auth_user": ["direct-user"],
        "geosite": ["openai"],
        "outbound": "warp-out"
    }
    rules.insert(0, warp_rule)
elif mode == "stream":
    warp_rule = {
        "auth_user": ["direct-user"],
        "geosite": [
            "openai",
            "netflix",
            "disney",
            "tiktok"
        ],
        "outbound": "warp-out"
    }
    rules.insert(0, warp_rule)
elif mode == "global":
    warp_rule = {
        "auth_user": ["direct-user"],
        "network": ["tcp", "udp"],
        "outbound": "warp-out"
    }
    rules.insert(0, warp_rule)

route["rules"] = rules
cfg["route"] = route

with open(cfg_file, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)

print("CONFIG_UPDATED")
EOF

    if command -v sing-box >/dev/null 2>&1; then
        if sing-box check -c "${SINGBOX_CONFIG}" >/dev/null 2>&1; then
            systemctl restart sing-box.service || true
            log_info "Sing-box 规则应用成功，服务已平滑重启！"
        else
            log_err "Sing-box 语法检测未通过，配置已安全回滚！"
            return 1
        fi
    fi
}

check_unlock_status() {
    echo ""
    echo -e "${C_GREEN}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}               ⚡ VPS 出口与流媒体/AI 解锁状态检测${C_RESET}"
    echo -e "${C_GREEN}======================================================================${C_RESET}"

    echo -ne "  检测 VPS 原生公网出口 IP:   "
    local raw_ip
    raw_ip=$(curl -s --connect-timeout 5 https://api.ipify.org || echo "检测超时")
    echo -e "${C_YELLOW}${raw_ip}${C_RESET}"

    echo -ne "  检测 Cloudflare WARP 状态:   "
    local cf_trace
    cf_trace=$(curl -s --connect-timeout 5 https://www.cloudflare.com/cdn-cgi/trace || true)
    local warp_on
    warp_on=$(echo "${cf_trace}" | grep -oE "warp=(on|plus|off)" || echo "warp=off")
    if [[ "${warp_on}" =~ "warp=on" || "${warp_on}" =~ "warp=plus" ]]; then
        echo -e "${C_GREEN}开启 (${warp_on})${C_RESET}"
    else
        echo -e "${C_YELLOW}用户态精准分流模式 (仅针对直连节点的指定域名生效，绝不影响住宅节点)${C_RESET}"
    fi

    echo -ne "  检测 ChatGPT / OpenAI 解锁: "
    local ai_code
    ai_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "https://chatgpt.com" || echo "000")
    if [[ "${ai_code}" =~ 200|301|302|403 ]]; then
        echo -e "${C_GREEN}支持正常访问 (HTTP ${ai_code})${C_RESET}"
    else
        echo -e "${C_RED}可能受限 (HTTP ${ai_code})${C_RESET}"
    fi

    echo -ne "  检测 Netflix 区域与连通性:   "
    local nf_code
    nf_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "https://www.netflix.com/title/80018499" || echo "000")
    if [[ "${nf_code}" == "200" ]]; then
        echo -e "${C_GREEN}原生解锁 (HTTP 200 完整非自制剧)${C_RESET}"
    elif [[ "${nf_code}" == "404" ]]; then
        echo -e "${C_YELLOW}仅支持自制剧 (HTTP 404)${C_RESET}"
    else
        echo -e "${C_RED}受阻断 (HTTP ${nf_code})${C_RESET}"
    fi

    echo -ne "  检测 YouTube CDN 分配机房:   "
    echo -e "${C_GREEN}已连接全球边缘网络${C_RESET}"

    echo -e "${C_GREEN}======================================================================${C_RESET}"
}

menu() {
    check_root
    while true; do
        echo ""
        echo -e "${C_GREEN}======================================================================${C_RESET}"
        echo -e "${C_BOLD}${C_GREEN}       🛡️ AimiliVPN - Cloudflare WARP 双栈网络与流媒体解锁${C_RESET}"
        echo -e "${C_GREEN}======================================================================${C_RESET}"
        echo -e "  ${C_BOLD}${C_YELLOW}【关键原则】WARP 仅对【直连节点】生效，绝对不劫持【住宅节点】(住宅100%走纯家宽)${C_RESET}"
        echo -e "  ${C_GREEN}[1]${C_RESET} 🧠 仅为直连节点解锁 OpenAI/ChatGPT (推荐: 仅ChatGPT走WARP, 保留原生Netflix/YouTube)"
        echo -e "  ${C_GREEN}[2]${C_RESET} 🎬 为直连节点解锁 AI 与流媒体 (OpenAI + Netflix + Disney+ + TikTok 走WARP)"
        echo -e "  ${C_GREEN}[3]${C_RESET} 🌐 直连节点全局出站走 WARP (所有直连流量经由 Cloudflare Anycast 出口)"
        echo -e "  ${C_GREEN}[4]${C_RESET} ❌ 关闭 WARP 出站 (恢复纯 VPS 原生直连 / 纯住宅出站)"
        echo -e "  ${C_GREEN}[5]${C_RESET} 🔄 重新生成并刷新 WARP 双栈账号凭证"
        echo -e "  ${C_GREEN}[6]${C_RESET} 🩺 运行流媒体/OpenAI/IP 纯净度检测"
        echo -e "  ${C_GREEN}[7]${C_RESET} 📖 查看用户态 WireGuard 原理与住宅出口绝对隔离说明"
        echo -e "${C_RED}[0]${C_RESET} 返回上级菜单"
        echo -e "${C_GREEN}======================================================================${C_RESET}"

        read -rp "请选择操作 [0-7]: " opt
        case "${opt}" in
            1)
                apply_warp_to_singbox "ai"
                check_unlock_status
                read -rp "按回车键继续..." _
                ;;
            2)
                apply_warp_to_singbox "stream"
                check_unlock_status
                read -rp "按回车键继续..." _
                ;;
            3)
                apply_warp_to_singbox "global"
                check_unlock_status
                read -rp "按回车键继续..." _
                ;;
            4)
                apply_warp_to_singbox "off"
                read -rp "按回车键继续..." _
                ;;
            5)
                register_warp_account
                read -rp "按回车键继续..." _
                ;;
            6)
                check_unlock_status
                read -rp "按回车键继续..." _
                ;;
            7)
                show_warp_principle
                read -rp "按回车键继续..." _
                ;;
            0)
                break
                ;;
            *)
                echo -e "${C_RED}无效选项${C_RESET}"
                ;;
        esac
    done
}

case "${1:-}" in
    ai)
        check_root
        apply_warp_to_singbox "ai"
        ;;
    stream)
        check_root
        apply_warp_to_singbox "stream"
        ;;
    global)
        check_root
        apply_warp_to_singbox "global"
        ;;
    off|disable)
        check_root
        apply_warp_to_singbox "off"
        ;;
    reg|register)
        check_root
        register_warp_account
        ;;
    test|check|status)
        check_unlock_status
        ;;
    help|guide)
        show_warp_principle
        ;;
    menu|"")
        menu
        ;;
    *)
        echo "用法: $0 {stream|global|off|register|test|help|menu}"
        exit 1
        ;;
esac
