#!/usr/bin/env bash
# ==============================================================================
# AimiliVPN - Cloudflare Argo 隧道管理器 (setup_argo.sh)
# 支持 Quick Tunnel (免CF账号临时穿透) 与 Named Tunnel (固定Token隧道)
# 支持穿透内网/本地端口 (8445/8443)，抗封锁、破NAT、无公网IP免端口映射
# ==============================================================================

set -e

INSTALL_DIR="/opt/aimilivpn"
DATA_DIR="${INSTALL_DIR}/vpngate_data"
ARGO_JSON="${DATA_DIR}/argo_info.json"
ARGO_LOG="/var/log/cloudflared-argo.log"
SERVICE_FILE="/etc/systemd/system/cloudflared-argo.service"
CLOUDFLARED_BIN="/usr/local/bin/cloudflared"

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

install_cloudflared() {
    if [[ -x "${CLOUDFLARED_BIN}" ]]; then
        local ver
        ver=$("${CLOUDFLARED_BIN}" --version 2>/dev/null | head -n 1 || true)
        log_info "cloudflared 已就绪: ${ver}"
        return 0
    fi

    log_info "正在检测系统架构并安装 Cloudflare cloudflared 二进制..."
    local arch
    arch=$(uname -m)
    local pkg_url=""

    case "${arch}" in
        x86_64|amd64)
            pkg_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
            ;;
        aarch64|arm64)
            pkg_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
            ;;
        armv7l|armhf)
            pkg_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm"
            ;;
        *)
            log_err "不支持的 CPU 架构: ${arch}"
            return 1
            ;;
    esac

    local mirrors=(
        "${pkg_url}"
        "https://ghproxy.net/${pkg_url}"
        "https://mirror.ghproxy.com/${pkg_url}"
    )

    local success=0
    for url in "${mirrors[@]}"; do
        log_info "正在下载: ${url} ..."
        if curl -fL --connect-timeout 10 --max-time 120 "${url}" -o "${CLOUDFLARED_BIN}.tmp"; then
            mv "${CLOUDFLARED_BIN}.tmp" "${CLOUDFLARED_BIN}"
            chmod +x "${CLOUDFLARED_BIN}"
            success=1
            break
        fi
    done

    if [[ ${success} -eq 1 ]]; then
        log_info "cloudflared 安装成功: $("${CLOUDFLARED_BIN}" --version)"
    else
        log_err "cloudflared 下载失败，请检查网络连接！"
        return 1
    fi
}

