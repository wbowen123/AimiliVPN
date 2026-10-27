#!/usr/bin/env bash
set -e

if [ ! -t 0 ] && [ -z "${AIMILI_YES:-}" ] && [ -z "${1:-}" ] && [ -c /dev/tty ]; then
    exec < /dev/tty 2>/dev/null || true
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
BOLD='\033[1m'
# 系统防火墙（甲骨文镜像自带 iptables INPUT REJECT、ufw、firewalld）放行 AimiliVPN 自己的对外端口：
# 8443（管理后台）、80（Let's Encrypt HTTP-01）、443（Reality TCP & Hy2 UDP）、8444（AnyTLS TCP）、8445/8446（VMess TCP）、18443（订阅服务）。
# UDP 端口：443（Hysteria 2）、8443（TUIC v5）、40000:50000（端口跳跃）。8500/8501 只听 127.0.0.1，不放行。
AIMILI_FW_PORTS="${AIMILI_FW_PORTS:-8443 80 443 8444 8445 8446 18443}"
AIMILI_FW_UDP_PORTS="${AIMILI_FW_UDP_PORTS:-443 8443 40000:50000}"
AIMILI_FW_ADDED="${AIMILI_FW_ADDED:-/etc/aimilivpn-fw.added}"
aimili_fw_persist() {
    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save >/dev/null 2>&1 && return 0
    fi
    if [ -f /etc/iptables/rules.v4 ]; then iptables-save > /etc/iptables/rules.v4 2>/dev/null || true; fi
    if [ -f /etc/iptables/rules.v6 ] && command -v ip6tables-save >/dev/null 2>&1; then ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true; fi
}
aimili_fw_open() {
    local p ipt changed=0 opened=""
    for ipt in iptables ip6tables; do
        command -v "$ipt" >/dev/null 2>&1 || continue
        "$ipt" -S INPUT 2>/dev/null | grep -qE '^-P INPUT (DROP|REJECT)|-j (REJECT|DROP)' || continue
        for p in $AIMILI_FW_PORTS; do
            "$ipt" -C INPUT -p tcp --dport "$p" -m comment --comment aimilivpn -j ACCEPT >/dev/null 2>&1 && continue
            "$ipt" -I INPUT 1 -p tcp --dport "$p" -m comment --comment aimilivpn -j ACCEPT >/dev/null 2>&1 && changed=1 && opened="$opened $ipt:$p(tcp)"
        done
        for p in $AIMILI_FW_UDP_PORTS; do
            "$ipt" -C INPUT -p udp --dport "$p" -m comment --comment aimilivpn -j ACCEPT >/dev/null 2>&1 && continue
            "$ipt" -I INPUT 1 -p udp --dport "$p" -m comment --comment aimilivpn -j ACCEPT >/dev/null 2>&1 && changed=1 && opened="$opened $ipt:$p(udp)"
        done
    done
    [ "$changed" = "1" ] && aimili_fw_persist
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        for p in $AIMILI_FW_PORTS; do
            ufw status 2>/dev/null | grep -qE "^${p}(/tcp)?[[:space:]].*ALLOW" && continue
            ufw allow "${p}/tcp" comment aimilivpn >/dev/null 2>&1 && echo "ufw ${p}/tcp" >> "$AIMILI_FW_ADDED" && opened="$opened ufw:$p(tcp)"
        done
        for p in $AIMILI_FW_UDP_PORTS; do
            ufw status 2>/dev/null | grep -qE "^${p}(/udp)?[[:space:]].*ALLOW" && continue
            ufw allow "${p}/udp" comment aimilivpn >/dev/null 2>&1 && echo "ufw ${p}/udp" >> "$AIMILI_FW_ADDED" && opened="$opened ufw:$p(udp)"
        done
    fi
    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        for p in $AIMILI_FW_PORTS; do
            firewall-cmd --query-port="${p}/tcp" >/dev/null 2>&1 && continue
            firewall-cmd --permanent --add-port="${p}/tcp" >/dev/null 2>&1 && firewall-cmd --add-port="${p}/tcp" >/dev/null 2>&1 \
                && echo "firewalld ${p}/tcp" >> "$AIMILI_FW_ADDED" && opened="$opened firewalld:$p(tcp)"
        done
        for p in $AIMILI_FW_UDP_PORTS; do
            p_fw="${p/:/-}"
            firewall-cmd --query-port="${p_fw}/udp" >/dev/null 2>&1 && continue
            firewall-cmd --permanent --add-port="${p_fw}/udp" >/dev/null 2>&1 && firewall-cmd --add-port="${p_fw}/udp" >/dev/null 2>&1 \
                && echo "firewalld ${p_fw}/udp" >> "$AIMILI_FW_ADDED" && opened="$opened firewalld:$p_fw(udp)"
        done
    fi
    [ -n "$opened" ] && echo -e "${YELLOW:-}  -> 系统防火墙原本拦截入站，已放行 AimiliVPN 端口（${opened# }），已持久化；卸载时会删掉。${PLAIN:-}"
    return 0
}
# apt-get update 遇到坏的第三方源（缺 GPG 公钥 NO_PUBKEY、404 没有 Release 文件、未签名）不中断安装：
# 识别报错的源，备份后临时注释/停用，再重试一次，并提示用户。系统官方源（ubuntu/debian）不动。
aimili_apt_update() {
    local out rc=0 urls u f changed=0 disabled="" ad="${AIMILI_APT_DIR:-/etc/apt}"
    out=$(LC_ALL=C apt-get update -q 2>&1) || rc=$?
    printf '%s\n' "$out" | tail -n 40
    urls=$(printf '%s\n' "$out" | grep -E "NO_PUBKEY|EXPKEYSIG|is not signed|does not have a Release file|404 +Not Found|Release' no longer has a Release" \
        | grep -oE "https?://[^ ']+" | sed -E 's#/(dists/.*|InRelease|Release)$##; s#/+$##' | sort -u)
    [ -z "$urls" ] && return $rc
    for u in $urls; do
        case "$u" in
            *://archive.ubuntu.com*|*://*.archive.ubuntu.com*|*://security.ubuntu.com*|*://ports.ubuntu.com*|*://deb.debian.org*|*://security.debian.org*|*://*.ec2.archive.ubuntu.com*) continue ;;
        esac
        for f in "$ad/sources.list" "$ad"/sources.list.d/*.list "$ad"/sources.list.d/*.sources; do
            [ -f "$f" ] && grep -qF "$u" "$f" || continue
            case "$f" in
                *.sources)
                    mv -f "$f" "$f.aimili-disabled" && changed=1 && disabled="$disabled $f" ;;
                *)
                    [ -e "$f.aimili-bak" ] || cp -a "$f" "$f.aimili-bak"
                    awk -v u="$u" 'index($0,u) && $0 ~ /^[[:space:]]*deb(-src)?[[:space:]]/ {print "# [AimiliVPN 临时停用，apt update 报错] " $0; next} {print}' "$f" >"$f.tmp" && mv -f "$f.tmp" "$f" \
                        && changed=1 && disabled="$disabled $f($u)" ;;
            esac
        done
    done
    if [ "$changed" = "1" ]; then
        echo -e "${YELLOW:-}  -> 以下第三方软件源 apt update 报错（缺公钥/404/未签名），已临时停用后重试：${PLAIN:-}"
        for f in $disabled; do echo -e "${YELLOW:-}     $f${PLAIN:-}"; done
        echo -e "${YELLOW:-}     原文件已备份为 *.aimili-bak（.sources 文件改名为 *.aimili-disabled）；修好公钥/地址后可自行恢复。${PLAIN:-}"
        LC_ALL=C apt-get update -q 2>&1 | tail -n 20; rc=${PIPESTATUS[0]}
    fi
    return $rc
}
PLAIN='\033[0m'

if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}错误: 必须以 root 权限运行此脚本。请使用: sudo bash $0${PLAIN}"
    exit 1
fi

OS_TYPE=""
PKG_MGR=""
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_TYPE=$ID
fi

case "$OS_TYPE" in
    ubuntu|debian)
        PKG_MGR="apt-get"
        export DEBIAN_FRONTEND=noninteractive
        ;;
    alpine)
        PKG_MGR="apk"
        ;;
    centos|rhel|rocky|almalinux|fedora|ol|amzn)
        if command -v dnf >/dev/null 2>&1; then
            PKG_MGR="dnf"
        else
            PKG_MGR="yum"
        fi
        ;;
    *)
        echo -e "${RED}错误: 不支持的操作系统 ($OS_TYPE)！目前仅支持 Ubuntu/Debian/Alpine/CentOS/RHEL/Rocky/AlmaLinux/Fedora/OracleLinux/AmazonLinux。${PLAIN}"
        exit 1
        ;;
esac

echo -e "${BLUE}==========================================================${PLAIN}"
echo -e "${BLUE}        欢迎使用 AimiliVPN 一键部署与管理脚本${PLAIN}"
echo -e "${BLUE}==========================================================${PLAIN}"

AIMILI_ACTION="${AIMILI_ACTION:-}"
case "${1:-}" in
    install|uninstall) AIMILI_ACTION="$1"; shift ;;
esac

aimili_mem_kb() { echo "${AIMILI_MEM_KB:-$(awk '/MemTotal:/ {print $2}' /proc/meminfo)}"; }
aimili_swap_kb() {
    if [ -n "${AIMILI_SWAP_KB:-}" ]; then echo "${AIMILI_SWAP_KB}"; return; fi
    awk '/SwapTotal:/ {print $2}' /proc/meminfo
}
aimili_swap_target_mb() {
    local mem_kb=$1
    if [ "${mem_kb}" -le 2097152 ]; then echo 1024
    elif [ "${mem_kb}" -le 4194304 ]; then echo 512
    else echo 0; fi
}
aimili_swap_plan_mb() {  # 需要新加多少 MB；0 表示不加
    local target have
    target=$(aimili_swap_target_mb "$(aimili_mem_kb)")
    have=$(( $(aimili_swap_kb) / 1024 ))
    local need=$(( target - have ))
    if [ "${need}" -lt 256 ]; then echo 0; else echo "${need}"; fi
}

aimili_port_owner() {  # 端口 -> 进程名（没人占则空）
    ss -ltnpH 2>/dev/null | awk -v p=":$1" '$4 ~ p"$" {print $NF; exit}' | sed -n 's/.*(("\([^"]*\)".*/\1/p'
}
jiuheyi_installed() {
    [ -f /etc/v2ray-agent/xray/xray ] || [ -f /etc/v2ray-agent/sing-box/sing-box ]
}
aimili_env_report() {
    local mem_kb swap_kb cores
    mem_kb=$(aimili_mem_kb); swap_kb=$(aimili_swap_kb); cores=$(nproc 2>/dev/null || echo 1)
    echo -e "${BLUE}---------------- 环境检测 ----------------${PLAIN}"
    echo -e "  系统:       ${PRETTY_NAME:-$OS_TYPE}"
    echo -e "  CPU 核数:   ${cores}"
    echo -e "  内存:       $((mem_kb / 1024)) MB"
    echo -e "  交换分区:   $((swap_kb / 1024)) MB（按规则目标 $(aimili_swap_target_mb "${mem_kb}") MB，将新增 $(aimili_swap_plan_mb) MB）"
    if jiuheyi_installed; then
        local cores_in=""
        [ -f /etc/v2ray-agent/xray/xray ] && cores_in="xray"
        [ -f /etc/v2ray-agent/sing-box/sing-box ] && cores_in="${cores_in:+${cores_in} + }sing-box"
        echo -e "  九合一:     已安装（${cores_in}）"
    else
        echo -e "  九合一:     未安装"
    fi
    AIMILI_PORT_CONFLICT=""
    local p owner
    for p in 8443 8500 8501 443; do
        owner=$(aimili_port_owner "$p")
        if [ -z "${owner}" ]; then
            echo -e "  端口 ${p}:   空闲"
        else
            case "${p}:${owner}" in
                8443:nginx|8500:python3|8501:python3) echo -e "  端口 ${p}:   ${owner}（AimiliVPN 自己）" ;;
                443:*) echo -e "  端口 ${p}:    ${owner}（九合一节点端口，AimiliVPN 不用 443）" ;;
                *) echo -e "  端口 ${p}:   ${RED}被 ${owner} 占用${PLAIN}"; AIMILI_PORT_CONFLICT="${AIMILI_PORT_CONFLICT} ${p}(${owner})" ;;
            esac
        fi
    done
    echo -e "${BLUE}------------------------------------------${PLAIN}"
}

