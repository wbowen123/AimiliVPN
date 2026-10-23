#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ==============================================================================
# AimiliVPN 全协议与双栈多出站订阅生成引擎 (Base64 / Clash Meta / Sing-box / Plaintext)
# 支持 IPv4/IPv6 双栈 × 3 种出口模式 (原生极速直连 + Aimili动态家宽 + Cloudflare CDN/Argo)
# ==============================================================================
import base64
import json
import os
import sys
import urllib.parse

def generate_subscriptions(nodes_data, output_dir):
    os.makedirs(output_dir, exist_ok=True)
    data_dir_path = nodes_data.get("data_dir", "/opt/aimilivpn/vpngate_data")

    public_ip = nodes_data.get("public_ip", "127.0.0.1")
    
    # 自动探测或读取 IPv6
    public_ipv6 = nodes_data.get("public_ipv6", "")
    if not public_ipv6:
        ipv6_file = os.path.join(data_dir_path, "public_ipv6.txt")
        if os.path.exists(ipv6_file):
            try:
                with open(ipv6_file, "r", encoding="utf-8") as f:
                    ip6 = f.read().strip()
                    if ":" in ip6 and len(ip6) > 4:
                        public_ipv6 = ip6
            except Exception:
                pass

    domain = nodes_data.get("domain", "")
    
    # --------------------------------------------------------------------------
    # 0. 双栈 DNS 物理隔离智能解析 (架构推荐最佳实践):
    # 规范: direct 走真实 IP (关小黄云跑满千兆), cdn 走 CDN 破墙 (开小黄云破局免流)
    # --------------------------------------------------------------------------
    direct_host = domain if domain else public_ip
    cdn_host = ""
    explicit_cdn = nodes_data.get("cdn_domain") or nodes_data.get("cf_cdn_host", "")
    if explicit_cdn:
        cdn_host = explicit_cdn.strip()
    elif domain:
        clean_d = domain.lower()
        if clean_d.startswith("direct."):
            base_d = clean_d[7:]
            direct_host = clean_d
            cand_cdn = f"cdn.{base_d}"
            try:
                import socket
                socket.gethostbyname(cand_cdn)
                cdn_host = cand_cdn
            except Exception:
                cdn_host = ""
                print(f"  [!] 提示: 检测到 direct. 域名 {clean_d}，但 {cand_cdn} 尚未配置 DNS 解析，跳过 CDN 节点生成。")
        elif clean_d.startswith("cdn."):
            base_d = clean_d[4:]
            cand_direct = f"direct.{base_d}"
            try:
                import socket
                socket.gethostbyname(cand_direct)
                direct_host = cand_direct
            except Exception:
                direct_host = clean_d
            cdn_host = clean_d
        else:
            cand_direct = f"direct.{clean_d}"
            cand_cdn = f"cdn.{clean_d}"
            try:
                import socket
                socket.gethostbyname(cand_direct)
                direct_host = cand_direct
            except Exception:
                direct_host = domain
            try:
                import socket
                socket.gethostbyname(cand_cdn)
                cdn_host = cand_cdn
            except Exception:
                cdn_host = ""
                print(f"  [!] 提示: 检测到域名 {domain}，但 {cand_cdn} 尚未配置 DNS 解析，跳过 CDN 节点生成（如需 CDN 节点，请在 Cloudflare 添加 {cand_cdn} 解析并开启小黄云）。")

    host = direct_host if direct_host else public_ip
    camouflage_sni = nodes_data.get("camouflage_domain", "gateway.icloud.com")
    public_key = nodes_data.get("public_key", "")
    short_id = nodes_data.get("short_id", "")
    direct_uuid = nodes_data.get("direct_uuid", "")
    resi_uuid = nodes_data.get("resi_uuid", "")

    # 端口分配与混淆加固
    vless_port = nodes_data.get("vless_port", 443)
    hy2_port = nodes_data.get("hy2_port", 443)
    hy2_obfs = nodes_data.get("hy2_obfs", "")
    hy2_hop_ports = nodes_data.get("hy2_hop_ports", "443,40000-50000")
    tuic_port = nodes_data.get("tuic_port", 8443)
    anytls_port = nodes_data.get("anytls_port", 8444)
    vmess_port = nodes_data.get("vmess_port", 8445)

    # 读取 Cloudflare 优选 IP (仅作用于 CDN 节点)
    clean_ip = "104.16.160.10"
    clean_file = os.path.join(data_dir_path, "cf_clean_ip.txt")
    if os.path.exists(clean_file):
        try:
            with open(clean_file, "r", encoding="utf-8") as cff:
                c = cff.read().strip()
                if c:
                    clean_ip = c
        except Exception:
            pass

    # 读取 Cloudflare 优选 IPv6 (作用于 IPv6 CDN 节点)
    cf_ipv6_clean = "2606:4700::6810:a00a"
    clean_v6_file = os.path.join(data_dir_path, "cf_clean_ipv6.txt")
    if os.path.exists(clean_v6_file):
        try:
            with open(clean_v6_file, "r", encoding="utf-8") as cv6f:
                cv6 = cv6f.read().strip()
                if ":" in cv6:
                    cf_ipv6_clean = cv6
        except Exception:
            pass

    # 读取 Argo 隧道配置
    argo_domain = nodes_data.get("argo_domain", "")
    if not argo_domain:
        argo_file = os.path.join(data_dir_path, "argo_info.json")
        if os.path.exists(argo_file):
            try:
                with open(argo_file, "r", encoding="utf-8") as af:
                    argo_data = json.load(af)
                    argo_domain = argo_data.get("domain", "")
            except Exception:
                pass

    # --------------------------------------------------------------------------
    # 1. 节点名称规范体系 (出站属性 + 协议 + 传输特征 + 网络协议栈)
    # --------------------------------------------------------------------------
    node_names = {
        # IPv4 原生直连
        "vless_direct_v4": "🚀 [直连-极速·IPv4] VLESS-Reality【TCP-Vision·原生千兆】",
        "vless_resi_v4":   "🏠 [住宅-家宽·IPv4] VLESS-Reality【TCP-Vision·Aimili动态家宽】",
        "hy2_direct_v4":   "🌪️ [直连-极速·IPv4] Hysteria 2【H3-UDP-Brutal·暴力抗丢包】",
        "hy2_resi_v4":     "🏘️ [住宅-家宽·IPv4] Hysteria 2【H3-UDP-Brutal·恶劣线路家宽加速】",
        "tuic_direct_v4":  "⚡ [直连-极速·IPv4] TUIC v5【H3-QUIC-0RTT·秒开首选】",
        "tuic_resi_v4":    "🏡 [住宅-家宽·IPv4] TUIC v5【H3-QUIC-0RTT·晚高峰家宽流媒体】",
        "anytls_direct_v4":"🛡️ [直连-极速·IPv4] AnyTLS【TCP-Padding·动态包长防探测】",
        "anytls_resi_v4":  "🌐 [住宅-家宽·IPv4] AnyTLS【TCP-Padding·特征防探测家宽】",
        "vmess_direct_v4": "☁️ [直连-极速·IPv4] VMess-xHTTP【H2/H3-分块·分段防审查】",
        "vmess_resi_v4":   "🛋️ [住宅-家宽·IPv4] VMess-xHTTP【H2/H3-分块·动态家宽流】",
        # IPv6 原生直连 (若检测到 IPv6)
        "vless_direct_v6": "🚀 [直连-极速·IPv6] VLESS-Reality【TCP-Vision·原生IPv6】",
        "hy2_direct_v6":   "🌪️ [直连-极速·IPv6] Hysteria 2【H3-UDP-Brutal·IPv6暴力加速】",
        "tuic_direct_v6":  "⚡ [直连-极速·IPv6] TUIC v5【H3-QUIC-0RTT·IPv6秒开】",
        "vmess_direct_v6": "☁️ [直连-极速·IPv6] VMess-xHTTP【H2/H3-分块·原生IPv6】",
        # Cloudflare CDN / Argo 穿透节点 (明确标注优选 IP 赋能)
        "vmess_argo_v4":   "⛅ [CDN-优选IP·IPv4] VMess-xHTTP-Argo【Anycast优选·Cloudflare全球破墙】",
        "vmess_cdn_v4":    "⛅ [CDN-小黄云·IPv4] VMess-xHTTP【Cloudflare-CDN·分块免流破墙】",
        "vless_cdn_v4":    "⛅ [CDN-小黄云·IPv4] VMess-WS-TLS【Cloudflare-CDN·小黄云破墙】",
        "vmess_cdn_v6":    "⛅ [CDN-小黄云·IPv6] VMess-xHTTP【Cloudflare-CDN-IPv6·分块穿透】"
    }

    links = []
    clash_proxies = []

    # ==========================================================================
    # A. 生成标准 IPv4 原生直连与住宅节点
    # ==========================================================================

    # A1. VLESS Reality IPv4
    vless_d_v4 = f"vless://{direct_uuid}@{public_ip}:{vless_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni={camouflage_sni}&fp=chrome&pbk={public_key}&sid={short_id}&type=tcp#{urllib.parse.quote(node_names['vless_direct_v4'])}"
    vless_r_v4 = f"vless://{resi_uuid}@{public_ip}:{vless_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni={camouflage_sni}&fp=chrome&pbk={public_key}&sid={short_id}&type=tcp#{urllib.parse.quote(node_names['vless_resi_v4'])}"
    links.extend([vless_d_v4, vless_r_v4])

    clash_proxies.append({
        "name": node_names["vless_direct_v4"], "type": "vless", "server": public_ip, "port": vless_port,
        "uuid": direct_uuid, "network": "tcp", "tls": True, "udp": True, "flow": "xtls-rprx-vision",
        "servername": camouflage_sni, "reality-opts": {"public-key": public_key, "short-id": short_id},
        "client-fingerprint": "chrome"
    })
    clash_proxies.append({
        "name": node_names["vless_resi_v4"], "type": "vless", "server": public_ip, "port": vless_port,
        "uuid": resi_uuid, "network": "tcp", "tls": True, "udp": True, "flow": "xtls-rprx-vision",
        "servername": camouflage_sni, "reality-opts": {"public-key": public_key, "short-id": short_id},
        "client-fingerprint": "chrome"
    })

    # A2. Hysteria 2 IPv4
    sni_param = f"&sni={domain}" if domain else f"&sni={camouflage_sni}&insecure=1"
    obfs_param = f"&obfs=salamander&obfs-password={urllib.parse.quote(hy2_obfs)}" if hy2_obfs else ""
    mport_val = hy2_hop_ports if hy2_hop_ports else hy2_port
    hy2_d_v4 = f"hysteria2://{direct_uuid}@{public_ip}:{hy2_port}?mport={mport_val}{sni_param}{obfs_param}#{urllib.parse.quote(node_names['hy2_direct_v4'])}"
    hy2_r_v4 = f"hysteria2://{resi_uuid}@{public_ip}:{hy2_port}?mport={mport_val}{sni_param}{obfs_param}#{urllib.parse.quote(node_names['hy2_resi_v4'])}"
    links.extend([hy2_d_v4, hy2_r_v4])

    hy2_p_d = {
        "name": node_names["hy2_direct_v4"], "type": "hysteria2", "server": public_ip, "port": hy2_port,
        "password": direct_uuid, "sni": domain if domain else camouflage_sni, "skip-cert-verify": bool(not domain)
    }
    hy2_p_r = {
        "name": node_names["hy2_resi_v4"], "type": "hysteria2", "server": public_ip, "port": hy2_port,
        "password": resi_uuid, "sni": domain if domain else camouflage_sni, "skip-cert-verify": bool(not domain)
    }
    if hy2_hop_ports:
        hy2_p_d["ports"] = str(hy2_hop_ports)
        hy2_p_r["ports"] = str(hy2_hop_ports)
    if hy2_obfs:
        hy2_p_d["obfs"] = "salamander"; hy2_p_d["obfs-password"] = hy2_obfs
        hy2_p_r["obfs"] = "salamander"; hy2_p_r["obfs-password"] = hy2_obfs
    clash_proxies.extend([hy2_p_d, hy2_p_r])

    # A3. TUIC v5 IPv4
    tuic_sni = domain if domain else camouflage_sni
    insec_flag = "0" if domain else "1"
    tuic_d_v4 = f"tuic://{direct_uuid}:{short_id}@{public_ip}:{tuic_port}?congestion_control=bbr&alpn=h3&sni={tuic_sni}&allow_insecure={insec_flag}#{urllib.parse.quote(node_names['tuic_direct_v4'])}"
    tuic_r_v4 = f"tuic://{resi_uuid}:{short_id}@{public_ip}:{tuic_port}?congestion_control=bbr&alpn=h3&sni={tuic_sni}&allow_insecure={insec_flag}#{urllib.parse.quote(node_names['tuic_resi_v4'])}"
    links.extend([tuic_d_v4, tuic_r_v4])

    clash_proxies.append({
        "name": node_names["tuic_direct_v4"], "type": "tuic", "server": public_ip, "port": tuic_port,
        "uuid": direct_uuid, "password": short_id, "alpn": ["h3"], "congestion-controller": "bbr",
        "sni": tuic_sni, "skip-cert-verify": bool(not domain)
    })
    clash_proxies.append({
        "name": node_names["tuic_resi_v4"], "type": "tuic", "server": public_ip, "port": tuic_port,
        "uuid": resi_uuid, "password": short_id, "alpn": ["h3"], "congestion-controller": "bbr",
        "sni": tuic_sni, "skip-cert-verify": bool(not domain)
    })

    # A4. AnyTLS IPv4 (仅在服务端开启 AnyTLS 监听时生成)
    if anytls_port and int(anytls_port) > 0:
        anytls_d_v4 = f"anytls://{direct_uuid}@{public_ip}:{anytls_port}?sni={tuic_sni}&insecure={insec_flag}#{urllib.parse.quote(node_names['anytls_direct_v4'])}"
        anytls_r_v4 = f"anytls://{resi_uuid}@{public_ip}:{anytls_port}?sni={tuic_sni}&insecure={insec_flag}#{urllib.parse.quote(node_names['anytls_resi_v4'])}"
        links.extend([anytls_d_v4, anytls_r_v4])

    # A5. VMess xHTTP IPv4 (直连 8445 明文传输，由 VMess AEAD 内部加密)
    vmess_obj_d_v4 = {
        "v": "2", "ps": node_names["vmess_direct_v4"], "add": public_ip, "port": vmess_port,
        "id": direct_uuid, "aid": 0, "net": "http", "type": "none", "host": host,
        "path": "/vmess", "tls": ""
    }
    vmess_obj_r_v4 = {
        "v": "2", "ps": node_names["vmess_resi_v4"], "add": public_ip, "port": vmess_port,
        "id": resi_uuid, "aid": 0, "net": "http", "type": "none", "host": host,
        "path": "/vmess", "tls": ""
    }
    links.append("vmess://" + base64.b64encode(json.dumps(vmess_obj_d_v4).encode("utf-8")).decode("utf-8"))
    links.append("vmess://" + base64.b64encode(json.dumps(vmess_obj_r_v4).encode("utf-8")).decode("utf-8"))

    clash_proxies.append({
        "name": node_names["vmess_direct_v4"], "type": "vmess", "server": public_ip, "port": vmess_port,
        "uuid": direct_uuid, "alterId": 0, "cipher": "auto", "network": "http",
        "http-opts": {"path": ["/vmess"], "headers": {"Host": [host]}}, "tls": False, "skip-cert-verify": False
    })
    clash_proxies.append({
        "name": node_names["vmess_resi_v4"], "type": "vmess", "server": public_ip, "port": vmess_port,
        "uuid": resi_uuid, "alterId": 0, "cipher": "auto", "network": "http",
        "http-opts": {"path": ["/vmess"], "headers": {"Host": [host]}}, "tls": False, "skip-cert-verify": False
    })

    # ==========================================================================
    # B. 生成 IPv6 原生直连节点 (若宿主机存在 IPv6)
    # ==========================================================================
    if public_ipv6:
        ip6_url_host = f"[{public_ipv6}]"

        # B1. VLESS Reality IPv6
        vless_d_v6 = f"vless://{direct_uuid}@{ip6_url_host}:{vless_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni={camouflage_sni}&fp=chrome&pbk={public_key}&sid={short_id}&type=tcp#{urllib.parse.quote(node_names['vless_direct_v6'])}"
        links.append(vless_d_v6)
        clash_proxies.append({
            "name": node_names["vless_direct_v6"], "type": "vless", "server": public_ipv6, "port": vless_port,
            "uuid": direct_uuid, "network": "tcp", "tls": True, "udp": True, "flow": "xtls-rprx-vision",
            "servername": camouflage_sni, "reality-opts": {"public-key": public_key, "short-id": short_id},
            "client-fingerprint": "chrome"
        })

        # B2. Hysteria 2 IPv6
        hy2_d_v6 = f"hysteria2://{direct_uuid}@{ip6_url_host}:{hy2_port}?mport={mport_val}{sni_param}{obfs_param}#{urllib.parse.quote(node_names['hy2_direct_v6'])}"
        links.append(hy2_d_v6)
        hy2_p_d_v6 = {
            "name": node_names["hy2_direct_v6"], "type": "hysteria2", "server": public_ipv6, "port": hy2_port,
            "password": direct_uuid, "sni": domain if domain else camouflage_sni, "skip-cert-verify": bool(not domain)
        }
        if hy2_hop_ports: hy2_p_d_v6["ports"] = str(hy2_hop_ports)
        if hy2_obfs: hy2_p_d_v6["obfs"] = "salamander"; hy2_p_d_v6["obfs-password"] = hy2_obfs
        clash_proxies.append(hy2_p_d_v6)

        # B3. TUIC v5 IPv6
        tuic_d_v6 = f"tuic://{direct_uuid}:{short_id}@{ip6_url_host}:{tuic_port}?congestion_control=bbr&alpn=h3&sni={tuic_sni}&allow_insecure={insec_flag}#{urllib.parse.quote(node_names['tuic_direct_v6'])}"
        links.append(tuic_d_v6)
        clash_proxies.append({
            "name": node_names["tuic_direct_v6"], "type": "tuic", "server": public_ipv6, "port": tuic_port,
            "uuid": direct_uuid, "password": short_id, "alpn": ["h3"], "congestion-controller": "bbr",
            "sni": tuic_sni, "skip-cert-verify": bool(not domain)
        })

        # B4. VMess xHTTP IPv6 (直连 8445 明文传输，由 VMess AEAD 内部加密)
        vmess_obj_d_v6 = {
            "v": "2", "ps": node_names["vmess_direct_v6"], "add": public_ipv6, "port": vmess_port,
            "id": direct_uuid, "aid": 0, "net": "http", "type": "none", "host": host,
            "path": "/vmess", "tls": ""
        }
        links.append("vmess://" + base64.b64encode(json.dumps(vmess_obj_d_v6).encode("utf-8")).decode("utf-8"))
        clash_proxies.append({
            "name": node_names["vmess_direct_v6"], "type": "vmess", "server": public_ipv6, "port": vmess_port,
            "uuid": direct_uuid, "alterId": 0, "cipher": "auto", "network": "http",
            "http-opts": {"path": ["/vmess"], "headers": {"Host": [host]}}, "tls": False, "skip-cert-verify": False
        })

    # ==========================================================================
    # C. 生成 Cloudflare CDN 与 Argo 穿透节点 (注入 Anycast 优选 IP)
    # ==========================================================================
    # C1. VMess-Argo (仅当配置了 Argo 隧道公网域名时激活，直通本地 8445 HTTP)
    if argo_domain:
        vmess_argo_obj = {
            "v": "2", "ps": node_names["vmess_argo_v4"], "add": clean_ip, "port": 443,
            "id": direct_uuid, "aid": 0, "net": "http", "type": "none",
            "host": argo_domain, "path": "/vmess", "tls": "tls", "sni": argo_domain
        }
        links.append("vmess://" + base64.b64encode(json.dumps(vmess_argo_obj).encode("utf-8")).decode("utf-8"))
        clash_proxies.append({
            "name": node_names["vmess_argo_v4"], "type": "vmess", "server": clean_ip, "port": 443,
            "uuid": direct_uuid, "alterId": 0, "cipher": "auto", "network": "http",
            "http-opts": {"path": ["/vmess"], "headers": {"Host": [argo_domain]}},
            "tls": True, "servername": argo_domain, "skip-cert-verify": False
        })

    # C2, C3, C4: Cloudflare CDN 小黄云代理节点 (严格使用 cdn_host，严禁被 argo_domain 或主域名污染)
    cf_cdn_host = cdn_host
    if cf_cdn_host:
        # C2. VMess-xHTTP CDN (开启小黄云，走 Cloudflare 8443 HTTPS 代理并经 Nginx 转发至 8445)
        vmess_cdn_obj = {
            "v": "2", "ps": node_names["vmess_cdn_v4"], "add": clean_ip, "port": 8443,
            "id": direct_uuid, "aid": 0, "net": "http", "type": "none",
            "host": cf_cdn_host, "path": "/vmess", "tls": "tls", "sni": cf_cdn_host
        }
        links.append("vmess://" + base64.b64encode(json.dumps(vmess_cdn_obj).encode("utf-8")).decode("utf-8"))
        clash_proxies.append({
            "name": node_names["vmess_cdn_v4"], "type": "vmess", "server": clean_ip, "port": 8443,
            "uuid": direct_uuid, "alterId": 0, "cipher": "auto", "network": "http",
            "http-opts": {"path": ["/vmess"], "headers": {"Host": [cf_cdn_host]}},
            "tls": True, "servername": cf_cdn_host, "skip-cert-verify": False
        })

        # C3. VMess-WS-TLS CDN (小黄云 WebSocket 转发至 8446，严格对齐服务端 VMess 协议)
        vmess_ws_cdn_obj = {
            "v": "2", "ps": node_names["vless_cdn_v4"], "add": clean_ip, "port": 8443,
            "id": direct_uuid, "aid": 0, "net": "ws", "type": "none",
            "host": cf_cdn_host, "path": "/vmess-ws", "tls": "tls", "sni": cf_cdn_host
        }
        links.append("vmess://" + base64.b64encode(json.dumps(vmess_ws_cdn_obj).encode("utf-8")).decode("utf-8"))
        clash_proxies.append({
            "name": node_names["vless_cdn_v4"], "type": "vmess", "server": clean_ip, "port": 8443,
            "uuid": direct_uuid, "alterId": 0, "cipher": "auto", "network": "ws",
            "ws-opts": {"path": "/vmess-ws", "headers": {"Host": cf_cdn_host}},
            "tls": True, "servername": cf_cdn_host, "skip-cert-verify": False
        })

        # C4. IPv6 CDN 节点 (Cloudflare Anycast IPv6 优选)
        if public_ipv6:
            vmess_cdn_v6_obj = {
                "v": "2", "ps": node_names["vmess_cdn_v6"], "add": cf_ipv6_clean, "port": 8443,
                "id": direct_uuid, "aid": 0, "net": "http", "type": "none",
                "host": cf_cdn_host, "path": "/vmess", "tls": "tls", "sni": cf_cdn_host
            }
            links.append("vmess://" + base64.b64encode(json.dumps(vmess_cdn_v6_obj).encode("utf-8")).decode("utf-8"))
            clash_proxies.append({
                "name": node_names["vmess_cdn_v6"], "type": "vmess", "server": cf_ipv6_clean, "port": 8443,
                "uuid": direct_uuid, "alterId": 0, "cipher": "auto", "network": "http",
                "http-opts": {"path": ["/vmess"], "headers": {"Host": [cf_cdn_host]}},
                "tls": True, "servername": cf_cdn_host, "skip-cert-verify": False
            })

    # --------------------------------------------------------------------------
    # 2. 输出 Base64 订阅文件 (sub.txt) 与 明文列表 (nodes.txt)
    # --------------------------------------------------------------------------
    raw_sub_text = "\n".join(links) + "\n"
    b64_sub_content = base64.b64encode(raw_sub_text.encode("utf-8")).decode("utf-8")

    with open(os.path.join(output_dir, "sub.txt"), "w", encoding="utf-8") as f:
        f.write(b64_sub_content)

    with open(os.path.join(output_dir, "nodes.txt"), "w", encoding="utf-8") as f:
        f.write(raw_sub_text)

    # 同步写入一份 nodes.txt 到 data_dir 便于本地 CLI 与脚本直接消费
    if os.path.isdir(data_dir_path) and os.path.abspath(data_dir_path) != os.path.abspath(output_dir):
        try:
            with open(os.path.join(data_dir_path, "nodes.txt"), "w", encoding="utf-8") as f:
                f.write(raw_sub_text)
        except Exception:
            pass

    # --------------------------------------------------------------------------
    # 3. 输出 Clash Meta / Mihomo 格式订阅 (clash.yaml)
    # --------------------------------------------------------------------------
    clash_direct_names = [p["name"] for p in clash_proxies if "直连" in p["name"]]
    clash_resi_names = [p["name"] for p in clash_proxies if "住宅" in p["name"]]
    clash_cdn_names = [p["name"] for p in clash_proxies if "CDN" in p["name"]]
    clash_tcp_names = [p["name"] for p in clash_proxies if "Reality" in p["name"] or "AnyTLS" in p["name"] or "VMess" in p["name"]]
    clash_all_names = [p["name"] for p in clash_proxies]

    proxy_groups = [
        {
            "name": "🚀 极速原生 (自动优选)",
            "type": "url-test",
            "proxies": clash_direct_names if clash_direct_names else clash_all_names,
            "url": "http://www.gstatic.com/generate_204",
            "interval": 300,
            "tolerance": 50
        },
        {
            "name": "🛡️ 晚高峰抗QoS (TCP优先)",
            "type": "url-test",
            "proxies": clash_tcp_names if clash_tcp_names else clash_all_names,
            "url": "http://www.gstatic.com/generate_204",
            "interval": 300,
            "tolerance": 50
        },
        {
            "name": "🏠 住宅家宽 (自动优选)",
            "type": "url-test",
            "proxies": clash_resi_names if clash_resi_names else clash_all_names,
            "url": "http://www.gstatic.com/generate_204",
            "interval": 300,
            "tolerance": 50
        }
    ]

    if clash_cdn_names:
        proxy_groups.append({
            "name": "⛅ CDN破墙 (自动优选)",
            "type": "url-test",
            "proxies": clash_cdn_names,
            "url": "http://www.gstatic.com/generate_204",
            "interval": 300,
            "tolerance": 50
        })

    group_select_candidates = ["🚀 极速原生 (自动优选)", "🛡️ 晚高峰抗QoS (TCP优先)", "🏠 住宅家宽 (自动优选)"]
    if clash_cdn_names:
        group_select_candidates.append("⛅ CDN破墙 (自动优选)")
    group_select_candidates.append("⚡ 故障转移 (Fallback)")

    proxy_groups.append({
        "name": "⚡ 故障转移 (Fallback)",
        "type": "fallback",
        "proxies": clash_all_names,
        "url": "http://www.gstatic.com/generate_204",
        "interval": 300
    })

    proxy_groups.append({
        "name": "🎯 手动选择 (MANUAL)",
        "type": "select",
        "proxies": group_select_candidates + clash_all_names
    })

    clash_config = {
        "port": 7890,
        "socks-port": 7891,
        "allow-lan": False,
        "mode": "rule",
        "log-level": "info",
        "unified-delay": True,
        "proxies": clash_proxies,
        "proxy-groups": proxy_groups,
        "rules": [
            "DOMAIN-SUFFIX,local,DIRECT",
            "IP-CIDR,127.0.0.0/8,DIRECT",
            "IP-CIDR,172.16.0.0/12,DIRECT",
            "IP-CIDR,192.168.0.0/16,DIRECT",
            "IP-CIDR,10.0.0.0/8,DIRECT",
            "GEOIP,CN,DIRECT",
            "MATCH,🎯 手动选择 (MANUAL)"
        ]
    }

    try:
        import yaml
        yaml_str = yaml.dump(clash_config, allow_unicode=True, sort_keys=False)
    except ImportError:
        def _to_yaml(obj, indent=0):
            lines = []
            prefix = "  " * indent
            if isinstance(obj, dict):
                for k, v in obj.items():
                    if isinstance(v, (dict, list)):
                        lines.append(f"{prefix}{k}:")
                        lines.append(_to_yaml(v, indent + 1))
                    else:
                        val = "true" if v is True else ("false" if v is False else (str(v) if v is not None else "''"))
                        if isinstance(v, str) and (":" in v or "#" in v or " " in v or "[" in v or "{" in v or "," in v or not v):
                            val = f'"{v}"'
                        lines.append(f"{prefix}{k}: {val}")
            elif isinstance(obj, list):
                for item in obj:
                    if isinstance(item, dict):
                        first = True
                        for k, v in item.items():
                            if first:
                                if isinstance(v, (dict, list)):
                                    lines.append(f"{prefix}- {k}:")
                                    lines.append(_to_yaml(v, indent + 2))
                                else:
                                    val = "true" if v is True else ("false" if v is False else str(v))
                                    if isinstance(v, str) and (":" in v or "#" in v or " " in v or "[" in v or "{" in v or "," in v or not v):
                                        val = f'"{v}"'
                                    lines.append(f"{prefix}- {k}: {val}")
                                first = False
                            else:
                                item_prefix = prefix + "  "
                                if isinstance(v, (dict, list)):
                                    lines.append(f"{item_prefix}{k}:")
                                    lines.append(_to_yaml(v, indent + 2))
                                else:
                                    val = "true" if v is True else ("false" if v is False else str(v))
                                    if isinstance(v, str) and (":" in v or "#" in v or " " in v or "[" in v or "{" in v or "," in v or not v):
                                        val = f'"{v}"'
                                    lines.append(f"{item_prefix}{k}: {val}")
                    else:
                        val = str(item)
                        if isinstance(item, str) and (":" in item or "#" in item or " " in item or "[" in item or "{" in item or "," in item or not item):
                            val = f'"{item}"'
                        lines.append(f"{prefix}- {val}")
            return "\n".join(lines)
        yaml_str = _to_yaml(clash_config)

    with open(os.path.join(output_dir, "clash.yaml"), "w", encoding="utf-8") as f:
        f.write(yaml_str)

    # --------------------------------------------------------------------------
    # 4. 输出 Sing-box 客户端开箱即用完整配置 (singbox.json)
    # --------------------------------------------------------------------------
    sb_outbounds_list = []

    # 构造客户端出站
    sb_outbounds_list.append({
        "type": "vless", "tag": node_names["vless_direct_v4"], "server": public_ip, "server_port": vless_port,
        "uuid": direct_uuid, "flow": "xtls-rprx-vision", "network": "tcp",
        "tls": {
            "enabled": True, "server_name": camouflage_sni, "reality": {"enabled": True, "public_key": public_key, "short_id": short_id},
            "utls": {"enabled": True, "fingerprint": "chrome"}
        }
    })
    sb_outbounds_list.append({
        "type": "vless", "tag": node_names["vless_resi_v4"], "server": public_ip, "server_port": vless_port,
        "uuid": resi_uuid, "flow": "xtls-rprx-vision", "network": "tcp",
        "tls": {
            "enabled": True, "server_name": camouflage_sni, "reality": {"enabled": True, "public_key": public_key, "short_id": short_id},
            "utls": {"enabled": True, "fingerprint": "chrome"}
        }
    })

    # Hysteria 2
    hy2_sb_d = {
        "type": "hysteria2", "tag": node_names["hy2_direct_v4"], "server": public_ip, "server_port": hy2_port,
        "password": direct_uuid, "tls": {"enabled": True, "server_name": domain if domain else camouflage_sni, "insecure": bool(not domain)}
    }
    hy2_sb_r = {
        "type": "hysteria2", "tag": node_names["hy2_resi_v4"], "server": public_ip, "server_port": hy2_port,
        "password": resi_uuid, "tls": {"enabled": True, "server_name": domain if domain else camouflage_sni, "insecure": bool(not domain)}
    }
    if hy2_hop_ports:
        hop_ranges = []
        for p in str(hy2_hop_ports).split(","):
            p = p.strip()
            if not p:
                continue
            if "-" in p or ":" in p:
                delim = "-" if "-" in p else ":"
                parts = p.split(delim)
                if len(parts) == 2 and parts[0].isdigit() and parts[1].isdigit():
                    hop_ranges.append(f"{parts[0]}:{parts[1]}")
            elif p.isdigit():
                hop_ranges.append(f"{p}:{p}")
        if hop_ranges:
            hy2_sb_d["server_ports"] = hop_ranges
            hy2_sb_r["server_ports"] = hop_ranges
    if hy2_obfs:
        hy2_sb_d["obfs"] = {"type": "salamander", "password": hy2_obfs}
        hy2_sb_r["obfs"] = {"type": "salamander", "password": hy2_obfs}
    sb_outbounds_list.extend([hy2_sb_d, hy2_sb_r])

    # TUIC v5
    sb_outbounds_list.append({
        "type": "tuic", "tag": node_names["tuic_direct_v4"], "server": public_ip, "server_port": tuic_port,
        "uuid": direct_uuid, "password": short_id, "congestion_control": "bbr",
        "tls": {"enabled": True, "server_name": tuic_sni, "alpn": ["h3"], "insecure": bool(not domain)}
    })
    sb_outbounds_list.append({
        "type": "tuic", "tag": node_names["tuic_resi_v4"], "server": public_ip, "server_port": tuic_port,
        "uuid": resi_uuid, "password": short_id, "congestion_control": "bbr",
        "tls": {"enabled": True, "server_name": tuic_sni, "alpn": ["h3"], "insecure": bool(not domain)}
    })

    # AnyTLS (仅在服务端开启 AnyTLS 监听时生成)
    if anytls_port and int(anytls_port) > 0:
        sb_outbounds_list.append({
            "type": "anytls", "tag": node_names["anytls_direct_v4"], "server": public_ip, "server_port": anytls_port,
            "password": direct_uuid, "tls": {"enabled": True, "server_name": domain if domain else camouflage_sni, "insecure": bool(not domain)}
        })
        sb_outbounds_list.append({
            "type": "anytls", "tag": node_names["anytls_resi_v4"], "server": public_ip, "server_port": anytls_port,
            "password": resi_uuid, "tls": {"enabled": True, "server_name": domain if domain else camouflage_sni, "insecure": bool(not domain)}
        })

    # VMess (直连 8445 明文传输，由 VMess AEAD 内部加密)
    sb_outbounds_list.append({
        "type": "vmess", "tag": node_names["vmess_direct_v4"], "server": public_ip, "server_port": vmess_port,
        "uuid": direct_uuid, "security": "auto",
        "transport": {"type": "http", "path": "/vmess", "host": [host]},
        "tls": {"enabled": False}
    })
    sb_outbounds_list.append({
        "type": "vmess", "tag": node_names["vmess_resi_v4"], "server": public_ip, "server_port": vmess_port,
        "uuid": resi_uuid, "security": "auto",
        "transport": {"type": "http", "path": "/vmess", "host": [host]},
        "tls": {"enabled": False}
    })

    # IPv6 原生直连节点追加至 Singbox 客户端出站 (保证双栈订阅矩阵 100% 对齐)
    if public_ipv6:
        sb_outbounds_list.append({
            "type": "vless", "tag": node_names["vless_direct_v6"], "server": public_ipv6, "server_port": vless_port,
            "uuid": direct_uuid, "flow": "xtls-rprx-vision", "network": "tcp",
            "tls": {
                "enabled": True, "server_name": camouflage_sni, "reality": {"enabled": True, "public_key": public_key, "short_id": short_id},
                "utls": {"enabled": True, "fingerprint": "chrome"}
            }
        })
        hy2_sb_v6 = {
            "type": "hysteria2", "tag": node_names["hy2_direct_v6"], "server": public_ipv6, "server_port": hy2_port,
            "password": direct_uuid, "tls": {"enabled": True, "server_name": domain if domain else camouflage_sni, "insecure": bool(not domain)}
        }
        if hy2_hop_ports and hop_ranges:
            hy2_sb_v6["server_ports"] = hop_ranges
        if hy2_obfs:
            hy2_sb_v6["obfs"] = {"type": "salamander", "password": hy2_obfs}
        sb_outbounds_list.append(hy2_sb_v6)

        sb_outbounds_list.append({
            "type": "tuic", "tag": node_names["tuic_direct_v6"], "server": public_ipv6, "server_port": tuic_port,
            "uuid": direct_uuid, "password": short_id, "congestion_control": "bbr",
            "tls": {"enabled": True, "server_name": tuic_sni, "alpn": ["h3"], "insecure": bool(not domain)}
        })
        sb_outbounds_list.append({
            "type": "vmess", "tag": node_names["vmess_direct_v6"], "server": public_ipv6, "server_port": vmess_port,
            "uuid": direct_uuid, "security": "auto",
            "transport": {"type": "http", "path": "/vmess", "host": [host]},
            "tls": {"enabled": False}
        })

    # 追加 CDN 节点到 Singbox 客户端配置
    if argo_domain:
        sb_outbounds_list.append({
            "type": "vmess", "tag": node_names["vmess_argo_v4"], "server": clean_ip, "server_port": 443,
            "uuid": direct_uuid, "security": "auto",
            "transport": {"type": "http", "path": "/vmess", "host": [argo_domain]},
            "tls": {"enabled": True, "server_name": argo_domain}
        })
    if cf_cdn_host:
        sb_outbounds_list.append({
            "type": "vmess", "tag": node_names["vmess_cdn_v4"], "server": clean_ip, "server_port": 8443,
            "uuid": direct_uuid, "security": "auto",
            "transport": {"type": "http", "path": "/vmess", "host": [cf_cdn_host]},
            "tls": {"enabled": True, "server_name": cf_cdn_host}
        })
        sb_outbounds_list.append({
            "type": "vmess", "tag": node_names["vless_cdn_v4"], "server": clean_ip, "server_port": 8443,
            "uuid": direct_uuid, "security": "auto",
            "transport": {"type": "ws", "path": "/vmess-ws", "headers": {"Host": cf_cdn_host}},
            "tls": {"enabled": True, "server_name": cf_cdn_host}
        })
        if public_ipv6:
            sb_outbounds_list.append({
                "type": "vmess", "tag": node_names["vmess_cdn_v6"], "server": cf_ipv6_clean, "server_port": 8443,
                "uuid": direct_uuid, "security": "auto",
                "transport": {"type": "http", "path": "/vmess", "host": [cf_cdn_host]},
                "tls": {"enabled": True, "server_name": cf_cdn_host}
            })

    sb_all_tags = [o["tag"] for o in sb_outbounds_list]
    sb_direct_tags = [t for t in sb_all_tags if "直连" in t]
    sb_resi_tags = [t for t in sb_all_tags if "住宅" in t]
    sb_cdn_tags = [t for t in sb_all_tags if "CDN" in t]
    sb_tcp_tags = [t for t in sb_all_tags if "Reality" in t or "AnyTLS" in t or "VMess" in t]

    singbox_selectors = [
        {
            "type": "selector",
            "tag": "🎯 手动选择",
            "outbounds": ["🚀 极速原生 (自动优选)", "🛡️ 晚高峰抗QoS (TCP优先)", "🏠 住宅家宽 (自动优选)"] + (["⛅ CDN破墙 (自动优选)"] if sb_cdn_tags else []) + ["⚡ 故障转移"] + sb_all_tags,
            "default": "🚀 极速原生 (自动优选)"
        },
        {
            "type": "urltest",
            "tag": "🚀 极速原生 (自动优选)",
            "outbounds": sb_direct_tags if sb_direct_tags else sb_all_tags,
            "url": "https://www.gstatic.com/generate_204",
            "interval": "3m"
        },
        {
            "type": "urltest",
            "tag": "🛡️ 晚高峰抗QoS (TCP优先)",
            "outbounds": sb_tcp_tags if sb_tcp_tags else sb_all_tags,
            "url": "https://www.gstatic.com/generate_204",
            "interval": "3m"
        },
        {
            "type": "urltest",
            "tag": "🏠 住宅家宽 (自动优选)",
            "outbounds": sb_resi_tags if sb_resi_tags else sb_all_tags,
            "url": "https://www.gstatic.com/generate_204",
            "interval": "3m"
        }
    ]

    if sb_cdn_tags:
        singbox_selectors.append({
            "type": "urltest",
            "tag": "⛅ CDN破墙 (自动优选)",
            "outbounds": sb_cdn_tags,
            "url": "https://www.gstatic.com/generate_204",
            "interval": "3m"
        })

    singbox_selectors.append({
        "type": "urltest",
        "tag": "⚡ 故障转移",
        "outbounds": sb_all_tags,
        "url": "https://www.gstatic.com/generate_204",
        "interval": "3m"
    })

    sb_final_outbounds = singbox_selectors + sb_outbounds_list + [{"type": "direct", "tag": "direct"}]

    sb_cn_domain_suffixes = [
        ".cn", ".163.com", ".baidu.com", ".qq.com", ".bilibili.com",
        ".jd.com", ".taobao.com", ".alipay.com", ".zhihu.com",
        ".weibo.com", ".sohu.com", ".sina.com.cn"
    ]

    sb_client_config = {
        "log": {"level": "warn", "timestamp": True},
        "experimental": {
            "cache_file": {
                "enabled": True
            }
        },
        "dns": {
            "servers": [
                {"tag": "remote-dns", "type": "https", "server": "8.8.8.8", "tls": {"enabled": True, "server_name": "dns.google"}, "detour": "🎯 手动选择"},
                {"tag": "local-dns", "type": "udp", "server": "223.5.5.5"}
            ],
            "rules": [
                {"clash_mode": "Direct", "server": "local-dns"},
                {"domain_suffix": sb_cn_domain_suffixes, "server": "local-dns"}
            ],
            "final": "remote-dns",
            "strategy": "prefer_ipv4"
        },
        "inbounds": [
            {"type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": 2080}
        ],
        "outbounds": sb_final_outbounds,
        "route": {
            "default_domain_resolver": "local-dns",
            "rules": [
                {"protocol": "dns", "action": "hijack-dns"},
                {"ip_is_private": True, "outbound": "direct"},
                {"clash_mode": "Direct", "outbound": "direct"},
                {"clash_mode": "Global", "outbound": "🎯 手动选择"},
                {"domain_suffix": sb_cn_domain_suffixes, "outbound": "direct"}
            ],
            "final": "🎯 手动选择",
            "auto_detect_interface": True
        }
    }

    with open(os.path.join(output_dir, "singbox.json"), "w", encoding="utf-8") as f:
        json.dump(sb_client_config, f, indent=2, ensure_ascii=False)

    return {
        "nodes_count": len(links),
        "links": links
    }


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("用法: python3 generate_subs.py <singbox_nodes.json> <output_dir>")
        sys.exit(1)
    nodes_file = sys.argv[1]
    out_dir = sys.argv[2]
    with open(nodes_file, "r", encoding="utf-8") as f:
        data = json.load(f)
    res = generate_subscriptions(data, out_dir)
    print(f"成功生成 {res['nodes_count']} 个多协议双栈节点订阅文件！")
