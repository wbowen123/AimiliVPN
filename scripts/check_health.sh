#!/usr/bin/env bash
# ==============================================================================
# AimiliVPN & Sing-box 全协议节点连通性与健康状态诊断工具
# 作用：全方位检测服务状态、端口监听、防火墙放行、住宅网桥出口及客户端测试 -1 根因排查
# ==============================================================================
set -euo pipefail

ROOT_DIR="/opt/aimilivpn"
DATA_DIR="${VPNGATE_DATA_DIR:-$ROOT_DIR/vpngate_data}"
NODES_JSON="$DATA_DIR/singbox_nodes.json"
KEYS_STORE="$DATA_DIR/singbox_keys.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
PLAIN='\033[0m'

echo -e "\n${BOLD}${BLUE}======================================================================${PLAIN}"
echo -e "${BOLD}${BLUE}       🔍 AimiliVPN & Sing-box 全协议矩阵与连通性全面诊断报告${PLAIN}"
echo -e "${BOLD}${BLUE}======================================================================${PLAIN}"

# ------------------------------------------------------------------------------
# 1. 核心系统服务状态
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}【1. 核心 Systemd 服务运行状态】${PLAIN}"

check_svc() {
    local name="$1"
    local desc="$2"
    if systemctl is-active --quiet "$name" 2>/dev/null; then
        echo -e "  * ${desc} (${name}):  ${GREEN}[ 运行中 - ACTIVE ]${PLAIN}"
        return 0
    elif [ "$(systemctl is-enabled "$name" 2>/dev/null || echo "")" = "disabled" ]; then
        echo -e "  * ${desc} (${name}):  ${YELLOW}[ 未启用 - DISABLED (当前为极速原生直连模式) ]${PLAIN}"
        return 0
    else
        local substate
        substate=$(systemctl is-failed "$name" 2>/dev/null || echo "inactive")
        echo -e "  * ${desc} (${name}):  ${RED}[ 异常 - ${substate^^} ]${PLAIN}"
        return 1
    fi
}

S_SINGBOX=0
S_AIMILI=0
S_NGINX=0
check_svc "sing-box" "Sing-box 分流代理核心" || S_SINGBOX=1
check_svc "aimilivpn" "AimiliVPN 动态住宅网桥" || S_AIMILI=1
check_svc "nginx" "Nginx 管理与订阅入口" || S_NGINX=1

# ------------------------------------------------------------------------------
# 2. 核心端口监听与占用诊断
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}【2. 核心网络端口监听诊断】${PLAIN}"

check_port_listen() {
    local proto="$1"
    local port="$2"
    local label="$3"
    local found=0

    if command -v ss >/dev/null 2>&1; then
        if [ "$proto" = "tcp" ]; then
            ss -ltn | grep -qE ":${port}\b" && found=1
        else
            ss -lun | grep -qE ":${port}\b" && found=1
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if [ "$proto" = "tcp" ]; then
            netstat -ltn 2>/dev/null | grep -qE ":${port}\b" && found=1
        else
            netstat -lun 2>/dev/null | grep -qE ":${port}\b" && found=1
        fi
    fi

    if [ "$found" -eq 1 ]; then
        echo -e "  * [${proto^^}] 端口 ${BOLD}${port}${PLAIN} (${label}): ${GREEN}正常监听中 [OK]${PLAIN}"
        return 0
    else
        echo -e "  * [${proto^^}] 端口 ${BOLD}${port}${PLAIN} (${label}): ${RED}未监听！[FAIL]${PLAIN}"
        return 1
    fi
}

check_port_listen "tcp" "443"   "VLESS-Reality" || true
check_port_listen "udp" "443"   "Hysteria 2" || true
check_port_listen "udp" "8443"  "TUIC v5" || true
check_port_listen "tcp" "8444"  "AnyTLS" || true
check_port_listen "tcp" "8445"  "VMess-xHTTP" || true
check_port_listen "tcp" "8446"  "VMess-WS" || true
check_port_listen "tcp" "8443"  "Nginx HTTPS 管理后台" || true
check_port_listen "tcp" "18443" "Nginx 全生态订阅入口" || true
check_port_listen "tcp" "18080" "Nginx HTTP 免证书纯净订阅入口" || true
check_port_listen "tcp" "8500"  "Aimili SOCKS5 住宅网桥 (127.0.0.1)" || true
check_port_listen "tcp" "8501"  "Aimili Python 内部面板" || true

# ------------------------------------------------------------------------------
# 3. 本地防火墙与端口跳跃规则检测
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}【3. 系统防火墙与内核端口跳跃 (Port Hopping) 规则】${PLAIN}"

