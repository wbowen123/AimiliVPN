#!/usr/bin/env bash
# ==============================================================================
# AimiliVPN 域名 SSL 证书全生命周期管理系统 (ACME / Let's Encrypt / ZeroSSL / DNS-01)
# 支持 HTTP-01 零停机申请、Cloudflare DNS API 免80端口泛域名、多CA切换、强制续期与自动同步
# ==============================================================================
set -euo pipefail

HOME="${HOME:-/root}"
ROOT_DIR="/opt/aimilivpn"
DATA_DIR="${VPNGATE_DATA_DIR:-$ROOT_DIR/vpngate_data}"
TLS_DIR="/etc/aimilivpn/tls"
CERT_FILE="$TLS_DIR/fullchain.pem"
KEY_FILE="$TLS_DIR/privkey.pem"
SB_CERT="/etc/sing-box/cert.pem"
SB_KEY="/etc/sing-box/key.pem"
PROXY_ENV_FILE="/etc/default/aimilivpn"
ACME_ROOT="/var/www/aimilivpn-acme"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
PLAIN='\033[0m'

if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}错误: 必须以 root 权限运行此脚本。${PLAIN}" >&2
    exit 1
fi

mkdir -p "$TLS_DIR" "/etc/sing-box" "$ACME_ROOT/.well-known/acme-challenge"

get_public_ip() {
    curl -4fsS --connect-timeout 4 --max-time 6 https://api.ipify.org 2>/dev/null || \
    curl -4fsS --connect-timeout 4 --max-time 6 https://ifconfig.me 2>/dev/null || \
    echo "127.0.0.1"
}

get_public_ipv6() {
    curl -6fsS --connect-timeout 4 --max-time 6 https://api64.ipify.org 2>/dev/null || \
    curl -6fsS --connect-timeout 4 --max-time 6 https://ifconfig.co 2>/dev/null || \
    echo ""
}

get_bound_domain() {
    local d=""
    if [ -f "$PROXY_ENV_FILE" ]; then
        d=$(grep '^AIMILIVPN_DOMAIN=' "$PROXY_ENV_FILE" | cut -d'=' -f2 | tr -d '"'"' " || true)
    fi
    if [ -z "$d" ] && [ -f "$CERT_FILE" ] && command -v openssl >/dev/null 2>&1; then
        d=$(openssl x509 -in "$CERT_FILE" -noout -ext subjectAltName 2>/dev/null | grep -o 'DNS:[^ ,]*' | head -1 | cut -d: -f2 || true)
    fi
    echo "$d" | tr -d '[:space:]'
}

ensure_acme_sh() {
    if [ -x "$HOME/.acme.sh/acme.sh" ]; then
        return 0
    fi
    echo -e "${YELLOW}  -> 正在初始化安装官方 ACME 证书签发引擎 (acme.sh)...${PLAIN}"
    local email="cert-aimili-$(head -c 4 /dev/urandom | xxd -p 2>/dev/null || date +%s)@gmail.com"
    curl -fsSL https://get.acme.sh | sh -s email="$email" >/dev/null 2>&1 || true
    if [ -x "$HOME/.acme.sh/acme.sh" ]; then
        "$HOME/.acme.sh/acme.sh" --upgrade --auto-upgrade >/dev/null 2>&1 || true
        echo -e "${GREEN}  -> ACME 引擎初始化成功！${PLAIN}"
    else
        echo -e "${YELLOW}  -> 正在使用系统备选 Certbot 模块...${PLAIN}"
    fi
}

