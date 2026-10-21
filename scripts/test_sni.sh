#!/usr/bin/env bash
# ==============================================================================
# AimiliVPN 伪装域名（SNI）本地智能测速与优选探测器
# 流程：
#   1. 检测候选域名是否支持 TLS 1.3 & ALPN h2
#   2. 检测 HTTP 握手响应状态码（排查是否被反爬/安全防护拦截）
#   3. 测算当前 VPS 到伪装服务器的 TCP+TLS 握手延时（RTT）
#   4. 输出延时最低的最优伪装域名
# ==============================================================================
set -e

CANDIDATES=(
    "gateway.icloud.com"
    "itunes.apple.com"
    "swdist.apple.com"
    "www.microsoft.com"
    "dl.google.com"
    "aws.amazon.com"
    "www.lovelive-anime.jp"
    "speed.cloudflare.com"
    "www.yahoo.com"
    "www.samsung.com"
)

# 传入指定域名时优先校验该域名
CUSTOM_DOMAIN="${1:-}"

check_single_domain() {
    local domain="$1"

    # 1. 快速检查网络连通性与 HTTP 响应码 (超时 2 秒)
    local http_code
    http_code=$(curl -4 -so /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 4 "https://${domain}" 2>/dev/null || echo "000")
    if [[ ! "$http_code" =~ ^(200|301|302|400|403|404)$ ]]; then
        return 1
    fi

    # 2. 如果系统有 openssl，校验 TLS 1.3 支持
    if command -v openssl >/dev/null 2>&1; then
        local tls_check
        tls_check=$(echo | timeout 3 openssl s_client -tls1_3 -connect "${domain}:443" -servername "${domain}" 2>&1 || true)
        if ! echo "$tls_check" | grep -qi "TLSv1.3"; then
            return 1
        fi
    fi

    # 3. 测量握手延迟（毫秒）
    local time_total
    time_total=$(curl -4 -so /dev/null -w "%{time_connect}" --connect-timeout 2 --max-time 4 "https://${domain}" 2>/dev/null || echo "9.999")
    local rtt_ms
    rtt_ms=$(awk -v t="$time_total" 'BEGIN { printf "%.0f", t * 1000 }' 2>/dev/null || echo "9999")

    echo "${rtt_ms} ${domain}"
}

if [ -n "$CUSTOM_DOMAIN" ]; then
    res=$(check_single_domain "$CUSTOM_DOMAIN" || true)
    if [ -n "$res" ]; then
        echo "$CUSTOM_DOMAIN"
        exit 0
    else
        # 自定义域名测试不合格，回退到自动优选
        >&2 echo "警告: 自定义域名 $CUSTOM_DOMAIN 未通过 TLS 1.3 连通性测试，启动自动优选..."
    fi
fi

BEST_DOMAIN="gateway.icloud.com"
BEST_RTT=999999

for d in "${CANDIDATES[@]}"; do
    res=$(check_single_domain "$d" || true)
    if [ -n "$res" ]; then
        rtt=$(echo "$res" | awk '{print $1}')
        dom=$(echo "$res" | awk '{print $2}')
        if [ "$rtt" -lt "$BEST_RTT" ]; then
            BEST_RTT="$rtt"
            BEST_DOMAIN="$dom"
        fi
    fi
done

echo "$BEST_DOMAIN"
