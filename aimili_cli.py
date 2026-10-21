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
    """读取已生成的节点与订阅配置"""
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

    direct_url = data.get("direct_url", "")
    resi_url = data.get("resi_url", "")

    # 如果 json 里没有链接，尝试从 links.txt 提取
    if (not direct_url or not resi_url) and os.path.exists(LINKS_FILE):
        try:
            with open(LINKS_FILE, "r", encoding="utf-8") as f:
                lines = [l.strip() for l in f if l.strip().startswith("vless://")]
                if len(lines) >= 2:
                    direct_url = direct_url or lines[0]
                    resi_url = resi_url or lines[1]
                elif len(lines) == 1:
                    direct_url = direct_url or lines[0]
        except Exception:
            pass

    return {
        "public_ip": public_ip,
        "domain": domain,
        "sub_host": sub_host,
        "direct_url": direct_url,
        "resi_url": resi_url,
        "sub_url_18443": f"https://{sub_host}:18443/sub.txt",
        "sub_url_8443": f"https://{sub_host}:8443/sub/sub.txt",
        "nodes_txt_url": f"https://{sub_host}:18443/nodes.txt",
        "short_id": data.get("short_id", ""),
        "public_key": data.get("public_key", ""),
        "camouflage_domain": data.get("camouflage_domain", "gateway.icloud.com")
    }


