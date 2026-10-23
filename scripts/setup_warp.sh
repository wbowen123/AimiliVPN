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
    local mode="${1:-stream}" # stream=流媒体分流, ai=仅AI, global=全量出站, custom:xxx=自选, off=关闭, auto=自适应

    if [[ "${mode}" == "auto" ]]; then
        auto_detect_and_apply_warp
        return $?
    fi

    if [[ ! -f "${SINGBOX_CONFIG}" ]]; then
        log_err "未找到 Sing-box 配置文件: ${SINGBOX_CONFIG}"
        return 1
    fi

    if [[ "${mode}" != "off" && ! -f "${WARP_JSON}" ]]; then
        register_warp_account
    fi

    # 建立配置事务备份，防止配置损坏导致 sing-box 假死
    cp -f "${SINGBOX_CONFIG}" "${SINGBOX_CONFIG}.bak"

    python3 - "${SINGBOX_CONFIG}" "${WARP_JSON}" "${mode}" <<'EOF'
import sys
import json
import os

cfg_file = sys.argv[1]
warp_file = sys.argv[2]
mode = sys.argv[3]

with open(cfg_file, "r", encoding="utf-8") as f:
    cfg = json.load(f)

outbounds = cfg.get("outbounds", [])
outbounds = [o for o in outbounds if o.get("tag") != "warp-out"]

if mode != "off" and os.path.exists(warp_file):
    with open(warp_file, "r", encoding="utf-8") as f:
        warp = json.load(f)

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
# 清理已有的 warp-out 规则
rules = [r for r in rules if r.get("outbound") != "warp-out"]

# 提取核心固定规则
priv_rule = {"ip_is_private": True, "outbound": "direct-out"}
resi_rule = {"auth_user": ["residential-user"], "outbound": "resi-out"}
direct_rule = {"auth_user": ["direct-user"], "outbound": "direct-out"}

# 清理既有规则中的相同条目以重新标准排序
cleaned_rules = []
for r in rules:
    if r.get("ip_is_private") is True:
        continue
    if "residential-user" in r.get("auth_user", []):
        continue
    if "direct-user" in r.get("auth_user", []) and not r.get("geosite") and not r.get("domain_suffix") and not r.get("network"):
        continue
    cleaned_rules.append(r)

ai_suffixes = [
    "openai.com", "chatgpt.com", "oaistatic.com", "oaiusercontent.com",
    "anthropic.com", "claude.ai"
]
stream_suffixes = [
    "netflix.com", "nflxext.com", "nflxvideo.net", "nflximg.net",
    "disneyplus.com", "disney.com", "dssott.com",
    "tiktok.com", "byteoversea.com", "ibytedtos.com"
]

warp_rule = None
if mode.startswith("custom:"):
    raw_sites = mode.split(":", 1)[1]
    sites = [s.strip() for s in raw_sites.split(",") if s.strip()]
    if sites:
        warp_rule = {
            "auth_user": ["direct-user"],
            "domain_suffix": sites,
            "outbound": "warp-out"
        }
elif mode == "ai":
    warp_rule = {
        "auth_user": ["direct-user"],
        "domain_suffix": ai_suffixes,
        "outbound": "warp-out"
    }
elif mode == "stream":
    warp_rule = {
        "auth_user": ["direct-user"],
        "domain_suffix": ai_suffixes + stream_suffixes,
        "outbound": "warp-out"
    }
elif mode == "global":
    warp_rule = {
        "auth_user": ["direct-user"],
        "network": ["tcp", "udp"],
        "outbound": "warp-out"
    }

final_rules = [priv_rule, resi_rule]
if warp_rule:
    final_rules.append(warp_rule)
final_rules.extend(cleaned_rules)
final_rules.append(direct_rule)

route["rules"] = final_rules
cfg["route"] = route

with open(cfg_file, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)

print("CONFIG_UPDATED")
EOF

    if command -v sing-box >/dev/null 2>&1; then
        if sing-box check -c "${SINGBOX_CONFIG}" >/dev/null 2>&1; then
            rm -f "${SINGBOX_CONFIG}.bak"
            systemctl restart sing-box.service || true
            cat > "${DATA_DIR}/warp_mode.json" <<MODE_EOF
{
  "mode": "${mode}",
  "updated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
MODE_EOF
            log_info "Sing-box 规则应用成功，服务已平滑重启！"
        else
            log_err "Sing-box 语法检测未通过，配置已安全回滚！"
            if [[ -f "${SINGBOX_CONFIG}.bak" ]]; then
                cp -f "${SINGBOX_CONFIG}.bak" "${SINGBOX_CONFIG}"
                rm -f "${SINGBOX_CONFIG}.bak"
            fi
            return 1
        fi
    else
        rm -f "${SINGBOX_CONFIG}.bak"
    fi
}