aimili_jiuheyi_back_to_direct() {
    local changed=0 f tmp
    if [ -f /etc/v2ray-agent/install.sh ] && grep -q 'JIUHEYI_SET_EGRESS' /etc/v2ray-agent/install.sh 2>/dev/null; then
        if JIUHEYI_SET_EGRESS=direct bash /etc/v2ray-agent/install.sh < /dev/null >/dev/null 2>&1; then
            echo -e "${GREEN}  -> 九合一出站已从 8500 改回直连。${PLAIN}"
        fi
    fi
    rm -f /etc/v2ray-agent/xray/conf/zz_socks5_outbound.json /etc/v2ray-agent/xray/conf/zz_egress.json 2>/dev/null && changed=1
    if [ -f /etc/v2ray-agent/xray/conf/00_dns.json ] && grep -q socks5_outbound /etc/v2ray-agent/xray/conf/00_dns.json; then
        printf '{\n  "dns": {\n    "servers": ["1.1.1.1", "8.8.8.8"]\n  }\n}\n' > /etc/v2ray-agent/xray/conf/00_dns.json
        changed=1
    fi
    local sb=/etc/v2ray-agent/sing-box/conf/config
    if [ -d "${sb}" ]; then
        [ -f "${sb}/socks5_outbound.json" ] && rm -f "${sb}/socks5_outbound.json" && changed=1
        for f in "${sb}"/*.json; do
            [ -f "$f" ] || continue
            if grep -q 'socks5_outbound' "$f" 2>/dev/null; then
                tmp=$(mktemp)
                if jq 'if .route then .route |= ((if .final == "socks5_outbound" then del(.final) else . end) | (if .rules then .rules |= map(select(.outbound != "socks5_outbound")) else . end)) else . end' "$f" > "${tmp}" 2>/dev/null; then
                    cat "${tmp}" > "$f"; changed=1
                fi
                rm -f "${tmp}"
            fi
        done
        printf 'direct\n' > /etc/v2ray-agent/jiuheyi_dns_mode 2>/dev/null || true
        if [ "${changed}" = "1" ] && [ -x /etc/v2ray-agent/sing-box/sing-box ]; then
            /etc/v2ray-agent/sing-box/sing-box merge /etc/v2ray-agent/sing-box/conf/config.json -C "${sb}/" -D /etc/v2ray-agent/sing-box/conf >/dev/null 2>&1 || true
            systemctl restart sing-box >/dev/null 2>&1 || true
        fi
    fi
    local xc=/etc/v2ray-agent/xray/conf
    if [ -d "${xc}" ]; then
        for f in "${xc}"/*.json; do
            [ -f "$f" ] || continue
            if grep -q 'socks5_outbound' "$f" 2>/dev/null; then
                tmp=$(mktemp)
                if jq '(if .outbounds then .outbounds |= map(select(.tag != "socks5_outbound")) else . end) | (if .routing.rules then .routing.rules |= map(select(.outboundTag != "socks5_outbound")) else . end)' "$f" > "${tmp}" 2>/dev/null; then
                    if jq -e '(.outbounds // [1]) | length > 0' "${tmp}" >/dev/null 2>&1; then cat "${tmp}" > "$f"; else rm -f "$f"; fi
                    changed=1
                fi
                rm -f "${tmp}"
            fi
        done
        [ "${changed}" = "1" ] && systemctl restart xray >/dev/null 2>&1 || true
    fi
    [ "${changed}" = "1" ] && echo -e "${GREEN}  -> 九合一出站已从 8500 改回直连。${PLAIN}"
    return 0
}

# 删掉安装时为 AimiliVPN 加的防火墙放行（iptables 按注释 aimilivpn；ufw/firewalld 只删记录过的；
# 九合一还在时 80 端口留给九合一，不删）
aimili_fw_close() {
    local ipt r changed=0 kind port added="${AIMILI_FW_ADDED:-/etc/aimilivpn-fw.added}"
    for ipt in iptables ip6tables; do
        command -v "$ipt" >/dev/null 2>&1 || continue
        while r=$("$ipt" -S INPUT 2>/dev/null | grep -m1 -- '--comment aimilivpn'); [ -n "$r" ]; do
            eval "$ipt ${r/-A INPUT/-D INPUT}" >/dev/null 2>&1 || break
            changed=1
        done
    done
    if [ "$changed" = "1" ]; then
        if command -v netfilter-persistent >/dev/null 2>&1; then netfilter-persistent save >/dev/null 2>&1 || true
        else
            [ -f /etc/iptables/rules.v4 ] && iptables-save > /etc/iptables/rules.v4 2>/dev/null
            [ -f /etc/iptables/rules.v6 ] && command -v ip6tables-save >/dev/null 2>&1 && ip6tables-save > /etc/iptables/rules.v6 2>/dev/null
        fi
    fi
    if [ -f "$added" ]; then
        while read -r kind port; do
            [ "${port%/tcp}" = "80" ] && [ -d /etc/v2ray-agent ] && continue
            case "$kind" in
                ufw) command -v ufw >/dev/null 2>&1 && ufw delete allow "$port" >/dev/null 2>&1 ;;
                firewalld) command -v firewall-cmd >/dev/null 2>&1 && { firewall-cmd --permanent --remove-port="$port" >/dev/null 2>&1; firewall-cmd --remove-port="$port" >/dev/null 2>&1; } ;;
            esac
        done < "$added"
        rm -f "$added"
    fi
    return 0
}
aimili_uninstall() {
    echo -e "${YELLOW}正在完全卸载 AimiliVPN...${PLAIN}"
    set +e
    local u self_pids p
    # 只杀 AimiliVPN 进程，排除本卸载脚本自身及其父进程（ml 调用 /opt/aimilivpn/install.sh 时命令行同样含 /opt/aimilivpn/）。
    self_pids=" $$ ${PPID} ${BASHPID:-} "
    aimili_kill_pattern() {
        for p in $(pgrep -f "$1" 2>/dev/null); do
            case "${self_pids}" in *" ${p} "*) continue ;; esac
            kill "${p}" >/dev/null 2>&1
        done
    }
    for u in aimilivpn aimilivpn-github-update.timer aimilivpn-github-update sing-box cloudflared-argo aimilivpn-tgbot; do
        systemctl stop "$u" >/dev/null 2>&1
        systemctl disable "$u" >/dev/null 2>&1
    done
    rc-service aimilivpn stop >/dev/null 2>&1
    rc-update del aimilivpn >/dev/null 2>&1
    aimili_kill_pattern '/opt/aimilivpn/.*\.py'
    aimili_kill_pattern 'openvpn --config /opt/aimilivpn'
    aimili_kill_pattern 'sstpc .*--save-server-route'
    aimili_kill_pattern 'dhclient .*vpn_'
    local ns
    for ns in $(ip netns list 2>/dev/null | awk '{print $1}' | grep -E '^(prod|aimili|alh|probe)'); do
        ip netns pids "${ns}" 2>/dev/null | xargs -r kill >/dev/null 2>&1
        ip netns del "${ns}" >/dev/null 2>&1
    done
    if command -v vpncmd >/dev/null 2>&1; then
        for a in $(vpncmd localhost /CLIENT /CMD AccountList 2>/dev/null | sed -n 's/^VPN Connection Setting Name *|\(.*\)$/\1/p' | tr -d ' '); do
            vpncmd localhost /CLIENT /CMD AccountDisconnect "$a" >/dev/null 2>&1
            vpncmd localhost /CLIENT /CMD AccountDelete "$a" >/dev/null 2>&1
        done
        for n in $(vpncmd localhost /CLIENT /CMD NicList 2>/dev/null | sed -n 's/^Virtual Network Adapter Name *|\(.*\)$/\1/p' | tr -d ' '); do
            vpncmd localhost /CLIENT /CMD NicDelete "$n" >/dev/null 2>&1
        done
    fi
    for dev in $(ls /sys/class/net 2>/dev/null | grep -E '^(tun0|tun-sw-|tun-sb|tun-hot|vpn_|alh)'); do
        ip link del "${dev}" >/dev/null 2>&1
    done
    while ip rule del fwmark 0x64 lookup 100 >/dev/null 2>&1; do :; done
    for t in 100 $(seq 200 220) $(seq 12100 12163); do ip route flush table "$t" >/dev/null 2>&1; done
    ip rule show 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="lookup"){t=$(i+1)+0; if(t==100||(t>=12100&&t<=12163)||(t>=200&&t<=220&&$0~/ oif /)){sub(":","",$1); print $1}}}' | while read -r pref; do ip rule del pref "${pref}" >/dev/null 2>&1; done
    for chain in OUTPUT FORWARD INPUT; do
        iptables -t mangle -S "${chain}" 2>/dev/null | grep -E 'TCPMSS|0x64' | grep -E '\-o (tun|ppp|vpn_|alh)|\-i (tun|ppp|vpn_|alh)|0x64' | sed 's/^-A /-D /' | while read -r rule; do eval iptables -t mangle ${rule} >/dev/null 2>&1; done
    done
    iptables -t nat -S POSTROUTING 2>/dev/null | grep -E '10\.254\.' | sed 's/^-A /-D /' | while read -r rule; do eval iptables -t nat ${rule} >/dev/null 2>&1; done
    # AimiliVPN 与九合一证书各自独立，卸载 AimiliVPN 不动九合一的证书、nginx 配置和 acme 续期任务，只把九合一经 8500 的出站改回直连。
    local nginx_changed=0 nginx_ok=1
    rm -f /lib/systemd/system/aimilivpn.service /etc/systemd/system/aimilivpn.service \
        /etc/systemd/system/aimilivpn-github-update.service /etc/systemd/system/aimilivpn-github-update.timer \
        /etc/init.d/aimilivpn /usr/bin/ml /usr/local/sbin/aimilivpn-github-update /etc/default/aimilivpn \
        /etc/sysctl.d/99-aimilivpn.conf /etc/sysctl.d/99-aimilivpn-bbr.conf
    # 停掉并禁用 AimiliVPN 装的 SoftEther/strongSwan/xl2tpd 系统服务（占 UDP 500/4500/1701、TCP 9931），清理 SoftEther 客户端配置。
    # 只处理 AimiliVPN 装的：安装时记录在 /var/lib/aimilivpn/vpn-deps.list；旧版本没有记录时，按 apt 历史里 AimiliVPN 的安装命令判断。
    local vpn_pkgs="" vp vsvc
    if [ -s /var/lib/aimilivpn/vpn-deps.list ]; then
        vpn_pkgs=$(cat /var/lib/aimilivpn/vpn-deps.list)
    elif zgrep -hs "^Commandline: apt-get install -y softether-vpnclient softether-vpncmd strongswan strongswan-starter xl2tpd" /var/log/apt/history.log* >/dev/null 2>&1; then
        vpn_pkgs="softether-vpnclient strongswan-starter xl2tpd"
    fi
    AIMILI_VPN_SVCS=""
    for vp in ${vpn_pkgs}; do
        case "${vp}" in
            softether-vpnclient) vsvc="softether-vpnclient" ;;
            strongswan-starter) vsvc="strongswan-starter strongswan ipsec" ;;
            xl2tpd) vsvc="xl2tpd" ;;
            *) continue ;;
        esac
        for u in ${vsvc}; do
            systemctl stop "$u" >/dev/null 2>&1
            systemctl disable "$u" >/dev/null 2>&1
        done
        case "${vp}" in
            softether-vpnclient) pkill -x vpnclient >/dev/null 2>&1; rm -rf /usr/libexec/softether/vpnclient/vpn_client.config /usr/libexec/softether/vpnclient/backup.vpn_client.config /usr/libexec/softether/vpnclient/client_log ;;
            strongswan-starter) pkill -x charon >/dev/null 2>&1; pkill -x starter >/dev/null 2>&1 ;;
            xl2tpd) pkill -x xl2tpd >/dev/null 2>&1 ;;
        esac
        AIMILI_VPN_SVCS="${AIMILI_VPN_SVCS} ${vp}"
    done
    # AimiliVPN 自己的 acme 与维护任务删掉；证书缓存 /var/lib/aimilivpn-acme 保留，重装直接装、不重签
    rm -f /etc/cron.d/aimilivpn-acme /etc/cron.d/aimilivpn-maintenance /var/log/aimilivpn-maintenance.log /var/log/cloudflared-argo.log /var/log/sing-box.log /var/log/aimilivpn.log /run/lock/aimilivpn-cert.lock
    rm -rf /etc/systemd/system/aimilivpn.service.d /etc/systemd/system/cloudflared-argo.service /etc/systemd/system/aimilivpn-tgbot.service \
        /opt/aimilivpn /etc/aimilivpn /var/lib/aimilivpn /var/www/aimilivpn-acme /var/www/aimilivpn-sub /var/www/camouflage \
        /etc/sing-box /etc/systemd/system/sing-box.service /usr/local/bin/sing-box /tmp/aimilivpn*
    while iptables -t nat -D PREROUTING -p udp --dport 40000:50000 -j REDIRECT --to-ports 443 2>/dev/null; do :; done
    while ip6tables -t nat -D PREROUTING -p udp --dport 40000:50000 -j REDIRECT --to-ports 443 2>/dev/null; do :; done
    if command -v netfilter-persistent >/dev/null 2>&1; then netfilter-persistent save >/dev/null 2>&1 || true; fi
    if command -v nft >/dev/null 2>&1; then nft delete table ip aimilivpn 2>/dev/null || true; fi
    systemctl daemon-reload >/dev/null 2>&1
    # 只删 AimiliVPN 自己的 nginx 站点（8443 管理入口 + ACME webroot），九合一的 nginx 配置不动。
    for f in /etc/nginx/conf.d/aimilivpn-production.conf /etc/nginx/conf.d/aimilivpn-acme.conf; do
        [ -e "$f" ] && rm -f "$f" && nginx_changed=1
    done
    if [ "${nginx_changed}" = "1" ] && command -v nginx >/dev/null 2>&1; then
        if nginx -t >/dev/null 2>&1; then
            if jiuheyi_installed; then
                systemctl reload nginx >/dev/null 2>&1 || nginx -s reload >/dev/null 2>&1 || nginx_ok=0
            else
                systemctl restart nginx >/dev/null 2>&1 || nginx -s reload >/dev/null 2>&1 || nginx_ok=0
            fi
        else
            nginx_ok=0
        fi
        # reload 是异步的：等旧监听（8443）真正释放再校验，最多 15 秒
        local w
        for w in $(seq 1 15); do
            ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq '(^|:)8443$' || break
            sleep 1
        done
    fi
    if [ -f /var/lib/aimilivpn-swapfile ]; then
        local sf; sf=$(cat /var/lib/aimilivpn-swapfile)
        if [ -n "${sf}" ] && [ -f "${sf}" ]; then
            swapoff "${sf}" >/dev/null 2>&1
            rm -f "${sf}"
            sed -i "\#^${sf} #d" /etc/fstab 2>/dev/null
        fi
        rm -f /var/lib/aimilivpn-swapfile /etc/sysctl.d/99-aimili-swap.conf
    fi
    if jiuheyi_installed; then
        aimili_jiuheyi_back_to_direct
    fi
    aimili_fw_close || true
    # 校验并打印清理清单，失败项标红。
    local fail=0
    aimili_chk() { # $1=名称 $2=0成功
        if [ "$2" = "0" ]; then echo -e "  ${GREEN}[已清理]${PLAIN} $1"; else echo -e "  ${RED}[失败]  $1${PLAIN}"; fail=1; fi
    }
    echo -e "${BLUE}---------------- 卸载清单 ----------------${PLAIN}"
    local r
    r=0; { systemctl is-active --quiet aimilivpn 2>/dev/null || [ -e /lib/systemd/system/aimilivpn.service ] || [ -e /etc/systemd/system/aimilivpn.service ] || [ -e /etc/init.d/aimilivpn ]; } && r=1
    aimili_chk "服务 aimilivpn（已停止并删除）" "$r"
    r=0; [ -e /etc/systemd/system/aimilivpn-github-update.timer ] && r=1; aimili_chk "自动更新定时器" "$r"
    r=0; [ -e /opt/aimilivpn ] && r=1; aimili_chk "程序目录 /opt/aimilivpn" "$r"
    r=0; [ -e /etc/aimilivpn ] && r=1; aimili_chk "证书与配置目录 /etc/aimilivpn" "$r"
    r=0; [ -e /var/lib/aimilivpn ] && r=1; aimili_chk "运行状态目录 /var/lib/aimilivpn" "$r"
    r=0; [ -e /etc/sing-box ] && r=1; aimili_chk "Sing-box 核心配置目录 /etc/sing-box" "$r"
    r=0; { [ -e /etc/nginx/conf.d/aimilivpn-production.conf ] || [ -e /etc/nginx/conf.d/aimilivpn-acme.conf ] || [ "${nginx_ok}" != "1" ]; } && r=1
    aimili_chk "nginx 站点 8443 管理入口/ACME（已删除并 reload，九合一配置未动）" "$r"
    r=0; ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq '(^|:)8443$' && r=1; aimili_chk "8443 端口已释放" "$r"
    r=0; [ -e /usr/bin/ml ] && r=1; aimili_chk "ml 命令 /usr/bin/ml" "$r"
    r=0; { iptables -S INPUT 2>/dev/null; ip6tables -S INPUT 2>/dev/null; } | grep -q -- '--comment aimilivpn' && r=1; aimili_chk "防火墙里为 AimiliVPN 放行的端口规则" "$r"
    r=0; { iptables -t nat -S PREROUTING 2>/dev/null; ip6tables -t nat -S PREROUTING 2>/dev/null; } | grep -q '40000:50000' && r=1; aimili_chk "Hysteria 2 端口跳跃转发规则" "$r"
    r=0; [ -e /etc/cron.d/aimilivpn-acme ] && r=1; aimili_chk "AimiliVPN 证书续期任务" "$r"
    r=0; [ -e /var/lib/aimilivpn-swapfile ] && r=1; aimili_chk "AimiliVPN 交换文件" "$r"
    r=0; ls /sys/class/net 2>/dev/null | grep -Eq '^(tun0|tun-sw-|tun-sb|tun-hot|vpn_|alh)' && r=1; aimili_chk "VPN 网卡/路由规则" "$r"
    if [ -n "${AIMILI_VPN_SVCS:-}" ]; then
        sleep 1
        r=0
        for vp in ${AIMILI_VPN_SVCS}; do case "$vp" in softether-vpnclient) pgrep -x vpnclient >/dev/null && r=1 ;; strongswan-starter) pgrep -x charon >/dev/null && r=1 ;; xl2tpd) pgrep -x xl2tpd >/dev/null && r=1 ;; esac; done
        ss -lnuH 2>/dev/null | awk '{print $4}' | grep -Eq '(^|:)(500|4500|1701)$' && pgrep -x 'charon|xl2tpd' >/dev/null && r=1
        aimili_chk "SoftEther/strongSwan/xl2tpd 服务已停止并禁用（${AIMILI_VPN_SVCS# }；UDP 500/4500/1701、TCP 9931 已释放）" "$r"
    fi
    if jiuheyi_installed; then
        r=0; grep -rqs --include='*.json' '127.0.0.1.\{0,8\}8500\|"server_port": *8500\|"port": *8500' /etc/v2ray-agent/xray/conf /etc/v2ray-agent/sing-box/conf 2>/dev/null && r=1
        aimili_chk "九合一出站已改回直连（九合一证书、nginx、续期任务未动）" "$r"
    fi
    if [ -d /var/lib/aimilivpn-acme ] && ls /var/lib/aimilivpn-acme/*/fullchain.cer >/dev/null 2>&1; then
        echo -e "  ${YELLOW}[保留]${PLAIN}  域名证书缓存 /var/lib/aimilivpn-acme（重装时直接使用，不重新申请，省 Let's Encrypt 额度；不需要可手动删除）"
    fi
    echo -e "${BLUE}------------------------------------------${PLAIN}"
    if [ "${fail}" = "0" ]; then
        echo -e "${GREEN}AimiliVPN 卸载完成，以上项目均已清理。${PLAIN}"
        return 0
    fi
    echo -e "${RED}AimiliVPN 卸载未完全成功，请检查上面标红的项目。${PLAIN}"
    return 1
}

