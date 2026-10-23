#!/usr/bin/env bash
# ==============================================================================
# AimiliVPN - Telegram Bot 节点与告警即时推送套件 (tg_bot.sh)
# 支持节点订阅直推 Telegram、服务崩溃/IP变更实时告警与 TG 指令交互
# ==============================================================================

set -e

INSTALL_DIR="/opt/aimilivpn"
DATA_DIR="${INSTALL_DIR}/vpngate_data"
TG_JSON="${DATA_DIR}/tg_bot.json"

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

get_tg_config() {
    if [[ -f "${TG_JSON}" ]]; then
        BOT_TOKEN=$(grep -oE '"bot_token": "[^"]+"' "${TG_JSON}" | cut -d'"' -f4 || true)
        CHAT_ID=$(grep -oE '"chat_id": "[^"]+"' "${TG_JSON}" | cut -d'"' -f4 || true)
    else
        BOT_TOKEN=""
        CHAT_ID=""
    fi
}

send_tg_message() {
    local text="$1"
    local parse_mode="${2:-HTML}"
    get_tg_config

    if [[ -z "${BOT_TOKEN}" || -z "${CHAT_ID}" ]]; then
        log_warn "未配置 Telegram Bot Token 或 Chat ID，无法发送消息。"
        return 1
    fi

    local api_url="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"

    # 使用 python 或 curl 进行安全传输
    python3 - "${api_url}" "${CHAT_ID}" "${text}" "${parse_mode}" <<'EOF'
import sys
import json
import urllib.request
import urllib.parse

api_url, chat_id, text, parse_mode = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

data = {
    "chat_id": chat_id,
    "text": text,
    "parse_mode": parse_mode,
    "disable_web_page_preview": True
}

req = urllib.request.Request(
    api_url,
    data=json.dumps(data).encode('utf-8'),
    headers={"Content-Type": "application/json"}
)

try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        res = json.loads(resp.read().decode('utf-8'))
        if res.get("ok"):
            print("OK")
            sys.exit(0)
        else:
            print("ERR: " + str(res.get("description")), file=sys.stderr)
            sys.exit(1)
except Exception as e:
    print(f"FAILED: {e}", file=sys.stderr)
    sys.exit(1)
EOF
}