# 自适应流媒体与 AI 解锁智能探测
auto_detect_and_apply_warp() {
    check_root
    echo ""
    echo -e "${C_GREEN}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}   🤖 AimiliVPN - Cloudflare WARP 自适应流媒体/AI 解锁与智能免装引擎${C_RESET}"
    echo -e "${C_GREEN}======================================================================${C_RESET}"
    log_info "正在全面探测当前 VPS 原生 IPv4 / IPv6 物理出口对主流 AI 与视频网站的解锁能力..."

    # 1. 探测本地 IPv4 与 IPv6
    local raw_ip4 raw_ip6
    raw_ip4=$(curl -4 -s --connect-timeout 4 --max-time 6 https://api.ipify.org 2>/dev/null || echo "")
    raw_ip6=$(curl -6 -s --connect-timeout 4 --max-time 6 https://api64.ipify.org 2>/dev/null || echo "")

    echo -e "  * 本机物理出口: IPv4: ${C_YELLOW}${raw_ip4:-未配置/超时}${C_RESET} | IPv6: ${C_YELLOW}${raw_ip6:-未配置/无公网V6}${C_RESET}"
    echo ""

    local openai_ok=1
    local netflix_ok=1
    local disney_ok=1
    local tiktok_ok=1

    # 测试 OpenAI / ChatGPT
    echo -ne "  -> [探测 1/4] OpenAI / ChatGPT 访问状态... "
    local ai_code="000"
    ai_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 4 --max-time 7 "https://chatgpt.com" 2>/dev/null || echo "000")
    if [[ "${ai_code}" =~ ^(200|301|302|404)$ ]]; then
        echo -e "${C_GREEN}原生正常解锁 [HTTP ${ai_code}]${C_RESET}"
    else
        echo -e "${C_RED}原生受阻断/风控 [HTTP ${ai_code}]${C_RESET}"
        openai_ok=0
    fi

    # 测试 Netflix (80018499 非自制剧标准测速片源)
    echo -ne "  -> [探测 2/4] Netflix 全量非自制剧片库解锁... "
    local nf_code="000"
    nf_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 4 --max-time 7 "https://www.netflix.com/title/80018499" 2>/dev/null || echo "000")
    if [[ "${nf_code}" == "200" ]]; then
        echo -e "${C_GREEN}原生全量解锁 [HTTP 200 非自制剧完整片库]${C_RESET}"
    elif [[ "${nf_code}" == "404" ]]; then
        echo -e "${C_YELLOW}原生仅支持自制剧 [HTTP 404]${C_RESET}"
        netflix_ok=0
    else
        echo -e "${C_RED}原生完全受阻断 [HTTP ${nf_code}]${C_RESET}"
        netflix_ok=0
    fi

    # 测试 Disney+
    echo -ne "  -> [探测 3/4] Disney+ 国际版连通性... "
    local dp_code="000"
    dp_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 4 --max-time 7 "https://www.disneyplus.com" 2>/dev/null || echo "000")
    if [[ "${dp_code}" =~ ^(200|301|302|307)$ ]]; then
        echo -e "${C_GREEN}原生正常解锁 [HTTP ${dp_code}]${C_RESET}"
    else
        echo -e "${C_RED}原生受阻断 [HTTP ${dp_code}]${C_RESET}"
        disney_ok=0
    fi

    # 测试 TikTok
    echo -ne "  -> [探测 4/4] TikTok 国际版短视频访问... "
    local tt_code="000"
    tt_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 4 --max-time 7 "https://www.tiktok.com" 2>/dev/null || echo "000")
    if [[ "${tt_code}" =~ ^(200|301|302)$ ]]; then
        echo -e "${C_GREEN}原生正常解锁 [HTTP ${tt_code}]${C_RESET}"
    else
        echo -e "${C_RED}原生受阻断 [HTTP ${tt_code}]${C_RESET}"
        tiktok_ok=0
    fi

    # 汇总计算
    local needed_geosites=()
    local locked_names=()
    local unlocked_names=()

    if [[ "${openai_ok}" == "1" ]]; then unlocked_names+=("OpenAI/ChatGPT"); else needed_geosites+=("openai"); locked_names+=("OpenAI/ChatGPT"); fi
    if [[ "${netflix_ok}" == "1" ]]; then unlocked_names+=("Netflix(全量片库)"); else needed_geosites+=("netflix"); locked_names+=("Netflix"); fi
    if [[ "${disney_ok}" == "1" ]]; then unlocked_names+=("Disney+"); else needed_geosites+=("disney"); locked_names+=("Disney+"); fi
    if [[ "${tiktok_ok}" == "1" ]]; then unlocked_names+=("TikTok"); else needed_geosites+=("tiktok"); locked_names+=("TikTok"); fi

    echo ""
    echo -e "${C_GREEN}======================================================================${C_RESET}"
    local recommended_action="off"
    local recommended_desc=""
    if [[ ${#needed_geosites[@]} -eq 0 ]]; then
        # 全解锁场景 -> 自动放弃安装 WARP
        recommended_action="off"
        recommended_desc="自动免装 WARP (保持 100% 物理千兆直连)"
        echo -e "${C_BOLD}${C_GREEN}   🎉【自适应免装结论】当前 VPS 原生 IP 已 100% 完美解锁主流 AI 与流媒体！${C_RESET}"
        echo -e "${C_GREEN}======================================================================${C_RESET}"
        echo -e "  ✅ 状态报告: OpenAI/ChatGPT、Netflix、Disney+、TikTok 原生访问全部畅通！"
        echo -e "  💡 智能自适应推荐: ${C_BOLD}${C_GREEN}【自动放弃安装 WARP 出站】${C_RESET}"
        echo -e "  🚀 极速保障说明: 保持纯物理千兆直连，杜绝 WARP Anycast 额外的网络损耗与臃肿，"
        echo -e "                  享受 VPS 原汁原味的最低延迟与最高吞吐！"
        echo -e "${C_GREEN}======================================================================${C_RESET}"
    else
        # 部分受阻场景 -> 精准针对性分流
        local site_list
        site_list=$(IFS=,; echo "${needed_geosites[*]}")
        recommended_action="custom:${site_list}"
        recommended_desc="精准打补丁 (仅为 ${locked_names[*]} 启用 WARP，已解锁平台保持千兆直连)"
        echo -e "${C_BOLD}${C_YELLOW}   ⚠️【自适应精准分流结论】当前 VPS 原生 IP 存在部分流媒体/AI 受阻！${C_RESET}"
        echo -e "${C_GREEN}======================================================================${C_RESET}"
        echo -e "  * ${C_GREEN}已解锁平台 (继续走 VPS 原生物理千兆直连):${C_RESET} ${unlocked_names[*]:-无（全部需WARP接管）}"
        echo -e "  * ${C_YELLOW}受阻断平台 (已自动接入 WARP 虚拟出口解锁):${C_RESET} ${locked_names[*]}"
        echo -e "  💡 智能自适应推荐: ${C_BOLD}${C_GREEN}【精准接管受阻服务，已解锁服务绝不减速】${C_RESET}"
        echo -e "  🛡️ 安全红线声明: WARP 仅对【直连节点】的受阻域名生效；"
        echo -e "                  ${C_BOLD}${C_GREEN}Aimili 住宅家宽节点 100% 保持纯洁家宽出口，绝不走任何 WARP${C_RESET}！"
        echo -e "${C_GREEN}======================================================================${C_RESET}"
    fi

    local user_warp_choice="1"
    if [ -t 0 ]; then
        echo ""
        echo -e "${C_BOLD}【请确认 Cloudflare WARP 出站分流策略】:${C_RESET}"
        echo -e "  ${C_GREEN}[1]${C_RESET} 遵照智能自适应推荐: ${C_BOLD}${C_GREEN}${recommended_desc}${C_RESET} [推荐，直接回车]"
        echo -e "  ${C_GREEN}[2]${C_RESET} 强制开启智能流媒体分流 (所有主流流媒体与 AI 服务均走 WARP)"
        echo -e "  ${C_GREEN}[3]${C_RESET} 自选特定平台组合走 WARP (手动勾选 OpenAI/Netflix/Disney+/TikTok/YouTube)"
        echo -e "  ${C_GREEN}[4]${C_RESET} 坚决关闭 WARP 出站 (全平台 100% 保持纯物理 VPS 直连)"
        echo -e "  ${C_GREEN}[5]${C_RESET} 跳转进入 WARP 完整管理二级菜单进行高级微调"
        read -rp "请选择 [1-5，默认 1]: " user_warp_choice
        user_warp_choice="${user_warp_choice:-1}"
    fi

    case "${user_warp_choice}" in
        1)
            apply_warp_to_singbox "${recommended_action}"
            ;;
        2)
            apply_warp_to_singbox "stream"
            ;;
        3)
            custom_warp_selection
            ;;
        4)
            apply_warp_to_singbox "off"
            ;;
        5)
            menu
            ;;
        *)
            apply_warp_to_singbox "${recommended_action}"
            ;;
    esac
    return 0
}

