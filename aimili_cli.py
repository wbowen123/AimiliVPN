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
import urllib.parse

INSTALL_DIR = "/opt/aimilivpn"
DATA_DIR = os.path.join(INSTALL_DIR, "vpngate_data")
KEY_FILE = os.path.join(DATA_DIR, "singbox_keys.json")
NODES_JSON = os.path.join(DATA_DIR, "singbox_nodes.json")
LINKS_FILE = os.path.join(DATA_DIR, "nodes.txt")
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


def get_web_auth_data():
    """读取网页控制面板认证信息与访问地址"""
    data = {}
    if os.path.exists(AUTH_FILE):
        try:
            with open(AUTH_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            pass

    username = data.get("username", "admin")
    password = data.get("password", "admin")
    secret_path = data.get("secret_path", "").strip("/")
    web_domain = data.get("web_domain", "").strip() or get_domain()
    public_ip = get_public_ip()
    host = web_domain if web_domain else public_ip

    port = data.get("port", 8443)
    if secret_path:
        web_url = f"https://{host}:{port}/{secret_path}/"
        fallback_url = f"https://{public_ip}:{port}/{secret_path}/" if web_domain else web_url
    else:
        web_url = f"https://{host}:{port}/"
        fallback_url = f"https://{public_ip}:{port}/" if web_domain else web_url

    return {
        "username": username,
        "password": password,
        "secret_path": secret_path,
        "web_domain": web_domain,
        "public_ip": public_ip,
        "port": port,
        "web_url": web_url,
        "fallback_url": fallback_url
    }


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
        nodes_txt_path = os.path.join(DATA_DIR, "nodes.txt")
    if not os.path.exists(nodes_txt_path):
        nodes_txt_path = os.path.join(DATA_DIR, "singbox_links.txt")
    if os.path.exists(nodes_txt_path):
        try:
            with open(nodes_txt_path, "r", encoding="utf-8") as f:
                all_links = [l.strip() for l in f if l.strip() and not l.startswith("#")]
        except Exception:
            pass

    import urllib.parse, base64

    def _get_link_text(l):
        try:
            if l.startswith("vmess://"):
                b64 = l[8:]
                padded = b64 + "=" * ((4 - len(b64) % 4) % 4)
                v_obj = json.loads(base64.b64decode(padded).decode("utf-8", errors="ignore"))
                return v_obj.get("ps", "")
            return urllib.parse.unquote(l)
        except Exception:
            return l

    direct_links = [l for l in all_links if "直连" in _get_link_text(l) or "原生" in _get_link_text(l)]
    resi_links = [l for l in all_links if "住宅" in _get_link_text(l) or "家宽" in _get_link_text(l)]
    argo_links = [l for l in all_links if "Argo" in _get_link_text(l) or "CDN" in _get_link_text(l)]

    return {
        "public_ip": public_ip,
        "domain": domain,
        "sub_host": sub_host,
        "all_links": all_links,
        "direct_links": direct_links,
        "resi_links": resi_links,
        "argo_links": argo_links,
        "direct_url": direct_links[0] if direct_links else (all_links[0] if all_links else ""),
        "resi_url": resi_links[0] if resi_links else "",
        "resi_egress_type": data.get("resi_egress_type", "local"),
        "resi_host": data.get("resi_host", "127.0.0.1"),
        "resi_port": data.get("resi_port", 8500),
        "sub_url_18443": f"https://{sub_host}:18443/sub.txt",
        "clash_url_18443": f"https://{sub_host}:18443/clash.yaml",
        "singbox_url_18443": f"https://{sub_host}:18443/singbox.json",
        "nodes_txt_url": f"https://{sub_host}:18443/nodes.txt",
        "sub_url_8443": f"https://{sub_host}:8443/sub/sub.txt",
        "short_id": data.get("short_id", ""),
        "public_key": data.get("public_key", ""),
        "camouflage_domain": data.get("camouflage_domain", "gateway.icloud.com")
    }


def print_terminal_qr(content, title="全生态聚合订阅二维码 (手机扫码一键导入)"):
    """渲染终端 ASCII / ANSI 二维码"""
    qr_script = os.path.join(INSTALL_DIR, "scripts", "print_qr.py")
    if os.path.exists(qr_script):
        subprocess.call(["python3", qr_script, content, title])
    elif shutil.which("qrencode"):
        print(f"\n{C_BOLD}{C_BLUE}📱 ========== 【{title}】 =========={C_RESET}")
        try:
            subprocess.call(["qrencode", "-t", "ANSIUTF8", content])
        except Exception:
            try:
                subprocess.call(["qrencode", "-t", "ANSI", content])
            except Exception:
                print(f"  * 订阅 URL: {content}")
        print(f"{C_BOLD}{C_BLUE}======================================================================{C_RESET}\n")
    else:
        print(f"\n{C_BOLD}{C_BLUE}📱 ========== 【{title}】 =========={C_RESET}")
        print(f"  * 订阅/节点 URL: {C_YELLOW}{content}{C_RESET}")
        print(f"  * 提示: 安装 qrencode 后可在终端直接显示二维码: {C_GREEN}apt-get install -y qrencode{C_RESET}")
        print(f"{C_BOLD}{C_BLUE}======================================================================{C_RESET}\n")


def print_web_dashboard():
    """格式化打印网页控制面板信息与认证凭据"""
    auth = get_web_auth_data()
    statuses = get_service_statuses()

    print(f"\n{C_GREEN}======================================================================{C_RESET}")
    print(f"{C_BOLD}{C_GREEN}            🌐 AimiliVPN 可视化网页管理面板信息{C_RESET}")
    print(f"{C_GREEN}======================================================================{C_RESET}")
    print(f"  * Nginx 前端状态:   {statuses['nginx']}")
    print(f"  * 管理后台地址:     {C_BOLD}{C_BLUE}{auth['web_url']}{C_RESET}")
    if auth.get("web_domain") and auth.get("public_ip"):
        print(f"  * 纯 IP 备用地址:   {C_BLUE}{auth['fallback_url']}{C_RESET}")
    print(f"  * 管理员账号:       {C_YELLOW}{auth['username']}{C_RESET}")
    print(f"  * 管理员密码:       {C_YELLOW}{auth['password']}{C_RESET}")
    if auth.get("secret_path"):
        print(f"  * 防扫描动态后缀:   {C_BLUE}/{auth['secret_path']}/{C_RESET}")
    print("----------------------------------------------------------------------")
    print("  💡 提示: 面板支持动态住宅节点切换、分流模式管理与系统监控")
    print(f"  💡 修改密码可在管理控制台执行: {C_YELLOW}ml password{C_RESET}")
    print(f"{C_GREEN}======================================================================{C_RESET}\n")


def print_subscription_card():
    """格式化打印全协议 18 节点矩阵、全生态聚合订阅与终端二维码"""
    sub = get_subscription_data()
    auth = get_web_auth_data()
    statuses = get_service_statuses()

    print(f"\n{C_GREEN}======================================================================{C_RESET}")
    print(f"{C_BOLD}{C_GREEN}        ⚡ AimiliVPN 全协议双栈矩阵 × 原生/家宽双出站聚合订阅{C_RESET}")
    print(f"{C_GREEN}======================================================================{C_RESET}")

    if not sub["all_links"]:
        print(f"{C_RED}未检测到已生成的 Sing-box 节点配置！{C_RESET}")
        print("请先运行以下命令一键部署全协议核心：")
        print(f"  {C_YELLOW}bash /opt/aimilivpn/scripts/setup_singbox.sh{C_RESET}\n")
        return

    print(f"{C_BOLD}【0. 核心服务与端口实时状态】{C_RESET}")
    print(f"  * Sing-box 代理矩阵: {statuses['singbox']}  (443 TCP/UDP, 8443 UDP, 8444 TCP, 8445 TCP)")
    print(f"  * Aimili 住宅家宽:   {statuses['aimilivpn']}  (127.0.0.1:8500 SOCKS5 虚拟隧道池)")
    print(f"  * Nginx 订阅系统:    {statuses['nginx']}  (18443 全格式聚合订阅 / 8443 HTTPS 管理)")

    print(f"\n{C_BOLD}【1. 多客户端通用聚合订阅地址】{C_RESET}")
    print(f"  * {C_GREEN}🌟 Base64 通用自适应订阅:{C_RESET} {C_BLUE}{C_BOLD}{sub['sub_url_18443']}{C_RESET}")
    print("    (自适应客户端，完美适配 Shadowrocket 小火箭、v2rayN、Loon、Surge、Quantumult X)")
    print(f"  * {C_GREEN}🐱 Clash Meta (Mihomo):{C_RESET}   {C_BLUE}{C_BOLD}{sub['clash_url_18443']}{C_RESET}")
    print("    (内置自动测速优选与故障转移策略组，支持 Clash Verge Rev、Mihomo Party)")
    print(f"  * {C_GREEN}📦 Sing-box 原生 1.10+ JSON:{C_RESET} {C_BLUE}{C_BOLD}{sub['singbox_url_18443']}{C_RESET}")
    print("    (内置 Smart-DNS 分流与原生路由规则，开箱即用无需转换)")
    print(f"  * {C_GREEN}📄 Plaintext 原始节点列表:{C_RESET}  {C_BLUE}{sub['nodes_txt_url']}{C_RESET}")
    print(f"  * 备用订阅地址:             {C_BLUE}{sub['sub_url_8443']}{C_RESET}")

    # 渲染终端 ASCII 二维码 (手机直接扫码)
    print_terminal_qr(sub["sub_url_18443"], "全生态聚合订阅二维码 (手机小火箭 / Sing-box 扫码一键导入)")

    print(f"{C_BOLD}【2. 原生机房极速出口节点 (VPS 千兆直连 / 低延迟 / 刷4K)】{C_RESET}")
    for idx, l in enumerate(sub["direct_links"], 1):
        name = urllib.parse.unquote(l.split("#")[-1]) if "#" in l else f"直连节点 {idx}"
        print(f"  {C_MAGENTA}{name}{C_RESET}\n    {C_YELLOW}{l}{C_RESET}")

    print(f"\n{C_BOLD}【3. 住宅家宽穿透出口节点 (Aimili 动态家宽 / 解锁流媒体 / 跨境防封)】{C_RESET}")
    for idx, l in enumerate(sub["resi_links"], 1):
        name = urllib.parse.unquote(l.split("#")[-1]) if "#" in l else f"家宽节点 {idx}"
        print(f"  {C_MAGENTA}{name}{C_RESET}\n    {C_YELLOW}{l}{C_RESET}")

    if sub.get("argo_links"):
        print(f"\n{C_BOLD}【4. Cloudflare CDN / Argo 穿透出口节点 (Anycast 优选 IP 赋能 / 破墙免流)】{C_RESET}")
        for idx, l in enumerate(sub["argo_links"], 1):
            name = urllib.parse.unquote(l.split("#")[-1]) if "#" in l else f"CDN节点 {idx}"
            print(f"  {C_MAGENTA}{name}{C_RESET}\n    {C_YELLOW}{l}{C_RESET}")

    print(f"\n{C_BOLD}【5. 网页控制面板 (可视化国家/节点切换)】{C_RESET}")
    print(f"  * 管理后台地址:     {C_BLUE}{C_BOLD}{auth['web_url']}{C_RESET}")
    print(f"  * 管理员账号:       {C_YELLOW}{auth['username']}{C_RESET}")
    print(f"  * 管理员密码:       {C_YELLOW}{auth['password']}{C_RESET}")
    if auth["secret_path"]:
        print(f"  * 安全访问后缀:     {C_GREEN}/{auth['secret_path']}/{C_RESET}（防探测机制，必须带后缀访问）")

    print(f"\n{C_BOLD}【6. 协议核心配置参数】{C_RESET}")
    print(f"  * VLESS-Reality:    {C_GREEN}TCP 443{C_RESET} | 伪装 SNI: {C_GREEN}{sub['camouflage_domain']}{C_RESET}")
    print(f"  * Hysteria 2:       {C_GREEN}UDP 443{C_RESET} (Brutal 暴力抗丢包 + 40000-50000 端口跳跃)")
    print(f"  * TUIC v5:          {C_GREEN}UDP 8443{C_RESET} (H3-QUIC / BBR 0-RTT 秒开)")
    print(f"  * AnyTLS:           {C_GREEN}TCP 8444{C_RESET} (动态数据包长度填充防探测)")
    print(f"  * VMess-xHTTP:      {C_GREEN}TCP 8445{C_RESET} (H2/H3 分块流防审查)")
    if sub["public_key"]:
        print(f"  * Reality 公钥:     {C_GREEN}{sub['public_key']}{C_RESET}")

    print(f"\n{C_BOLD}【7. 客户端导入与使用说明】{C_RESET}")
    print(f"  * {C_BOLD}手机一键扫码{C_RESET}: 打开 Shadowrocket / Sing-box 客户端，扫描上方终端二维码即可自动导入所有节点；")
    print(f"  * {C_BOLD}电脑一键导入{C_RESET}: 复制上方 {C_BLUE}clash.yaml{C_RESET} 或 {C_BLUE}sub.txt{C_RESET} 地址直接填入客户端；")
    print(f"  * {C_BOLD}单节点手动导入{C_RESET}: 直接复制上方任一协议单链接通过剪贴板导入；")
    print(f"  * 命令行随时调出此卡片: {C_YELLOW}ml sub{C_RESET}  |  仅查看二维码: {C_YELLOW}ml qr{C_RESET}  |  调出网页后台: {C_YELLOW}ml web{C_RESET}")
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
    except SystemExit as se:
        if se.code not in (None, 0):
            sys.exit(se.code)
    except Exception as e:
        print(f"{C_RED}执行出错: {e}{C_RESET}")


def update_env_file(key_values):
    """更新或添加 /etc/default/aimilivpn 中的环境变量"""
    env_lines = []
    if os.path.exists(PROXY_ENV):
        try:
            with open(PROXY_ENV, "r", encoding="utf-8") as f:
                env_lines = f.readlines()
        except Exception:
            env_lines = []

    new_keys = set(key_values.keys())
    out_lines = []
    matched_keys = set()
    for line in env_lines:
        line_s = line.strip()
        matched = False
        for k in new_keys:
            if line_s.startswith(f"{k}="):
                matched = True
                matched_keys.add(k)
                out_lines.append(f'{k}="{key_values[k]}"\n')
                break
        if not matched:
            out_lines.append(line)

    for k, v in key_values.items():
        if k not in matched_keys:
            out_lines.append(f'{k}="{v}"\n')

    try:
        os.makedirs(os.path.dirname(PROXY_ENV), exist_ok=True)
        with open(PROXY_ENV, "w", encoding="utf-8") as f:
            f.writelines(out_lines)
        return True
    except Exception as e:
        print(f"{C_RED}写入 {PROXY_ENV} 失败: {e}{C_RESET}")
        return False


def configure_residential_egress():
    """配置住宅出口双模：AimiliVPN 原生内置动态池 (8500) 或 外部第三方商业住宅 SOCKS5"""
    sub_data = get_subscription_data()
    current_type = sub_data.get("resi_egress_type", "local")
    curr_host = sub_data.get("resi_host", "127.0.0.1")
    curr_port = str(sub_data.get("resi_port", 8500))
    curr_user = ""
    curr_pass = ""

    if os.path.exists(PROXY_ENV):
        try:
            with open(PROXY_ENV, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("RESI_EGRESS_TYPE="):
                        current_type = line.split("=", 1)[1].strip().strip('"').strip("'")
                    elif line.startswith("EXTERNAL_PROXY_HOST="):
                        curr_host = line.split("=", 1)[1].strip().strip('"').strip("'")
                    elif line.startswith("EXTERNAL_PROXY_PORT="):
                        curr_port = line.split("=", 1)[1].strip().strip('"').strip("'")
                    elif line.startswith("EXTERNAL_PROXY_USER="):
                        curr_user = line.split("=", 1)[1].strip().strip('"').strip("'")
                    elif line.startswith("EXTERNAL_PROXY_PASS="):
                        curr_pass = line.split("=", 1)[1].strip().strip('"').strip("'")
        except Exception:
            pass

    print("\n" + "=" * 60)
    print(f"{C_BOLD}{C_BLUE}     🏠 AimiliVPN 住宅出口模式配置 (双模自适应架构){C_RESET}")
    print("=" * 60)
    if current_type == "external":
        print(f"当前住宅出口模式: {C_GREEN}外部第三方 SOCKS5 落地代理{C_RESET}")
        print(f"  * 落地代理地址:   {C_BLUE}{curr_host}:{curr_port}{C_RESET}")
        print(f"  * 认证用户名:     {C_YELLOW}{curr_user if curr_user else '(无密码认证)'}{C_RESET}")
    else:
        print(f"当前住宅出口模式: {C_GREEN}AimiliVPN 原生内置动态家宽池{C_RESET}")
        print(f"  * 本地网桥:       {C_BLUE}127.0.0.1:8500{C_RESET} (由 AimiliVPN 自动轮换海量公共/住宅节点)")
    print("-" * 60)
    print("请选择要切换的住宅出口模式:")
    print(f"  {C_GREEN}[1]{C_RESET} 切换为 AimiliVPN 原生内置动态家宽池 (127.0.0.1:8500)")
    print(f"  {C_GREEN}[2]{C_RESET} 配置外部第三方住宅/商业级 SOCKS5 代理落地")
    print(f"  {C_RED}[0]{C_RESET} 取消并返回")
    print("=" * 60)

    try:
        opt = input(f"{C_BOLD}请输入选项 [0-2]: {C_RESET}").strip()
    except (KeyboardInterrupt, EOFError):
        return

    if opt == "1":
        update_env_file({"RESI_EGRESS_TYPE": "local"})
        print(f"{C_GREEN}已设置为: AimiliVPN 内置动态家宽池 (127.0.0.1:8500){C_RESET}")
    elif opt == "2":
        try:
            host = input(f"请输入第三方 SOCKS5 服务器 IP 或域名 [{curr_host}]: ").strip() or curr_host
            port = input(f"请输入第三方 SOCKS5 端口 [{curr_port}]: ").strip() or curr_port
            user = input(f"请输入认证用户名 (无密码则直接回车) [{curr_user}]: ").strip()
            if not user and curr_user:
                keep = input(f"是否保留原用户名 '{curr_user}'? [Y/n]: ").strip().lower()
                if keep != 'n':
                    user = curr_user
            pwd = input("请输入认证密码 (无密码则直接回车): ").strip()
            if not pwd and curr_pass:
                keep = input("是否保留原密码? [Y/n]: ").strip().lower()
                if keep != 'n':
                    pwd = curr_pass
        except (KeyboardInterrupt, EOFError):
            print("\n已取消配置。")
            return

        update_env_file({
            "RESI_EGRESS_TYPE": "external",
            "EXTERNAL_PROXY_HOST": host,
            "EXTERNAL_PROXY_PORT": port,
            "EXTERNAL_PROXY_USER": user,
            "EXTERNAL_PROXY_PASS": pwd
        })
        print(f"{C_GREEN}已成功更新外部第三方 SOCKS5 配置: {host}:{port}{C_RESET}")
    elif opt in ["0", "q", "exit"]:
        return
    else:
        print(f"{C_RED}无效选项。{C_RESET}")
        return

    # 询问是否立刻重新生成 Sing-box 配置并热重启生效
    try:
        apply_now = input(f"{C_YELLOW}是否立即重新生成 Sing-box 配置并热重启生效？[Y/n]: {C_RESET}").strip().lower()
        if apply_now != 'n':
            setup_script = os.path.join(INSTALL_DIR, "scripts", "setup_singbox.sh")
            if os.path.exists(setup_script):
                print(f"{C_BLUE}正在执行事务快照与原子配置更新...{C_RESET}")
                subprocess.call(["bash", setup_script])
                print(f"{C_GREEN}住宅出口分流更新成功！{C_RESET}")
            else:
                print(f"{C_RED}未找到脚本: {setup_script}{C_RESET}")
    except (KeyboardInterrupt, EOFError):
        pass


def interactive_menu():
    """交互式主控制台菜单"""
    while True:
        status = get_service_statuses()
        sub = get_subscription_data()
        auth = get_web_auth_data()

        resi_mode = "第三方 SOCKS5 代理" if sub.get("resi_egress_type") == "external" else "AimiliVPN 动态家宽池 (8500)"

        print("\n" + "=" * 60)
        print(f"{C_BOLD}{C_BLUE}         🚀 AimiliVPN & Sing-box 双核心管理控制台{C_RESET}")
        print("=" * 60)
        print("【核心服务状态】")
        print(f"  AimiliVPN 住宅代理: {status['aimilivpn']}  (SOCKS5 端口: 8500)")
        print(f"  Sing-box 分流核心:  {status['singbox']}  (Reality: 443 | 住宅出口: {resi_mode})")
        print(f"  Nginx 入口转发:     {status['nginx']}  (管理: 8443 / 订阅: 18443)")
        if sub.get("direct_url") or sub.get("all_links"):
            print(f"  通用 HTTPS 订阅:    {C_BLUE}{sub['sub_url_18443']}{C_RESET}")
        print(f"  网页控制面板:       {C_BLUE}{auth['web_url']}{C_RESET}")
        print(f"  管理员账号/密码:    {C_YELLOW}{auth['username']}{C_RESET} / {C_YELLOW}{auth['password']}{C_RESET}")
        print("-" * 60)
        print(f"{C_BOLD}【快捷操作】{C_RESET}")
        print(f"  {C_GREEN}[1]{C_RESET} 查看 18 节点双栈矩阵、聚合订阅与二维码 ({C_YELLOW}ml sub{C_RESET})")
        print(f"  {C_GREEN}[2]{C_RESET} 查看网页控制面板地址与账号密码 ({C_YELLOW}ml web{C_RESET})")
        print(f"  {C_GREEN}[3]{C_RESET} 查看 AimiliVPN 运行状态 ({C_YELLOW}ml status{C_RESET})")
        print(f"  {C_GREEN}[4]{C_RESET} 重启 Sing-box 核心服务")
        print(f"  {C_GREEN}[5]{C_RESET} 重启 AimiliVPN 服务")
        print(f"  {C_GREEN}[6]{C_RESET} 查看 Sing-box 实时日志")
        print(f"  {C_GREEN}[7]{C_RESET} 查看 AimiliVPN 实时日志 ({C_YELLOW}ml logs{C_RESET})")
        print(f"  {C_GREEN}[8]{C_RESET} 重新生成 Sing-box 节点与全生态订阅")
        print(f"  {C_GREEN}[9]{C_RESET} 住宅出口路由配置 (内置Aimili池 / 外接第三方SOCKS5) ({C_YELLOW}ml egress{C_RESET})")
        print(f"  {C_GREEN}[10]{C_RESET} 全自动节点连通性与健康诊断 (排查-1超时/端口/阻断) ({C_YELLOW}ml test{C_RESET})")
        print(f"  {C_GREEN}[11]{C_RESET} Sing-box 内核版本管理 (升级最新稳定版/切换指定版本) ({C_YELLOW}ml core{C_RESET})")
        print(f"  {C_GREEN}[12]{C_RESET} 域名 SSL 证书管理 (申请/续期/ZeroSSL/Cloudflare DNS API) ({C_YELLOW}ml cert{C_RESET})")
        print(f"  {C_GREEN}[13]{C_RESET} Cloudflare Argo 隧道穿透 (免CF账号临时穿透/固定Token) ({C_YELLOW}ml argo{C_RESET})")
        print(f"  {C_GREEN}[14]{C_RESET} Cloudflare WARP 双栈自适应解锁 (Native WireGuard) ({C_YELLOW}ml warp{C_RESET})")
        print(f"  {C_GREEN}[15]{C_RESET} Cloudflare CDN 三网优选 IP 测速与替换 ({C_YELLOW}ml cf{C_RESET})")
        print(f"  {C_GREEN}[16]{C_RESET} HTML5 本地高保真伪装网站模版库切换 ({C_YELLOW}ml camo{C_RESET})")
        print(f"  {C_GREEN}[17]{C_RESET} Telegram Bot 节点与告警即时推送 ({C_YELLOW}ml tg{C_RESET})")
        print(f"  {C_GREEN}[18]{C_RESET} 定时系统自愈与内存深度清理管理 ({C_YELLOW}ml cron{C_RESET})")
        print(f"  {C_GREEN}[19]{C_RESET} 📖 Cloudflare DNS 双栈解析与子域名傻瓜向导 ({C_YELLOW}ml dns{C_RESET})")
        print(f"  {C_GREEN}[20]{C_RESET} 📱 独立打印手机扫码二维码 ({C_YELLOW}ml qr{C_RESET})")
        print(f"  {C_GREEN}[21]{C_RESET} 🔄 检查脚本更新与智能平滑升级 ({C_YELLOW}ml update{C_RESET})")
        print(f"  {C_GREEN}[22]{C_RESET} ⚙️  原生底层管理菜单 (修改密码/端口/卸载等)")
        print(f"  {C_RED}[0]{C_RESET} 退出控制台")
        print("=" * 60)

        try:
            choice = input(f"{C_BOLD}请选择操作 [0-22]: {C_RESET}").strip()
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
            configure_residential_egress()
            input(f"\n{C_BLUE}按回车键返回菜单...{C_RESET}")
        elif choice == "10":
            diag_script = os.path.join(INSTALL_DIR, "scripts", "check_health.sh")
            if os.path.exists(diag_script):
                subprocess.call(["bash", diag_script])
            else:
                print(f"{C_RED}未找到诊断脚本: {diag_script}{C_RESET}")
            input(f"\n{C_BLUE}按回车键返回菜单...{C_RESET}")
        elif choice == "11":
            core_script = os.path.join(INSTALL_DIR, "scripts", "manage_core.sh")
            if os.path.exists(core_script):
                subprocess.call(["bash", core_script])
            else:
                print(f"{C_RED}未找到核心管理脚本: {core_script}{C_RESET}")
            input(f"\n{C_BLUE}按回车键返回菜单...{C_RESET}")
        elif choice == "12":
            cert_script = os.path.join(INSTALL_DIR, "scripts", "manage_cert.sh")
            if os.path.exists(cert_script):
                subprocess.call(["bash", cert_script])
            else:
                print(f"{C_RED}未找到证书管理脚本: {cert_script}{C_RESET}")
            input(f"\n{C_BLUE}按回车键返回菜单...{C_RESET}")
        elif choice == "13":
            argo_script = os.path.join(INSTALL_DIR, "scripts", "setup_argo.sh")
            if os.path.exists(argo_script):
                subprocess.call(["bash", argo_script])
            else:
                print(f"{C_RED}未找到 Argo 脚本: {argo_script}{C_RESET}")
            input(f"\n{C_BLUE}按回车键返回菜单...{C_RESET}")
        elif choice == "14":
            warp_script = os.path.join(INSTALL_DIR, "scripts", "setup_warp.sh")
            if os.path.exists(warp_script):
                subprocess.call(["bash", warp_script])
            else:
                print(f"{C_RED}未找到 WARP 脚本: {warp_script}{C_RESET}")
            input(f"\n{C_BLUE}按回车键返回菜单...{C_RESET}")
        elif choice == "15":
            cf_script = os.path.join(INSTALL_DIR, "scripts", "cf_speedtest.sh")
            if os.path.exists(cf_script):
                subprocess.call(["bash", cf_script])
            else:
                print(f"{C_RED}未找到优选测速脚本: {cf_script}{C_RESET}")
            input(f"\n{C_BLUE}按回车键返回菜单...{C_RESET}")
        elif choice == "16":
            camo_script = os.path.join(INSTALL_DIR, "scripts", "setup_camouflage.sh")
            if os.path.exists(camo_script):
                subprocess.call(["bash", camo_script])
            else:
                print(f"{C_RED}未找到伪装网站脚本: {camo_script}{C_RESET}")
            input(f"\n{C_BLUE}按回车键返回菜单...{C_RESET}")
        elif choice == "17":
            tg_script = os.path.join(INSTALL_DIR, "scripts", "tg_bot.sh")
            if os.path.exists(tg_script):
                subprocess.call(["bash", tg_script])
            else:
                print(f"{C_RED}未找到 TG Bot 脚本: {tg_script}{C_RESET}")
            input(f"\n{C_BLUE}按回车键返回菜单...{C_RESET}")
        elif choice == "18":
            cron_script = os.path.join(INSTALL_DIR, "scripts", "setup_cron.sh")
            if os.path.exists(cron_script):
                subprocess.call(["bash", cron_script])
            else:
                print(f"{C_RED}未找到定时维护脚本: {cron_script}{C_RESET}")
            input(f"\n{C_BLUE}按回车键返回菜单...{C_RESET}")
        elif choice == "19":
            cf_script = os.path.join(INSTALL_DIR, "scripts", "cf_speedtest.sh")
            if os.path.exists(cf_script):
                subprocess.call(["bash", cf_script, "guide"])
            else:
                print(f"{C_RED}未找到脚本: {cf_script}{C_RESET}")
            input(f"\n{C_BLUE}按回车键返回菜单...{C_RESET}")
        elif choice == "20":
            sub = get_subscription_data()
            print_terminal_qr(sub["sub_url_18443"], "全生态聚合订阅二维码 (手机扫码一键导入)")
            if sub["all_links"]:
                direct_url = sub["direct_links"][0] if sub["direct_links"] else sub["all_links"][0]
                print_terminal_qr(direct_url, "极速原生 Reality 单节点二维码")
            input(f"\n{C_BLUE}按回车键返回菜单...{C_RESET}")
        elif choice == "21":
            upgrade_script = os.path.join(INSTALL_DIR, "scripts", "upgrade_script.sh")
            if os.path.exists(upgrade_script):
                subprocess.call(["bash", upgrade_script])
            else:
                print(f"{C_RED}未找到升级脚本: {upgrade_script}{C_RESET}")
            input(f"\n{C_BLUE}按回车键返回菜单...{C_RESET}")
        elif choice == "22":
            call_aimili_ml([])
            break
        elif choice in ["0", "q", "quit", "exit"]:
            print("已退出控制台。")
            break
        else:
            print(f"{C_RED}无效选项，请输入 0 到 22 之间的数字。{C_RESET}")


def main():
    if len(sys.argv) > 1:
        cmd = sys.argv[1].lower()
        if cmd in ["update", "upgrade", "pull", "sync"]:
            upgrade_script = os.path.join(INSTALL_DIR, "scripts", "upgrade_script.sh")
            if os.path.exists(upgrade_script):
                subprocess.call(["bash", upgrade_script])
            else:
                print(f"{C_RED}未找到升级脚本: {upgrade_script}{C_RESET}")
            return
        elif cmd in ["sub", "subs", "subscription", "subscribe", "node", "nodes", "link", "links"]:
            print_subscription_card()
            return
        elif cmd in ["qr", "qrcode"]:
            sub = get_subscription_data()
            print_terminal_qr(sub["sub_url_18443"], "全生态聚合订阅二维码 (手机扫码一键导入)")
            if sub["all_links"]:
                direct_url = sub["direct_links"][0] if sub["direct_links"] else sub["all_links"][0]
                print_terminal_qr(direct_url, "极速原生 Reality 单节点二维码")
            return
        elif cmd in ["web", "ui", "panel", "admin", "dashboard"]:
            print_web_dashboard()
            return
        elif cmd in ["egress", "proxy", "socks5", "resi"]:
            configure_residential_egress()
            return
        elif cmd in ["test", "check", "diag", "doctor", "health"]:
            diag_script = os.path.join(INSTALL_DIR, "scripts", "check_health.sh")
            if os.path.exists(diag_script):
                subprocess.call(["bash", diag_script])
            else:
                print(f"{C_RED}未找到诊断脚本: {diag_script}{C_RESET}")
            return
        elif cmd in ["core", "upgrade-core", "update-core", "kernel"]:
            core_script = os.path.join(INSTALL_DIR, "scripts", "manage_core.sh")
            if os.path.exists(core_script):
                args = sys.argv[2:] if len(sys.argv) > 2 else []
                subprocess.call(["bash", core_script] + args)
            else:
                print(f"{C_RED}未找到核心管理脚本: {core_script}{C_RESET}")
            return
        elif cmd in ["cert", "ssl", "tls", "acme", "certificate"]:
            cert_script = os.path.join(INSTALL_DIR, "scripts", "manage_cert.sh")
            if os.path.exists(cert_script):
                args = sys.argv[2:] if len(sys.argv) > 2 else []
                subprocess.call(["bash", cert_script] + args)
            else:
                print(f"{C_RED}未找到证书管理脚本: {cert_script}{C_RESET}")
            return
        elif cmd in ["argo", "tunnel", "trycloudflare"]:
            argo_script = os.path.join(INSTALL_DIR, "scripts", "setup_argo.sh")
            if os.path.exists(argo_script):
                args = sys.argv[2:] if len(sys.argv) > 2 else []
                subprocess.call(["bash", argo_script] + args)
            else:
                print(f"{C_RED}未找到 Argo 脚本: {argo_script}{C_RESET}")
            return
        elif cmd in ["warp", "wireguard", "stream", "unlock"]:
            warp_script = os.path.join(INSTALL_DIR, "scripts", "setup_warp.sh")
            if os.path.exists(warp_script):
                args = sys.argv[2:] if len(sys.argv) > 2 else []
                subprocess.call(["bash", warp_script] + args)
            else:
                print(f"{C_RED}未找到 WARP 脚本: {warp_script}{C_RESET}")
            return
        elif cmd in ["cf", "speedtest", "cleanip", "anycast"]:
            cf_script = os.path.join(INSTALL_DIR, "scripts", "cf_speedtest.sh")
            if os.path.exists(cf_script):
                args = sys.argv[2:] if len(sys.argv) > 2 else []
                subprocess.call(["bash", cf_script] + args)
            else:
                print(f"{C_RED}未找到优选测速脚本: {cf_script}{C_RESET}")
            return
        elif cmd in ["camo", "camouflage", "template", "fake"]:
            camo_script = os.path.join(INSTALL_DIR, "scripts", "setup_camouflage.sh")
            if os.path.exists(camo_script):
                args = sys.argv[2:] if len(sys.argv) > 2 else []
                subprocess.call(["bash", camo_script] + args)
            else:
                print(f"{C_RED}未找到伪装网站脚本: {camo_script}{C_RESET}")
            return
        elif cmd in ["tg", "telegram", "bot", "notify"]:
            tg_script = os.path.join(INSTALL_DIR, "scripts", "tg_bot.sh")
            if os.path.exists(tg_script):
                args = sys.argv[2:] if len(sys.argv) > 2 else []
                subprocess.call(["bash", tg_script] + args)
            else:
                print(f"{C_RED}未找到 TG Bot 脚本: {tg_script}{C_RESET}")
            return
        elif cmd in ["cron", "auto", "maintenance", "watchdog"]:
            cron_script = os.path.join(INSTALL_DIR, "scripts", "setup_cron.sh")
            if os.path.exists(cron_script):
                args = sys.argv[2:] if len(sys.argv) > 2 else []
                subprocess.call(["bash", cron_script] + args)
            else:
                print(f"{C_RED}未找到定时维护脚本: {cron_script}{C_RESET}")
            return
        elif cmd in ["dns", "dualstack", "guide"]:
            cf_script = os.path.join(INSTALL_DIR, "scripts", "cf_speedtest.sh")
            if os.path.exists(cf_script):
                subprocess.call(["bash", cf_script, "guide"])
            else:
                print(f"{C_RED}未找到脚本: {cf_script}{C_RESET}")
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
                print("可用 singbox 子命令: status, start, stop, restart, logs, setup")
            return
        elif cmd == "status":
            call_aimili_ml(["status"])
            sub = get_subscription_data()
            auth = get_web_auth_data()
            if sub.get("direct_url") or sub.get("all_links"):
                print(f"\n{C_GREEN}【Sing-box 订阅与全协议矩阵就绪】{C_RESET}")
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
