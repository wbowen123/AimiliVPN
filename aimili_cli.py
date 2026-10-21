#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
AimiliVPN & Sing-box 统一管理 CLI 与交互控制台
提供双节点查看、订阅提取、核心控制与原生管理菜单无缝联动
"""
import os
import sys
import json
import subprocess
import shutil

INSTALL_DIR = "/opt/aimilivpn"
DATA_DIR = os.path.join(INSTALL_DIR, "vpngate_data")
KEY_FILE = os.path.join(DATA_DIR, "singbox_keys.json")
NODES_JSON = os.path.join(DATA_DIR, "singbox_nodes.json")
LINKS_FILE = os.path.join(DATA_DIR, "singbox_links.txt")
AUTH_FILE = os.path.join(DATA_DIR, "ui_auth.json")
PROXY_ENV = "/etc/default/aimilivpn"

# ANSI 颜色定义
C_RED = "\033[0;31m"
C_GREEN = "\033[0;32m"
C_YELLOW = "\033[0;33m"
C_BLUE = "\033[0;36m"
C_MAGENTA = "\033[0;35m"
C_BOLD = "\033[1m"
C_RESET = "\033[0m"


def get_public_ip():
    """获取保存的公网 IP 或读取本地配置"""
    ip_file = os.path.join(DATA_DIR, "public_ip.txt")
    if os.path.exists(ip_file):
        try:
            with open(ip_file, "r", encoding="utf-8") as f:
                ip = f.read().strip()
                if ip and ip != "您的服务器公网IP":
                    return ip
        except Exception:
            pass
    return "您的服务器IP"


def get_domain():
    """检测绑定的 HTTPS 域名"""
    domain = os.environ.get("AIMILIVPN_DOMAIN", "").strip()
    if domain:
        return domain

    if os.path.exists(AUTH_FILE):
        try:
            with open(AUTH_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                d = data.get("web_domain", "").strip()
                if d:
                    return d
        except Exception:
            pass

    if os.path.exists(PROXY_ENV):
        try:
            with open(PROXY_ENV, "r", encoding="utf-8") as f:
                for line in f:
                    if line.startswith("AIMILIVPN_DOMAIN="):
                        d = line.split("=", 1)[1].strip().strip('"').strip("'")
                        if d:
                            return d
        except Exception:
            pass

    cert_file = "/etc/aimilivpn/tls/fullchain.pem"
    if os.path.exists(cert_file) and shutil.which("openssl"):
        try:
            out = subprocess.check_output(
                ["openssl", "x509", "-in", cert_file, "-noout", "-ext", "subjectAltName"],
                stderr=subprocess.DEVNULL
            ).decode("utf-8", errors="ignore")
            for part in out.split(","):
                part = part.strip()
                if part.startswith("DNS:"):
                    return part.split(":", 1)[1].strip()
        except Exception:
            pass

    return ""


def get_subscription_data():
    """读取已生成的全协议节点与全生态订阅配置"""
    data = {}
    if os.path.exists(NODES_JSON):
        try:
            with open(NODES_JSON, "r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            pass

    domain = data.get("domain") or get_domain()
    public_ip = data.get("public_ip") or get_public_ip()
    sub_host = domain if domain else public_ip

    # 读取全部节点链接
    all_links = []
    nodes_txt_path = "/var/www/aimilivpn-sub/nodes.txt"
    if not os.path.exists(nodes_txt_path):
        nodes_txt_path = os.path.join(DATA_DIR, "singbox_links.txt")
    if os.path.exists(nodes_txt_path):
        try:
            with open(nodes_txt_path, "r", encoding="utf-8") as f:
                all_links = [l.strip() for l in f if l.strip() and not l.startswith("#")]
        except Exception:
            pass

    direct_links = [l for l in all_links if "直连" in l or "原生" in l]
    resi_links = [l for l in all_links if "住宅" in l or "家宽" in l]

    return {
        "public_ip": public_ip,
        "domain": domain,
        "sub_host": sub_host,
        "all_links": all_links,
        "direct_links": direct_links,
        "resi_links": resi_links,
        "sub_url_18443": f"https://{sub_host}:18443/sub.txt",
        "clash_url_18443": f"https://{sub_host}:18443/clash.yaml",
        "singbox_url_18443": f"https://{sub_host}:18443/singbox.json",
        "nodes_txt_url": f"https://{sub_host}:18443/nodes.txt",
        "sub_url_8443": f"https://{sub_host}:8443/sub/sub.txt",
        "short_id": data.get("short_id", ""),
        "public_key": data.get("public_key", ""),
        "camouflage_domain": data.get("camouflage_domain", "gateway.icloud.com")
    }


def print_subscription_card():
    """格式化打印全协议 10 大节点与全生态订阅详情"""
    sub = get_subscription_data()
    auth = get_web_auth_data()

    print(f"\n{C_GREEN}======================================================================{C_RESET}")
    print(f"{C_BOLD}{C_GREEN}          ⚡ AimiliVPN 全协议矩阵 × 原生/家宽双出站订阅{C_RESET}")
    print(f"{C_GREEN}======================================================================{C_RESET}")

    if not sub["all_links"]:
        print(f"{C_RED}未检测到已生成的 Sing-box 节点配置！{C_RESET}")
        print(f"请先运行以下命令一键部署全协议核心：")
        print(f"  {C_YELLOW}bash /opt/aimilivpn/scripts/setup_singbox.sh{C_RESET}\n")
        return

    print(f"{C_BOLD}【1. 多客户端通用订阅地址】{C_RESET}")
    print(f"  * {C_GREEN}Base64 通用订阅:{C_RESET}   {C_BLUE}{C_BOLD}{sub['sub_url_18443']}{C_RESET}")
    print(f"    (支持 v2rayN、Shadowrocket 小火箭、Loon、Surge、Quantumult X)")
    print(f"  * {C_GREEN}Clash Meta 订阅:{C_RESET}   {C_BLUE}{C_BOLD}{sub['clash_url_18443']}{C_RESET}")
    print(f"    (内置自动优选与故障转移策略组，支持 Clash Verge Rev、Mihomo)")
    print(f"  * {C_GREEN}Sing-box 订阅:{C_RESET}     {C_BLUE}{C_BOLD}{sub['singbox_url_18443']}{C_RESET}")
    print(f"    (内置 Smart-DNS 与分流规则，开箱即用)")
    print(f"  * 明文节点列表:     {C_BLUE}{sub['nodes_txt_url']}{C_RESET}")
    print(f"  * 备用订阅地址:     {C_BLUE}{sub['sub_url_8443']}{C_RESET}")

    print(f"\n{C_BOLD}【2. 原生机房极速出口节点 (VPS 千兆直连 / 低延迟 / 刷4K)】{C_RESET}")
    for idx, l in enumerate(sub["direct_links"], 1):
        print(f"  {C_MAGENTA}[直连节点 {idx}]{C_RESET} {C_YELLOW}{l}{C_RESET}")

    print(f"\n{C_BOLD}【3. 住宅家宽穿透出口节点 (Aimili 动态家宽 / 解锁流媒体 / 跨境防封)】{C_RESET}")
    for idx, l in enumerate(sub["resi_links"], 1):
        print(f"  {C_MAGENTA}[家宽节点 {idx}]{C_RESET} {C_YELLOW}{l}{C_RESET}")

    print(f"\n{C_BOLD}【4. 网页控制面板 (可视化国家/节点切换)】{C_RESET}")
    print(f"  * 管理后台地址:     {C_BLUE}{C_BOLD}{auth['web_url']}{C_RESET}")
    print(f"  * 管理员账号:       {C_YELLOW}{auth['username']}{C_RESET}")
    print(f"  * 管理员密码:       {C_YELLOW}{auth['password']}{C_RESET}")
    if auth["secret_path"]:
        print(f"  * 安全访问后缀:     {C_GREEN}/{auth['secret_path']}/{C_RESET}（防探测机制，必须带后缀访问）")

    print(f"\n{C_BOLD}【5. 协议核心配置参数】{C_RESET}")
    print(f"  * VLESS-Reality:    {C_GREEN}TCP 443{C_RESET} | 伪装 SNI: {C_GREEN}{sub['camouflage_domain']}{C_RESET}")
    print(f"  * Hysteria 2:       {C_GREEN}UDP 443{C_RESET} (Brutal 拥塞对抗)")
    print(f"  * TUIC v5:          {C_GREEN}UDP 8443{C_RESET} (QUIC / BBR 0-RTT)")
    print(f"  * AnyTLS:           {C_GREEN}TCP 8444{C_RESET} (动态数据包长度混淆)")
    print(f"  * VMess-xHTTP:      {C_GREEN}TCP 8445{C_RESET} (分块流防审查)")
    if sub["public_key"]:
        print(f"  * Reality 公钥:     {C_GREEN}{sub['public_key']}{C_RESET}")

    print(f"\n{C_BOLD}【6. 客户端导入与使用说明】{C_RESET}")
    print(f"  * {C_BOLD}推荐一键导入{C_RESET}: 复制上方 {C_BLUE}clash.yaml{C_RESET} 或 {C_BLUE}sub.txt{C_RESET} 地址直接填入客户端；")
    print(f"  * {C_BOLD}单节点手动导入{C_RESET}: 直接复制上方任一协议单链接通过剪贴板导入；")
    print(f"  * 命令行随时调出此卡片: {C_YELLOW}ml sub{C_RESET}  |  调出网页后台信息: {C_YELLOW}ml web{C_RESET}")
    print(f"{C_GREEN}======================================================================{C_RESET}\n")


def check_unit_active(unit_name):
    """检查 systemd 服务运行状态"""
    if not shutil.which("systemctl"):
        return False
    try:
        ret = subprocess.call(
            ["systemctl", "is-active", "--quiet", unit_name],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        return ret == 0
    except Exception:
        return False


def get_service_statuses():
    """获取所有核心服务的状态"""
    aimili_active = check_unit_active("aimilivpn")
    singbox_active = check_unit_active("sing-box")
    nginx_active = check_unit_active("nginx")

    def format_badge(active):
        return f"{C_GREEN}● 运行中{C_RESET}" if active else f"{C_RED}○ 未启动{C_RESET}"

    return {
        "aimilivpn": format_badge(aimili_active),
        "singbox": format_badge(singbox_active),
        "nginx": format_badge(nginx_active),
        "aimili_raw": aimili_active,
        "singbox_raw": singbox_active,
        "nginx_raw": nginx_active
    }


def call_aimili_ml(args):
    """透传执行原作者的 aimili_ml 模块"""
    sys.path.insert(0, INSTALL_DIR)
    try:
        import aimili_ml
        sys.argv = ["ml"] + args
        aimili_ml.main()
    except ImportError:
        print(f"{C_RED}错误: 未找到 aimili_ml 核心模块（/opt/aimilivpn）。{C_RESET}")
    except SystemExit:
        pass
    except Exception as e:
        print(f"{C_RED}执行出错: {e}{C_RESET}")


def interactive_menu():
    """交互式主控制台菜单"""
    while True:
        status = get_service_statuses()
        sub = get_subscription_data()
        auth = get_web_auth_data()

        print("\n" + "=" * 60)
        print(f"{C_BOLD}{C_BLUE}         🚀 AimiliVPN & Sing-box 双核心管理控制台{C_RESET}")
        print("=" * 60)
        print(f"【核心服务状态】")
        print(f"  AimiliVPN 住宅代理: {status['aimilivpn']}  (SOCKS5 端口: 8500)")
        print(f"  Sing-box 分流核心:  {status['singbox']}  (Reality 端口: 443)")
        print(f"  Nginx 入口转发:     {status['nginx']}  (管理: 8443 / 订阅: 18443)")
        if sub["direct_url"]:
            print(f"  通用 HTTPS 订阅:    {C_BLUE}{sub['sub_url_18443']}{C_RESET}")
        print(f"  网页控制面板:       {C_BLUE}{auth['web_url']}{C_RESET}")
        print(f"  管理员账号/密码:    {C_YELLOW}{auth['username']}{C_RESET} / {C_YELLOW}{auth['password']}{C_RESET}")
        print("-" * 60)
        print(f"{C_BOLD}【快捷操作】{C_RESET}")
        print(f"  {C_GREEN}[1]{C_RESET} 查看双节点与通用订阅链接 ({C_YELLOW}ml sub{C_RESET})")
        print(f"  {C_GREEN}[2]{C_RESET} 查看网页控制面板地址与账号密码 ({C_YELLOW}ml web{C_RESET})")
        print(f"  {C_GREEN}[3]{C_RESET} 查看 AimiliVPN 运行状态 ({C_YELLOW}ml status{C_RESET})")
        print(f"  {C_GREEN}[4]{C_RESET} 重启 Sing-box 核心服务")
        print(f"  {C_GREEN}[5]{C_RESET} 重启 AimiliVPN 服务")
        print(f"  {C_GREEN}[6]{C_RESET} 查看 Sing-box 实时日志")
        print(f"  {C_GREEN}[7]{C_RESET} 查看 AimiliVPN 实时日志 ({C_YELLOW}ml logs{C_RESET})")
        print(f"  {C_GREEN}[8]{C_RESET} 重新生成 Sing-box 节点与订阅")
        print(f"  {C_GREEN}[9]{C_RESET} 原生管理菜单 (修改密码/端口/更新/卸载)")
        print(f"  {C_RED}[0]{C_RESET} 退出控制台")
        print("=" * 60)

        try:
            choice = input(f"{C_BOLD}请选择操作 [0-9]: {C_RESET}").strip()
        except (KeyboardInterrupt, EOFError):
            print("\n已退出。")
            break

        if choice == "1":
            print_subscription_card()
            input(f"{C_BLUE}按回车键返回菜单...{C_RESET}")
        elif choice == "2":
            print_web_dashboard()
            input(f"{C_BLUE}按回车键返回菜单...{C_RESET}")
        elif choice == "3":
            call_aimili_ml(["status"])
            input(f"\n{C_BLUE}按回车键返回菜单...{C_RESET}")
        elif choice == "4":
            print(f"{C_YELLOW}正在重启 Sing-box 服务...{C_RESET}")
            subprocess.call(["systemctl", "restart", "sing-box.service"])
            print(f"{C_GREEN}Sing-box 重启完成！{C_RESET}")
            input(f"{C_BLUE}按回车键返回菜单...{C_RESET}")
        elif choice == "5":
            print(f"{C_YELLOW}正在重启 AimiliVPN 服务...{C_RESET}")
            subprocess.call(["systemctl", "restart", "aimilivpn.service"])
            print(f"{C_GREEN}AimiliVPN 重启完成！{C_RESET}")
            input(f"{C_BLUE}按回车键返回菜单...{C_RESET}")
        elif choice == "6":
            print(f"{C_YELLOW}正在查看 Sing-box 最近日志 (按 Ctrl+C 退出)...{C_RESET}")
            try:
                subprocess.call(["journalctl", "-u", "sing-box", "-n", "30", "-f"])
            except KeyboardInterrupt:
                pass
        elif choice == "7":
            call_aimili_ml(["logs"])
        elif choice == "8":
            setup_script = os.path.join(INSTALL_DIR, "scripts", "setup_singbox.sh")
            if os.path.exists(setup_script):
                subprocess.call(["bash", setup_script])
            else:
                print(f"{C_RED}未找到脚本: {setup_script}{C_RESET}")
            input(f"\n{C_BLUE}按回车键返回菜单...{C_RESET}")
        elif choice == "9":
            call_aimili_ml([])
            break
        elif choice in ["0", "q", "quit", "exit"]:
            print("已退出控制台。")
            break
        else:
            print(f"{C_RED}无效选项，请输入 0 到 9 之间的数字。{C_RESET}")


def main():
    if len(sys.argv) > 1:
        cmd = sys.argv[1].lower()
        if cmd in ["sub", "subs", "subscription", "subscribe", "node", "nodes", "link", "links"]:
            print_subscription_card()
            return
        elif cmd in ["web", "ui", "panel", "admin", "dashboard"]:
            print_web_dashboard()
            return
        elif cmd in ["singbox", "sb"]:
            subcmd = sys.argv[2] if len(sys.argv) > 2 else "status"
            if subcmd == "status":
                active = check_unit_active("sing-box")
                print(f"Sing-box 服务状态: {'运行中' if active else '未启动'}")
                subprocess.call(["systemctl", "status", "sing-box", "--no-pager"])
            elif subcmd in ["restart", "reload"]:
                subprocess.call(["systemctl", "restart", "sing-box"])
                print(f"{C_GREEN}Sing-box 服务已重启。{C_RESET}")
            elif subcmd == "stop":
                subprocess.call(["systemctl", "stop", "sing-box"])
                print(f"{C_YELLOW}Sing-box 服务已停止。{C_RESET}")
            elif subcmd == "start":
                subprocess.call(["systemctl", "start", "sing-box"])
                print(f"{C_GREEN}Sing-box 服务已启动。{C_RESET}")
            elif subcmd in ["log", "logs"]:
                subprocess.call(["journalctl", "-u", "sing-box", "-n", "50", "-f"])
            elif subcmd in ["setup", "install"]:
                setup_script = os.path.join(INSTALL_DIR, "scripts", "setup_singbox.sh")
                subprocess.call(["bash", setup_script])
            else:
                print(f"可用 singbox 子命令: status, start, stop, restart, logs, setup")
            return
        elif cmd == "status":
            call_aimili_ml(["status"])
            sub = get_subscription_data()
            auth = get_web_auth_data()
            if sub["direct_url"]:
                print(f"\n{C_GREEN}【Sing-box 订阅与双节点就绪】{C_RESET}")
                print(f"  * 订阅入口: {C_BLUE}{sub['sub_url_18443']}{C_RESET}")
                print(f"  * 节点详情: {C_YELLOW}ml sub{C_RESET}")
            print(f"\n{C_GREEN}【网页控制面板】{C_RESET}")
            print(f"  * 管理后台: {C_BLUE}{auth['web_url']}{C_RESET}")
            print(f"  * 账号/密码: {C_YELLOW}{auth['username']}{C_RESET} / {C_YELLOW}{auth['password']}{C_RESET}")
            return
        else:
            # 透传其余所有命令至原有 aimili_ml (start, stop, restart, logs, update, uninstall, port, password)
            call_aimili_ml(sys.argv[1:])
            return

    # 无参数时启动全新交互式管理控制台
    interactive_menu()


if __name__ == "__main__":
    main()