view_cert_details() {
    echo -e "\n${BOLD}${BLUE}==========================================================${PLAIN}"
    echo -e "${BOLD}${BLUE}              📜 当前系统 TLS/SSL 证书详情${PLAIN}"
    echo -e "${BOLD}${BLUE}==========================================================${PLAIN}"

    if [ ! -s "$CERT_FILE" ]; then
        echo -e "${RED}当前系统未检测到有效证书文件 (${CERT_FILE})。${PLAIN}"
        return
    fi

    local subj issuer not_before not_after sans
    subj=$(openssl x509 -in "$CERT_FILE" -noout -subject 2>/dev/null | sed 's/^subject=//')
    issuer=$(openssl x509 -in "$CERT_FILE" -noout -issuer 2>/dev/null | sed 's/^issuer=//')
    not_before=$(openssl x509 -in "$CERT_FILE" -noout -startdate 2>/dev/null | cut -d= -f2)
    not_after=$(openssl x509 -in "$CERT_FILE" -noout -enddate 2>/dev/null | cut -d= -f2)
    sans=$(openssl x509 -in "$CERT_FILE" -noout -ext subjectAltName 2>/dev/null | grep -v '^X509v3' | tr -d '[:space:]' || echo "无")

    local end_epoch now_epoch left_days
    end_epoch=$(date -d "$not_after" +%s 2>/dev/null || python3 -c "import email.utils, sys; print(int(email.utils.parsedate_to_datetime(sys.argv[1]).timestamp()))" "$not_after" 2>/dev/null || echo 0)
    now_epoch=$(date +%s)
    left_days=$(( (end_epoch - now_epoch) / 86400 ))

    local cert_type="自签名证书 (IP 默认)"
    if [ "$subj" != "$issuer" ]; then
        if echo "$issuer" | grep -qi "Let's Encrypt"; then
            cert_type="Let's Encrypt 官方权威证书"
        elif echo "$issuer" | grep -qi "ZeroSSL"; then
            cert_type="ZeroSSL 官方权威证书"
        elif echo "$issuer" | grep -qi "Buypass"; then
            cert_type="Buypass 权威证书"
        else
            cert_type="第三方 CA 机构颁发正式证书"
        fi
    fi

    echo -e "  * 证书类型:       ${GREEN}${cert_type}${PLAIN}"
    echo -e "  * 证书主题 (CN):  ${BLUE}${subj}${PLAIN}"
    echo -e "  * 颁发机构 (CA):  ${BLUE}${issuer}${PLAIN}"
    echo -e "  * 绑定域名 (SAN): ${YELLOW}${sans}${PLAIN}"
    echo -e "  * 生效时间:       ${not_before}"
    echo -e "  * 到期时间:       ${not_after}"

    if [ "$left_days" -lt 0 ]; then
        echo -e "  * 状态:           ${RED}已过期 ($(( -left_days )) 天前过期)${PLAIN}"
    elif [ "$left_days" -lt 15 ]; then
        echo -e "  * 状态:           ${YELLOW}即将过期 (剩余 ${left_days} 天，建议立即续期)${PLAIN}"
    else
        echo -e "  * 状态:           ${GREEN}正常有效 (剩余 ${left_days} 天)${PLAIN}"
    fi

    echo -e "${BOLD}${BLUE}==========================================================${PLAIN}\n"
}