if command -v iptables >/dev/null 2>&1; then
    # 检查跳跃重定向规则
    if iptables -t nat -S PREROUTING 2>/dev/null | grep -q "40000:50000.*REDIRECT.*443"; then
        echo -e "  * Hysteria 2 端口跳跃 (UDP 40000-50000 -> 443): ${GREEN}已生效 [OK]${PLAIN}"
    else
        echo -e "  * Hysteria 2 端口跳跃 (UDP 40000-50000 -> 443): ${YELLOW}未检测到 iptables 转发规则（单端口 443 模式）${PLAIN}"
    fi

    # 检查 443 放行
    if iptables -S INPUT 2>/dev/null | grep -qE -- "--dport 443\b.*ACCEPT"; then
        echo -e "  * iptables 核心 443 端口放行: ${GREEN}已放行 [OK]${PLAIN}"
    else
        echo -e "  * iptables 核心 443 端口放行: ${YELLOW}未发现显式 ACCEPT（若 INPUT 策略为 ACCEPT 则不影响）${PLAIN}"
    fi
fi

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    echo -e "  * UFW 防火墙状态: ${YELLOW}已启用 (Active)${PLAIN}"
    for p in 443 8443 8444 8445 8446 18443 18080; do
        if ufw status 2>/dev/null | grep -qE "^${p}\b.*ALLOW"; then
            echo -e "    - 端口 ${p}: ${GREEN}ALLOW${PLAIN}"
        else
            echo -e "    - 端口 ${p}: ${RED}未发现放行规则！可能被 UFW 阻断${PLAIN}"
        fi
    done
fi

# ------------------------------------------------------------------------------
# 4. AimiliVPN 动态住宅网桥出口真实连通性测试 (127.0.0.1:8500)
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}【4. 住宅出口网桥 (127.0.0.1:8500) 真实代理测试】${PLAIN}"

PROXY_ENV_FILE="/etc/default/aimilivpn"
SOCKS_USER="socks5"
SOCKS_PASS="ilovestudy"
if [ -f "$PROXY_ENV_FILE" ]; then
    SOCKS_USER=$(grep '^LOCAL_PROXY_USER=' "$PROXY_ENV_FILE" | cut -d'=' -f2 | tr -d '"'"' " || echo "socks5")
    SOCKS_PASS=$(grep '^LOCAL_PROXY_PASS=' "$PROXY_ENV_FILE" | cut -d'=' -f2 | tr -d '"'"' " || echo "ilovestudy")
fi

