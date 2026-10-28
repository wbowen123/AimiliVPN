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

    if command -v systemctl >/dev/null 2>&1; then
        setup_systemd_service
    fi

    echo -e "\n正在向您的 Telegram 发送测试消息..."
    send_test_message
}

setup_systemd_service() {
    local service_path="/etc/systemd/system/aimilivpn-tgbot.service"
    cat > "${service_path}" <<EOF
[Unit]
Description=AimiliVPN Telegram Bot Service
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/bin/bash ${INSTALL_DIR}/scripts/tg_bot.sh daemon
Restart=on-failure
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable aimilivpn-tgbot.service >/dev/null 2>&1 || true
    systemctl restart aimilivpn-tgbot.service >/dev/null 2>&1 || true
    log_info "已配置并启动 Telegram Bot 常驻后台服务 (aimilivpn-tgbot.service)"
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

    local content
    content=$(python3 - "${DATA_DIR}" <<'EOF'
import sys, json, os

data_dir = sys.argv[1]
nodes_file = os.path.join(data_dir, 'singbox_nodes.json')
links_file = os.path.join(data_dir, 'nodes.txt')
sub_dir = '/var/www/aimilivpn-sub'

domain = ''
if os.path.exists(nodes_file):
    try:
        with open(nodes_file, encoding='utf-8') as f:
            domain = json.load(f).get('domain', '')
    except Exception: pass

ip = '您的IP'
ip_file = os.path.join(data_dir, 'public_ip.txt')
if os.path.exists(ip_file):
    try:
        with open(ip_file, encoding='utf-8') as f: ip = f.read().strip()
    except Exception: pass

secret_path = ''
auth_file = os.path.join(data_dir, 'ui_auth.json')
if os.path.exists(auth_file):
    try:
        with open(auth_file, encoding='utf-8') as f:
            secret_path = json.load(f).get('secret_path', '').strip('/')
    except Exception: pass
sub_prefix = f'sub_{secret_path}/' if secret_path else ''

host = domain if domain else ip
sub_url = f'https://{host}:18443/{sub_prefix}sub.txt'
clash_url = f'https://{host}:18443/{sub_prefix}clash.yaml'
singbox_url = f'https://{host}:18443/{sub_prefix}singbox.json'

lines = [
    '⚡ <b>AimiliVPN 全协议订阅推送</b>',
    '',
    '🌐 <b>通用 HTTPS 订阅:</b>',
    f'<code>{sub_url}</code>',
    '',
    '🐱 <b>Clash / Mihomo 订阅:</b>',
    f'<code>{clash_url}</code>',
    '',
    '📦 <b>Sing-box 格式配置:</b>',
    f'<code>{singbox_url}</code>',
    ''
]

nodes = []
for p in [os.path.join(sub_dir, 'nodes.txt'), os.path.join(data_dir, 'nodes.txt'), os.path.join(data_dir, 'singbox_links.txt')]:
    if os.path.exists(p):
        try:
            with open(p, encoding='utf-8') as f:
                nodes = [l.strip() for l in f if l.strip() and not l.startswith('#')]
            if nodes:
                break
        except Exception:
            pass

if nodes:
    lines.append(f'📋 <b>已激活节点数:</b> {len(nodes)} 个')
    lines.append('💡 推荐直接复制上方 HTTPS 订阅 URL 导入 Shadowrocket / Clash Verge / v2rayN 即可自动同步全部节点。')

print('\n'.join(lines))
EOF
)
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

    if ! send_tg_message "${msg}"; then
        log_warn "Telegram 告警推送失败，请核对 Bot Token 及网络配置。"
        return 1
    fi
    return 0
}

run_daemon() {
    get_tg_config
    if [[ -z "${BOT_TOKEN}" || -z "${CHAT_ID}" ]]; then
        log_err "未配置 Telegram Bot Token 或 Chat ID，Daemon 退出。"
        exit 1
    fi
    log_info "启动 AimiliVPN Telegram Bot 守护进程..."
    python3 - "${TG_JSON}" "${INSTALL_DIR}" <<'EOF'
import sys, os, time, json, urllib.request, urllib.parse, subprocess

tg_json = sys.argv[1]
install_dir = sys.argv[2]

if not os.path.exists(tg_json):
    sys.exit(0)

try:
    with open(tg_json, 'r', encoding='utf-8') as f:
        cfg = json.load(f)
    token = cfg.get('bot_token', '')
    allowed_chat = str(cfg.get('chat_id', ''))
except Exception:
    sys.exit(1)

if not token or not allowed_chat:
    sys.exit(0)

def send_msg(chat_id, text):
    try:
        url = f"https://api.telegram.org/bot{token}/sendMessage"
        payload = {"chat_id": chat_id, "text": text, "parse_mode": "HTML", "disable_web_page_preview": True}
        req = urllib.request.Request(url, data=json.dumps(payload).encode('utf-8'), headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            pass
    except Exception:
        pass

offset = 0
while True:
    try:
        url = f"https://api.telegram.org/bot{token}/getUpdates?offset={offset}&timeout=20"
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=25) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            if data.get("ok"):
                for update in data.get("result", []):
                    offset = update["update_id"] + 1
                    msg = update.get("message", {})
                    chat = str(msg.get("chat", {}).get("id", ""))
                    if chat != allowed_chat:
                        continue
                    text = msg.get("text", "").strip()
                    if text in ("/start", "/help"):
                        send_msg(chat, "👋 <b>您好！我是 AimiliVPN 专属管理机器人。</b>\n\n可用指令：\n/nodes - 提取全协议 10 大节点与订阅链接\n/status - 检查 VPS 运行与服务健康状态\n/help - 显示此帮助信息")
                    elif text == "/nodes":
                        sub_script = os.path.join(install_dir, "scripts", "tg_bot.sh")
                        subprocess.run(["/bin/bash", sub_script, "sub"], timeout=30)
                    elif text == "/status":
                        health_script = os.path.join(install_dir, "scripts", "check_health.sh")
                        try:
                            st = subprocess.check_output(["/bin/bash", health_script], stderr=subprocess.STDOUT, timeout=15).decode('utf-8', errors='ignore')
                            send_msg(chat, f"📊 <b>VPS 运行状态:</b>\n<pre>{st[:3000]}</pre>")
                        except Exception as e:
                            send_msg(chat, f"⚠️ 获取状态失败: {e}")
    except Exception:
        time.sleep(5)
EOF
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
    daemon)
        run_daemon
        ;;
    service)
        setup_systemd_service
        ;;
    status|info)
        show_status
        ;;
    menu|"")
        menu
        ;;
    *)
        echo "用法: $0 {config|test|sub|alert <title> <message>|status|daemon|service|menu}"
        exit 1
        ;;
esac