configure_bot() {
    get_tg_config
    echo ""
    echo -e "${C_GREEN}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}            🤖 Telegram Bot 通知配置 (AimiliVPN)${C_RESET}"
    echo -e "${C_GREEN}======================================================================${C_RESET}"

    echo -ne "请输入 Telegram Bot Token (当前: ${BOT_TOKEN:-未设置}): "
    read -r input_token
    if [[ -n "${input_token}" ]]; then
        BOT_TOKEN="${input_token}"
    fi

    echo -ne "请输入 Telegram Chat ID (当前: ${CHAT_ID:-未设置}): "
    read -r input_chat
    if [[ -n "${input_chat}" ]]; then
        CHAT_ID="${input_chat}"
    fi

    if [[ -z "${BOT_TOKEN}" || -z "${CHAT_ID}" ]]; then
        log_err "Bot Token 或 Chat ID 不能为空！"
        return 1
    fi

    cat > "${TG_JSON}" <<EOF
{
  "bot_token": "${BOT_TOKEN}",
  "chat_id": "${CHAT_ID}",
  "enabled": true,
  "updated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    chmod 600 "${TG_JSON}"
    log_info "配置已成功保存至 ${TG_JSON} (权限 600 已加固)"
    echo -e "\n正在向您的 Telegram 发送测试消息..."
    send_test_message
}

send_test_message() {
    local host
    host=$(hostname)
    local ip
    ip=$(cat "${DATA_DIR}/public_ip.txt" 2>/dev/null || curl -s --connect-timeout 3 https://api.ipify.org || echo "未知")

    local msg="🚀 <b>AimiliVPN 节点与告警服务测试成功！</b>%0A%0A"
    msg+="💻 <b>主机名:</b> <code>${host}</code>%0A"
    msg+="🌐 <b>公网IP:</b> <code>${ip}</code>%0A"
    msg+="⏰ <b>时间:</b> $(date '+%Y-%m-%d %H:%M:%S')%0A%0A"
    msg+="✅ 您的 Telegram 已成功与 AimiliVPN VPS 节点绑定，后续节点更新与异常告警将直接推送到此窗口。"

    # 将 %0A 还原为换行
    local formatted
    formatted=$(echo -e "${msg//%0A/\\n}")

    if send_tg_message "${formatted}"; then
        log_info "测试消息发送成功，请在 Telegram 客户端查收！"
    else
        log_err "测试消息发送失败，请核对 Bot Token 及 Chat ID 是否有效，以及是否已在 Telegram 中主动与该 Bot 开启对话 (/start)。"
    fi
}

send_subscriptions() {
    log_info "正在提取全协议 10 大节点与订阅链接并发送到 Telegram..."
    get_tg_config
    if [[ -z "${BOT_TOKEN}" || -z "${CHAT_ID}" ]]; then
        log_err "未配置 Telegram Bot，请先运行: ml tg config"
        return 1
    fi

    local python_cmd="
import json, os
data_dir = '${DATA_DIR}'
nodes_file = os.path.join(data_dir, 'singbox_nodes.json')
links_file = os.path.join(data_dir, 'singbox_links.txt')
sub_dir = '/var/www/aimilivpn-sub'

domain = ''
if os.path.exists(nodes_file):
    try:
        with open(nodes_file) as f:
            domain = json.load(f).get('domain', '')
    except: pass

ip = '您的IP'
ip_file = os.path.join(data_dir, 'public_ip.txt')
if os.path.exists(ip_file):
    try:
        with open(ip_file) as f: ip = f.read().strip()
    except: pass

host = domain if domain else ip
sub_url = f'https://{host}:18443/sub.txt'
clash_url = f'https://{host}:18443/clash.yaml'
singbox_url = f'https://{host}:18443/singbox.json'

text = '⚡ <b>AimiliVPN 全协议订阅推送</b>\\n\\n'
text += f'🌐 <b>通用 HTTPS 订阅:</b>\\n<code>{sub_url}</code>\\n\\n'
text += f'🐱 <b>Clash / Mihomo 订阅:</b>\\n<code>{clash_url}</code>\\n\\n'
text += f'📦 <b>Sing-box 格式配置:</b>\\n<code>{singbox_url}</code>\\n\\n'

nodes = []
if os.path.exists(os.path.join(sub_dir, 'nodes.txt')):
    with open(os.path.join(sub_dir, 'nodes.txt')) as f:
        nodes = [l.strip() for l in f if l.strip() and not l.startswith('#')]
elif os.path.exists(links_file):
    with open(links_file) as f:
        nodes = [l.strip() for l in f if l.strip() and not l.startswith('#')]

if nodes:
    text += f'📋 <b>已激活节点数:</b> {len(nodes)} 个\\n'
    text += '💡 推荐直接复制上方 HTTPS 订阅 URL 导入 Shadowrocket / Clash Verge / v2rayN 即可自动同步全部节点。'

print(text)
"
    local content
    content=$(python3 -c "${python_cmd}")
    send_tg_message "${content}"
    log_info "订阅已推送至 Telegram！"
}

send_alert() {
    local title="${1:-系统状态告警}"
    local body="${2:-无详细描述}"
    local host
    host=$(hostname)

    local msg="⚠️ <b>[AimiliVPN 告警] ${title}</b>\n\n"
    msg+="💻 <b>主机名:</b> <code>${host}</code>\n"
    msg+="⏰ <b>发生时间:</b> $(date '+%Y-%m-%d %H:%M:%S')\n"
    msg+="📝 <b>详情:</b> ${body}\n"

    send_tg_message "${msg}" >/dev/null 2>&1 || true
}

show_status() {
    get_tg_config
    echo ""
    echo -e "${C_GREEN}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}             🤖 Telegram Bot 当前集成状态${C_RESET}"
    echo -e "${C_GREEN}======================================================================${C_RESET}"
    if [[ -n "${BOT_TOKEN}" && -n "${CHAT_ID}" ]]; then
        echo -e "  状态:         ${C_GREEN}已配置并激活${C_RESET}"
        echo -e "  Bot Token:    ${C_BLUE}${BOT_TOKEN:0:10}******${BOT_TOKEN: -5}${C_RESET}"
        echo -e "  Chat ID:      ${C_YELLOW}${CHAT_ID}${C_RESET}"
    else
        echo -e "  状态:         ${C_RED}未配置${C_RESET}"
    fi
    echo -e "${C_GREEN}======================================================================${C_RESET}"
}

menu() {
    while true; do
        echo ""
        echo -e "${C_GREEN}======================================================================${C_RESET}"
        echo -e "${C_BOLD}${C_GREEN}        🤖 AimiliVPN - Telegram 节点推送与监控告警${C_RESET}"
        echo -e "${C_GREEN}======================================================================${C_RESET}"
        echo -e "  ${C_GREEN}[1]${C_RESET} 配置 Telegram Bot (Token 与 Chat ID)"
        echo -e "  ${C_GREEN}[2]${C_RESET} 发送连通性测试消息"
        echo -e "  ${C_GREEN}[3]${C_RESET} 一键推送 10 大节点矩阵与订阅链接至 Telegram"
        echo -e "  ${C_GREEN}[4]${C_RESET} 查看当前 Telegram 集成配置"
        echo -e "  ${C_RED}[0]${C_RESET} 返回上级菜单"
        echo -e "${C_GREEN}======================================================================${C_RESET}"

        read -rp "请选择操作 [0-4]: " opt
        case "${opt}" in
            1)
                configure_bot
                read -rp "按回车键继续..." _
                ;;
            2)
                send_test_message
                read -rp "按回车键继续..." _
                ;;
            3)
                send_subscriptions
                read -rp "按回车键继续..." _
                ;;
            4)
                show_status
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
    config)
        configure_bot
        ;;
    test)
        send_test_message
        ;;
    sub|subs|nodes|send-subs)
        send_subscriptions
        ;;
    alert)
        shift
        send_alert "$@"
        ;;
    status|info)
        show_status
        ;;
    menu|"")
        menu
        ;;
    *)
        echo "用法: $0 {config|test|sub|alert <title> <message>|status|menu}"
        exit 1
        ;;
esac