INSTALL_SINGBOX="y"
INSTALL_RESI="y"
INSTALL_WARP="auto"
INSTALL_SUB="y"
INSTALL_CAMO="y"
INSTALL_BBR="y"
SINGBOX_CAMOUFLAGE="${SINGBOX_CAMOUFLAGE:-}"
INSTALL_JIUHEYI="n"

if [ -n "${1:-}" ]; then
    case "$1" in
        uninstall|remove|8) AIMILI_ACTION="uninstall" ;;
        1) AIMILI_ACTION="install"; INSTALL_SINGBOX=y; INSTALL_RESI=y; INSTALL_WARP=auto; INSTALL_SUB=y; INSTALL_CAMO=y; INSTALL_BBR=y ;;
        2) AIMILI_ACTION="install"; INSTALL_SINGBOX=y; INSTALL_RESI=n; INSTALL_WARP=n; INSTALL_SUB=y; INSTALL_CAMO=y; INSTALL_BBR=y ;;
        3) AIMILI_ACTION="install"; INSTALL_SINGBOX=n; INSTALL_RESI=y; INSTALL_WARP=n; INSTALL_SUB=n; INSTALL_CAMO=n; INSTALL_BBR=y ;;
        4) AIMILI_ACTION="install"; INSTALL_SINGBOX=y; INSTALL_RESI=n; INSTALL_WARP=auto; INSTALL_SUB=y; INSTALL_CAMO=y; INSTALL_BBR=y ;;
        5) AIMILI_ACTION="install"; INSTALL_SINGBOX=y; INSTALL_RESI=y; INSTALL_WARP=n; INSTALL_SUB=y; INSTALL_CAMO=y; INSTALL_BBR=y ;;
        6) AIMILI_ACTION="install"; INSTALL_SINGBOX=n; INSTALL_RESI=n; INSTALL_WARP=n; INSTALL_SUB=y; INSTALL_CAMO=y; INSTALL_BBR=n ;;
        install) AIMILI_ACTION="install" ;;
    esac
fi

if [ -z "${AIMILI_ACTION}" ] && [ "${AIMILI_FROM_JIUHEYI:-}" != "1" ] && [ -t 0 ]; then
    echo -e "${BLUE}======================================================================${PLAIN}"
    echo -e "${BOLD}${BLUE}       🛡️ AimiliVPN 模块化架构一键部署向导 - 请选择安装组合模式${PLAIN}"
    echo -e "${BLUE}======================================================================${PLAIN}"
    echo -e "  ${BOLD}${GREEN}[1] 🌟【全套旗舰尊享版】(默认推荐)${PLAIN}"
    echo -e "      ${BOLD}包含:${PLAIN} 极速原生直连五协议 + Aimili动态住宅家宽 + 自适应WARP + 伪装站 + 全格式聚合订阅"
    echo -e "      ${BOLD}说明:${PLAIN} 部署全部功能。原生直连跑满千兆；家宽自动轮转全球无污染 IP；自适应预测速"
    echo -e "            判定流媒体解锁（全解免装WARP，缺啥补啥）；生成 18 节点双栈全格式聚合订阅。"
    echo -e "      ${BOLD}适用:${PLAIN} 需要兼顾千兆低延迟极速、流媒体与AI完美解锁、跨境抗封锁的全能用户。"
    echo ""
    echo -e "  ${BOLD}${GREEN}[2] 🚀【仅单独安装 极速原生直连代理矩阵】(轻量极速)${PLAIN}"
    echo -e "      ${BOLD}包含:${PLAIN} VLESS-Reality / Hysteria 2 / TUIC v5 / AnyTLS / VMess-xHTTP"
    echo -e "      ${BOLD}说明:${PLAIN} 仅部署 Sing-box 5 大抗审查协议，直接走本机公网千兆出口，不运行 Aimili 家宽后台，"
    echo -e "            内存占用 < 50MB，CPU 零空载，适合搬瓦工/甲骨文等低配 VPS，看 4K 极度丝滑。"
    echo ""
    echo -e "  ${BOLD}${GREEN}[3] 🏠【仅单独安装 Aimili 动态住宅家宽网桥】(独立家宽落地)${PLAIN}"
    echo -e "      ${BOLD}包含:${PLAIN} SOCKS5 127.0.0.1:8500 虚拟隧道池 + 8443 HTTPS 可视化管理控制台"
    echo -e "      ${BOLD}说明:${PLAIN} 仅安装 AimiliVPN 核心守护进程，不安装对外节点协议。启动本地 8500 住宅网桥，"
    echo -e "            可供本机现有程序或第三方自建代理（如 Xray/九合一）调用作为住宅出口落地。"
    echo ""
    echo -e "  ${BOLD}${GREEN}[4] ⚡【组合安装: 原生直连 + 自适应 WARP 流媒体解锁】(不含住宅家宽)${PLAIN}"
    echo -e "      ${BOLD}包含:${PLAIN} Sing-box 原生五协议 + Cloudflare WARP 用户态自适应智能解锁引擎"
    echo -e "      ${BOLD}说明:${PLAIN} 先自动测试原生 IP4/IP6 对 ChatGPT/Netflix 解锁，全解免装 WARP，部分受阻精准接管；"
    echo -e "            不启动 Aimili 家宽后台，兼顾超低资源开销与 100% 主流流媒体/AI 原生解锁。"
    echo ""
    echo -e "  ${BOLD}${GREEN}[5] 🌐【组合安装: 原生直连 + Aimili 动态住宅家宽】(不含 WARP)${PLAIN}"
    echo -e "      ${BOLD}包含:${PLAIN} Sing-box 原生五协议 + Aimili 动态住宅网桥 (纯物理直连 + 纯净家宽出站)"
    echo -e "      ${BOLD}说明:${PLAIN} 直连走机房 IP，住宅走真实家宽，无需 Cloudflare 介入，保证原生与住宅 IP 纯洁度。"
    echo ""
    echo -e "  ${BOLD}${GREEN}[6] 📦【仅单独安装 全生态聚合订阅分发系统与 Web 管理后台】(订阅中心)${PLAIN}"
    echo -e "      ${BOLD}包含:${PLAIN} Nginx 18443 订阅分发中心 (sub.txt / clash.yaml / singbox.json) + 8443 面板"
    echo -e "      ${BOLD}说明:${PLAIN} 仅部署多客户端订阅转换托管服务与 HTTPS 控制台，便于集中托管与分发现有节点。"
    echo ""
    echo -e "  ${BOLD}${GREEN}[7] 🛠️【自定义模块高级自由勾选】(交互式按需挑选各个子组件)${PLAIN}"
    echo -e "      ${BOLD}包含:${PLAIN} 自由选择: ①原生直连五协议 ②Aimili住宅家宽 ③自适应WARP ④伪装站 ⑤BBR优化 ⑥Hysteria2防护模式"
    echo -e "      ${BOLD}说明:${PLAIN} 满足极客深度定制需求，自由组合出站网络、流媒体解锁引擎与传输防嗅探策略。"
    echo -e "      ${BOLD}建议:${PLAIN} 适合对网络拓扑有特定需求或需要针对性调优的高级用户。"
    echo ""
    echo -e "  ${BOLD}${RED}[8] 🗑️【完全卸载 AimiliVPN 及所有关联组件】(深度清理)${PLAIN}"
    echo -e "      ${BOLD}包含:${PLAIN} 停止并清理全部关联 systemd 服务、内核网桥、iptables 端口跳跃规则、Nginx 管理站点与程序目录"
    echo -e "      ${BOLD}说明:${PLAIN} 彻底清理 AimiliVPN 的所有进程、配置、日志及端口映射，严格保留九合一与系统原有业务。"
    echo -e "      ${BOLD}建议:${PLAIN} 欲彻底重置网络或需要净空 VPS 环境时选择此项。"
    echo ""
    echo -e "  ${BOLD}[0] 🚪【退出安装程序】${PLAIN}"
    echo -e "      ${BOLD}说明:${PLAIN} 不执行任何安装或改动，安全退出当前向导脚本。"
    echo -e "${BLUE}======================================================================${PLAIN}"

    read -r -p "请选择安装模式 [0-8，回车默认为 1 全套旗舰版]: " _mode_choice
    case "${_mode_choice:-1}" in
        1)
            AIMILI_ACTION=install
            INSTALL_SINGBOX=y; INSTALL_RESI=y; INSTALL_WARP=auto; INSTALL_SUB=y; INSTALL_CAMO=y; INSTALL_BBR=y
            ;;
        2)
            AIMILI_ACTION=install
            INSTALL_SINGBOX=y; INSTALL_RESI=n; INSTALL_WARP=n; INSTALL_SUB=y; INSTALL_CAMO=y; INSTALL_BBR=y
            ;;
        3)
            AIMILI_ACTION=install
            INSTALL_SINGBOX=n; INSTALL_RESI=y; INSTALL_WARP=n; INSTALL_SUB=n; INSTALL_CAMO=n; INSTALL_BBR=y
            ;;
        4)
            AIMILI_ACTION=install
            INSTALL_SINGBOX=y; INSTALL_RESI=n; INSTALL_WARP=auto; INSTALL_SUB=y; INSTALL_CAMO=y; INSTALL_BBR=y
            ;;
        5)
            AIMILI_ACTION=install
            INSTALL_SINGBOX=y; INSTALL_RESI=y; INSTALL_WARP=n; INSTALL_SUB=y; INSTALL_CAMO=y; INSTALL_BBR=y
            ;;
        6)
            AIMILI_ACTION=install
            INSTALL_SINGBOX=n; INSTALL_RESI=n; INSTALL_WARP=n; INSTALL_SUB=y; INSTALL_CAMO=y; INSTALL_BBR=n
            ;;
        7)
            AIMILI_ACTION=install
            echo -e "\n${YELLOW}--- 进入自定义按需勾选向导 ---${PLAIN}"
            read -r -p "1. 是否安装 Sing-box 原生直连五协议矩阵？(Y/n): " _c_sb
            case "${_c_sb:-y}" in n|N) INSTALL_SINGBOX=n ;; *) INSTALL_SINGBOX=y ;; esac

            read -r -p "2. 是否安装 Aimili 动态住宅家宽网桥 (SOCKS5 8500)？(Y/n): " _c_resi
            case "${_c_resi:-y}" in n|N) INSTALL_RESI=n ;; *) INSTALL_RESI=y ;; esac

            read -r -p "3. 是否启用 Cloudflare WARP 自适应流媒体/AI 解锁？(Y/n): " _c_warp
            case "${_c_warp:-y}" in n|N) INSTALL_WARP=n ;; *) INSTALL_WARP=auto ;; esac

            read -r -p "4. 是否安装 Nginx 18443 全生态聚合订阅分发服务？(Y/n): " _c_sub
            case "${_c_sub:-y}" in n|N) INSTALL_SUB=n ;; *) INSTALL_SUB=y ;; esac

            read -r -p "5. 是否部署 HTML5 本地高保真伪装网站？(Y/n): " _c_camo
            case "${_c_camo:-y}" in n|N) INSTALL_CAMO=n ;; *) INSTALL_CAMO=y ;; esac

            read -r -p "6. 是否开启 Linux 原生 BBR 内核拥塞优化？(Y/n): " _c_bbr
            case "${_c_bbr:-y}" in n|N) INSTALL_BBR=n ;; *) INSTALL_BBR=y ;; esac

            echo -e "\n  ${BOLD}7. Hysteria 2 防护模式二选一:${PLAIN}"
            echo -e "     [1] 🌟 标准 HTTP/3 伪装站 (默认推荐: 伪装为真实网页, 抗嗅探, 全平台客户端无缝兼容)"
            echo -e "     [2] 🌪️ Salamander 强混淆 (适合晚高峰 QUIC 被运营商深度 QoS 掐断的恶劣网络, 伪装站自动关闭)"
            read -r -p "     请选择 Hysteria 2 防护模式 [1-2，回车默认为 1]: " _c_hy2_mode
            case "${_c_hy2_mode:-1}" in
                2) export HY2_OBFS_MODE="obfs"; export HY2_ENABLE_OBFS="1" ;;
                *) export HY2_OBFS_MODE="masquerade"; export HY2_ENABLE_OBFS="0" ;;
            esac
            ;;
        8)
            AIMILI_ACTION=uninstall
            ;;
        0)
            exit 0
            ;;
        *)
            AIMILI_ACTION=install
            INSTALL_SINGBOX=y; INSTALL_RESI=y; INSTALL_WARP=auto; INSTALL_SUB=y; INSTALL_CAMO=y; INSTALL_BBR=y
            ;;
    esac