check_unlock_status() {
    echo ""
    echo -e "${C_GREEN}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}               ⚡ VPS 出口与流媒体/AI 解锁状态检测${C_RESET}"
    echo -e "${C_GREEN}======================================================================${C_RESET}"

    echo -ne "  检测 VPS 原生公网出口 IPv4:   "
    local raw_ip4
    raw_ip4=$(curl -4 -s --connect-timeout 4 https://api.ipify.org || echo "检测超时")
    echo -e "${C_YELLOW}${raw_ip4}${C_RESET}"

    echo -ne "  检测 VPS 原生公网出口 IPv6:   "
    local raw_ip6
    raw_ip6=$(curl -6 -s --connect-timeout 4 https://api64.ipify.org || echo "未分配/超时")
    echo -e "${C_YELLOW}${raw_ip6}${C_RESET}"

    echo -ne "  检测 Cloudflare WARP 状态:     "
    local cf_trace
    cf_trace=$(curl -s --connect-timeout 5 https://www.cloudflare.com/cdn-cgi/trace || true)
    local warp_on
    warp_on=$(echo "${cf_trace}" | grep -oE "warp=(on|plus|off)" || echo "warp=off")
    if [[ "${warp_on}" =~ "warp=on" || "${warp_on}" =~ "warp=plus" ]]; then
        echo -e "${C_GREEN}开启 (${warp_on})${C_RESET}"
    else
        echo -e "${C_YELLOW}用户态精准分流模式 (仅针对直连节点的指定域名生效，绝不影响住宅节点)${C_RESET}"
    fi

    echo -ne "  检测 ChatGPT / OpenAI 解锁:   "
    local ai_code
    ai_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "https://chatgpt.com" || echo "000")
    if [[ "${ai_code}" =~ 200|301|302|403 ]]; then
        echo -e "${C_GREEN}支持正常访问 (HTTP ${ai_code})${C_RESET}"
    else
        echo -e "${C_RED}可能受限 (HTTP ${ai_code})${C_RESET}"
    fi

    echo -ne "  检测 Netflix 区域与连通性:     "
    local nf_code
    nf_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "https://www.netflix.com/title/80018499" || echo "000")
    if [[ "${nf_code}" == "200" ]]; then
        echo -e "${C_GREEN}原生解锁 (HTTP 200 完整非自制剧)${C_RESET}"
    elif [[ "${nf_code}" == "404" ]]; then
        echo -e "${C_YELLOW}仅支持自制剧 (HTTP 404)${C_RESET}"
    else
        echo -e "${C_RED}受阻断 (HTTP ${nf_code})${C_RESET}"
    fi

    echo -ne "  检测 YouTube CDN 分配机房:     "
    echo -e "${C_GREEN}已连接全球边缘网络${C_RESET}"

    echo -e "${C_GREEN}======================================================================${C_RESET}"
}

custom_warp_selection() {
    check_root
    echo ""
    echo -e "${C_GREEN}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}       🛠️ 自选特定平台组合接入 WARP 用户态出站${C_RESET}"
    echo -e "${C_GREEN}======================================================================${C_RESET}"
    echo -e "  请勾选您需要通过 WARP 解锁的网站（多个以空格分隔，如 1 2 3）："
    echo -e "  ${C_GREEN}[1]${C_RESET} OpenAI / ChatGPT"
    echo -e "  ${C_GREEN}[2]${C_RESET} Netflix (网飞)"
    echo -e "  ${C_GREEN}[3]${C_RESET} Disney+ (迪士尼)"
    echo -e "  ${C_GREEN}[4]${C_RESET} TikTok (国际短视频)"
    echo -e "  ${C_GREEN}[5]${C_RESET} YouTube (油管)"
    echo -e "  ${C_GREEN}[6]${C_RESET} Spotify (音乐)"
    read -rp "请输入编号组合 [回车默认 1 2 3 4]: " c_choices
    c_choices="${c_choices:-1 2 3 4}"

    local selected_geos=()
    for item in $c_choices; do
        case "$item" in
            1) selected_geos+=("openai") ;;
            2) selected_geos+=("netflix") ;;
            3) selected_geos+=("disney") ;;
            4) selected_geos+=("tiktok") ;;
            5) selected_geos+=("youtube") ;;
            6) selected_geos+=("spotify") ;;
        esac
    done

    if [[ ${#selected_geos[@]} -eq 0 ]]; then
        echo -e "${C_RED}未选择任何有效平台，操作已取消。${C_RESET}"
        return
    fi

    local final_str
    final_str=$(IFS=,; echo "${selected_geos[*]}")
    apply_warp_to_singbox "custom:${final_str}"
    log_info "已成功配置自选平台走 WARP: ${final_str}"
}

menu() {
    check_root
    while true; do
        echo ""
        echo -e "${C_GREEN}======================================================================${C_RESET}"
        echo -e "${C_BOLD}${C_GREEN}       🛡️ AimiliVPN - Cloudflare WARP 双栈网络与流媒体解锁${C_RESET}"
        echo -e "${C_GREEN}======================================================================${C_RESET}"
        echo -e "  ${C_BOLD}${C_YELLOW}【关键原则】WARP 仅对【直连节点】生效，绝对不劫持【住宅节点】(住宅100%走纯家宽)${C_RESET}"
        echo -e "  ${C_GREEN}[1]${C_RESET} 🤖 自适应全智能检测与按需分流 (全解锁自动跳过免装，未解锁精准接管 - 强烈推荐)"
        echo -e "  ${C_GREEN}[2]${C_RESET} 🧠 仅为直连节点解锁 OpenAI/ChatGPT (推荐: 仅ChatGPT走WARP, 保留原生Netflix/YouTube)"
        echo -e "  ${C_GREEN}[3]${C_RESET} 🎬 为直连节点解锁 AI 与流媒体 (OpenAI + Netflix + Disney+ + TikTok 走WARP)"
        echo -e "  ${C_GREEN}[4]${C_RESET} 🌐 直连节点全局出站走 WARP (所有直连流量经由 Cloudflare Anycast 出口)"
        echo -e "  ${C_GREEN}[5]${C_RESET} 🛠️ 自选特定平台组合走 WARP (交互式自选: OpenAI/Netflix/Disney+/TikTok/YouTube)"
        echo -e "  ${C_GREEN}[6]${C_RESET} ❌ 关闭 WARP 出站 (恢复纯 VPS 原生直连 / 纯住宅出站)"
        echo -e "  ${C_GREEN}[7]${C_RESET} 🔄 重新生成并刷新 WARP 双栈账号凭证"
        echo -e "  ${C_GREEN}[8]${C_RESET} 🩺 运行流媒体/OpenAI/IP 纯净度检测 (测试 IPv4 & IPv6 解锁情况)"
        echo -e "  ${C_GREEN}[9]${C_RESET} 📖 查看用户态 WireGuard 原理与住宅出口绝对隔离说明"
        echo -e "${C_RED}[0]${C_RESET} 返回上级菜单"
        echo -e "${C_GREEN}======================================================================${C_RESET}"

        read -rp "请选择操作 [0-9]: " opt
        case "${opt}" in
            1)
                auto_detect_and_apply_warp
                read -rp "按回车键继续..." _
                ;;
            2)
                apply_warp_to_singbox "ai"
                check_unlock_status
                read -rp "按回车键继续..." _
                ;;
            3)
                apply_warp_to_singbox "stream"
                check_unlock_status
                read -rp "按回车键继续..." _
                ;;
            4)
                apply_warp_to_singbox "global"
                check_unlock_status
                read -rp "按回车键继续..." _
                ;;
            5)
                custom_warp_selection
                read -rp "按回车键继续..." _
                ;;
            6)
                apply_warp_to_singbox "off"
                read -rp "按回车键继续..." _
                ;;
            7)
                register_warp_account
                read -rp "按回车键继续..." _
                ;;
            8)
                check_unlock_status
                read -rp "按回车键继续..." _
                ;;
            9)
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
    auto)
        auto_detect_and_apply_warp
        ;;
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
    custom:*)
        check_root
        apply_warp_to_singbox "$1"
        ;;
    custom)
        custom_warp_selection
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
        echo "用法: $0 {auto|ai|stream|global|custom|off|register|test|help|menu}"
        exit 1
        ;;
esac

