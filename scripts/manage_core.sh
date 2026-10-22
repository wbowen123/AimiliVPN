#!/usr/bin/env bash
# ==============================================================================
# AimiliVPN Sing-box 核心版本管理与自动升级工具
# 支持一键检测最新 GitHub Release、自选稳定版本、多镜像加速下载与平滑无缝热替换
# ==============================================================================
set -euo pipefail

SB_BIN="/usr/local/bin/sing-box"
SB_CONFIG="/etc/sing-box/config.json"
SB_SERVICE="sing-box.service"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
BOLD='\033[1m'
PLAIN='\033[0m'

if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}错误: 必须以 root 权限运行此脚本。${PLAIN}" >&2
    exit 1
fi

ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64) SB_ARCH="amd64" ;;
    aarch64|arm64) SB_ARCH="arm64" ;;
    *) echo -e "${RED}不支持的 CPU 架构: ${ARCH}${PLAIN}"; exit 1 ;;
esac

get_current_version() {
    if [ -x "$SB_BIN" ]; then
        "$SB_BIN" version 2>/dev/null | awk '/sing-box version/ {print $3}' || echo "未安装"
    else
        echo "未安装"
    fi
}

get_latest_release() {
    local api_url="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
    local tag=""
    tag=$(curl -fsSL --connect-timeout 4 --max-time 8 -H "User-Agent: Mozilla/5.0" "$api_url" 2>/dev/null | grep '"tag_name":' | head -1 | sed -E 's/.*"([^"]+)".*/\1/' | sed 's/^v//' || true)
    if [ -z "$tag" ]; then
        # 兜底备用：通过 GitHub 重定向获取最新 tag
        tag=$(curl -fsSI --connect-timeout 4 --max-time 8 "https://github.com/SagerNet/sing-box/releases/latest" 2>/dev/null | grep -i '^location:' | sed -E 's/.*\/tag\/v?([^/\r\n]+).*/\1/' || true)
    fi
    [ -z "$tag" ] && tag="1.14.3"
    echo "$tag"
}

install_version() {
    local ver="$1"
    ver="${ver#v}"  # 统一去除 v 前缀
    echo -e "\n${BLUE}==========================================================${PLAIN}"
    echo -e "${BLUE}   正在下载并部署 Sing-box v${ver} (${SB_ARCH})...${PLAIN}"
    echo -e "${BLUE}==========================================================${PLAIN}"

    local download_url="https://github.com/SagerNet/sing-box/releases/download/v${ver}/sing-box-${ver}-linux-${SB_ARCH}.tar.gz"
    local tmp_tar="/tmp/sing-box-${ver}.tar.gz"
    local tmp_dir="/tmp/sing-box-extract-$$"
    rm -rf "$tmp_dir" "$tmp_tar"
    mkdir -p "$tmp_dir"

    local mirrors=(
        "$download_url"
        "https://ghfast.top/${download_url}"
        "https://mirror.ghproxy.com/${download_url}"
    )

    local downloaded=0
    for m in "${mirrors[@]}"; do
        echo -e "${YELLOW}  -> 尝试从下载源获取: ${m}${PLAIN}"
        if curl -fSL --connect-timeout 8 --max-time 120 "$m" -o "$tmp_tar" 2>/dev/null; then
            if tar -tzf "$tmp_tar" >/dev/null 2>&1; then
                downloaded=1
                echo -e "${GREEN}  -> 下载完成并校验通过！${PLAIN}"
                break
            fi
        fi
        echo -e "${YELLOW}  -> 下载源响应缓慢或校验不通过，尝试下一个镜像...${PLAIN}"
    done

    if [ "$downloaded" != "1" ]; then
        echo -e "${RED}错误: 无法下载 Sing-box v${ver}，请检查网络或版本号是否存在！${PLAIN}"
        rm -rf "$tmp_dir" "$tmp_tar"
        return 1
    fi

    tar -xzf "$tmp_tar" -C "$tmp_dir"
    local extracted_bin
    extracted_bin=$(find "$tmp_dir" -type f -name sing-box | head -n 1)
    if [ -z "$extracted_bin" ] || [ ! -x "$extracted_bin" ]; then
        echo -e "${RED}错误: 解压文件中未找到有效的 sing-box 二进制文件。${PLAIN}"
        rm -rf "$tmp_dir" "$tmp_tar"
        return 1
    fi

    # 语法兼容性预检
    if [ -f "$SB_CONFIG" ]; then
        echo -e "${YELLOW}  -> 正在对现有业务配置执行兼容性预检...${PLAIN}"
        if ! "$extracted_bin" check -c "$SB_CONFIG" >/dev/null 2>&1; then
            echo -e "${YELLOW}警告: 现有配置文件与新版本核心语法存在微小差异，准备启动配置自愈兼容...${PLAIN}"
            # 尝试自愈
            python3 -c "
import json
try:
    with open('$SB_CONFIG', 'r') as f:
        cfg = json.load(f)
    for ob in cfg.get('outbounds', []):
        if ob.get('type') == 'socks' and not ob.get('username'):
            ob.pop('username', None)
            ob.pop('password', None)
    with open('$SB_CONFIG', 'w') as f:
        json.dump(cfg, f, indent=2)
except Exception:
    pass
" || true
            if ! "$extracted_bin" check -c "$SB_CONFIG"; then
                echo -e "${RED}错误: 新内核版本未能通过当前生产配置校验，已终止替换以防止断网！${PLAIN}"
                rm -rf "$tmp_dir" "$tmp_tar"
                return 1
            fi
        fi
    fi

    # 原子替换
    local backup_bin="${SB_BIN}.bak.$$"
    if [ -f "$SB_BIN" ]; then
        cp -f "$SB_BIN" "$backup_bin"
    fi

    install -m 755 "$extracted_bin" "$SB_BIN"
    rm -rf "$tmp_dir" "$tmp_tar"

    # 重启并验证
    if systemctl is-enabled --quiet "$SB_SERVICE" 2>/dev/null; then
        echo -e "${YELLOW}  -> 正在重启 Sing-box 服务...${PLAIN}"
        systemctl daemon-reload
        systemctl restart "$SB_SERVICE" || true
        sleep 1.5
        if systemctl is-active --quiet "$SB_SERVICE"; then
            echo -e "${GREEN}  -> Sing-box 服务成功平滑热重启并健康运行！${PLAIN}"
            rm -f "$backup_bin"
        else
            echo -e "${RED}警告: 新版本启动失败，触发自动保护回滚机制...${PLAIN}"
            if [ -f "$backup_bin" ]; then
                mv -f "$backup_bin" "$SB_BIN"
                systemctl restart "$SB_SERVICE" || true
                echo -e "${GREEN}  -> 已成功自动回滚至上一版旧内核！${PLAIN}"
            fi
            return 1
        fi
    fi

    echo -e "${GREEN}==========================================================${PLAIN}"
    echo -e "${GREEN}  🎉 Sing-box 核心升级成功！当前版本: $($SB_BIN version | head -n 1)${PLAIN}"
    echo -e "${GREEN}==========================================================${PLAIN}"
    return 0
}