fi
AIMILI_ACTION="${AIMILI_ACTION:-install}"
if [ "${AIMILI_ACTION}" = "uninstall" ]; then
    if [ -t 0 ] && [ "${AIMILI_YES:-}" != "1" ]; then
        read -r -p "确定完全卸载 AimiliVPN？会删除 /opt/aimilivpn、服务、证书和 8443 配置 (y/N): " _yn
        case "${_yn}" in y|Y) ;; *) echo "已取消。"; exit 0 ;; esac
    fi
    aimili_uninstall
    exit $?
fi

aimili_env_report
if [ -n "${AIMILI_PORT_CONFLICT}" ] && [ "${AIMILI_IGNORE_PORTS:-}" != "1" ]; then
    echo -e "${RED}端口被其它程序占用:${AIMILI_PORT_CONFLICT}。请先停掉它们，或设 AIMILI_IGNORE_PORTS=1 强行继续。${PLAIN}"
    exit 1
fi
if [ "${AIMILI_DETECT_ONLY:-}" = "1" ]; then
    exit 0
fi

if [ "${AIMILI_FROM_JIUHEYI:-}" != "1" ] && [ -d /opt/aimilivpn ] && [ "${AIMILI_ALLOW_EXISTING:-}" != "1" ]; then
    echo -e "${YELLOW}检测到 /opt/aimilivpn 已存在（之前的安装或卸载残留）。${PLAIN}"
    if [ -t 0 ]; then
        echo -e "  1. 先完全卸载，再全新安装（推荐）"
        echo -e "  2. 覆盖重装（保留现有数据）"
        echo -e "  0. 退出"
        read -r -p "请选择（回车或输入 1 为先卸载再装）: " _ex
        case "${_ex:-1}" in
            1) aimili_uninstall || { echo -e "${RED}卸载未完成，已停止安装。${PLAIN}"; exit 1; }; set -e ;;
            2) ;;
            *) exit 0 ;;
        esac
    else
        echo -e "${RED}非交互模式下已停止。覆盖重装请执行 AIMILI_ALLOW_EXISTING=1 bash install.sh；先卸载请执行 bash install.sh uninstall${PLAIN}"
        exit 1
    fi
fi

if [ "${AIMILI_FROM_JIUHEYI:-}" != "1" ] && [ -t 0 ]; then
    if [ "${INSTALL_SINGBOX}" = "y" ] || [ "${INSTALL_SUB}" = "y" ]; then
        if [ -z "${AIMILIVPN_DOMAIN+x}" ]; then
            echo -e "\n${BOLD}${BLUE}【SSL/TLS 域名绑定与双栈 DNS 物理隔离规范 (推荐最佳实践)】${PLAIN}"
            echo -e "  * ${GREEN}双栈物理隔离规范 (彻底解决开小黄云拖慢直连与家宽的问题)${PLAIN}:"
            echo -e "    ① direct.域名 -> 解析本机 IPv4/IPv6 [必须关闭小黄云/灰云] (专供直连与家宽跑满物理千兆)"
            echo -e "    ② cdn.域名    -> 解析本机 IPv4/IPv6 [必须开启小黄云/橙云] (专供 CDN/Argo 破墙救急与免流)"
            echo -e "  * ${YELLOW}若暂无域名${PLAIN}: 直接回车，系统将自动签发 10 年免维护 IP ECC 专属证书（后续可随时 ml cert 补绑）；"
            read -r -p "请输入您的域名 (例如 direct.example.com 或 example.com) [直接回车使用纯 IP 证书]: " AIMILIVPN_DOMAIN
        fi
        AIMILIVPN_DOMAIN=$(printf '%s' "${AIMILIVPN_DOMAIN:-}" | tr -d '[:space:]')

        if [ -n "${AIMILIVPN_DOMAIN}" ]; then
            echo -e "\n${BOLD}${BLUE}【域名证书签发与验证模式】${PLAIN}"
            echo -e "  * [1] 官方 HTTP-01 验证 (需要开放 80 端口，全自动申请与续签) [推荐，直接回车]"
            echo -e "  * [2] Cloudflare DNS-01 API 验证 (免 80 端口 / 适合 80 端口被封的 VPS / 支持泛域名)"
            read -r -p "请选择验证方式 [1-2，默认 1]: " CERT_VERIFY_MODE
            CERT_VERIFY_MODE="${CERT_VERIFY_MODE:-1}"
            if [ "${CERT_VERIFY_MODE}" = "2" ]; then
                read -r -s -p "请输入 Cloudflare API Token (需具备 Zone:DNS:Edit 权限): " CF_TOKEN_INPUT
                echo
                export CF_Token="${CF_TOKEN_INPUT}"
            fi
        fi
    fi
    if [ "${INSTALL_SINGBOX}" = "y" ]; then
        if [ -z "${SINGBOX_CAMOUFLAGE}" ]; then
            echo -e "\n${BOLD}${BLUE}【VLESS-Reality 极速直连伪装目标】${PLAIN}"
            read -r -p "请输入 Reality 伪装域名 [直接按回车由系统自动执行延迟优选]: " SINGBOX_CAMOUFLAGE
            SINGBOX_CAMOUFLAGE=$(printf '%s' "${SINGBOX_CAMOUFLAGE}" | tr -d '[:space:]' | tr -cd 'a-zA-Z0-9.-')
        fi
    fi

    if [ "${INSTALL_CAMO:-y}" = "y" ]; then
        echo -e "\n${BOLD}${BLUE}【HTML5 本地高保真伪装网站模板选择】${PLAIN}"
        echo -e "  * [1] 现代化科技云原生与 SaaS 平台官网 (推荐，极简科技风) [默认直接回车]"
        echo -e "  * [2] 全功能在线工具箱与极简计算器 (真实可交互、可算数)"
        echo -e "  * [3] 极简极客技术博客与工程随笔 (学术极客风格)"
        echo -e "  * [4] 经典 HTML5 2048 益智小游戏 (真实可玩)"
        read -r -p "请选择伪装模板 [1-4，默认 1]: " CAMO_TEMPLATE_CHOICE
        CAMO_TEMPLATE_CHOICE="${CAMO_TEMPLATE_CHOICE:-1}"
    fi

    if [ "${INSTALL_SINGBOX:-y}" = "y" ]; then
        echo -e "\n${BOLD}${BLUE}【Cloudflare CDN Anycast 三网优选 IP 测速】${PLAIN}"
        echo -e "  * 作用说明: 仅为走 CDN/Argo 破墙穿透的节点替换为三网最优延迟 IP，绝不影响 VPS 真实物理直连与家宽。"
        read -r -p "是否在部署时自动执行三网 Anycast 延迟测速并自选最优 IP？[Y/n，默认 Y]: " DO_CF_SPEEDTEST
        DO_CF_SPEEDTEST=$(echo "${DO_CF_SPEEDTEST:-y}" | tr '[:upper:]' '[:lower:]')
    fi

    if [ "${INSTALL_BBR:-y}" = "y" ]; then
        echo -e "\n${BOLD}${BLUE}【Linux 内核 BBR 拥塞控制与 TCP 缓冲区深度调优】${PLAIN}"
        echo -e "  * 作用说明: 开启 BBR + FQ 队列，调大 TCP 读写缓冲区，显著降低跨国长距离网络 4K 播放丢包卡顿。"
        read -r -p "是否立即应用内核网络性能调优？[Y/n，默认 Y]: " DO_TUNE_BBR
        DO_TUNE_BBR=$(echo "${DO_TUNE_BBR:-y}" | tr '[:upper:]' '[:lower:]')
    fi

    mem_mb=$(( $(aimili_mem_kb) / 1024 ))
    echo -e "\n${BOLD}${BLUE}【定时系统自愈、每日内存深度清理与 15分钟看门狗】${PLAIN}"
    echo -e "  * 作用说明: 每日 04:00 深度释放内核缓存内存 + HTTPS 时钟校准 + 证书自动续签，每 15 分钟守护进程自愈。"
    if [ "${mem_mb}" -le 1024 ]; then
        echo -e "  * 💡 ${YELLOW}系统检测: 当前 VPS 物理内存为 ${mem_mb}MB (<= 1GB)，强烈推荐开启以彻底预防 OOM 崩溃！${PLAIN}"
    fi
    read -r -p "是否立即激活该定时维护看门狗任务？[Y/n，默认 Y]: " DO_SETUP_CRON
    DO_SETUP_CRON=$(echo "${DO_SETUP_CRON:-y}" | tr '[:upper:]' '[:lower:]')
fi
# 域名校验放在问完问题之后、安装任何东西之前。格式须是完整域名（FQDN），且解析到本机公网 IPv4/IPv6。
# 不通过就红字「域名无效或无法解析」并退出（此时还没装任何东西，无需回滚）。
aimili_public_ips() {
    local u
    for u in https://api.ipify.org https://ipv4.icanhazip.com https://ifconfig.me/ip; do
        if command -v curl >/dev/null 2>&1; then curl -4 -fsS --max-time 6 "$u" 2>/dev/null && echo && break
        elif command -v wget >/dev/null 2>&1; then wget -4 -qO- -T 6 "$u" 2>/dev/null && echo && break; fi
    done
    for u in https://api64.ipify.org https://ipv6.icanhazip.com; do
        if command -v curl >/dev/null 2>&1; then curl -6 -fsS --max-time 6 "$u" 2>/dev/null && echo && break
        elif command -v wget >/dev/null 2>&1; then wget -6 -qO- -T 6 "$u" 2>/dev/null && echo && break; fi
    done
    ip -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1
}
aimili_resolve_domain() {
    # 公网 DNS 为准（DoH，不受 /etc/hosts 影响）；再 dig 外部 DNS；最后本机解析（忽略 127.x/::1 这类本地映射）。
    local d="$1" t
    if command -v curl >/dev/null 2>&1; then
        for t in A AAAA; do
            curl -fsS --max-time 6 -H 'accept: application/dns-json' "https://cloudflare-dns.com/dns-query?name=${d}&type=${t}" 2>/dev/null \
                | grep -o '"data":"[0-9a-fA-F:.]*"' | cut -d'"' -f4
        done
    fi
    if command -v dig >/dev/null 2>&1; then dig +short A "$d" @1.1.1.1 2>/dev/null; dig +short AAAA "$d" @1.1.1.1 2>/dev/null; fi
    if command -v getent >/dev/null 2>&1; then getent ahosts "$d" 2>/dev/null | awk '{print $1}' | grep -vE '^(127\.|::1$|0\.0\.0\.0$)' | sort -u; fi
}
aimili_domain_valid() {
    local d="$1" ips mine x
    printf '%s' "$d" | grep -Eq '^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$' || return 1
    ips=$(aimili_resolve_domain "$d" | grep -E '^[0-9a-fA-F:.]+$' | sort -u)
    [ -n "$ips" ] || return 1
    mine=$(aimili_public_ips | tr -d '\r' | grep -E '^[0-9a-fA-F:.]+$' | sort -u)
    [ -n "$mine" ] || return 0   # 查不到本机公网 IP 时只校验格式和能解析
    for x in $ips; do printf '%s\n' "$mine" | grep -qxF "$x" && return 0; done
    return 1
}
if [ "${AIMILI_FROM_JIUHEYI:-}" != "1" ] && [ -n "${AIMILIVPN_DOMAIN:-}" ] && [ "${AIMILI_SKIP_DOMAIN_CHECK:-}" != "1" ]; then
    if ! aimili_domain_valid "${AIMILIVPN_DOMAIN}"; then
        echo -e "${RED}域名无效或无法解析：${AIMILIVPN_DOMAIN}（需要完整域名，且解析到本机公网 IP）。未做任何安装，已退出。${PLAIN}"
        exit 1
    fi
    echo -e "${GREEN}域名校验通过：${AIMILIVPN_DOMAIN}${PLAIN}"