apply_new_cert_http() {
    local target_domain="${1:-}"
    local target_ca="${2:-}"
    ensure_acme_sh
    local pub_ip
    pub_ip=$(get_public_ip)
    local pub_ipv6
    pub_ipv6=$(get_public_ipv6)
    local cur_domain
    cur_domain=$(get_bound_domain)

    if [ -z "$target_domain" ]; then
        echo -e "\n${BOLD}${BLUE}【申请正式域名 SSL 证书 - HTTP-01 验证模式】${PLAIN}"
        echo -e "说明：此模式将在本机 80 端口验证域名所有权，支持 Let's Encrypt / ZeroSSL。"
        echo -e "要求：必须提前将域名 A / AAAA 记录解析到本 VPS 公网 IP (${GREEN}${pub_ip}${PLAIN})！"
        echo "----------------------------------------------------------"

        read -r -p "请输入您要绑定的完整域名 (例如: vpn.example.com) [${cur_domain}]: " input_domain
        target_domain="${input_domain:-$cur_domain}"
    fi
    local domain
    domain=$(echo "$target_domain" | tr -d '[:space:]')
    if [ -z "$domain" ]; then
        echo -e "${RED}域名不能为空！${PLAIN}"
        return 1
    fi

    echo -e "${YELLOW}  -> 正在检测域名 ${domain} 的双栈 DNS 解析 (IPv4 / IPv6)...${PLAIN}"
    local dns_res
    dns_res=$(python3 -c "
import socket, sys
domain = sys.argv[1]
v4, v6 = [], []
try:
    for item in socket.getaddrinfo(domain, None):
        ip = item[4][0]
        if ':' in ip and ip not in v6:
            v6.append(ip)
        elif '.' in ip and ip not in v4:
            v4.append(ip)
except Exception:
    pass
print(';'.join(v4) + '|' + ';'.join(v6))
" "$domain" 2>/dev/null || echo "|")

    local resolved_v4="${dns_res%%|*}"
    local resolved_v6="${dns_res##*|}"

    local is_cf_cdn=0
    # 检查是否为 Cloudflare CDN IP 段 (开启了小黄云代理)
    if [[ "$resolved_v4" =~ (104\.(1[6-9]|2[0-7])\.|172\.(6[4-9]|7[0-1])\.|162\.159\.|198\.41\.) ]] || [[ "$resolved_v6" =~ 2606:4700: ]]; then
        is_cf_cdn=1
    fi

    if [ -n "$resolved_v4" ]; then
        if [ "$resolved_v4" = "$pub_ip" ]; then
            echo -e "${GREEN}  -> [IPv4 A 记录] 解析正常: ${domain} -> ${resolved_v4} (与本机 IPv4 匹配)${PLAIN}"
        else
            echo -e "${YELLOW}  -> [IPv4 A 记录] 解析为: ${resolved_v4} (本机公网 IPv4: ${pub_ip})${PLAIN}"
        fi
    else
        echo -e "${YELLOW}  -> [IPv4 A 记录] 未检测到 IPv4 解析${PLAIN}"
    fi

    if [ -n "$resolved_v6" ]; then
        if [ -n "$pub_ipv6" ] && [[ "$resolved_v6" == *"$pub_ipv6"* ]]; then
            echo -e "${GREEN}  -> [IPv6 AAAA 记录] 解析正常: ${domain} -> ${resolved_v6} (与本机 IPv6 匹配)${PLAIN}"
        else
            echo -e "${YELLOW}  -> [IPv6 AAAA 记录] 解析为: ${resolved_v6} (本机公网 IPv6: ${pub_ipv6:-未探测到})${PLAIN}"
        fi
    else
        echo -e "${YELLOW}  -> [IPv6 AAAA 记录] 未检测到 IPv6 解析${PLAIN}"
    fi

    if [ "$is_cf_cdn" = "1" ]; then
        echo ""
        echo -e "${RED}======================================================================${PLAIN}"
        echo -e "${BOLD}${RED}⚠️【严重告警: 检测到当前域名已开启 Cloudflare CDN 代理 (小黄云)！】${PLAIN}"
        echo -e "${RED}======================================================================${PLAIN}"
        echo -e "  * 当前公网解析已被 Cloudflare 边缘节点接管 (Anycast CDN IP)。"
        echo -e "  * 官方 HTTP-01 验证必须由 Let's Encrypt 直接连接您 VPS 本机的 80 端口。"
        echo -e "    若开启了小黄云，验证请求将被 Cloudflare 拦截，将导致申请失败！"
        echo -e "  * ${BOLD}${GREEN}解决方案建议:${PLAIN}"
        echo -e "    ① ${BOLD}${YELLOW}[方案 A - 强烈推荐]${PLAIN} 改用 ${BOLD}ml cert${PLAIN} 菜单中的 ${CYAN}[2] Cloudflare DNS-01 API 验证${PLAIN}；"
        echo -e "       (无论是否开小黄云、无论 80 端口是否被封，直接通过 API 秒级签发泛域名证书！)"
        echo -e "    ② ${BOLD}${YELLOW}[方案 B - 临时关云]${PLAIN} 登录 Cloudflare 将该域名的代理状态临时切为 ${BOLD}仅 DNS (灰云)${PLAIN}，"
        echo -e "       待本脚本签发成功后，再切回开启小黄云。"
        echo -e "${RED}======================================================================${PLAIN}"
        echo ""
        if [ -t 0 ] && [ -z "${1:-}" ]; then
            read -r -p "是否仍要尝试继续强制签发？[y/N]: " force_cf_go
            if [[ ! "$force_cf_go" =~ ^[yY]$ ]]; then
                echo "已取消。建议改用 Cloudflare DNS API 模式签发。"
                return 1
            fi
        fi
    fi

    local ca_choice="${target_ca:-1}"
    if [ -z "$target_ca" ] && [ -t 0 ]; then
        echo -e "\n请选择证书颁发机构 (CA):"
        echo -e "  ${GREEN}[1]${PLAIN} Let's Encrypt (推荐，开箱即用无阻碍)"
        echo -e "  ${GREEN}[2]${PLAIN} ZeroSSL"
        echo -e "  ${GREEN}[3]${PLAIN} Buypass (180天较长有效期)"
        read -r -p "请选择 CA [1-3, 默认 1]: " ca_choice
    fi
    local ca_server="letsencrypt"
    case "$ca_choice" in
        2) ca_server="zerossl" ;;
        3) ca_server="buypass" ;;
        *) ca_server="letsencrypt" ;;
    esac

    # 防火墙临时放行 80 端口用于验证 (IPv4 + IPv6 双栈)
    if command -v iptables >/dev/null 2>&1; then
        iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
    fi
    if command -v ip6tables >/dev/null 2>&1; then
        ip6tables -I INPUT 1 -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
    fi
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw allow 80/tcp >/dev/null 2>&1 || true
    fi
    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        firewall-cmd --add-port=80/tcp >/dev/null 2>&1 || true
    fi

    local acme_bin="$HOME/.acme.sh/acme.sh"
    local issue_success=0

    if [ -x "$acme_bin" ]; then
        echo -e "${YELLOW}  -> 正在使用 acme.sh 签发 ${domain} 证书 (CA: ${ca_server})...${PLAIN}"
        "$acme_bin" --set-default-ca --server "$ca_server" >/dev/null 2>&1 || true

        # 确保 ACME 注册邮箱符合公共顶级域名 (TLD) 规范，杜绝 Let's Encrypt invalidContact (400) 拒绝
        local reg_email="cert-admin-$(head -c 4 /dev/urandom | xxd -p 2>/dev/null || date +%s)@gmail.com"
        if [ -f "$HOME/.acme.sh/account.conf" ]; then
            sed -i "s|admin@aimilivpn.local|${reg_email}|g" "$HOME/.acme.sh/account.conf" 2>/dev/null || true
            sed -i "s|\.local'|@gmail.com'|g" "$HOME/.acme.sh/account.conf" 2>/dev/null || true
        fi
        "$acme_bin" --register-account -m "$reg_email" --server "$ca_server" >/dev/null 2>&1 || true
        "$acme_bin" --update-account --accountemail "$reg_email" >/dev/null 2>&1 || true

        # 优先使用 Nginx Webroot 模式（零停机）
        if systemctl is-active --quiet nginx 2>/dev/null; then
            if "$acme_bin" --issue -d "$domain" --webroot "$ACME_ROOT" --keylength ec-256; then
                issue_success=1
            fi
        fi

        # 若 Webroot 失败则尝试 Standalone 独立模式
        if [ "$issue_success" != "1" ]; then
            echo -e "${YELLOW}  -> Webroot 模式受阻，尝试 Standalone 独立端口签发...${PLAIN}"
            systemctl stop nginx 2>/dev/null || true
            if "$acme_bin" --issue -d "$domain" --standalone --keylength ec-256; then
                issue_success=1
            fi
            systemctl start nginx 2>/dev/null || true
        fi

        if [ "$issue_success" = "1" ]; then
            echo -e "${GREEN}  -> 证书签发成功！正在安装部署证书...${PLAIN}"
            "$acme_bin" --install-cert -d "$domain" --ecc \
                --key-file "$KEY_FILE" \
                --fullchain-file "$CERT_FILE" \
                --reloadcmd "systemctl reload nginx 2>/dev/null || systemctl restart nginx 2>/dev/null || true"
        fi
    fi

    # 兜底：使用 Certbot
    if [ "$issue_success" != "1" ] && command -v certbot >/dev/null 2>&1; then
        echo -e "${YELLOW}  -> 正在切换使用 certbot 签发...${PLAIN}"
        if certbot certonly --webroot -w "$ACME_ROOT" -d "$domain" --non-interactive --agree-tos --register-unsafely-without-email --keep-until-expiring 2>/dev/null; then
            local le_dir="/etc/letsencrypt/live/${domain}"
            if [ -s "$le_dir/fullchain.pem" ]; then
                cp -f "$le_dir/fullchain.pem" "$CERT_FILE"
                cp -f "$le_dir/privkey.pem" "$KEY_FILE"
                issue_success=1
            fi
        fi
    fi

    if [ "$issue_success" != "1" ]; then
        echo -e "${RED}错误: 证书签发失败！${PLAIN}"
        echo -e "常见原因：80 端口被云厂商拦截未开放、域名未解析到本机、或触发了 CA 频次限额。"
        return 1
    fi

    # 成功后统一同步分发与配置更新
    sync_cert_and_reload "$domain"
}

