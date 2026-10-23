#!/usr/bin/env bash
# ==============================================================================
# AimiliVPN - 定时系统自愈与内存深度清理调度管理器 (setup_cron.sh)
# 功能:
# 1. 每日凌晨 04:00 执行内存页面释放 (drop_caches)，解决小内存 VPS (512M/1G) OOM 痛点
# 2. 定时调用 HTTPS 权威时钟同步，彻底根绝 VMess/VLESS 时间漂移 >90s 导致连接断开
# 3. 每 15 分钟守护监控: 核心服务 (sing-box/aimilivpn) 崩溃自愈拉起
# 4. 公网 IP 动态变更检测: 若发现 IP 漂移，自动更新订阅并通过 Telegram Bot 推送
# 5. SSL 证书静默续期与 systemd 日志轻量化清理 (防磁盘爆满)
# ==============================================================================

set -e

INSTALL_DIR="/opt/aimilivpn"
DATA_DIR="${INSTALL_DIR}/vpngate_data"
CRON_FILE="/etc/cron.d/aimilivpn-maintenance"
MAINT_LOG="/var/log/aimilivpn-maintenance.log"

C_RED="\033[0;31m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[0;33m"
C_BLUE="\033[0;36m"
C_BOLD="\033[1m"
C_RESET="\033[0m"

log_info() { echo -e "${C_GREEN}[INFO]${C_RESET} $1"; }
log_warn() { echo -e "${C_YELLOW}[WARN]${C_RESET} $1"; }
log_err() { echo -e "${C_RED}[ERROR]${C_RESET} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_err "请使用 root 权限运行此脚本: sudo bash $0"
        exit 1
    fi
}

install_cron() {
    check_root
    log_info "正在配置系统定时自愈与维护任务至 /etc/cron.d/..."

    cat > "${CRON_FILE}" <<EOF
# AimiliVPN 自动化系统自愈与深度维护调度
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# 每日凌晨 04:00 执行深度内存释放、时间校准与证书检测
0 4 * * * root /bin/bash ${INSTALL_DIR}/scripts/setup_cron.sh run >> ${MAINT_LOG} 2>&1

# 每 15 分钟执行进程保活守护与 IP 变更探测
*/15 * * * * root /bin/bash ${INSTALL_DIR}/scripts/setup_cron.sh watchdog >> ${MAINT_LOG} 2>&1
EOF

    chmod 644 "${CRON_FILE}"
    if systemctl is-active --quiet cron 2>/dev/null; then
        systemctl restart cron
    elif systemctl is-active --quiet crond 2>/dev/null; then
        systemctl restart crond
    fi

    log_info "定时任务已成功安装并启用！"
    show_status
}

uninstall_cron() {
    check_root
    log_info "正在移除 AimiliVPN 定时维护任务..."
    rm -f "${CRON_FILE}"
    log_info "定时维护任务已成功卸载。"
}

# 深度日常维护 (每日凌晨 04:00 执行)
run_maintenance() {
    echo "=========================================================="
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始执行 AimiliVPN 深度系统维护..."

    # 1. 内存同步与缓存释放
    echo "1. 正在同步磁盘并释放 Linux 内核页面缓存 (drop_caches)..."
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    echo "   内存清理完毕: 当前可用内存 $(free -m | awk '/Mem:/ {print $7}') MB"

    # 2. 权威 HTTPS 时钟校准
    if [[ -x "${INSTALL_DIR}/scripts/check_time_sync.sh" ]]; then
        echo "2. 正在执行 HTTPS 权威时钟同步..."
        "${INSTALL_DIR}/scripts/check_time_sync.sh" fix || true
    fi

    # 3. 域名 SSL 证书续期检测
    if [[ -x "${INSTALL_DIR}/scripts/manage_cert.sh" ]]; then
        echo "3. 正在检测 SSL 证书有效期..."
        "${INSTALL_DIR}/scripts/manage_cert.sh" renew || true
    fi

    # 4. 日志轻量化与磁盘清理 (保留最近 3 天日志，清除 /tmp 垃圾)
    if command -v journalctl >/dev/null 2>&1; then
        echo "4. 正在缩减 systemd 日志 (保留最近 3 天)..."
        journalctl --vacuum-time=3d >/dev/null 2>&1 || true
    fi
    find /tmp -type f -atime +7 -delete >/dev/null 2>&1 || true

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] AimiliVPN 深度系统维护完成！"
    echo "=========================================================="
}

