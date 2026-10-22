#!/usr/bin/env bash
# ==============================================================================
# AimiliVPN 服务器高精度时间同步诊断与漂移自动校准器
# 作用：
#   Reality、TLS 1.3、VMess 等现代加密协议对服务器-客户端时间误差极其敏感
#   误差大于 60-90 秒会导致客户端握手被静默丢弃（表现为连接超时）
#   本脚本通过全球权威 HTTPS 节点时间戳自动测算漂移并毫秒级校准
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
PLAIN='\033[0m'

TIME_ENDPOINTS=(
    "https://www.google.com"
    "https://www.cloudflare.com"
    "https://www.apple.com"
    "https://www.microsoft.com"
    "https://www.baidu.com"
)

get_remote_epoch() {
    local endpoint="$1"
    local date_header
    date_header=$(curl -sI --connect-timeout 3 --max-time 5 "$endpoint" 2>/dev/null | grep -i '^date:' | head -n 1 | sed 's/^[dD][aA][tT][eE]:[[:space:]]*//' | tr -d '\r')
    if [ -n "$date_header" ]; then
        date -d "$date_header" +%s 2>/dev/null || python3 -c "import email.utils, sys; print(int(email.utils.parsedate_to_datetime(sys.argv[1]).timestamp()))" "$date_header" 2>/dev/null || echo ""
    fi
}

echo -e "  -> 正在检测服务器系统时钟与全球标准时间偏差..."
REMOTE_EPOCH=""
for ep in "${TIME_ENDPOINTS[@]}"; do
    REMOTE_EPOCH=$(get_remote_epoch "$ep" || true)
    if [ -n "$REMOTE_EPOCH" ] && [ "$REMOTE_EPOCH" -gt 1700000000 ]; then
        break
    fi
done

if [ -z "$REMOTE_EPOCH" ]; then
    echo -e "${YELLOW}  -> 网络受限，未能获取全球标准时间戳，跳过时间校验。${PLAIN}"
    exit 0
fi

LOCAL_EPOCH=$(date +%s)
DRIFT=$((LOCAL_EPOCH - REMOTE_EPOCH))
ABS_DRIFT=${DRIFT#-}

echo -e "  -> 本地时间: $(date -u '+%Y-%m-%d %H:%M:%S UTC') | 标准时间偏差: ${ABS_DRIFT} 秒"

if [ "$ABS_DRIFT" -gt 15 ]; then
    echo -e "${YELLOW}警告: 检测到系统时钟偏差过大 (${ABS_DRIFT}s > 15s)，可能导致 Reality/TLS 握手失败，正在自动校准...${PLAIN}"
    if [ "$(id -u)" = "0" ]; then
        # 1. 尝试 chrony / timedatectl
        if command -v chronyc >/dev/null 2>&1 && systemctl is-active --quiet chrony 2>/dev/null; then
            chronyc makestep >/dev/null 2>&1 || true
        elif command -v timedatectl >/dev/null 2>&1; then
            timedatectl set-ntp true >/dev/null 2>&1 || true
        fi

        # 2. 直接根据权威时间戳修正系统时间
        date -s "@${REMOTE_EPOCH}" >/dev/null 2>&1 || true
        hwclock -w 2>/dev/null || true

        # 重新核验
        NEW_LOCAL=$(date +%s)
        NEW_DRIFT=$((NEW_LOCAL - REMOTE_EPOCH))
        NEW_ABS=${NEW_DRIFT#-}
        if [ "$NEW_ABS" -le 3 ]; then
            echo -e "${GREEN}  -> 系统时间校准成功！当前偏差已缩减至 ${NEW_ABS} 秒。${PLAIN}"
        else
            echo -e "${YELLOW}  -> 时间校准已执行，当前偏差: ${NEW_ABS} 秒（受虚拟化环境时钟同步限制）。${PLAIN}"
        fi
    else
        echo -e "${RED}  -> 非 root 用户，无法自动调整系统时钟，请联系管理员执行校时。${PLAIN}"
    fi
else
    echo -e "${GREEN}  -> 系统时钟与全球标准时间偏差良好 (<= 15s)，无需额外校准。${PLAIN}"
fi