fi
[ -n "${JIUHEYI_CORE_CHOICE}" ] || JIUHEYI_CORE_CHOICE=1
JIUHEYI_CAMOUFLAGE_AUTO=0
[ -z "${JIUHEYI_CAMOUFLAGE}" ] && JIUHEYI_CAMOUFLAGE_AUTO=1
AIMILIVPN_DOMAIN=$(printf '%s' "${AIMILIVPN_DOMAIN:-}" | tr -d '[:space:]')
export AIMILIVPN_DOMAIN
if [ -z "${AIMILIVPN_DOMAIN}" ]; then
    export AIMILIVPN_IP_CERT_FOREVER=1
fi

DEFAULT_USER="wbowen123"
DEFAULT_REPO="AimiliVPN"

# 若 $1 是操作模式参数 (1-8, install, uninstall)，则不作为 GitHub 用户名
case "${1:-}" in
    1|2|3|4|5|6|7|8|uninstall|remove|install|"")
        GITHUB_USER="${GITHUB_USER:-${DEFAULT_USER}}"
        ;;
    *)
        GITHUB_USER="${1:-${DEFAULT_USER}}"
        ;;
esac
GITHUB_REPO="${GITHUB_REPO:-${2:-${DEFAULT_REPO}}}"

GITHUB_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}.git"

echo -e "\n${YELLOW}[1/4] 正在安装系统基础依赖...${PLAIN}"
swap_mb=$(aimili_swap_plan_mb)
if [ "${swap_mb}" -gt 0 ]; then
    avail_kb=$(df -k --output=avail / 2>/dev/null | awk 'NR==2{print $1}')
    if [ -z "${avail_kb}" ]; then
        avail_kb=$(df -k / | awk 'NR==2{print $4}')
    fi
    need_kb=$((swap_mb * 1024 + 512 * 1024))
    swap_file=/swapfile-aimili
    if [ "${avail_kb:-0}" -lt "${need_kb}" ]; then
        echo -e "${YELLOW}  -> 磁盘剩余不够 ${swap_mb}MB 交换分区，跳过，继续安装。${PLAIN}"
    elif [ "${AIMILI_SWAP_DRYRUN:-}" = "1" ]; then
        echo -e "${YELLOW}  -> （试运行）将添加 ${swap_mb}MB 交换分区 ${swap_file}。${PLAIN}"
    else
        echo -e "${YELLOW}  -> 内存约 $(( $(aimili_mem_kb) / 1024 ))MB，交换 $(( $(aimili_swap_kb) / 1024 ))MB，添加 ${swap_mb}MB（${swap_file}）。${PLAIN}"
        swapoff "${swap_file}" >/dev/null 2>&1 || true
        rm -f "${swap_file}"
        if ! fallocate -l "${swap_mb}M" "${swap_file}" 2>/dev/null; then
            dd if=/dev/zero of="${swap_file}" bs=1M count="${swap_mb}" status=none || true
        fi
        chmod 600 "${swap_file}" 2>/dev/null || true
        if mkswap "${swap_file}" >/dev/null 2>&1 && swapon "${swap_file}" >/dev/null 2>&1; then
            grep -q "^${swap_file} " /etc/fstab 2>/dev/null || echo "${swap_file} none swap sw 0 0" >> /etc/fstab
            mkdir -p /var/lib && printf '%s\n' "${swap_file}" > /var/lib/aimilivpn-swapfile
        else
            swapoff "${swap_file}" >/dev/null 2>&1 || true
            rm -f "${swap_file}"
            echo -e "${YELLOW}  -> 交换分区未启用，继续安装。${PLAIN}"
        fi
    fi
else
    echo -e "  -> 交换分区够用（内存 $(( $(aimili_mem_kb) / 1024 ))MB，交换 $(( $(aimili_swap_kb) / 1024 ))MB），不再添加。"
fi
if [ -d /proc/sys/vm ]; then
    mkdir -p /etc/sysctl.d
    printf 'vm.swappiness=10\n' > /etc/sysctl.d/99-aimili-swap.conf
    sysctl -w vm.swappiness=10 >/dev/null 2>&1 || true
fi
if [ "$PKG_MGR" = "apt-get" ]; then
    echo -e "  -> 正在运行 apt-get update 更新软件源清单..."
    aimili_apt_update || true
    echo -e "  -> 正在运行 apt-get install 安装基础依赖包..."
    apt-get install -y openvpn curl git ca-certificates iptables iproute2 psmisc python3 python3-venv python3-pip python3-dev ppp procps net-tools dnsutils wget unzip jq openssl mount util-linux iputils-ping qrencode
    if [ "$OS_TYPE" = "ubuntu" ]; then
        echo -e "  -> 安装 Ubuntu 多协议 VPN 依赖（SoftEther / L2TP-IPsec / SSTP）..."
        # 记下本次新装的多协议服务包（装之前没有的），卸载时只停/清这些，原本就有的不动
        mkdir -p /var/lib/aimilivpn
        for p in softether-vpnclient strongswan-starter xl2tpd; do
            dpkg -s "$p" >/dev/null 2>&1 || grep -qx "$p" /var/lib/aimilivpn/vpn-deps.list 2>/dev/null || echo "$p" >>/var/lib/aimilivpn/vpn-deps.list
        done
        apt-get install -y softether-vpnclient softether-vpncmd strongswan strongswan-starter xl2tpd sstp-client ppp busybox openconnect || \
          echo -e "${YELLOW}  -> 部分多协议组件未安装成功；OpenVPN 主链路仍可继续，安装日志请检查软件源支持情况。${PLAIN}"
        apt-get install -y isc-dhcp-client || \
          echo -e "${YELLOW}  -> dhclient 未安装，SoftEther 只用 busybox udhcpc 拿地址。${PLAIN}"
    fi
elif [ "$PKG_MGR" = "apk" ]; then
    echo -e "  -> 正在运行 apk update 更新软件源清单..."
    apk update || true
    echo -e "  -> 正在运行 apk add 安装基础依赖包..."
    apk add openvpn curl git ca-certificates iptables iproute2 psmisc python3 python3-dev py3-pip bash procps net-tools bind-tools wget unzip jq openssl util-linux iputils qrencode
elif [ "$PKG_MGR" = "dnf" ] || [ "$PKG_MGR" = "yum" ]; then
    echo -e "  -> 正在运行 $PKG_MGR 安装基础依赖包..."
    if [ "$OS_TYPE" != "fedora" ] && [ "$OS_TYPE" != "amzn" ]; then
        echo -e "     -> 正在安装 EPEL 软件源 (以支持 openvpn)..."
        $PKG_MGR install -y epel-release || true
    fi
    $PKG_MGR install -y openvpn curl git ca-certificates iptables iproute psmisc python3 python3-pip python3-devel ppp procps-ng net-tools bind-utils wget unzip jq openssl util-linux iputils qrencode || \
    $PKG_MGR install -y openvpn curl git ca-certificates iptables iproute2 psmisc python3 python3-pip python3-devel ppp procps-ng net-tools bind-utils wget unzip jq openssl util-linux iputils qrencode
fi

INSTALL_DIR="/opt/aimilivpn"
DEFAULT_DEPLOY_BRANCH="main"

CURRENT_BRANCH=""
if [ -d "${INSTALL_DIR}/.git" ]; then
    CURRENT_BRANCH=$(cd "${INSTALL_DIR}" && git rev-parse --abbrev-ref HEAD 2>/dev/null)
fi
DEPLOY_BRANCH="${AIMILIVPN_BRANCH:-$DEFAULT_DEPLOY_BRANCH}"