apply_new_cert_dns() {
    ensure_acme_sh
    local acme_bin="$HOME/.acme.sh/acme.sh"
    if [ ! -x "$acme_bin" ]; then
        echo -e "${RED}错误: 未检测到 acme.sh 引擎。${PLAIN}"
        return 1
    fi

    echo -e "\n${BOLD}${BLUE}【通过 Cloudflare DNS-01 API 申请证书 (免 80 端口 / 支持泛域名)】${PLAIN}"
    echo -e "说明：此模式利用 Cloudflare API 自动添加 TXT 记录验证，${GREEN}完全不需要开放 80 端口${PLAIN}，"
    echo -e "      适合 80 端口被封锁的 VPS，并支持申请 ${YELLOW}*.yourdomain.com${PLAIN} 通配符泛域名！"
    echo "----------------------------------------------------------"

    local cf_domain="${1:-}"
    if [ -z "$cf_domain" ]; then
        read -r -p "请输入要申请的域名 (支持单个域名或泛域名 *.example.com): " cf_domain
        cf_domain=$(echo "$cf_domain" | tr -d '[:space:]')
    fi
    if [ -z "$cf_domain" ]; then
        echo -e "${RED}域名不能为空！${PLAIN}"
        return 1
    fi

    if [ -z "${CF_Token:-}" ] && [ -z "${CF_Key:-}" ]; then
        echo -e "请选择 Cloudflare 认证方式:"
        echo -e "  ${GREEN}[1]${PLAIN} Cloudflare API Token (推荐，权限受限更安全)"
        echo -e "  ${GREEN}[2]${PLAIN} Cloudflare Global API Key + 邮箱"
        read -r -p "请选择 [1-2, 默认 1]: " cf_auth_mode

        if [ "$cf_auth_mode" = "2" ]; then
            read -r -p "请输入 Cloudflare 账号邮箱: " CF_Email
            read -r -s -p "请输入 Cloudflare Global API Key: " CF_Key
            echo
            export CF_Email="$CF_Email"
            export CF_Key="$CF_Key"
        else
            read -r -s -p "请输入 Cloudflare API Token (具备 Zone:DNS:Edit 权限): " CF_Token
            echo
            export CF_Token="$CF_Token"
        fi
    fi

    local reg_email="cert-admin-$(head -c 4 /dev/urandom | xxd -p 2>/dev/null || date +%s)@gmail.com"
    if [ -f "$HOME/.acme.sh/account.conf" ]; then
        sed -i "s|admin@aimilivpn.local|${reg_email}|g" "$HOME/.acme.sh/account.conf" 2>/dev/null || true
        sed -i "s|\.local'|@gmail.com'|g" "$HOME/.acme.sh/account.conf" 2>/dev/null || true
    fi
    "$acme_bin" --register-account -m "$reg_email" >/dev/null 2>&1 || true
    "$acme_bin" --update-account --accountemail "$reg_email" >/dev/null 2>&1 || true

    echo -e "${YELLOW}  -> 正在通过 Cloudflare DNS API 自动化签发证书...${PLAIN}"
    if "$acme_bin" --issue --dns dns_cf -d "$cf_domain" --keylength ec-256; then
        echo -e "${GREEN}  -> 泛域名/DNS 证书签发成功！${PLAIN}"
        "$acme_bin" --install-cert -d "$cf_domain" --ecc \
            --key-file "$KEY_FILE" \
            --fullchain-file "$CERT_FILE" \
            --reloadcmd "systemctl reload nginx 2>/dev/null || systemctl restart nginx 2>/dev/null || true"
        
        local clean_d="${cf_domain#\*.}"
        sync_cert_and_reload "$clean_d"
    else
        echo -e "${RED}错误: DNS 证书签发失败，请检查 API Token 权限与域名是否托管在 Cloudflare！${PLAIN}"
        return 1
    fi
}