start_quick_tunnel() {
    install_cloudflared || return 1
    local local_port="${1:-8445}"
    log_info "正在启动 Cloudflare 临时 Argo 隧道 (Quick Tunnel)，穿透本地端口 ${local_port}..."

    # 停止旧服务
    systemctl stop cloudflared-argo.service >/dev/null 2>&1 || true

    cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Cloudflare Argo Quick Tunnel Client for AimiliVPN
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=${CLOUDFLARED_BIN} tunnel --url http://127.0.0.1:${local_port} --no-autoupdate
Restart=on-failure
RestartSec=5s
StandardOutput=file:${ARGO_LOG}
StandardError=file:${ARGO_LOG}

[Install]
WantedBy=multi-user.target
EOF

    > "${ARGO_LOG}"
    systemctl daemon-reload
    systemctl enable cloudflared-argo.service >/dev/null 2>&1 || true
    systemctl restart cloudflared-argo.service

    log_info "服务已启动，正在等待 Cloudflare 分配 *.trycloudflare.com 隧道域名..."
    local argo_domain=""
    for i in {1..30}; do
        sleep 1
        if [[ -f "${ARGO_LOG}" ]]; then
            argo_domain=$(grep -oE "https://[a-zA-Z0-9-]+\.trycloudflare\.com" "${ARGO_LOG}" | tail -n 1 | sed 's|https://||' || true)
            if [[ -n "${argo_domain}" ]]; then
                break
            fi
        fi
    done

    if [[ -z "${argo_domain}" ]]; then
        log_warn "未能自动抓取到 Argo 域名，请查看日志: cat ${ARGO_LOG}"
    else
        log_info "🎉 成功分配 Argo 临时穿透域名: ${C_BOLD}${C_BLUE}${argo_domain}${C_RESET}"
        cat > "${ARGO_JSON}" <<EOF
{
  "type": "quick",
  "local_port": ${local_port},
  "domain": "${argo_domain}",
  "updated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    fi

    show_status
}

start_token_tunnel() {
    install_cloudflared || return 1
    local token="$1"
    local domain="$2"
    local local_port="$3"

    if [[ -z "${token}" ]]; then
        echo ""
        echo -e "${C_BOLD}${C_YELLOW}┌────────────────────────────────────────────────────────────────────────┐${C_RESET}"
        echo -e "${C_BOLD}${C_YELLOW}│  Cloudflare Zero Trust 固定隧道 (Named Tunnel) 关键配置向导            │${C_RESET}"
        echo -e "${C_BOLD}${C_YELLOW}└────────────────────────────────────────────────────────────────────────┘${C_RESET}"
        echo -ne "${C_BOLD}请输入 Cloudflare Zero Trust 隧道 Token: ${C_RESET}"
        read -r token
    fi

    if [[ -z "${token}" ]]; then
        log_err "Token 不能为空！"
        return 1
    fi

    if [[ -z "${domain}" ]]; then
        echo ""
        echo -e "${C_CYAN}请输入您在 Cloudflare Zero Trust 控制台为该隧道绑定的公网域名：${C_RESET}"
        echo -e "例如: ${C_GREEN}argo.yourdomain.com${C_RESET}"
        echo -ne "公网域名: "
        read -r domain
    fi

    if [[ -z "${local_port}" ]]; then
        echo ""
        echo -e "${C_YELLOW}【关键回源端口提示】${C_RESET}"
        echo -e "AimiliVPN 的 Sing-box VMess 服务默认监听在本地 ${C_GREEN}8445${C_RESET} 端口 (HTTP)。"
        echo -e "${C_RED}⚠️ 注意：Cloudflare 控制台新建主机名时，默认可能会填入 8001 或 80 等占位符。${C_RESET}"
        echo -e "${C_RED}切勿使用 8001！必须将 Cloudflare 控制台的 URL 修改为与此处完全一致的端口！${C_RESET}"
        echo -ne "请输入本地回源端口 [默认推荐 8445]: "
        read -r local_port
        local_port="${local_port:-8445}"
    fi

    echo ""
    echo -e "${C_GREEN}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}  📌 Cloudflare Zero Trust 控制台回源核对清单 (务必核实):${C_RESET}"
    echo -e "  ① 登录 Cloudflare Zero Trust -> Networks -> Tunnels -> 点击你的隧道"
    echo -e "  ② 进入 ${C_YELLOW}Public Hostnames${C_RESET} 标签页 -> 点击 Add a public hostname"
    echo -e "  ③ 严格按照以下参数填写:"
    echo -e "     - Subdomain / Domain:  ${C_BOLD}${C_CYAN}${domain:-未填写}${C_RESET}"
    echo -e "     - Path:                ${C_CYAN}/vmess${C_RESET} (或留空)"
    echo -e "     - Service Type:        ${C_BOLD}${C_YELLOW}HTTP${C_RESET}  ${C_RED}(千万不要选 HTTPS)${C_RESET}"
    echo -e "     - URL:                 ${C_BOLD}${C_GREEN}127.0.0.1:${local_port}${C_RESET} (或 localhost:${local_port})"
    echo -e "  ⚠️ 若 Cloudflare 界面默认显示 8001，请务必覆盖为: ${C_BOLD}${C_GREEN}127.0.0.1:${local_port}${C_RESET}"
    echo -e "${C_GREEN}======================================================================${C_RESET}"
    echo ""

    log_info "正在配置 Cloudflare 固定 Token 隧道服务 (Named Tunnel)..."
    systemctl stop cloudflared-argo.service >/dev/null 2>&1 || true

    cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Cloudflare Argo Named Tunnel Client for AimiliVPN
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=${CLOUDFLARED_BIN} tunnel run --token ${token}
Restart=on-failure
RestartSec=5s
StandardOutput=file:${ARGO_LOG}
StandardError=file:${ARGO_LOG}

[Install]
WantedBy=multi-user.target
EOF

    > "${ARGO_LOG}"
    systemctl daemon-reload
    systemctl enable cloudflared-argo.service >/dev/null 2>&1 || true
    systemctl restart cloudflared-argo.service

    cat > "${ARGO_JSON}" <<EOF
{
  "type": "token",
  "domain": "${domain}",
  "local_port": ${local_port},
  "token_masked": "${token:0:8}***${token: -6}",
  "updated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

    log_info "固定 Token 隧道已常驻启动！"

    # 自动刷新订阅，注入包含公网域名的 Argo 节点
    if [[ -n "${domain}" ]]; then
        log_info "正在自动更新客户端聚合订阅，注入 Argo 穿透节点..."
        if [[ -f "/usr/local/bin/aimilivpn-generate-subs" ]]; then
            /usr/local/bin/aimilivpn-generate-subs >/dev/null 2>&1 || true
        elif [[ -f "${SCRIPT_DIR}/generate_subs.py" ]]; then
            python3 "${SCRIPT_DIR}/generate_subs.py" "${DATA_DIR}/singbox_nodes.json" /var/www/aimilivpn-sub >/dev/null 2>&1 || true
        fi
        log_info "订阅已更新完成，包含 Argo Anycast 优选节点！"
    fi

    show_status
}

stop_tunnel() {
    log_info "正在停止 Cloudflare Argo 隧道服务..."
    systemctl stop cloudflared-argo.service >/dev/null 2>&1 || true
    systemctl disable cloudflared-argo.service >/dev/null 2>&1 || true
    rm -f "${ARGO_JSON}"
    log_info "Argo 隧道已完全关闭。"
}

show_status() {
    echo ""
    echo -e "${C_GREEN}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}               ⚡ Cloudflare Argo 隧道运行状态${C_RESET}"
    echo -e "${C_GREEN}======================================================================${C_RESET}"

    local is_active="未运行"
    if systemctl is-active --quiet cloudflared-argo.service 2>/dev/null; then
        is_active="${C_GREEN}正在运行 (active)${C_RESET}"
    else
        is_active="${C_RED}未运行 (inactive)${C_RESET}"
    fi

    echo -e "  服务状态:           ${is_active}"

    if [[ -f "${ARGO_JSON}" ]]; then
        local t
        t=$(grep -oE '"type": "[^"]+"' "${ARGO_JSON}" | cut -d'"' -f4 || true)
        local d
        d=$(grep -oE '"domain": "[^"]+"' "${ARGO_JSON}" | cut -d'"' -f4 || true)
        echo -e "  隧道类型:           ${C_YELLOW}${t}${C_RESET}"
        if [[ -n "${d}" ]]; then
            echo -e "  穿透域名:           ${C_BLUE}https://${d}${C_RESET}"
            echo -e "  节点伪装 SNI/Host:  ${C_BLUE}${d}${C_RESET}"
            echo -e "  节点连接地址:       可直接使用 Cloudflare 优选 IP (如 104.16.0.1) 提升速度！"
        fi
    fi

    if [[ -f "${ARGO_LOG}" ]]; then
        echo -e "\n${C_BOLD}【最近 5 行运行日志】${C_RESET}"
        tail -n 5 "${ARGO_LOG}" | while IFS= read -r line; do
            echo -e "  ${line}"
        done
    fi
    echo -e "${C_GREEN}======================================================================${C_RESET}"
}

uninstall_argo() {
    log_info "正在清理并卸载 Argo 隧道..."
    systemctl stop cloudflared-argo.service >/dev/null 2>&1 || true
    systemctl disable cloudflared-argo.service >/dev/null 2>&1 || true
    rm -f "${SERVICE_FILE}" "${ARGO_LOG}" "${ARGO_JSON}"
    rm -f "${CLOUDFLARED_BIN}"
    systemctl daemon-reload
    log_info "Argo 隧道与 cloudflared 已完全卸载。"
}

show_token_guide() {
    echo ""
    echo -e "${C_GREEN}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}     📖 Cloudflare Zero Trust 固定隧道 (Named Tunnel) Token 获取向导${C_RESET}"
    echo -e "${C_GREEN}======================================================================${C_RESET}"
    echo -e "  固定隧道可让您的穿透域名永久固定，彻底免受 IP/端口被墙困扰，支持绑定自备域名！"
    echo ""
    echo -e "  ${C_BOLD}【4 步傻瓜式获取 Token】${C_RESET}"
    echo -e "  步骤 ①: 登录 Cloudflare 控制台 -> 点击左侧 ${C_BLUE}Zero Trust${C_RESET}"
    echo -e "          (或直接访问 https://one.dash.cloudflare.com )"
    echo -e "  步骤 ②: 进入左侧菜单 ${C_YELLOW}Networks${C_RESET} -> ${C_YELLOW}Tunnels${C_RESET} -> 点击 ${C_GREEN}Add a tunnel${C_RESET}"
    echo -e "  步骤 ③: 隧道类型选择 ${C_BLUE}Cloudflared${C_RESET}，输入任意名称 (如: aimili-tunnel)，点击 Save"
    echo -e "  步骤 ④: 在 'Install and run a connector' 页面选择 Linux 操作系统，"
    echo -e "          下方会展示命令: cloudflared service install ${C_BOLD}${C_YELLOW}eyJhIjoiYTY4...${C_RESET}"
    echo -e "          ${C_BOLD}${C_GREEN}其中那一长串以 eyJh 开头的长文本即为您的专属 Token！${C_RESET}"
    echo ""
    echo -e "  ${C_BOLD}${C_YELLOW}【关键防坑！Public Hostname 回源配置】${C_RESET}"
    echo -e "  在隧道设置页面的 ${C_YELLOW}Public Hostnames${C_RESET} 标签页中添加主机名:"
    echo -e "    * Subdomain / Domain: 您的专属子域名 (如: ${C_CYAN}argo.yourdomain.com${C_RESET})"
    echo -e "    * Path:               留空 或输入 ${C_CYAN}/vmess${C_RESET}"
    echo -e "    * Service Type:       必须选择 ${C_BOLD}${C_YELLOW}HTTP${C_RESET} (切勿选 HTTPS)"
    echo -e "    * URL:                必须填写 ${C_BOLD}${C_GREEN}127.0.0.1:8445${C_RESET} (或 localhost:8445)"
    echo -e "  ${C_RED}⚠️ 警告：Cloudflare 界面默认占位符常常是 8001 或 80，切勿使用默认的 8001！${C_RESET}"
    echo -e "  ${C_RED}AimiliVPN 服务监听在 8445，如果留着 8001，隧道请求将必定报 502 错误！${C_RESET}"
    echo -e "${C_GREEN}======================================================================${C_RESET}"
}

menu() {
    check_root
    while true; do
        echo ""
        echo -e "${C_GREEN}======================================================================${C_RESET}"
        echo -e "${C_BOLD}${C_GREEN}          🌐 AimiliVPN - Cloudflare Argo 隧道穿透管理${C_RESET}"
        echo -e "${C_GREEN}======================================================================${C_RESET}"
        echo -e "  ${C_GREEN}[1]${C_RESET} 开启临时隧道 (Quick Tunnel - 免CF账号/一键自动分配 trycloudflare 域名)"
        echo -e "  ${C_GREEN}[2]${C_RESET} 配置固定隧道 (Named Tunnel - 绑定用户自备 Cloudflare Token/永久域名)"
        echo -e "  ${C_GREEN}[3]${C_RESET} 📖 查看 Cloudflare Zero Trust 固定隧道 Token 获取傻瓜图文指南"
        echo -e "  ${C_GREEN}[4]${C_RESET} 查看当前 Argo 隧道运行状态与日志"
        echo -e "  ${C_GREEN}[5]${C_RESET} 重启 Argo 隧道服务"
        echo -e "  ${C_GREEN}[6]${C_RESET} 停止 Argo 隧道服务"
        echo -e "  ${C_GREEN}[7]${C_RESET} 卸载 Argo 隧道与 cloudflared"
        echo -e "  ${C_RED}[0]${C_RESET} 返回上级菜单"
        echo -e "${C_GREEN}======================================================================${C_RESET}"

        read -rp "请选择操作 [0-7]: " opt
        case "${opt}" in
            1)
                read -rp "请输入需要穿透的本地服务端口 (默认 8445): " p
                p="${p:-8445}"
                start_quick_tunnel "${p}"
                read -rp "按回车键继续..." _
                ;;
            2)
                start_token_tunnel
                read -rp "按回车键继续..." _
                ;;
            3)
                show_token_guide
                read -rp "按回车键继续..." _
                ;;
            4)
                show_status
                read -rp "按回车键继续..." _
                ;;
            5)
                systemctl restart cloudflared-argo.service >/dev/null 2>&1 || true
                log_info "服务已重启"
                show_status
                read -rp "按回车键继续..." _
                ;;
            6)
                stop_tunnel
                read -rp "按回车键继续..." _
                ;;
            7)
                uninstall_argo
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

# CLI 参数调用分发
case "${1:-}" in
    quick)
        check_root
        start_quick_tunnel "${2:-8445}"
        ;;
    token)
        check_root
        start_token_tunnel "${2:-}" "${3:-}" "${4:-8445}"
        ;;
    status|info)
        show_status
        ;;
    restart)
        check_root
        systemctl restart cloudflared-argo.service
        show_status
        ;;
    stop)
        check_root
        stop_tunnel
        ;;
    uninstall)
        check_root
        uninstall_argo
        ;;
    menu|"")
        menu
        ;;
    *)
        echo "用法: $0 {quick [port]|token <token> [domain] [port]|status|restart|stop|uninstall|menu}"
        exit 1
        ;;
esac