SCRIPT_SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo -e "\n${YELLOW}[2/4] 正在部署源代码到 ${INSTALL_DIR} (目标分支: ${DEPLOY_BRANCH})...${PLAIN}"
if [ "${AIMILI_LOCAL_SOURCE:-}" = "1" ] || [ -f "${INSTALL_DIR}/.local_dev" ] || [ -f "${SCRIPT_SOURCE_DIR}/.local_dev" ]; then
    echo -e "${GREEN}检测到本地源码模式 (AIMILI_LOCAL_SOURCE / .local_dev)，跳过 GitHub 克隆并同步本地最新代码至 ${INSTALL_DIR} ...${PLAIN}"
    mkdir -p "${INSTALL_DIR}"
    if [ "${SCRIPT_SOURCE_DIR}" != "${INSTALL_DIR}" ]; then
        cp -rf "${SCRIPT_SOURCE_DIR}"/* "${INSTALL_DIR}/"
    fi
    touch "${INSTALL_DIR}/.local_dev"
else
    if [ -d "${INSTALL_DIR}" ]; then
        echo -e "  -> 目录 ${INSTALL_DIR} 已存在，正在更新并强制覆盖本地文件..."
        cd "${INSTALL_DIR}"
        if [ -d ".git" ]; then
            git remote set-url origin "${GITHUB_URL}" || true
        else
            echo -e "  -> 检测到非 Git 安装目录，将先保留备份后重新克隆..."
            cd "$(dirname "${INSTALL_DIR}")"
            mv "${INSTALL_DIR}" "${INSTALL_DIR}.backup-$(date +%Y%m%d-%H%M%S)"
            git clone -b "${DEPLOY_BRANCH}" "${GITHUB_URL}" "${INSTALL_DIR}"
            cd "${INSTALL_DIR}"
        fi
        git fetch --all || true
        git checkout "${DEPLOY_BRANCH}" || git checkout -b "${DEPLOY_BRANCH}" "origin/${DEPLOY_BRANCH}" || true
        echo -e "  -> 正在强制重置本地文件至 origin/${DEPLOY_BRANCH} ..."
        if git reset --hard "origin/${DEPLOY_BRANCH}"; then
            echo -e "${GREEN}  -> 程序更新成功！${PLAIN}"
        else
            if git pull origin "${DEPLOY_BRANCH}"; then
                echo -e "${GREEN}  -> 程序更新成功！${PLAIN}"
            else
                echo -e "${YELLOW}  -> 警告: git pull/reset 失败，将保留当前本地文件并继续安装。${PLAIN}"
            fi
        fi
    else
        echo -e "  -> 正在克隆 GitHub 仓库 ${GITHUB_URL} (分支: ${DEPLOY_BRANCH}) ..."
        if git clone -b "${DEPLOY_BRANCH}" "${GITHUB_URL}" "${INSTALL_DIR}"; then
            echo -e "${GREEN}  -> 克隆成功！${PLAIN}"
        else
            echo -e "  -> 尝试默认克隆..."
            if git clone "${GITHUB_URL}" "${INSTALL_DIR}"; then
                cd "${INSTALL_DIR}"
                git checkout "${DEPLOY_BRANCH}" || git checkout -b "${DEPLOY_BRANCH}" "origin/${DEPLOY_BRANCH}" || true
                echo -e "${GREEN}  -> 克隆成功！${PLAIN}"
            else
                SCRIPT_SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
                if [ -f "${SCRIPT_SOURCE_DIR}/aimili_cli.py" ]; then
                    echo -e "${YELLOW}  -> GitHub 克隆受阻，检测到当前目录已包含完整源码，正在同步本地源码至 ${INSTALL_DIR} ...${PLAIN}"
                    mkdir -p "${INSTALL_DIR}"
                    cp -rf "${SCRIPT_SOURCE_DIR}"/* "${INSTALL_DIR}/"
                    echo -e "${GREEN}  -> 本地源码同步成功！${PLAIN}"
                else
                    echo -e "${RED}  -> 错误: 无法克隆仓库 ${GITHUB_URL}，且无本地源码可用！${PLAIN}"
                    exit 1
                fi
            fi
        fi
    fi
fi

if ! command -v acme.sh >/dev/null 2>&1; then
    echo -e "${YELLOW}  -> 安装 HTTPS 证书辅助工具 acme.sh ...${PLAIN}"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL https://get.acme.sh | sh -s email=admin@aimilivpn.local || echo -e "${YELLOW}  -> acme.sh 在线安装失败；不会阻断主程序安装。${PLAIN}"
        [ -f "$HOME/.acme.sh/acme.sh" ] && ln -sf "$HOME/.acme.sh/acme.sh" /usr/local/bin/acme.sh || true
    fi
fi

echo -e "\n${YELLOW}[版本信息] 正在检查 GitHub 仓库与版本分支...${PLAIN}"
EXPECTED_REMOTE_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}.git"
cd "${INSTALL_DIR}"
LOCAL_VERIFY_SHA=$(git rev-parse HEAD 2>/dev/null || echo "custom-build")
ORIGIN_VERIFY_SHA=$(git rev-parse "origin/${DEPLOY_BRANCH}" 2>/dev/null || echo "$LOCAL_VERIFY_SHA")
echo -e "${GREEN}  -> GitHub 来源: ${EXPECTED_REMOTE_URL}${PLAIN}"
echo -e "  -> 部署分支:   ${DEPLOY_BRANCH}"
echo -e "  -> 本地提交:   ${LOCAL_VERIFY_SHA}"

bash scripts/select_core.sh "${INSTALL_DIR}" || exit 1
python3 -m py_compile vpngate_manager.py proxy_server.py
echo -e "${GREEN}  -> Python 语法/构建校验通过${PLAIN}"

PROXY_ENV_FILE="/etc/default/aimilivpn"
mkdir -p /etc/default
[ -f "$PROXY_ENV_FILE" ] || touch "$PROXY_ENV_FILE"
if ! grep -q '^LOCAL_PROXY_USER=' "$PROXY_ENV_FILE"; then
    echo 'LOCAL_PROXY_USER="socks5"' >> "$PROXY_ENV_FILE"
fi
if ! grep -q '^LOCAL_PROXY_PASS=' "$PROXY_ENV_FILE"; then
    echo 'LOCAL_PROXY_PASS="ilovestudy"' >> "$PROXY_ENV_FILE"
fi
if ! grep -q '^LOCAL_PROXY_ALLOW=' "$PROXY_ENV_FILE"; then
    echo 'LOCAL_PROXY_ALLOW="127.0.0.1/32,::1/128"' >> "$PROXY_ENV_FILE"
fi
if ! grep -q '^LOCAL_PROXY_HOST=' "$PROXY_ENV_FILE"; then
    echo 'LOCAL_PROXY_HOST="127.0.0.1"' >> "$PROXY_ENV_FILE"
fi
if ! grep -q '^LOCAL_PROXY_PORT=' "$PROXY_ENV_FILE"; then
    echo 'LOCAL_PROXY_PORT="8500"' >> "$PROXY_ENV_FILE"
fi
if ! grep -q '^LOCAL_PROXY_DEFAULT_SCHEME=' "$PROXY_ENV_FILE"; then
    echo 'LOCAL_PROXY_DEFAULT_SCHEME="socks5"' >> "$PROXY_ENV_FILE"
fi
if ! grep -q '^ACCESS_LOG_ENABLED=' "$PROXY_ENV_FILE"; then
    echo 'ACCESS_LOG_ENABLED="false"' >> "$PROXY_ENV_FILE"
fi
if ! grep -q '^BACKGROUND_PROBE_BATCH=' "$PROXY_ENV_FILE"; then
    echo 'BACKGROUND_PROBE_BATCH="8"' >> "$PROXY_ENV_FILE"
fi
if ! grep -q '^ACTIVE_BACKGROUND_PROBE_BATCH=' "$PROXY_ENV_FILE"; then
    echo 'ACTIVE_BACKGROUND_PROBE_BATCH="2"' >> "$PROXY_ENV_FILE"
fi
if ! grep -q '^PROTOCOL_PROBE_BATCH=' "$PROXY_ENV_FILE"; then
    echo 'PROTOCOL_PROBE_BATCH="2"' >> "$PROXY_ENV_FILE"
fi
if ! grep -q '^FAST_LIVENESS_INTERVAL_SECONDS=' "$PROXY_ENV_FILE"; then
    echo 'FAST_LIVENESS_INTERVAL_SECONDS="5"' >> "$PROXY_ENV_FILE"
fi
if ! grep -q '^PROXY_HEALTH_INTERVAL_SECONDS=' "$PROXY_ENV_FILE"; then
    echo 'PROXY_HEALTH_INTERVAL_SECONDS="20"' >> "$PROXY_ENV_FILE"
fi
if ! grep -q '^MAX_PROXY_CONNECTIONS=' "$PROXY_ENV_FILE"; then
    echo 'MAX_PROXY_CONNECTIONS="64"' >> "$PROXY_ENV_FILE"
fi
if [ -n "${AIMILIVPN_DOMAIN:-}" ]; then
    if grep -q '^AIMILIVPN_DOMAIN=' "$PROXY_ENV_FILE"; then
        sed -i "s|^AIMILIVPN_DOMAIN=.*|AIMILIVPN_DOMAIN=\"${AIMILIVPN_DOMAIN}\"|" "$PROXY_ENV_FILE"
    else
        echo "AIMILIVPN_DOMAIN=\"${AIMILIVPN_DOMAIN}\"" >> "$PROXY_ENV_FILE"
    fi
fi
chmod 600 "$PROXY_ENV_FILE"
echo -e "${GREEN}  -> 本地代理默认: SOCKS5 127.0.0.1:8500${PLAIN}"
echo -e "${GREEN}  -> 账号: socks5 / 密码: ilovestudy${PLAIN}"

install -m 755 "${INSTALL_DIR}/github_update.sh" /usr/local/sbin/aimilivpn-github-update

cat > /etc/systemd/system/aimilivpn-github-update.service <<'UNIT'
[Unit]
Description=AimiliVPN GitHub production updater
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/aimilivpn-github-update
TimeoutStartSec=15min
UNIT
systemctl daemon-reload
echo -e "\n${YELLOW}[3/4] 正在配置系统服务...${PLAIN}"
if command -v systemctl >/dev/null 2>&1; then
    echo -e "  -> 检测到 systemd，正在创建服务配置 /lib/systemd/system/aimilivpn.service ..."
    cat > /lib/systemd/system/aimilivpn.service <<EOF
[Unit]
Description=AimiliVPN OpenVPN Manager with HTTP/SOCKS5 Proxy
After=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/python3 vpngate_manager.py
Restart=always
RestartSec=5
Environment=HOME=/root
EnvironmentFile=-/etc/default/aimilivpn
LimitNOFILE=65535
TasksMax=1024

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable aimilivpn.service
elif command -v rc-service >/dev/null 2>&1; then
    echo -e "  -> 检测到 OpenRC，正在创建服务配置 /etc/init.d/aimilivpn ..."
    cat > /etc/init.d/aimilivpn <<EOF
#!/sbin/openrc-run

description="AimiliVPN OpenVPN Manager with HTTP/SOCKS5 Proxy"
command="/usr/bin/python3"
command_args="${INSTALL_DIR}/vpngate_manager.py"
command_background="yes"
directory="${INSTALL_DIR}"
pidfile="/run/aimilivpn.pid"

if [ -f /etc/default/aimilivpn ]; then
    . /etc/default/aimilivpn
    export LOCAL_PROXY_USER LOCAL_PROXY_PASS LOCAL_PROXY_ALLOW
fi

depend() {
    need net
    after firewall
}
EOF
    chmod +x /etc/init.d/aimilivpn
    rc-update add aimilivpn default
else
    echo -e "${YELLOW}警告: 未能检测到 systemd 或 OpenRC，请手动管理服务。${PLAIN}"
fi

echo -e "\n${YELLOW}[4/4] 正在创建全局命令快捷接口 'ml'...${PLAIN}"
echo -e "  -> 正在写入管理脚本 /usr/bin/ml ..."
cat > /usr/bin/ml <<'EOF'
#!/usr/bin/env python3
import sys
sys.path.insert(0, "/opt/aimilivpn")
try:
    import aimili_cli
    aimili_cli.main()
except ImportError:
    try:
        import aimili_ml
        aimili_ml.main()
    except ImportError:
        sys.stderr.write("AimiliVPN 未安装或程序文件缺失（/opt/aimilivpn）。\n")
        raise SystemExit(1)
EOF
chmod +x /usr/bin/ml

AUTH_FILE="${INSTALL_DIR}/vpngate_data/ui_auth.json"
mkdir -p "${INSTALL_DIR}/vpngate_data"

is_custom="n"
if [ ! -f "$AUTH_FILE" ]; then
    if [ -n "${AIMILI_CUSTOM:-}" ]; then
        is_custom="${AIMILI_CUSTOM}"
    else
        echo -e "\n${YELLOW}网页安全后缀、账号、密码已自动生成，安装后可在网页「安全」里修改。${PLAIN}"
    fi
    
    UI_PORT=8501
    SECRET_PATH=$(python3 -c "import secrets, string; print(''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(12)))")
    UI_PASSWORD=$(python3 -c "
import secrets, string
chars = string.ascii_letters + string.digits
while True:
    pwd = ''.join(secrets.choice(chars) for _ in range(12))
    if any(c.islower() for c in pwd) and any(c.isupper() for c in pwd) and any(c.isdigit() for c in pwd):
        print(pwd)
        break
")
    UI_USERNAME=$(python3 -c "
import secrets, string
chars = string.ascii_letters + string.digits
while True:
    uname = ''.join(secrets.choice(chars) for _ in range(12))
    if uname[0].isalpha() and any(c.islower() for c in uname) and any(c.isupper() for c in uname) and any(c.isdigit() for c in uname):
        print(uname)
        break
")

    if [[ "$is_custom" =~ ^[Yy]$ ]]; then
        UI_PORT=8501
        while true; do
            read -p "请输入网页登录自定义安全后缀 [字母与数字组合, 默认随机]: " input_suffix
            if [ -z "$input_suffix" ]; then
                break
            fi
            if [[ "$input_suffix" =~ ^[A-Za-z0-9]+$ ]]; then
                SECRET_PATH=$input_suffix
                break
            else
                echo -e "${RED}输入错误: 后缀仅能由英文字母和数字组成！${PLAIN}"
            fi
        done
        
        read -p "请输入登录账号 [默认 $UI_USERNAME]: " input_user
        if [ -n "$input_user" ]; then
            UI_USERNAME=$input_user
        fi
        
        while true; do
            read -p "请输入登录密码 [默认随机生成, 建议包含字母、数字与符号]: " input_pass
            if [ -z "$input_pass" ]; then
                break
            fi
            if [ ${#input_pass} -ge 4 ]; then
                UI_PASSWORD=$input_pass
                break
            else
                echo -e "${RED}输入错误: 密码长度不能少于 4 位！${PLAIN}"
            fi
        done
    fi

    python3 - "$AUTH_FILE" "$UI_PORT" "$SECRET_PATH" "$UI_USERNAME" "$UI_PASSWORD" <<'PY'
import json
import sys

import os
auth_file, ui_port, secret_path, username, password = sys.argv[1:6]
cfg = {
    "host": "127.0.0.1",
    "port": int(ui_port),
    "proxy_port": 8500,
    "secret_path": secret_path,
    "username": username,
    "password": password,
    "web_domain": os.environ.get("AIMILIVPN_DOMAIN", ""),
}
with open(auth_file, "w", encoding="utf-8") as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
PY
fi

echo -e "\n正在优化网络参数 (配置反向路径过滤 rp_filter=2 以支持策略路由)..."
if [ -d "/etc/sysctl.d" ]; then
    cat > /etc/sysctl.d/99-aimilivpn.conf <<EOF
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.core.somaxconn = 32768
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
EOF
    sysctl -p /etc/sysctl.d/99-aimilivpn.conf >/dev/null 2>&1 || true
else
    if ! grep -q "net.ipv4.conf.all.rp_filter" /etc/sysctl.conf; then
        echo "" >> /etc/sysctl.conf
        echo "net.ipv4.conf.all.rp_filter = 2" >> /etc/sysctl.conf
        echo "net.ipv4.conf.default.rp_filter = 2" >> /etc/sysctl.conf
    else
        sed -i 's/net.ipv4.conf.all.rp_filter\s*=\s*[0-9]/net.ipv4.conf.all.rp_filter = 2/g' /etc/sysctl.conf
        sed -i 's/net.ipv4.conf.default.rp_filter\s*=\s*[0-9]/net.ipv4.conf.default.rp_filter = 2/g' /etc/sysctl.conf
    fi
    sysctl -p >/dev/null 2>&1 || true
fi
echo "2" > /proc/sys/net/ipv4/conf/all/rp_filter 2>/dev/null || sysctl -w net.ipv4.conf.all.rp_filter=2 >/dev/null 2>&1 || true
echo "2" > /proc/sys/net/ipv4/conf/default/rp_filter 2>/dev/null || sysctl -w net.ipv4.conf.default.rp_filter=2 >/dev/null 2>&1 || true
if command -v modprobe >/dev/null 2>&1; then modprobe tcp_bbr >/dev/null 2>&1 || true; fi
if [ -d /etc/sysctl.d ]; then
    cat > /etc/sysctl.d/99-aimilivpn-bbr.conf <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
fi
if sysctl net.ipv4.tcp_available_congestion_control >/dev/null 2>&1; then
    if sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
        sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1 || true
        sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1 || true
        sysctl -p /etc/sysctl.d/99-aimilivpn-bbr.conf >/dev/null 2>&1 || true
    fi
fi
for key in net.netfilter.nf_conntrack_udp_timeout_stream net.netfilter.nf_conntrack_udp_timeout; do
    sysctl "$key" >/dev/null 2>&1 && sysctl -w "$key=600" >/dev/null 2>&1 || true
done

if [ -d "/proc/sys/net/ipv4/conf" ]; then
    for dev_dir in /proc/sys/net/ipv4/conf/*; do
        dev_name=$(basename "$dev_dir")
        echo "2" > "/proc/sys/net/ipv4/conf/${dev_name}/rp_filter" 2>/dev/null || sysctl -w net.ipv4.conf.${dev_name}.rp_filter=2 >/dev/null 2>&1 || true
    done
fi

if [ "${INSTALL_RESI:-y}" = "y" ]; then
    echo -e "\n正在启动 AimiliVPN 服务并初始化网络..."
    if command -v systemctl >/dev/null 2>&1; then
        if ! systemctl restart aimilivpn.service; then
            echo -e "${RED}错误: aimilivpn.service 启动失败，安装终止。${PLAIN}"
            systemctl --no-pager --full status aimilivpn.service || true
            exit 1
        fi
        sleep 2
        if ! systemctl is-active --quiet aimilivpn.service; then
            echo -e "${RED}错误: aimilivpn.service 未进入 active 状态，安装终止。${PLAIN}"
            systemctl --no-pager --full status aimilivpn.service || true
            exit 1
        fi
        echo -e "${GREEN}  -> aimilivpn.service 已验证为 active${PLAIN}"
    elif command -v rc-service >/dev/null 2>&1; then
        if ! rc-service aimilivpn restart; then
            echo -e "${RED}错误: aimilivpn OpenRC 服务启动失败，安装终止。${PLAIN}"
            exit 1
        fi
        echo -e "${GREEN}  -> aimilivpn OpenRC 服务已启动${PLAIN}"
    fi
else
    echo -e "\n${YELLOW}  -> 跳过启动 AimiliVPN 家宽后台进程 (当前为极速原生直连模式，系统保持极致轻量)${PLAIN}"
    systemctl stop aimilivpn.service >/dev/null 2>&1 || true
    systemctl disable aimilivpn.service >/dev/null 2>&1 || true
fi

if [ -x "${INSTALL_DIR}/scripts/setup_https.sh" ]; then
    echo -e "\n正在配置 HTTPS 管理后台与订阅入口..."
    bash "${INSTALL_DIR}/scripts/setup_https.sh"
fi
aimili_fw_open || true

# AimiliVPN 域名证书是否就绪（文件存在、未过期、非自签 subject!=issuer、SAN 含 DNS:域名）
aimili_cert_ready() {
    local f=/etc/aimilivpn/tls/fullchain.pem d="$1" subj iss
    [ -n "$d" ] && [ -s "$f" ] && [ -s /etc/aimilivpn/tls/privkey.pem ] || return 1
    openssl x509 -in "$f" -noout -checkend 0 >/dev/null 2>&1 || return 1
    subj=$(openssl x509 -in "$f" -noout -subject -nameopt RFC2253 2>/dev/null | sed 's/^subject=//')
    iss=$(openssl x509 -in "$f" -noout -issuer -nameopt RFC2253 2>/dev/null | sed 's/^issuer=//')
    [ -n "$subj" ] && [ "$subj" != "$iss" ] || return 1
    # Let's Encrypt staging / 测试 CA 客户端不信任，不算就绪（测试时 AIMILI_ALLOW_STAGING_CERT=1）
    if [ "${AIMILI_ALLOW_STAGING_CERT:-}" != "1" ] && grep -Eqi 'STAGING|Fake LE|Pebble|\(TEST\)' <<<"$iss"; then return 1; fi
    openssl x509 -in "$f" -noout -ext subjectAltName 2>/dev/null | tr ',' '\n' | sed 's/^[[:space:]]*//' | grep -Fxqi "DNS:$d"
}
# acme.sh 里已有该域名的有效证书（剩余 14 天以上、非自签）就直接装到 /etc/aimilivpn/tls，不重新签发（省 Let's Encrypt 额度）
aimili_cert_from_acme_cache() {
    local d="$1" acme home dir c k subj iss
    # 只看本程序自己的证书目录 /var/lib/aimilivpn-acme（卸载时保留），以及旧版服务因没设 HOME 写到的 /.acme.sh；
    # 不碰 ~/.acme.sh 默认目录（那里可能是九合一的同域名证书，install-cert 会改掉它的安装路径）。
    for dir in "/var/lib/aimilivpn-acme/${d}_ecc" "/.acme.sh/${d}_ecc"; do
        home="${dir%/*}"
        acme=/root/.acme.sh/acme.sh; [ -x "$acme" ] || acme=$(command -v acme.sh 2>/dev/null)
        [ -n "$acme" ] && [ -x "$acme" ] || continue
        c="$dir/fullchain.cer"; k="$dir/${d}.key"
        [ -s "$c" ] && [ -s "$k" ] || continue
        openssl x509 -in "$c" -noout -checkend 1209600 >/dev/null 2>&1 || continue
        subj=$(openssl x509 -in "$c" -noout -subject -nameopt RFC2253 2>/dev/null | sed 's/^subject=//')
        iss=$(openssl x509 -in "$c" -noout -issuer -nameopt RFC2253 2>/dev/null | sed 's/^issuer=//')
        [ -n "$subj" ] && [ "$subj" != "$iss" ] || continue
        if [ "${AIMILI_ALLOW_STAGING_CERT:-}" != "1" ] && grep -Eqi 'STAGING|Fake LE|Pebble|\(TEST\)' <<<"$iss"; then continue; fi
        openssl x509 -in "$c" -noout -ext subjectAltName 2>/dev/null | tr ',' '\n' | sed 's/^[[:space:]]*//' | grep -Fxqi "DNS:$d" || continue
        mkdir -p /etc/aimilivpn/tls
        HOME=/root "$acme" --home /root/.acme.sh --cert-home "$home" --install-cert -d "$d" --ecc \
            --key-file /etc/aimilivpn/tls/privkey.pem --fullchain-file /etc/aimilivpn/tls/fullchain.pem \
            --reloadcmd "nginx -t && systemctl reload nginx" >/dev/null 2>&1 || continue
        chmod 600 /etc/aimilivpn/tls/privkey.pem 2>/dev/null || true
        return 0
    done
    return 1
}
# AimiliVPN 与九合一证书各自申请、各自续期，互不复用。证书只由一方申请：
# aimilivpn 服务启动时发现 web_domain 未配证书会自己申请（resume），安装脚本不再同时调用，只等服务的结果；
# 服务 20 秒内没有开始时才由安装脚本申请。acme.sh 里已有本程序自己的有效证书时直接安装，不重签（省 Let's Encrypt 额度）。
aimili_cert_state() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(str(d.get("status") or "")+"|"+str(d.get("domain") or "")+"|"+str(d.get("last_error") or d.get("message") or "")[-200:])' "${INSTALL_DIR}/vpngate_data/web_certificate.json" 2>/dev/null; }
if [ -n "${AIMILIVPN_DOMAIN:-}" ]; then
    if ! aimili_cert_ready "${AIMILIVPN_DOMAIN}" && aimili_cert_from_acme_cache "${AIMILIVPN_DOMAIN}"; then
        echo -e "\n${GREEN}acme.sh 已有本程序 ${AIMILIVPN_DOMAIN} 的有效证书，直接安装，不重新申请。${PLAIN}"
    fi
    if aimili_cert_ready "${AIMILIVPN_DOMAIN}"; then
        echo -e "\n${GREEN}本地已有 ${AIMILIVPN_DOMAIN} 的证书，直接使用，不再重新申请。${PLAIN}"
    elif [ "${CERT_VERIFY_MODE:-}" = "2" ] || [ -n "${CF_Token:-}" ]; then
        echo -e "\n${YELLOW}正在通过 Cloudflare DNS-01 API 为 ${AIMILIVPN_DOMAIN} 申请免 80 端口证书...${PLAIN}"
        if bash "${INSTALL_DIR}/scripts/manage_cert.sh" dns "${AIMILIVPN_DOMAIN}"; then
            echo -e "${GREEN}Cloudflare DNS-01 域名证书已成功签发并安装！${PLAIN}"
        else
            echo -e "${YELLOW}Cloudflare DNS 申请未成功完成，继续尝试默认流程兜底...${PLAIN}"
        fi
    else
        echo -e "\n${YELLOW}本地没有 ${AIMILIVPN_DOMAIN} 的证书，正在申请。失败则继续使用 IP 证书。${PLAIN}"
        cs=""; w=0
        while [ "$w" -lt 20 ]; do
            cs=$(aimili_cert_state); case "${cs}" in issuing\|"${AIMILIVPN_DOMAIN}"\|*|installing\|"${AIMILIVPN_DOMAIN}"\|*|active\|"${AIMILIVPN_DOMAIN}"\|*|error\|"${AIMILIVPN_DOMAIN}"\|*) break ;; esac
            sleep 2; w=$((w + 2))
        done
        case "${cs}" in
            issuing\|*|installing\|*|active\|*|error\|*)
                echo -e "  -> 由 AimiliVPN 服务申请（安装脚本不重复申请），等待结果..."
                w=0
                while [ "$w" -lt "${AIMILI_CERT_WAIT:-300}" ]; do
                    cs=$(aimili_cert_state); case "${cs}" in active\|*|error\|*) break ;; esac
                    sleep 3; w=$((w + 3))
                done ;;
            *)
                python3 - "${INSTALL_DIR}" "${AIMILIVPN_DOMAIN}" <<'PY' >/dev/null 2>&1 || true