force_renew_cert() {
    ensure_acme_sh
    local acme_bin="$HOME/.acme.sh/acme.sh"
    local domain
    domain=$(get_bound_domain)
    if [ -z "$domain" ]; then
        echo -e "${YELLOW}当前未绑定正式域名，无需续期（自签名证书有效期 10 年）。${PLAIN}"
        return 0
    fi

    echo -e "${YELLOW}  -> 正在对域名 ${domain} 执行强制重新签发/续期...${PLAIN}"
    if [ -x "$acme_bin" ]; then
        if "$acme_bin" --renew -d "$domain" --ecc --force; then
            echo -e "${GREEN}  -> ACME 证书续期成功！${PLAIN}"
            sync_cert_and_reload "$domain"
            return 0
        fi
    fi

    if command -v certbot >/dev/null 2>&1; then
        if certbot renew --force-renewal; then
            echo -e "${GREEN}  -> Certbot 证书续期成功！${PLAIN}"
            local le_live="/etc/letsencrypt/live/${domain}"
            [ ! -d "$le_live" ] && le_live="/etc/letsencrypt/live/aimilivpn-ip"
            if [ -d "$le_live" ] && [ -f "$le_live/fullchain.pem" ]; then
                cp -f "$le_live/fullchain.pem" "$CERT_FILE"
                cp -f "$le_live/privkey.pem" "$KEY_FILE"
                chmod 644 "$CERT_FILE"
                chmod 600 "$KEY_FILE"
            fi
            sync_cert_and_reload "$domain"
            return 0
        fi
    fi

    echo -e "${RED}续期失败，请检查 80 端口连通性。${PLAIN}"
    return 1
}