def print_subscription_card():
    """格式化打印双节点与订阅详情"""
    sub = get_subscription_data()

    print(f"\n{C_GREEN}======================================================================{C_RESET}")
    print(f"{C_BOLD}{C_GREEN}              ⚡ AimiliVPN & Sing-box 双节点分流与订阅{C_RESET}")
    print(f"{C_GREEN}======================================================================{C_RESET}")

    if not sub["direct_url"] and not sub["resi_url"]:
        print(f"{C_RED}未检测到已生成的 Sing-box 节点配置！{C_RESET}")
        print(f"请先运行以下命令一键部署 Sing-box 核心：")
        print(f"  {C_YELLOW}bash /opt/aimilivpn/scripts/setup_singbox.sh{C_RESET}\n")
        return

    print(f"{C_BOLD}【1. HTTPS 客户端通用订阅地址】{C_RESET}")
    print(f"  * 推荐订阅地址:   {C_BLUE}{C_BOLD}{sub['sub_url_18443']}{C_RESET}")
    print(f"  * 备用订阅地址:   {C_BLUE}{sub['sub_url_8443']}{C_RESET}")
    if sub["domain"]:
        print(f"  * IP 备用订阅:    {C_BLUE}https://{sub['public_ip']}:18443/sub.txt{C_RESET}")
    print(f"  * 明文节点列表:   {C_BLUE}{sub['nodes_txt_url']}{C_RESET}")

    print(f"\n{C_BOLD}【2. 节点链接 (可直接复制导入客户端)】{C_RESET}")
    print(f"  {C_MAGENTA}🚀 [节点 1: 原生直连 - VPS 原生千兆极速]{C_RESET}")
    print(f"  {C_YELLOW}{sub['direct_url']}{C_RESET}")
    print(f"\n  {C_MAGENTA}🏠 [节点 2: 住宅穿透 - AimiliVPN 家宽出口]{C_RESET}")
    print(f"  {C_YELLOW}{sub['resi_url']}{C_RESET}")

    print(f"\n{C_BOLD}【3. Reality 核心配置参数】{C_RESET}")
    print(f"  * 监听端口:       {C_GREEN}443{C_RESET} (TCP / xtls-rprx-vision)")
    print(f"  * 伪装域名(SNI):  {C_GREEN}{sub['camouflage_domain']}{C_RESET}")
    if sub["public_key"]:
        print(f"  * 公钥 (PublicKey): {C_GREEN}{sub['public_key']}{C_RESET}")
    if sub["short_id"]:
        print(f"  * ShortId:        {C_GREEN}{sub['short_id']}{C_RESET}")

    print(f"\n{C_BOLD}【4. 客户端导入与使用说明】{C_RESET}")
    print(f"  * {C_BOLD}手机客户端{C_RESET} (Shadowrocket / Loon / Surge / Sing-box / Clash Verge):")
    print(f"    打开客户端 -> 添加订阅 -> 粘贴上方 {C_BLUE}{sub['sub_url_18443']}{C_RESET} -> 更新配置即可。")
    print(f"  * {C_BOLD}电脑客户端{C_RESET} (v2rayN / Clash Verge Rev / Sing-box):")
    print(f"    支持直接复制上方 {C_YELLOW}vless://{C_RESET} 完整单链接，通过剪贴板直接一键导入。")
    print(f"  * 命令行随时调出此卡片: {C_YELLOW}ml sub{C_RESET}")
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

        print("\n" + "=" * 60)
        print(f"{C_BOLD}{C_BLUE}         🚀 AimiliVPN & Sing-box 双核心管理控制台{C_RESET}")
        print("=" * 60)
        print(f"【核心服务状态】")
        print(f"  AimiliVPN 住宅代理: {status['aimilivpn']}  (SOCKS5 端口: 8500)")
        print(f"  Sing-box 分流核心:  {status['singbox']}  (Reality 端口: 443)")
        print(f"  Nginx 入口转发:     {status['nginx']}  (管理: 8443 / 订阅: 18443)")
        if sub["direct_url"]:
            print(f"  通用 HTTPS 订阅:    {C_BLUE}{sub['sub_url_18443']}{C_RESET}")
        print("-" * 60)
        print(f"{C_BOLD}【快捷操作】{C_RESET}")
        print(f"  {C_GREEN}[1]{C_RESET} 查看双节点与订阅链接 ({C_YELLOW}ml sub{C_RESET})")
        print(f"  {C_GREEN}[2]{C_RESET} 查看 AimiliVPN 运行状态 ({C_YELLOW}ml status{C_RESET})")
        print(f"  {C_GREEN}[3]{C_RESET} 重启 Sing-box 核心服务")
        print(f"  {C_GREEN}[4]{C_RESET} 重启 AimiliVPN 服务")
        print(f"  {C_GREEN}[5]{C_RESET} 查看 Sing-box 实时日志")
        print(f"  {C_GREEN}[6]{C_RESET} 查看 AimiliVPN 实时日志 ({C_YELLOW}ml logs{C_RESET})")
        print(f"  {C_GREEN}[7]{C_RESET} 重新生成 Sing-box 节点与订阅")
        print(f"  {C_GREEN}[8]{C_RESET} 原生管理菜单 (修改密码/端口/更新/卸载)")
        print(f"  {C_RED}[0]{C_RESET} 退出控制台")
        print("=" * 60)

        try:
            choice = input(f"{C_BOLD}请选择操作 [0-8]: {C_RESET}").strip()
        except (KeyboardInterrupt, EOFError):
            print("\n已退出。")
            break

        if choice == "1":
            print_subscription_card()
            input(f"{C_BLUE}按回车键返回菜单...{C_RESET}")
        elif choice == "2":
            call_aimili_ml(["status"])
            input(f"\n{C_BLUE}按回车键返回菜单...{C_RESET}")
        elif choice == "3":
            print(f"{C_YELLOW}正在重启 Sing-box 服务...{C_RESET}")
            subprocess.call(["systemctl", "restart", "sing-box.service"])
            print(f"{C_GREEN}Sing-box 重启完成！{C_RESET}")
            input(f"{C_BLUE}按回车键返回菜单...{C_RESET}")
        elif choice == "4":
            print(f"{C_YELLOW}正在重启 AimiliVPN 服务...{C_RESET}")
            subprocess.call(["systemctl", "restart", "aimilivpn.service"])
            print(f"{C_GREEN}AimiliVPN 重启完成！{C_RESET}")
            input(f"{C_BLUE}按回车键返回菜单...{C_RESET}")
        elif choice == "5":
            print(f"{C_YELLOW}正在查看 Sing-box 最近日志 (按 Ctrl+C 退出)...{C_RESET}")
            try:
                subprocess.call(["journalctl", "-u", "sing-box", "-n", "30", "-f"])
            except KeyboardInterrupt:
                pass
        elif choice == "6":
            call_aimili_ml(["logs"])
        elif choice == "7":
            setup_script = os.path.join(INSTALL_DIR, "scripts", "setup_singbox.sh")
            if os.path.exists(setup_script):
                subprocess.call(["bash", setup_script])
            else:
                print(f"{C_RED}未找到脚本: {setup_script}{C_RESET}")
            input(f"\n{C_BLUE}按回车键返回菜单...{C_RESET}")
        elif choice == "8":
            call_aimili_ml([])
            break
        elif choice in ["0", "q", "quit", "exit"]:
            print("已退出控制台。")
            break
        else:
            print(f"{C_RED}无效选项，请输入 0 到 8 之间的数字。{C_RESET}")


def main():
    if len(sys.argv) > 1:
        cmd = sys.argv[1].lower()
        if cmd in ["sub", "subs", "subscription", "subscribe", "node", "nodes", "link", "links"]:
            print_subscription_card()
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
            if sub["direct_url"]:
                print(f"\n{C_GREEN}【Sing-box 订阅与双节点就绪】{C_RESET}")
                print(f"  * 订阅入口: {C_BLUE}{sub['sub_url_18443']}{C_RESET}")
                print(f"  * 查看节点详情请输入: {C_YELLOW}ml sub{C_RESET}")
            return
        else:
            # 透传其余所有命令至原有 aimili_ml (start, stop, restart, logs, update, uninstall, web, port, password)
            call_aimili_ml(sys.argv[1:])
            return

    # 无参数时启动全新交互式管理控制台
    interactive_menu()


if __name__ == "__main__":
    main()
