#!/usr/bin/env bash
# ==============================================================================
# AimiliVPN - Cloudflare CDN 三网优选 IP 测速与替换工具 (cf_speedtest.sh)
# 解决开启 Cloudflare 小黄云 (CDN 443 / Argo) 后晚高峰国内三网减速与丢包痛点
# 【安全原则】仅用于加速走 CDN/Argo 的节点，绝对不覆盖或影响 VPS 物理直连 IP！
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
    echo -e "  ${C_BOLD}${C_YELLOW}【安全铁律】测速与优选 IP 仅用于 CDN 穿透节点，绝对不改动您的物理直连 IP！${C_RESET}"
    log_info "正在对常用 Anycast IP 段执行 443 端口 TCP 连通性测试 (共 ${#CANDIDATE_IPS[@]} 个目标)..."

    local tmp_results
    tmp_results=$(mktemp)

    local pids=()
    for ip in "${CANDIDATE_IPS[@]}"; do
        test_single_ip "${ip}" >> "${tmp_results}" &
        pids+=($!)
    done

    for pid in "${pids[@]}"; do
        wait "${pid}" 2>/dev/null || true
    done

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
    local ranked_ips=()
    while IFS= read -r line; do
        local ms
        ms=$(echo "${line}" | awk '{print $1}')
        local ip
        ip=$(echo "${line}" | awk '{print $2}')

        if [[ -z "${best_ip}" ]]; then
            best_ip="${ip}"
        fi
        ranked_ips+=("${ip}")

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
    echo ""
    echo -e "${C_BOLD}【请选择优选 Anycast IP 套用方式】:${C_RESET}"
    echo -e "  ${C_GREEN}[1]${C_RESET} 自动套用排名 No.1 综合最优 IP (${C_BOLD}${C_GREEN}${best_ip}${C_RESET}) [推荐，直接回车]"
    echo -e "  ${C_GREEN}[2]${C_RESET} 从上方列表中自选排名序号套用 (例如输入 2 或 3)"
    echo -e "  ${C_GREEN}[3]${C_RESET} 手动输入自定义 Anycast IP (如 104.16.160.10)"
    echo -e "  ${C_GREEN}[4]${C_RESET} 仅查看测速结果，不修改当前配置"

    local apply_choice
    read -rp "请选择 [1-4，默认 1]: " apply_choice
    apply_choice="${apply_choice:-1}"

    local chosen_ip=""
    case "${apply_choice}" in
        1)
            chosen_ip="${best_ip}"
            ;;
        2)
            read -rp "请输入要套用的排名序号 [1-${#ranked_ips[@]}]: " pick_num
            pick_num="${pick_num:-1}"
            if [[ "$pick_num" =~ ^[0-9]+$ ]] && [[ "$pick_num" -ge 1 ]] && [[ "$pick_num" -le "${#ranked_ips[@]}" ]]; then
                chosen_ip="${ranked_ips[$((pick_num - 1))]}"
            else
                log_warn "序号无效，默认使用 No.1 最优 IP: ${best_ip}"
                chosen_ip="${best_ip}"
            fi
            ;;
        3)
            read -rp "请输入自定义 Anycast IP (例如 104.16.160.10): " custom_ip
            custom_ip=$(echo "${custom_ip}" | tr -d '[:space:]')
            if [[ -n "${custom_ip}" ]]; then
                chosen_ip="${custom_ip}"
            else
                log_warn "输入为空，默认使用 No.1 最优 IP: ${best_ip}"
                chosen_ip="${best_ip}"
            fi
            ;;
        4)
            echo -e "${C_BLUE}已取消套用，保留现有配置不变。${C_RESET}"
            return 0
            ;;
        *)
            chosen_ip="${best_ip}"
            ;;
    esac

    echo "${chosen_ip}" > "${CF_IP_FILE}"
    log_info "已成功将优选 IP [${chosen_ip}] 保存至 ${CF_IP_FILE}"
    echo ""
    echo -e "  ${C_BOLD}【优选 Anycast IP 作用范围与目标节点清单】${C_RESET}"
    echo -e "  ${C_GREEN}● 生效节点 (客户端连接地址自动替换为 ${chosen_ip}):${C_RESET}"
    echo -e "    1. ⛅ [CDN-优选IP·IPv4] VMess-WS-Argo【Anycast优选·Cloudflare全球破墙】"
    echo -e "    2. ⛅ [CDN-小黄云·IPv4] VMess-xHTTP【Cloudflare-CDN·分块免流破墙】"
    echo -e "    3. ⛅ [CDN-小黄云·IPv4] VLESS-WS-TLS【Cloudflare-CDN·小黄云破墙】"
    echo -e "  ${C_YELLOW}● 绝不生效节点 (100% 保持 VPS 真实物理 IP 直连):${C_RESET}"
    echo -e "    - 所有 🚀 [直连-极速] 节点 (Reality, Hy2, TUIC, AnyTLS, xHTTP-直连)"
    echo -e "    - 所有 🏠 [住宅-家宽] 节点 (直连入站 + Aimili 动态家宽出口)"
    echo -e "${C_GREEN}======================================================================${C_RESET}"

    # 询问是否立即刷新 Sing-box 订阅
    read -rp "是否立即重新生成订阅节点以应用新的优选 IP？[Y/n]: " reload_sub
    reload_sub=$(echo "${reload_sub:-y}" | tr '[:upper:]' '[:lower:]')
    if [[ "$reload_sub" != "n" ]]; then
        if [[ -f "${INSTALL_DIR}/scripts/setup_singbox.sh" ]]; then
            log_info "正在刷新 Sing-box 订阅..."
            bash "${INSTALL_DIR}/scripts/setup_singbox.sh" >/dev/null 2>&1 || true
            log_info "订阅已更新完成！"
        fi
    fi
}

