#!/usr/bin/env bash
# ==============================================================================
# AimiliVPN - Cloudflare CDN 三网优选 IP 测速与替换工具 (cf_speedtest.sh)
# 解决开启 Cloudflare 小黄云 (CDN 443 / Argo) 后晚高峰国内三网减速与丢包痛点
# 原理: 保持请求 SNI / Host 为用户域名，将客户端连接 IP 替换为直连最快的 Anycast 边缘节点
# ==============================================================================

set -e

INSTALL_DIR="/opt/aimilivpn"
DATA_DIR="${INSTALL_DIR}/vpngate_data"
CF_IP_FILE="${DATA_DIR}/cf_clean_ip.txt"

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

# 经典全球 Anycast 优质测速候选 IP 库 (覆盖电信/联通/移动亚太直连段)
CANDIDATE_IPS=(
    "104.16.160.10"
    "104.16.161.12"
    "104.17.150.15"
    "104.18.32.20"
    "104.19.18.30"
    "104.20.48.50"
    "104.22.10.88"
    "104.24.120.10"
    "104.25.150.25"
    "172.64.32.1"
    "172.65.182.1"
    "172.67.70.1"
    "162.159.192.1"
    "162.159.193.10"
    "162.159.153.1"
    "198.41.214.162"
    "188.114.96.1"
    "188.114.97.2"
    "141.101.90.1"
    "108.162.192.1"
)

test_single_ip() {
    local ip="$1"
    local rtt=9999

    # 优先使用 curl 测试 443 端口 TCP 握手延迟
    if command -v curl >/dev/null 2>&1; then
        local time_connect
        time_connect=$(curl -s -k --connect-timeout 2 -o /dev/null -w "%{time_connect}" "https://${ip}:443" 2>/dev/null || echo "0")
        if [[ "${time_connect}" != "0" && "${time_connect}" != "0.000" && "${time_connect}" != "" ]]; then
            # 转为毫秒
            rtt=$(awk "BEGIN {print int(${time_connect} * 1000)}")
        fi
    fi

    # 回退到 ping
    if [[ "${rtt}" -eq 9999 ]] && command -v ping >/dev/null 2>&1; then
        local p_out
        p_out=$(ping -c 2 -W 2 "${ip}" 2>/dev/null | tail -1 || true)
        if echo "${p_out}" | grep -q "/"; then
            rtt=$(echo "${p_out}" | awk -F '/' '{print int($5)}')
        fi
    fi

    echo "${rtt} ${ip}"
}

run_speedtest() {
    echo ""
    echo -e "${C_GREEN}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}        ⚡ Cloudflare CDN Anycast 三网边缘节点毫秒级延迟测速${C_RESET}"
    echo -e "${C_GREEN}======================================================================${C_RESET}"
    log_info "正在对常用 Anycast IP 段执行 443 端口 TCP 连通性测试 (共 ${#CANDIDATE_IPS[@]} 个目标)..."

    local tmp_results
    tmp_results=$(mktemp)

    local pids=()
    for ip in "${CANDIDATE_IPS[@]}"; do
        test_single_ip "${ip}" >> "${tmp_results}" &
        pids+=($!)
    done

    # 等待并发测速完成
    for pid in "${pids[@]}"; do
        wait "${pid}" 2>/dev/null || true
    done

    # 过滤出成功延迟并按延迟从小到大排序
    local sorted_results
    sorted_results=$(grep -v "^9999" "${tmp_results}" | sort -n || true)
    rm -f "${tmp_results}"

    if [[ -z "${sorted_results}" ]]; then
        log_warn "未能获取到低延迟 IP，可能当前服务器防火墙限制了出站 443 测试，使用默认推荐优选 IP: 104.16.160.10"
        echo "104.16.160.10" > "${CF_IP_FILE}"
        return 0
    fi

    echo ""
    printf "%-8s | %-18s | %-16s | %-10s\n" "排名" "优选 Anycast IP" "延迟 (TCP 443)" "推荐运营商"
    echo "----------------------------------------------------------------------"

    local rank=1
    local best_ip=""
    while IFS= read -r line; do
        local ms
        ms=$(echo "${line}" | awk '{print $1}')
        local ip
        ip=$(echo "${line}" | awk '{print $2}')

        if [[ -z "${best_ip}" ]]; then
            best_ip="${ip}"
        fi

        local isp="三网通用"
        if [[ "${ip}" =~ ^104\.1[67] ]]; then
            isp="中国电信/移动"
        elif [[ "${ip}" =~ ^104\.2[24] || "${ip}" =~ ^172\.64 ]]; then
            isp="中国联通"
        elif [[ "${ip}" =~ ^162\.159 || "${ip}" =~ ^188\.114 ]]; then
            isp="中国移动/广电"
        fi

        printf "No.%-5d | %-18s | %-5s ms         | %-10s\n" "${rank}" "${ip}" "${ms}" "${isp}"
        ((rank++))
        if [[ ${rank} -gt 10 ]]; then
            break
        fi
    done <<< "${sorted_results}"

    echo "----------------------------------------------------------------------"
    echo -e "🏆 综合测速最高得分最优 IP: ${C_BOLD}${C_GREEN}${best_ip}${C_RESET}"
    echo "${best_ip}" > "${CF_IP_FILE}"
    log_info "已将最优 IP [${best_ip}] 保存至 ${CF_IP_FILE}"
    echo -e "💡 客户端使用提示: 将 VLESS-WS / VMess-WS 节点的【地址/Address】改为该 IP，"
    echo -e "   【伪装域名/SNI/Host】依然保持您的实际域名即可享受 Anycast 极速加速！"
    echo -e "${C_GREEN}======================================================================${C_RESET}"
}

show_current() {
    if [[ -f "${CF_IP_FILE}" ]]; then
        local cur
        cur=$(cat "${CF_IP_FILE}")
        echo -e "当前保存的 Cloudflare 优选 IP: ${C_BOLD}${C_BLUE}${cur}${C_RESET}"
    else
        echo -e "尚未运行过测速，默认推荐 IP: 104.16.160.10"
    fi
}

case "${1:-}" in
    test|run|"")
        run_speedtest
        ;;
    get|show)
        show_current
        ;;
    set)
        if [[ -n "${2:-}" ]]; then
            echo "$2" > "${CF_IP_FILE}"
            log_info "已手动设置优选 IP: $2"
        else
            echo "用法: $0 set <IP>"
        fi
        ;;
    *)
        echo "用法: $0 {test|show|set <IP>}"
        exit 1
        ;;
esac