interactive_core_menu() {
    local cur_ver
    cur_ver=$(get_current_version)
    echo -e "${YELLOW}正在检测 GitHub 官方最新 Release 版本...${PLAIN}"
    local latest_ver
    latest_ver=$(get_latest_release)

    echo -e "\n${BOLD}${BLUE}==========================================================${PLAIN}"
    echo -e "${BOLD}${BLUE}          🛠️ Sing-box 核心版本管理与自动升级${PLAIN}"
    echo -e "${BOLD}${BLUE}==========================================================${PLAIN}"
    echo -e "  当前已安装版本:   ${GREEN}${cur_ver}${PLAIN}"
    echo -e "  GitHub 最新稳定版: ${YELLOW}v${latest_ver}${PLAIN}"
    echo -e "  系统架构:         ${BLUE}${SB_ARCH}${PLAIN}"
    echo -e "----------------------------------------------------------"
    echo -e "  ${GREEN}[1]${PLAIN} 一键升级到 GitHub 官方最新稳定版 (${YELLOW}v${latest_ver}${PLAIN})"
    echo -e "  ${GREEN}[2]${PLAIN} 部署长期推荐稳定版 (${YELLOW}v1.11.4${PLAIN})"
    echo -e "  ${GREEN}[3]${PLAIN} 部署广泛兼容版 (${YELLOW}v1.10.7${PLAIN})"
    echo -e "  ${GREEN}[4]${PLAIN} 手动输入任意指定版本号 (如 1.9.7 / 1.12.0)"
    echo -e "  ${RED}[0]${PLAIN} 返回上级控制台"
    echo -e "=========================================================="

    read -r -p "请选择操作 [0-4]: " choice
    case "$choice" in
        1)
            install_version "$latest_ver"
            ;;
        2)
            install_version "1.11.4"
            ;;
        3)
            install_version "1.10.7"
            ;;
        4)
            read -r -p "请输入欲安装的 Sing-box 版本号 (例如 1.9.7): " user_ver
            user_ver=$(echo "$user_ver" | tr -d '[:space:]')
            if [ -n "$user_ver" ]; then
                install_version "$user_ver"
            else
                echo -e "${RED}输入不能为空。${PLAIN}"
            fi
            ;;
        0|q|quit|exit)
            echo "已返回。"
            exit 0
            ;;
        *)
            echo -e "${RED}无效输入。${PLAIN}"
            ;;
    esac
}

# 命令行直接调用支持: bash manage_core.sh [version|latest]
if [ $# -gt 0 ]; then
    arg="$1"
    if [ "$arg" = "latest" ]; then
        target=$(get_latest_release)
        install_version "$target"
    else
        install_version "$arg"
    fi
else
    interactive_core_menu
fi