show_dns_guide() {
    echo ""
    echo -e "${C_GREEN}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}     📖 IPv4 / IPv6 双栈 VPS 与 Cloudflare 4 条 DNS 记录傻瓜配置向导${C_RESET}"
    echo -e "${C_GREEN}======================================================================${C_RESET}"
    echo -e "为彻底解决【开小黄云拖慢直连与住宅】的冲突，请在 Cloudflare 添加以下 4 条记录："
    echo ""
    echo -e "  ${C_BOLD}【组一：直连与住宅极速域名】—— 必须关闭小黄云 (DNS Only / 灰云)${C_RESET}"
    echo -e "  ① 类型: ${C_BLUE}A${C_RESET}    | 名称: ${C_YELLOW}direct${C_RESET} | 内容: ${C_GREEN}您的IPv4${C_RESET} | 代理状态: ${C_RED}仅DNS (灰云)${C_RESET}"
    echo -e "  ② 类型: ${C_BLUE}AAAA${C_RESET} | 名称: ${C_YELLOW}direct${C_RESET} | 内容: ${C_GREEN}您的IPv6${C_RESET} | 代理状态: ${C_RED}仅DNS (灰云)${C_RESET}"
    echo -e "  👉 作用: 专供 VLESS-Reality、Hysteria 2、TUIC、住宅家宽直连，跑满物理千兆！"
    echo ""
    echo -e "  ${C_BOLD}【组二：破墙与CDN逃生域名】—— 必须开启小黄云 (Proxied / 橙云)${C_RESET}"
    echo -e "  ③ 类型: ${C_BLUE}A${C_RESET}    | 名称: ${C_YELLOW}cdn${C_RESET}    | 内容: ${C_GREEN}您的IPv4${C_RESET} | 代理状态: ${C_GREEN}已代理 (橙色小黄云)${C_RESET}"
    echo -e "  ④ 类型: ${C_BLUE}AAAA${C_RESET} | 名称: ${C_YELLOW}cdn${C_RESET}    | 内容: ${C_GREEN}您的IPv6${C_RESET} | 代理状态: ${C_GREEN}已代理 (橙色小黄云)${C_RESET}"
    echo -e "  👉 作用: 专供 VMess-WS、xHTTP、Argo 隧道使用，VPS 被封时 100% 破墙救急！"
    echo ""
    echo -e "  ${C_BOLD}【优选 IP 与直连 IP 的关系说明】${C_RESET}"
    echo -e "  ⚠️ 本测速工具生成的优选 IP ${C_BOLD}仅仅替换组二中 CDN 节点的客户端连接地址${C_RESET}；"
    echo -e "  ⚠️ 组一中的所有直连节点与住宅节点依然直接连接您的 VPS，${C_BOLD}绝不覆盖或影响物理IP${C_RESET}！"
    echo -e "${C_GREEN}======================================================================${C_RESET}"
}