# 实时进程看门狗与 IP 变更自愈 (每 15 分钟执行)
run_watchdog() {
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')

    # 1. 检查 Sing-box 服务 (仅在服务已启用时守护自愈)
    if [ "$(systemctl is-enabled sing-box.service 2>/dev/null || echo '')" = "enabled" ]; then
        if ! systemctl is-active --quiet sing-box.service 2>/dev/null; then
            echo "[${now}] [WATCHDOG] ⚠️ 发现 Sing-box 处于停止/异常状态，正在自动拉起自愈..."
            systemctl restart sing-box.service || true
            # 如果存在 TG Bot，则发送告警
            if [[ -x "${INSTALL_DIR}/scripts/tg_bot.sh" ]]; then
                "${INSTALL_DIR}/scripts/tg_bot.sh" alert "核心服务异常" "Sing-box 进程退出，看门狗已自动拉起重启。" || true
            fi
        fi
    fi

    # 2. 检查 AimiliVPN 基础管理服务 (仅在服务已启用时守护自愈，尊重纯直连极简模式)
    if [ "$(systemctl is-enabled aimilivpn.service 2>/dev/null || echo '')" = "enabled" ]; then
        if ! systemctl is-active --quiet aimilivpn.service 2>/dev/null; then
            echo "[${now}] [WATCHDOG] ⚠️ 发现 AimiliVPN 基础服务处于停止状态，正在自动拉起..."
            systemctl restart aimilivpn.service || true
        fi
    fi

    # 3. 检查公网 IP 变动
    local old_ip=""
    local cur_ip=""
    local ip_file="${DATA_DIR}/public_ip.txt"
    if [[ -f "${ip_file}" ]]; then
        old_ip=$(cat "${ip_file}" | tr -d '[:space:]')
    fi

    cur_ip=$(curl -s --connect-timeout 4 https://api.ipify.org || true)
    if [[ -n "${cur_ip}" && -n "${old_ip}" && "${cur_ip}" != "${old_ip}" && "${old_ip}" != "您的服务器公网IP" ]]; then
        echo "[${now}] [WATCHDOG] 🔔 检测到 VPS 公网 IP 发生变更: ${old_ip} -> ${cur_ip}，正在自动更新配置与订阅..."
        echo "${cur_ip}" > "${ip_file}"
        if [[ -f "${INSTALL_DIR}/scripts/generate_subs.py" && -f "${DATA_DIR}/singbox_nodes.json" ]]; then
            python3 "${INSTALL_DIR}/scripts/generate_subs.py" "${DATA_DIR}/singbox_nodes.json" "/var/www/aimilivpn-sub" >> "${MAINT_LOG}" 2>&1 || true
            if [[ -d "/var/lib/aimilivpn/subscriptions" ]]; then
                cp -f /var/www/aimilivpn-sub/* /var/lib/aimilivpn/subscriptions/ 2>/dev/null || true
            fi
        fi
        if [[ -f "${INSTALL_DIR}/scripts/tg_bot.sh" ]]; then
            bash "${INSTALL_DIR}/scripts/tg_bot.sh" alert "VPS 公网 IP 变动" "检测到服务器 IP 从 ${old_ip} 变更至 ${cur_ip}，已自动更新全部协议订阅配置！" || true
            bash "${INSTALL_DIR}/scripts/tg_bot.sh" sub || true
        fi
    fi
}

show_status() {
    echo ""
    echo -e "${C_GREEN}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}            ⏰ AimiliVPN 系统定时自愈与维护状态${C_RESET}"
    echo -e "${C_GREEN}======================================================================${C_RESET}"
    if [[ -f "${CRON_FILE}" ]]; then
        echo -e "  状态:         ${C_GREEN}已启用 (active)${C_RESET}"
        echo -e "  调度配置文件: ${C_BLUE}${CRON_FILE}${C_RESET}"
        echo -e "  维护任务:     每日 04:00 (内存页面释放 + 时钟校准 + 证书续期)"
        echo -e "  看门狗任务:   每 15 分钟 (核心服务自愈拉起 + IP 变更监听)"
    else
        echo -e "  状态:         ${C_RED}未启用 (inactive)${C_RESET}"
    fi

    if [[ -f "${MAINT_LOG}" ]]; then
        echo -e "\n${C_BOLD}【最近 6 行维护与看门狗日志】${C_RESET}"
        tail -n 6 "${MAINT_LOG}" | while IFS= read -r line; do
            echo -e "  ${line}"
        done
    fi
    echo -e "${C_GREEN}======================================================================${C_RESET}"
}

menu() {
    check_root
    while true; do
        echo ""
        echo -e "${C_GREEN}======================================================================${C_RESET}"
        echo -e "${C_BOLD}${C_GREEN}      ⏰ AimiliVPN - 定时系统自愈与内存清理管理${C_RESET}"
        echo -e "${C_GREEN}======================================================================${C_RESET}"
        local total_mem_mb
        total_mem_mb=$(free -m 2>/dev/null | awk '/Mem:/ {print $2}' || echo "2048")
        if [[ "${total_mem_mb}" -le 1024 ]]; then
            echo -e "  💡 ${C_YELLOW}系统检测: 当前物理内存为 ${total_mem_mb}MB (<= 1GB)，强烈推荐启用定时自愈与看门狗，防 OOM 假死！${C_RESET}"
        fi
        echo -e "  ${C_GREEN}[1]${C_RESET} 启用定时自愈与看门狗任务 (推荐，全自动无忧运维)"
        echo -e "  ${C_GREEN}[2]${C_RESET} 立即执行一次深度维护 (内存深度清理 + 时钟校准 + 证书检测)"
        echo -e "  ${C_GREEN}[3]${C_RESET} 立即执行一次进程看门狗与 IP 检查"
        echo -e "  ${C_GREEN}[4]${C_RESET} 查看当前计划任务与最新运行日志"
        echo -e "  ${C_GREEN}[5]${C_RESET} 卸载并禁用定时自愈任务"
        echo -e "  ${C_RED}[0]${C_RESET} 返回上级菜单"
        echo -e "${C_GREEN}======================================================================${C_RESET}"

        read -rp "请选择操作 [0-5]: " opt
        case "${opt}" in
            1)
                install_cron
                read -rp "按回车键继续..." _
                ;;
            2)
                run_maintenance
                read -rp "按回车键继续..." _
                ;;
            3)
                run_watchdog
                log_info "看门狗检测完成！"
                read -rp "按回车键继续..." _
                ;;
            4)
                show_status
                read -rp "按回车键继续..." _
                ;;
            5)
                uninstall_cron
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
    install|enable)
        install_cron
        ;;
    uninstall|disable)
        uninstall_cron
        ;;
    run|maintenance)
        run_maintenance
        ;;
    watchdog|check)
        run_watchdog
        ;;
    status|info)
        show_status
        ;;
    menu|"")
        menu
        ;;
    *)
        echo "用法: $0 {install|uninstall|run|watchdog|status|menu}"
        exit 1
        ;;
esac
