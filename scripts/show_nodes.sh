#!/usr/bin/env bash
# ==============================================================================
# AimiliVPN & Sing-box 双节点链接与订阅快速查看脚本
# ==============================================================================
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$ROOT_DIR/aimili_cli.py" ]; then
    python3 "$ROOT_DIR/aimili_cli.py" sub
elif [ -x /usr/bin/ml ]; then
    /usr/bin/ml sub
else
    echo "未找到 aimili_cli.py，尝试直接读取节点文件..."
    cat /var/www/aimilivpn-sub/nodes.txt 2>/dev/null || \
    cat /var/lib/aimilivpn/subscriptions/nodes.txt 2>/dev/null || \
    cat "$ROOT_DIR/vpngate_data/nodes.txt" 2>/dev/null || \
    cat "$ROOT_DIR/vpngate_data/singbox_links.txt" 2>/dev/null || \
    echo "暂无节点数据，请先运行 setup_singbox.sh"
fi
