#!/usr/bin/env bash
# ==============================================================================
# AimiliVPN Linux BBR 拥塞控制与 TCP 网络栈深度调优脚本
# 适用：Ubuntu / Debian / CentOS / AlmaLinux / Rocky Linux
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
PLAIN='\033[0m'

if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}错误: 必须以 root 权限运行此脚本。${PLAIN}" >&2
    exit 1
fi

echo -e "${BLUE}==========================================================${PLAIN}"
echo -e "${BLUE}      正在优化 Linux 内核 TCP 缓冲区与启用 BBR 加速...${PLAIN}"
echo -e "${BLUE}==========================================================${PLAIN}"

# 1. 检查内核版本
KERNEL_VER=$(uname -r | cut -d- -f1)
MAJOR=$(echo "$KERNEL_VER" | cut -d. -f1)
MINOR=$(echo "$KERNEL_VER" | cut -d. -f2)

echo -e "  -> 当前内核版本: ${GREEN}${KERNEL_VER}${PLAIN}"

if [ "$MAJOR" -lt 4 ] || ([ "$MAJOR" -eq 4 ] && [ "$MINOR" -lt 9 ]); then
    echo -e "${YELLOW}警告: 当前内核版本低于 4.9，原生不支持 BBR。建议升级内核后再试。${PLAIN}"
    exit 0
fi

# 2. 检查并加载 tcp_bbr 模块
if ! lsmod | grep -q tcp_bbr; then
    modprobe tcp_bbr 2>/dev/null || true
fi

# 3. 写入持久化 sysctl 配置
mkdir -p /etc/sysctl.d
SYSCTL_CONF="/etc/sysctl.d/99-aimilivpn-bbr.conf"

cat > "$SYSCTL_CONF" <<'EOF'
# AimiliVPN 深度网络性能优化
fs.file-max = 1000000
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 提升 TCP 读写缓冲区大小（突破跨国长延迟线路下 4K 播放限速）
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432

# 关闭空闲后的慢启动，保持高吞吐连接热度
net.ipv4.tcp_slow_start_after_idle = 0

# 提升系统 Socket 处理队列上限
net.core.netdev_max_backlog = 10000
net.core.somaxconn = 32768
net.ipv4.tcp_max_syn_backlog = 16384

# 开启 TCP 窗口缩放与快速回收
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
EOF

# 4. 生效配置
if command -v sysctl >/dev/null 2>&1; then
    sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1 || sysctl --system >/dev/null 2>&1 || true
fi

# 5. 校验 BBR 状态
CURRENT_CC=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $NF}' || echo "unknown")
CURRENT_QDISC=$(sysctl net.core.default_qdisc 2>/dev/null | awk '{print $NF}' || echo "unknown")

if [ "$CURRENT_CC" = "bbr" ]; then
    echo -e "${GREEN}  -> Google BBR 加速已成功开启！ (拥塞算法: ${CURRENT_CC}, 排队规则: ${CURRENT_QDISC})${PLAIN}"
else
    echo -e "${YELLOW}  -> 当前系统拥塞控制算法为: ${CURRENT_CC}（可能由于容器虚拟化环境受限）${PLAIN}"
fi

echo -e "${GREEN}==========================================================${PLAIN}\n"