import sys
from pathlib import Path
root, domain = sys.argv[1], sys.argv[2]
sys.path.insert(0, root)
from web_certificate import WebCertificateManager
WebCertificateManager(Path(root) / "vpngate_data" / "web_certificate.json")._worker(domain)
PY
                cs=$(aimili_cert_state) ;;
        esac
        if aimili_cert_ready "${AIMILIVPN_DOMAIN}"; then
            echo -e "${GREEN}域名证书已安装：${AIMILIVPN_DOMAIN}（$(openssl x509 -in /etc/aimilivpn/tls/fullchain.pem -noout -issuer 2>/dev/null | sed 's/^issuer= *//')）${PLAIN}"
        else
            echo -e "${YELLOW}域名证书申请失败：${cs##*|}${PLAIN}"
            echo -e "${YELLOW}继续使用已安装的 IP 证书。域名解析到本机并放开 80 端口后，可在网页里重试。${PLAIN}"
        fi
    fi
fi

if [ "${INSTALL_RESI:-y}" = "y" ]; then
    echo -e "\n正在等待 AimiliVPN 首次获取节点并建立加密通道 (此过程可能需要 5-30 秒)..."
    ACTIVE_ID=""
    LAST_MSG=""
    for i in {1..90}; do
        if [ -f "${INSTALL_DIR}/vpngate_data/state.json" ]; then
            ACTIVE_ID=$(python3 -c "import json; print(json.load(open('${INSTALL_DIR}/vpngate_data/state.json')).get('active_openvpn_node_id', ''))" 2>/dev/null || echo "")
            IS_CONN=$(python3 -c "import json; print(json.load(open('${INSTALL_DIR}/vpngate_data/state.json')).get('is_connecting', False))" 2>/dev/null || echo "False")
            CUR_MSG=$(python3 -c "import json; print(json.load(open('${INSTALL_DIR}/vpngate_data/state.json')).get('last_check_message', ''))" 2>/dev/null || echo "")
            
            if [ "$IS_CONN" = "False" ] || [ "$IS_CONN" = "false" ]; then
                if [ -n "$ACTIVE_ID" ]; then
                    echo -e "  -> ${GREEN}[已就绪]${PLAIN} 首次节点连接成功，活动节点: ${GREEN}$ACTIVE_ID${PLAIN}"
                    break
                else
                    if [ -n "$CUR_MSG" ] && [ "$CUR_MSG" != "$LAST_MSG" ]; then
                        echo -e "  -> 提示: ${YELLOW}${CUR_MSG}${PLAIN}"
                        LAST_MSG="$CUR_MSG"
                    fi
                fi
            else
                if [ -n "$CUR_MSG" ] && [ "$CUR_MSG" != "$LAST_MSG" ]; then
                    echo -e "  -> 状态: ${YELLOW}${CUR_MSG}${PLAIN}"
                    LAST_MSG="$CUR_MSG"
                fi
            fi
        else
            echo -n "."
        fi
        sleep 1
    done
    if [ -z "$ACTIVE_ID" ]; then
        echo -e "  -> ${YELLOW}[加载超时]${PLAIN} 首次节点获取或连接超时，将在后台继续尝试..."
    fi
fi

RAND_PATH=$(python3 -c "import secrets, string; print(''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(12)))" 2>/dev/null || openssl rand -hex 6 2>/dev/null || echo "admin$RANDOM")
SECRET_PATH="${RAND_PATH}"
USERNAME="未配置"
PASSWORD="未配置"
UI_PORT=8501
PROXY_PORT=8500
AUTH_FILE="${INSTALL_DIR}/vpngate_data/ui_auth.json"
if [ -f "$AUTH_FILE" ]; then
    SECRET_PATH=$(python3 -c "import json; print(json.load(open('$AUTH_FILE')).get('secret_path', '${RAND_PATH}'))" 2>/dev/null || echo "${RAND_PATH}")
    USERNAME=$(python3 -c "import json; print(json.load(open('$AUTH_FILE')).get('username', '未配置'))" 2>/dev/null || echo "未配置")
    PASSWORD=$(python3 -c "import json; print(json.load(open('$AUTH_FILE')).get('password', '未配置'))" 2>/dev/null || echo "未配置")
    UI_PORT=$(python3 -c "import json; print(json.load(open('$AUTH_FILE')).get('port', 8501))" 2>/dev/null || echo "8501")
    PROXY_PORT=$(python3 -c "import json; print(json.load(open('$AUTH_FILE')).get('proxy_port', 8500))" 2>/dev/null || echo "8500")
fi