RESI_IP_RES=""
RESI_TIME=0
START_TS=$(date +%s%N 2>/dev/null || date +%s)
RESI_IP_RES=$(curl -s4 --connect-timeout 5 --max-time 8 --proxy "socks5h://${SOCKS_USER}:${SOCKS_PASS}@127.0.0.1:8500" https://api.ipify.org 2>/dev/null || \
              curl -s4 --connect-timeout 5 --max-time 8 --proxy "socks5h://127.0.0.1:8500" https://api.ipify.org 2>/dev/null || echo "")
END_TS=$(date +%s%N 2>/dev/null || date +%s)

if [ -n "$RESI_IP_RES" ]; then
    echo -e "  * 住宅网桥连通状态: ${GREEN}100% 畅通可用 [PASS]${PLAIN}"
    echo -e "  * 当前住宅出站 IP:  ${GREEN}${RESI_IP_RES}${PLAIN}"
    if [ "$START_TS" -gt 0 ] && [ "$END_TS" -ge "$START_TS" ]; then
        if [ ${#START_TS} -gt 10 ]; then
            RESI_TIME=$(( (END_TS - START_TS) / 1000000 ))
        else
            RESI_TIME=$(( (END_TS - START_TS) * 1000 ))
        fi
        echo -e "  * 住宅出口响应延迟: ${GREEN}${RESI_TIME} ms${PLAIN}"
    fi
    echo -e "  * 住宅节点穿透特征: ${BLUE}所有 [住宅-家宽] 节点访问外部均以此住宅 IP 出站！${PLAIN}"
else
    echo -e "  * 住宅网桥连通状态: ${RED}连接超时或未就绪 [NOT READY]${PLAIN}"
    echo -e "  ${YELLOW}⚠️  重点提示：${PLAIN}"
    echo -e "     当前 AimiliVPN 尚未建立活跃住宅隧道。此状态下，客户端导入订阅后："
    echo -e "     - ${GREEN}[直连-极速]${PLAIN} 节点走 VPS 原生网卡，${GREEN}完全不受影响，正常连接${PLAIN}；"
    echo -e "     - ${RED}[住宅-家宽]${PLAIN} 节点因为需要经由 8500 出口转发，在客户端测试时会表现为 ${RED}-1 或超时${PLAIN}！"
    echo -e "     ${BLUE}解决方法：${PLAIN}"
    echo -e "     1. 登录后台 ${BLUE}https://你的IP:8443/面板后缀/${PLAIN} 手动切换一个延迟低的国家；"
    echo -e "     2. 或执行 ${YELLOW}ml logs${PLAIN} 查看后台自动连接进度（首次拨号可能需 10-30 秒）。"
fi

# ------------------------------------------------------------------------------
# 5. 全协议订阅入口与文件存在性检测
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}【5. 全生态客户端订阅托管诊断】${PLAIN}"

WWW_SUB="/var/www/aimilivpn-sub"
check_sub_file() {
    local file="$1"
    local desc="$2"
    if [ -s "$WWW_SUB/$file" ]; then
        local size
        size=$(wc -c < "$WWW_SUB/$file" | tr -d ' ')
        echo -e "  * ${desc} (${file}): ${GREEN}已就绪 [OK]${PLAIN} (${size} 字节)"
    else
        echo -e "  * ${desc} (${file}): ${RED}缺失或为空文件！[FAIL]${PLAIN}"
    fi
}

check_sub_file "sub.txt" "通用 Base64 订阅"
check_sub_file "clash.yaml" "Clash Meta / Mihomo 订阅"
check_sub_file "singbox.json" "Sing-box 开箱即用配置"
check_sub_file "nodes.txt" "明文节点链接列表"

# ------------------------------------------------------------------------------
# 6. 客户端导入显示 -1 根因深度诊断与排查指南
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${MAGENTA}======================================================================${PLAIN}"
echo -e "${BOLD}${MAGENTA}   💡 客户端导入订阅后显示 -1 (Ping/延迟测试超时) 根因与排错指南${PLAIN}"
echo -e "${BOLD}${MAGENTA}======================================================================${PLAIN}"

echo -e "如果您在 Clash Verge / Mihomo / v2rayN / Sing-box 客户端中测试节点显示 ${RED}-1${PLAIN}，请对照排查："
echo
echo -e "  ${BOLD}1. 只有 [住宅-家宽] 节点显示 -1，[直连-极速] 节点有延迟正常：${PLAIN}"
echo -e "     -> 根因：AimiliVPN 住宅池正在寻找/切换节点，8500 网桥暂无活跃隧道。"
echo -e "     -> 解决：运行 ${YELLOW}ml logs${PLAIN} 查看连接日志，或登录网页管理后台点击切换目标节点。"
echo
echo -e "  ${BOLD}2. 全部 10 个节点全部显示 -1（直连和住宅全都不通）：${PLAIN}"
echo -e "     -> 根因 1【最常见】：${RED}云服务器厂商外层安全组（云防火墙）没有放行 443 端口！${PLAIN}"
echo -e "        AWS Lightsail、Oracle Cloud (甲骨文)、阿里云、腾讯云、Google Cloud 默认在控制台拦截入站流量。"
echo -e "        ${GREEN}解决办法：请前往云服务商控制台 -> 实例安全组 / 防火墙 -> 添加允许规则：${PLAIN}"
echo -e "        - TCP 端口: ${YELLOW}443, 8443, 8444, 8445, 8446, 18443${PLAIN}"
echo -e "        - UDP 端口: ${YELLOW}443, 8443, 40000-50000${PLAIN}"
echo -e "     -> 根因 2：本地系统时间与网络标准时间严重偏差（大于 60 秒）导致 Reality 握手被拒。"
echo -e "        ${GREEN}解决办法：运行 ${YELLOW}bash /opt/aimilivpn/scripts/check_time_sync.sh${PLAIN} 自动对时。"
echo
echo -e "  ${BOLD}3. 仅 AnyTLS 节点显示 -1：${PLAIN}"
echo -e "     -> 根因：AnyTLS 属于前沿实验协议，目前仅 Sing-box 客户端支持。Clash 和 v2rayN 不支持 AnyTLS。"
echo -e "     -> 解决：在 Clash 中使用 VLESS-Reality 或 Hysteria 2 节点即可。"
echo
echo -e "  ${BOLD}4. 仅 Hysteria 2 节点显示 -1：${PLAIN}"
echo -e "     -> 根因：部分旧版 Clash 客户端不支持 Salamander 混淆，或本地运营商 QoS 丢弃 UDP 443。"
echo -e "     -> 解决：优先选用原生极速 VLESS-Reality 节点，或升级客户端到最新 Mihomo 内核。"
echo
echo -e "${BOLD}${BLUE}======================================================================${PLAIN}\n"

# 7. 返回整体健康码 (Sing-box 或 Nginx 核心故障时返回 1，供监控与自动化流水线判定)
if [ "${S_SINGBOX:-0}" -ne 0 ] || [ "${S_NGINX:-0}" -ne 0 ]; then
    exit 1
fi
exit 0