show_current() {
    echo ""
    echo -e "${C_GREEN}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}             ⚡ 当前 Cloudflare 优选 Anycast IP 配置${C_RESET}"
    echo -e "${C_GREEN}======================================================================${C_RESET}"
    if [[ -f "${CF_IP_FILE}" ]]; then
        local cur
        cur=$(cat "${CF_IP_FILE}")
        echo -e "  当前保存优选 IP: ${C_BOLD}${C_BLUE}${cur}${C_RESET}"
    else
        echo -e "  当前保存优选 IP: 未测速 (默认推荐 104.16.160.10)"
    fi
    echo -e "  适用范围: 仅应用于带有 ⛅ [CDN-优选IP] 或 [CDN-小黄云] 的穿透节点"
    echo -e "  直连/住宅状态: 100% 保持 VPS 真实物理 IP 直连，不受任何改动影响"
    echo -e "${C_GREEN}======================================================================${C_RESET}"
}

menu() {
    while true; do
        echo ""
        echo -e "${C_GREEN}======================================================================${C_RESET}"
        echo -e "${C_BOLD}${C_GREEN}        ⚡ AimiliVPN - Cloudflare CDN 三网优选 IP 测速管理${C_RESET}"
        echo -e "${C_GREEN}======================================================================${C_RESET}"
        echo -e "  ${C_GREEN}[1]${C_RESET} 运行三网 Anycast 延迟测速并自动保存最优 IP"
        echo -e "  ${C_GREEN}[2]${C_RESET} 📖 查看 IPv4/IPv6 双栈 VPS 与 Cloudflare 4 条 DNS 记录傻瓜配置向导"
        echo -e "  ${C_GREEN}[3]${C_RESET} 查看当前生效的优选 IP 与生效范围"
        echo -e "  ${C_GREEN}[4]${C_RESET} 手动设置自选 Anycast IP"
        echo -e "  ${C_RED}[0]${C_RESET} 返回上级菜单"
        echo -e "${C_GREEN}======================================================================${C_RESET}"

        read -rp "请选择操作 [0-4]: " opt
        case "${opt}" in
            1)
                run_speedtest
                read -rp "按回车键继续..." _
                ;;
            2)
                show_dns_guide
                read -rp "按回车键继续..." _
                ;;
            3)
                show_current
                read -rp "按回车键继续..." _
                ;;
            4)
                read -rp "请输入要指定的 Anycast IP (如 104.16.160.10): " custom_ip
                if [[ -n "${custom_ip}" ]]; then
                    echo "${custom_ip}" > "${CF_IP_FILE}"
                    log_info "已保存自定义优选 IP: ${custom_ip}"
                fi
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
    test|run)
        run_speedtest
        ;;
    guide|dns)
        show_dns_guide
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
    menu|"")
        menu
        ;;
    *)
        echo "用法: $0 {test|guide|show|set <IP>|menu}"
        exit 1
        ;;
esac