reset_ip_self_signed() {
    local pub_ip
    pub_ip=$(get_public_ip)
    echo -e "${YELLOW}  -> 正在生成纯 IP ECC P-256 高安全自签名证书 (IP: ${pub_ip})...${PLAIN}"
    openssl ecparam -name prime256v1 -genkey -noout -out "$KEY_FILE"
    openssl req -new -x509 -days 3650 -key "$KEY_FILE" -out "$CERT_FILE" \
        -subj "/CN=${pub_ip}" \
        -addext "subjectAltName=IP:${pub_ip},DNS:${pub_ip}.nip.io" 2>/dev/null || \
    openssl req -new -x509 -days 3650 -key "$KEY_FILE" -out "$CERT_FILE" -subj "/CN=${pub_ip}" 2>/dev/null
    chmod 600 "$KEY_FILE"
    chmod 644 "$CERT_FILE"

    # 清除域名记录
    sed -i '/^AIMILIVPN_DOMAIN=/d' "$PROXY_ENV_FILE" 2>/dev/null || true

    sync_cert_and_reload ""
    echo -e "${GREEN}  -> 已成功重置为纯 IP 自签名证书环境！${PLAIN}"
}

sync_cert_and_reload() {
    local domain="$1"
    # 1. 复制给 Sing-box
    cp -f "$CERT_FILE" "$SB_CERT"
    cp -f "$KEY_FILE" "$SB_KEY"
    chmod 644 "$CERT_FILE" "$SB_CERT"
    chmod 600 "$KEY_FILE" "$SB_KEY"

    # 2. 写入全局环境
    if [ -n "$domain" ]; then
        if grep -q '^AIMILIVPN_DOMAIN=' "$PROXY_ENV_FILE" 2>/dev/null; then
            sed -i "s/^AIMILIVPN_DOMAIN=.*/AIMILIVPN_DOMAIN=\"${domain}\"/" "$PROXY_ENV_FILE"
        else
            echo "AIMILIVPN_DOMAIN=\"${domain}\"" >> "$PROXY_ENV_FILE"
        fi
    fi

    # 3. 更新 Nginx 配置 server_name
    local ng_conf="/etc/nginx/conf.d/aimilivpn-production.conf"
    [ ! -f "$ng_conf" ] && ng_conf="/etc/nginx/http.d/aimilivpn-production.conf"
    if [ -f "$ng_conf" ]; then
        python3 -c "
import sys, re
p = sys.argv[1]
dom = sys.argv[2]
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()
repl = lambda m: m.group(1) + dom + ';'
c = re.sub(r'(listen\s+(?:\[::\]:)?8443\s+ssl;[^{]*?server_name\s+)[^;]+;', repl, c)
with open(p, 'w', encoding='utf-8') as f:
    f.write(c)
" "$ng_conf" "${domain:-_}" 2>/dev/null || true
    fi

    # 4. 热重载 Web 与代理服务
    if command -v nginx >/dev/null 2>&1; then
        nginx -t >/dev/null 2>&1 && (systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1 || true)
    fi
    if systemctl is-active --quiet sing-box 2>/dev/null; then
        systemctl restart sing-box || true
    fi

    # 5. 触发刷新节点与订阅
    if [ -f "$ROOT_DIR/scripts/setup_singbox.sh" ]; then
        echo -e "${YELLOW}  -> 正在同步更新全协议订阅与 10 大节点矩阵...${PLAIN}"
        bash "$ROOT_DIR/scripts/setup_singbox.sh" >/dev/null 2>&1 || true
    fi

    echo -e "${GREEN}==========================================================${PLAIN}"
    echo -e "${GREEN}  🎉 证书与订阅配置同步完成！${PLAIN}"
    if [ -n "$domain" ]; then
        echo -e "  * 绑定域名:       ${BLUE}https://${domain}:8443/${PLAIN}"
        echo -e "  * HTTPS 订阅入口: ${BLUE}https://${domain}:18443/sub.txt${PLAIN}"
    fi
    echo -e "${GREEN}==========================================================${PLAIN}"
}