echo -e "正在获取 VPS 公网 IP..."
PUBLIC_IP=$(curl -4fsS --connect-timeout 4 --max-time 8 https://api.ipify.org 2>/dev/null || \
            curl -4fsS --connect-timeout 4 --max-time 8 https://ifconfig.me 2>/dev/null || \
            curl -4fsS --connect-timeout 4 --max-time 8 https://icanhazip.com 2>/dev/null || echo "")
PUBLIC_IP=$(echo "$PUBLIC_IP" | tr -d '[:space:]')
if [[ "$PUBLIC_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo -n "$PUBLIC_IP" > "${INSTALL_DIR}/vpngate_data/public_ip.txt"
else
    PUBLIC_IP="您的服务器公网IP"
fi

echo -e "正在获取 VPS 公网 IPv6..."
PUBLIC_IPV6=$(curl -6fsS --connect-timeout 4 --max-time 8 https://api64.ipify.org 2>/dev/null || \
              curl -6fsS --connect-timeout 4 --max-time 8 https://ipv6.icanhazip.com 2>/dev/null || echo "")
PUBLIC_IPV6=$(echo "$PUBLIC_IPV6" | tr -d '[:space:]')
if [ -n "$PUBLIC_IPV6" ]; then
    echo -n "$PUBLIC_IPV6" > "${INSTALL_DIR}/vpngate_data/public_ipv6.txt"
fi

# 列出本机对外监听的端口（云防火墙/安全组需放行），TCP 与 UDP 分开
aimili_public_ports() {
    local t u
    t=$(ss -ltnH 2>/dev/null | awk '{print $4}' | grep -vE '^(127\.|\[::1\]|\[::ffff:127)' | sed 's/.*://' | sort -n -u | tr '\n' ' ')
    u=$(ss -lunH 2>/dev/null | awk '{print $4}' | grep -vE '^(127\.|\[::1\]|\[::ffff:127)' | sed 's/.*://' | grep -vE '^(68|546|323|5353)$' | sort -n -u | tr '\n' ' ')
    printf 'TCP %s%s' "${t:-无}" "${u:+ / UDP ${u}}"
}
# 完成汇总：联合安装时等九合一装完（其输出在前）后在最末尾统一打印一次
aimili_print_summary() {
    echo -e "\n${GREEN}==========================================================${PLAIN}"
    echo -e "${GREEN}             AimiliVPN 一键部署已完成！${PLAIN}"
    echo -e "${GREEN}==========================================================${PLAIN}"
    if [ -n "${AIMILIVPN_DOMAIN:-}" ]; then
        echo -e "  * HTTPS 管理后台:       ${BLUE}https://${AIMILIVPN_DOMAIN}:8443/${SECRET_PATH}/${PLAIN}"
        echo -e "  * 备用（IP）:           ${BLUE}https://${PUBLIC_IP}:8443/${SECRET_PATH}/${PLAIN}"
    else
        echo -e "  * HTTPS 管理后台:       ${BLUE}https://${PUBLIC_IP}:8443/${SECRET_PATH}/${PLAIN}"
    fi
    if [ -n "$PUBLIC_IPV6" ]; then
        echo -e "  * HTTPS 管理后台(IPv6):  ${BLUE}https://[${PUBLIC_IPV6}]:8443/${SECRET_PATH}/${PLAIN}"
    fi
    echo -e "  * 网页管理账号:          ${YELLOW}${USERNAME}${PLAIN}"
    echo -e "  * 网页管理密码:          ${YELLOW}${PASSWORD}${PLAIN}"
    echo -e "  * HTTPS 订阅入口:       ${BLUE}https://${AIMILIVPN_DOMAIN:-${PUBLIC_IP}}:18443/${PLAIN}${AIMILIVPN_DOMAIN:+  （备用 IP: https://${PUBLIC_IP}:18443/）}"
    echo -e "  * HTTP/SOCKS5代理:   ${BLUE}${PUBLIC_IP}:8500${PLAIN}"
    echo -e "  * 代理账号配置:         ${BLUE}/etc/default/aimilivpn${PLAIN}"
    echo -e "  * 默认 SOCKS5 密码:     ${YELLOW}ilovestudy${PLAIN}（建议首次部署后修改）"
    echo -e "  * 默认允许来源:         ${BLUE}127.0.0.1/32,::1/128${PLAIN}"
    echo -e " --------------------------------------------------------"
    echo -e "  * ${YELLOW}云防火墙/安全组需放行:${PLAIN} $(aimili_public_ports)（另需 TCP 80 用于证书续期；AWS Lightsail 在实例「网络」页添加）"
    echo -e "  * 快速状态指令:   ${YELLOW}ml status${PLAIN}  或  ${YELLOW}ml${PLAIN}"
    echo -e "  * 查看实时日志:   ${YELLOW}ml logs${PLAIN}"
    echo -e "  * 停止服务:       ${YELLOW}ml stop${PLAIN}"
    echo -e "  * 重启服务:       ${YELLOW}ml restart${PLAIN}"
    echo -e "=========================================================="
    echo
    if [ -x /usr/local/bin/sing-box ] && [ -f "${INSTALL_DIR}/vpngate_data/singbox_nodes.json" ]; then
        if [ -f "${INSTALL_DIR}/aimili_cli.py" ]; then
            python3 "${INSTALL_DIR}/aimili_cli.py" sub
        else
            local sub_host="${AIMILIVPN_DOMAIN:-${PUBLIC_IP}}"
            echo -e "${GREEN}======================================================================${PLAIN}"
            echo -e "${BOLD}${GREEN}        ⚡ AimiliVPN 全协议双栈矩阵 × 原生/家宽双出站聚合订阅${PLAIN}"
            echo -e "${GREEN}======================================================================${PLAIN}"
            echo -e "  * 核心状态:             ${GREEN}运行中 (端口 443 / VLESS Reality / Hysteria 2 / TUIC)${PLAIN}"
            echo -e "  * 🌟 Base64 通用订阅:   ${BLUE}https://${sub_host}:18443/sub.txt${PLAIN}"
            echo -e "  * 🐱 Clash Meta 订阅:   ${BLUE}https://${sub_host}:18443/clash.yaml${PLAIN}"
            echo -e "  * 📦 Sing-box 原生订阅: ${BLUE}https://${sub_host}:18443/singbox.json${PLAIN}"
            echo -e "  * 📄 Plaintext 节点:    ${BLUE}https://${sub_host}:18443/nodes.txt${PLAIN}"
            echo -e "  * 备用 HTTPS 订阅:      ${BLUE}https://${sub_host}:8443/sub/sub.txt${PLAIN}"
            if [ -f "${INSTALL_DIR}/scripts/print_qr.py" ]; then
                python3 "${INSTALL_DIR}/scripts/print_qr.py" "https://${sub_host}:18443/sub.txt" "全生态聚合订阅二维码 (手机扫码一键导入)"
            fi
            echo -e "${GREEN}======================================================================${PLAIN}"
            echo
        fi
    elif [ "${INSTALL_JIUHEYI:-}" = "y" ] || [ "${INSTALL_JIUHEYI:-}" = "Y" ]; then
        local jstat sub_port sub_host
        if [ -x /etc/v2ray-agent/xray/xray ] || [ -x /etc/v2ray-agent/sing-box/sing-box ]; then jstat="${GREEN}已安装${PLAIN}"; else jstat="${RED}未安装成功（见上方九合一输出）${PLAIN}"; fi
        echo -e "${GREEN}                     九合一${PLAIN}"
        echo -e "  * 九合一:               ${jstat}"
        sub_port=$(grep -hsE '^\s*listen' /etc/nginx/conf.d/subscribe.conf /etc/nginx/http.d/subscribe.conf 2>/dev/null | awk '{print $2}' | head -1)
        if [ -n "${sub_port}" ] && [ "${sub_port}" != "18443" ]; then
            sub_host="${AIMILIVPN_DOMAIN:-${PUBLIC_IP}}"
            echo -e "  * 九合一订阅端口:       ${BLUE}https://${sub_host}:${sub_port}/${PLAIN}${AIMILIVPN_DOMAIN:+  （备用 IP: https://${PUBLIC_IP}:${sub_port}/）}"
        fi
        echo -e "  * 节点与订阅链接:       ${YELLOW}vasma${PLAIN} → 7.用户管理 → 2.查看订阅"
        echo -e "  * 出站:                 九合一经 AimiliVPN 8500 出站"
        echo -e "=========================================================="
        echo
    fi
}


if [ "${INSTALL_SINGBOX:-}" = "y" ] || [ "${INSTALL_SINGBOX:-}" = "Y" ]; then
    echo -e "\n${YELLOW}开始配置 Sing-box 全协议核心与全生态订阅...${PLAIN}"
    if [ -f "${INSTALL_DIR}/scripts/setup_singbox.sh" ]; then
        bash "${INSTALL_DIR}/scripts/setup_singbox.sh" "${SINGBOX_CAMOUFLAGE:-gateway.icloud.com}"
    fi

    # 执行 WARP 自适应流媒体与 AI 解锁配置
    if [ "${INSTALL_WARP:-auto}" = "auto" ] || [ "${INSTALL_WARP:-}" = "y" ]; then
        echo -e "\n${YELLOW}开始执行 Cloudflare WARP 自适应流媒体与 AI 解锁智能探测...${PLAIN}"
        if [ -f "${INSTALL_DIR}/scripts/setup_warp.sh" ]; then
            bash "${INSTALL_DIR}/scripts/setup_warp.sh" auto || true
        fi
    elif [ "${INSTALL_WARP:-}" = "n" ]; then
        if [ -f "${INSTALL_DIR}/scripts/setup_warp.sh" ]; then
            bash "${INSTALL_DIR}/scripts/setup_warp.sh" off >/dev/null 2>&1 || true
        fi
    fi

    # 执行 Cloudflare CDN 三网优选测速
    if [ "${DO_CF_SPEEDTEST:-y}" != "n" ]; then
        if [ -f "${INSTALL_DIR}/scripts/cf_speedtest.sh" ]; then
            echo -e "\n${YELLOW}开始执行 Cloudflare CDN 三网优选 Anycast 测速...${PLAIN}"
            bash "${INSTALL_DIR}/scripts/cf_speedtest.sh" test || true
        fi
    fi
elif [ "${INSTALL_JIUHEYI:-}" = "y" ] || [ "${INSTALL_JIUHEYI:-}" = "Y" ]; then
    if [ -f /etc/v2ray-agent/xray/xray ] || [ -f /etc/v2ray-agent/sing-box/sing-box ]; then
        echo -e "${YELLOW}九合一已安装，跳过。${PLAIN}"
    else
        echo -e "${YELLOW}开始安装九合一...${PLAIN}"
        if [ -n "${JIUHEYI_INSTALL_URL:-}" ]; then
            curl -fsSL "${JIUHEYI_INSTALL_URL}" -o /tmp/jiuheyi-install.sh
        elif ! curl -fsSL "https://raw.githubusercontent.com/hankinsus/ilovestudy-node-9/main/install.sh" -o /tmp/jiuheyi-install.sh \
            || ! grep -q "九合一 V1.0.1" /tmp/jiuheyi-install.sh; then
            curl -fsSL "https://raw.githubusercontent.com/ilovestudyus-sketch/ilovestudy-node-9/main/install.sh" -o /tmp/jiuheyi-install.sh
        fi
        JIUHEYI_FROM_AIMILI=1 JIUHEYI_EGRESS=aimili JIUHEYI_ONECLICK=1 \
            JIUHEYI_CORE="${JIUHEYI_CORE_CHOICE:-1}" \
            JIUHEYI_REALITY_DOMAIN="${JIUHEYI_CAMOUFLAGE:-}" \
            JIUHEYI_CAMOUFLAGE_AUTO="${JIUHEYI_CAMOUFLAGE_AUTO:-1}" \
            JIUHEYI_USER_PREFIX="${JIUHEYI_USER_PREFIX:-}" \
            JIUHEYI_DOMAIN="${AIMILIVPN_DOMAIN}" \
            domain="${AIMILIVPN_DOMAIN}" bash /tmp/jiuheyi-install.sh </dev/null
    fi
fi

# 执行 HTML5 本地高保真伪装站部署
if [ "${INSTALL_CAMO:-y}" = "y" ] && [ -f "${INSTALL_DIR}/scripts/setup_camouflage.sh" ]; then
    echo -e "\n${YELLOW}开始部署 HTML5 本地高保真伪装网站...${PLAIN}"
    bash "${INSTALL_DIR}/scripts/setup_camouflage.sh" "${CAMO_TEMPLATE_CHOICE:-1}" || true
fi

# 执行 Linux BBR 拥塞控制与 TCP 缓冲区深度调优
if [ "${DO_TUNE_BBR:-y}" != "n" ] && [ -f "${INSTALL_DIR}/scripts/tune_bbr.sh" ]; then
    echo -e "\n${YELLOW}开始调优 Linux 内核 TCP 缓冲区与启用 BBR 加速...${PLAIN}"
    bash "${INSTALL_DIR}/scripts/tune_bbr.sh" || true
fi

# 执行定时系统自愈与看门狗任务配置
if [ "${DO_SETUP_CRON:-y}" != "n" ] && [ -f "${INSTALL_DIR}/scripts/setup_cron.sh" ]; then
    echo -e "\n${YELLOW}开始启用系统定时自愈与看门狗守护任务...${PLAIN}"
    bash "${INSTALL_DIR}/scripts/setup_cron.sh" install || true
fi

if command -v nginx >/dev/null 2>&1 && [ -f /etc/nginx/conf.d/aimilivpn-production.conf ]; then
    nginx_8443_up() { ss -ltn 2>/dev/null | grep -qE '[:.]8443[[:space:]]'; }
    if ! nginx_8443_up; then
        if nginx -t >/dev/null 2>&1; then
            systemctl enable nginx >/dev/null 2>&1 || true
            systemctl restart nginx >/dev/null 2>&1 || rc-service nginx restart >/dev/null 2>&1 || true
            for _ in 1 2 3 4 5; do nginx_8443_up && break; sleep 1; done
        fi
        if nginx_8443_up; then
            echo -e "${GREEN}  -> nginx 已重新启动，8443 管理入口正常。${PLAIN}"
        else
            echo -e "${RED}警告: 8443 管理入口没有监听。请执行 nginx -t 查看错误，修好后 systemctl restart nginx。${PLAIN}"
            nginx -t 2>&1 | tail -3 || true
        fi
    fi
fi

aimili_print_summary