interactive_cert_menu() {
    while true; do
        view_cert_details
        echo -e "${BOLD}【SSL/TLS 证书管理菜单】${PLAIN}"
        echo -e "  ${GREEN}[1]${PLAIN} 申请新域名可信 SSL 证书 (HTTP-01 验证模式，推荐)"
        echo -e "  ${GREEN}[2]${PLAIN} 通过 Cloudflare DNS API 申请证书 (免 80 端口 / 支持泛域名)"
        echo -e "  ${GREEN}[3]${PLAIN} 强制立即续期现有证书 (Force Renew)"
        echo -e "  ${GREEN}[4]${PLAIN} 重置/生成纯 IP ECC 自签名证书 (适用于无域名)"
        echo -e "  ${GREEN}[5]${PLAIN} 查看当前证书详细信息"
        echo -e "  ${RED}[0]${PLAIN} 返回上级控制台"
        echo -e "=========================================================="

        read -r -p "请选择操作 [0-5]: " choice
        case "$choice" in
            1) apply_new_cert_http ;;
            2) apply_new_cert_dns ;;
            3) force_renew_cert ;;
            4) reset_ip_self_signed ;;
            5) view_cert_details ;;
            0|q|quit|exit) break ;;
            *) echo -e "${RED}无效选项。${PLAIN}" ;;
        esac
        read -r -p "按回车键继续..."
    done
}

if [ $# -gt 0 ]; then
    case "$1" in
        view|status|info) view_cert_details ;;
        renew) force_renew_cert ;;
        reset) reset_ip_self_signed ;;
        dns) apply_new_cert_dns "${2:-}" ;;
        http) apply_new_cert_http "${2:-}" "${3:-1}" ;;
        *) apply_new_cert_http "${1:-}" "${2:-1}" ;;
    esac
else
    interactive_cert_menu
fi
