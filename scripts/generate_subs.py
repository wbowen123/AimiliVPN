#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ==============================================================================
# AimiliVPN 全协议订阅生成引擎 (Base64 / Clash Meta / Sing-box / Plaintext)
# 支持 5 大协议 × 2 种出口 (VPS 原生极速 + Aimili 动态家宽) = 10 大节点矩阵
# ==============================================================================
import base64
import json
import os
import sys
import urllib.parse

def generate_subscriptions(nodes_data, output_dir):
    os.makedirs(output_dir, exist_ok=True)

    public_ip = nodes_data.get("public_ip", "127.0.0.1")
    domain = nodes_data.get("domain", "")
    host = domain if domain else public_ip
    camouflage_sni = nodes_data.get("camouflage_domain", "gateway.icloud.com")
    public_key = nodes_data.get("public_key", "")
    short_id = nodes_data.get("short_id", "")
    direct_uuid = nodes_data.get("direct_uuid", "")
    resi_uuid = nodes_data.get("resi_uuid", "")

    # 端口分配
    vless_port = nodes_data.get("vless_port", 443)
    hy2_port = nodes_data.get("hy2_port", 443)
    tuic_port = nodes_data.get("tuic_port", 8443)
    anytls_port = nodes_data.get("anytls_port", 8444)
    vmess_port = nodes_data.get("vmess_port", 8445)

    # 节点命名定义
    node_names = {
        "vless_direct": "🚀 [直连-极速] VLESS-Reality (原生千兆)",
        "vless_resi":   "🏠 [住宅-家宽] VLESS-Reality (Aimili动态家宽)",
        "hy2_direct":   "🌪️ [直连-暴力] Hysteria 2 (晚高峰不丢包)",
        "hy2_resi":     "🏘️ [住宅-家宽] Hysteria 2 (恶劣线路家宽加速)",
        "tuic_direct":  "⚡ [直连-极速] TUIC v5 (QUIC 0-RTT秒开)",
        "tuic_resi":    "🏡 [住宅-家宽] TUIC v5 (晚高峰家宽流媒体)",
        "anytls_direct":"🛡️ [直连-混淆] AnyTLS (动态包长混淆)",
        "anytls_resi":  "🌐 [住宅-混淆] AnyTLS (特征防探测家宽)",
        "vmess_direct": "☁️ [直连-分段] VMess-xHTTP (分块流防审查)",
        "vmess_resi":   "🛋️ [住宅-分段] VMess-xHTTP (分块流动态家宽)"
    }

    # --------------------------------------------------------------------------
    # 1. 生成 10 个标准的通用节点链接
    # --------------------------------------------------------------------------
    links = []

    # 1.1 VLESS Reality
    vless_d = f"vless://{direct_uuid}@{public_ip}:{vless_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni={camouflage_sni}&fp=chrome&pbk={public_key}&sid={short_id}&type=tcp#{urllib.parse.quote(node_names['vless_direct'])}"
    vless_r = f"vless://{resi_uuid}@{public_ip}:{vless_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni={camouflage_sni}&fp=chrome&pbk={public_key}&sid={short_id}&type=tcp#{urllib.parse.quote(node_names['vless_resi'])}"
    links.extend([vless_d, vless_r])

    # 1.2 Hysteria 2
    sni_param = f"&sni={domain}" if domain else f"&sni={camouflage_sni}&insecure=1"
    hy2_d = f"hysteria2://{direct_uuid}@{public_ip}:{hy2_port}?mport={hy2_port}{sni_param}#{urllib.parse.quote(node_names['hy2_direct'])}"
    hy2_r = f"hysteria2://{resi_uuid}@{public_ip}:{hy2_port}?mport={hy2_port}{sni_param}#{urllib.parse.quote(node_names['hy2_resi'])}"
    links.extend([hy2_d, hy2_r])

    # 1.3 TUIC v5
    tuic_sni = domain if domain else camouflage_sni
    insec_flag = "0" if domain else "1"
    tuic_d = f"tuic://{direct_uuid}:{short_id}@{public_ip}:{tuic_port}?congestion_control=bbr&alpn=h3&sni={tuic_sni}&allow_insecure={insec_flag}#{urllib.parse.quote(node_names['tuic_direct'])}"
    tuic_r = f"tuic://{resi_uuid}:{short_id}@{public_ip}:{tuic_port}?congestion_control=bbr&alpn=h3&sni={tuic_sni}&allow_insecure={insec_flag}#{urllib.parse.quote(node_names['tuic_resi'])}"
    links.extend([tuic_d, tuic_r])

    # 1.4 AnyTLS
    anytls_d = f"anytls://{direct_uuid}@{public_ip}:{anytls_port}?sni={tuic_sni}&insecure={insec_flag}#{urllib.parse.quote(node_names['anytls_direct'])}"
    anytls_r = f"anytls://{resi_uuid}@{public_ip}:{anytls_port}?sni={tuic_sni}&insecure={insec_flag}#{urllib.parse.quote(node_names['anytls_resi'])}"
    links.extend([anytls_d, anytls_r])

    # 1.5 VMess xHTTP
    vmess_obj_d = {
        "v": "2", "ps": node_names["vmess_direct"], "add": public_ip, "port": vmess_port,
        "id": direct_uuid, "aid": 0, "net": "http", "type": "none", "host": host,
        "path": "/vmess", "tls": "tls" if domain else ""
    }
    vmess_obj_r = {
        "v": "2", "ps": node_names["vmess_resi"], "add": public_ip, "port": vmess_port,
        "id": resi_uuid, "aid": 0, "net": "http", "type": "none", "host": host,
        "path": "/vmess", "tls": "tls" if domain else ""
    }
    vmess_d = "vmess://" + base64.b64encode(json.dumps(vmess_obj_d).encode("utf-8")).decode("utf-8")
    vmess_r = "vmess://" + base64.b64encode(json.dumps(vmess_obj_r).encode("utf-8")).decode("utf-8")
    links.extend([vmess_d, vmess_r])

    # --------------------------------------------------------------------------
    # 2. 输出 Base64 订阅文件 (sub.txt) 与 明文列表 (nodes.txt)
    # --------------------------------------------------------------------------
    raw_sub_text = "\n".join(links) + "\n"
    b64_sub_content = base64.b64encode(raw_sub_text.encode("utf-8")).decode("utf-8")

    with open(os.path.join(output_dir, "sub.txt"), "w", encoding="utf-8") as f:
        f.write(b64_sub_content)

    with open(os.path.join(output_dir, "nodes.txt"), "w", encoding="utf-8") as f:
        f.write(raw_sub_text)

    # --------------------------------------------------------------------------
    # 3. 输出 Clash Meta / Mihomo 格式订阅 (clash.yaml)
    # --------------------------------------------------------------------------
    direct_proxy_names = [node_names["vless_direct"], node_names["hy2_direct"], node_names["tuic_direct"], node_names["anytls_direct"], node_names["vmess_direct"]]
    resi_proxy_names = [node_names["vless_resi"], node_names["hy2_resi"], node_names["tuic_resi"], node_names["anytls_resi"], node_names["vmess_resi"]]
    all_proxy_names = direct_proxy_names + resi_proxy_names

    clash_proxies = [
        # VLESS Reality Direct & Resi
        {
            "name": node_names["vless_direct"], "type": "vless", "server": public_ip, "port": vless_port,
            "uuid": direct_uuid, "network": "tcp", "tls": True, "udp": True, "flow": "xtls-rprx-vision",
            "servername": camouflage_sni, "reality-opts": {"public-key": public_key, "short-id": short_id},
            "client-fingerprint": "chrome"
        },
        {
            "name": node_names["vless_resi"], "type": "vless", "server": public_ip, "port": vless_port,
            "uuid": resi_uuid, "network": "tcp", "tls": True, "udp": True, "flow": "xtls-rprx-vision",
            "servername": camouflage_sni, "reality-opts": {"public-key": public_key, "short-id": short_id},
            "client-fingerprint": "chrome"
        },
        # Hysteria 2 Direct & Resi
        {
            "name": node_names["hy2_direct"], "type": "hysteria2", "server": public_ip, "port": hy2_port,
            "password": direct_uuid, "sni": domain if domain else camouflage_sni, "skip-cert-verify": bool(not domain)
        },
        {
            "name": node_names["hy2_resi"], "type": "hysteria2", "server": public_ip, "port": hy2_port,
            "password": resi_uuid, "sni": domain if domain else camouflage_sni, "skip-cert-verify": bool(not domain)
        },
        # TUIC v5 Direct & Resi
        {
            "name": node_names["tuic_direct"], "type": "tuic", "server": public_ip, "port": tuic_port,
            "uuid": direct_uuid, "password": short_id, "alpn": ["h3"], "congestion-controller": "bbr",
            "sni": domain if domain else camouflage_sni, "skip-cert-verify": bool(not domain)
        },
        {
            "name": node_names["tuic_resi"], "type": "tuic", "server": public_ip, "port": tuic_port,
            "uuid": resi_uuid, "password": short_id, "alpn": ["h3"], "congestion-controller": "bbr",
            "sni": domain if domain else camouflage_sni, "skip-cert-verify": bool(not domain)
        },
        # VMess Direct & Resi
        {
            "name": node_names["vmess_direct"], "type": "vmess", "server": public_ip, "port": vmess_port,
            "uuid": direct_uuid, "alterId": 0, "cipher": "auto", "network": "http",
            "http-opts": {"path": ["/vmess"], "headers": {"Host": [host]}}, "tls": bool(domain), "skip-cert-verify": bool(not domain)
        },
        {
            "name": node_names["vmess_resi"], "type": "vmess", "server": public_ip, "port": vmess_port,
            "uuid": resi_uuid, "alterId": 0, "cipher": "auto", "network": "http",
            "http-opts": {"path": ["/vmess"], "headers": {"Host": [host]}}, "tls": bool(domain), "skip-cert-verify": bool(not domain)
        }
    ]

    clash_config = {
        "port": 7890,
        "socks-port": 7891,
        "allow-lan": False,
        "mode": "rule",
        "log-level": "info",
        "unified-delay": True,
        "proxies": clash_proxies,
        "proxy-groups": [
            {
                "name": "🚀 极速原生 (自动优选)",
                "type": "url-test",
                "proxies": direct_proxy_names,
                "url": "http://www.gstatic.com/generate_204",
                "interval": 300,
                "tolerance": 50
            },
            {
                "name": "🏠 住宅家宽 (自动优选)",
                "type": "url-test",
                "proxies": resi_proxy_names,
                "url": "http://www.gstatic.com/generate_204",
                "interval": 300,
                "tolerance": 50
            },
            {
                "name": "⚡ 故障转移 (Fallback)",
                "type": "fallback",
                "proxies": all_proxy_names,
                "url": "http://www.gstatic.com/generate_204",
                "interval": 300
            },
            {
                "name": "🎯 手动选择 (MANUAL)",
                "type": "select",
                "proxies": ["🚀 极速原生 (自动优选)", "🏠 住宅家宽 (自动优选)", "⚡ 故障转移 (Fallback)"] + all_proxy_names
            }
        ],
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
                        if isinstance(v, str) and (":" in v or "#" in v or " " in v or "[" in v or "{" in v or not v):
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
                                    if isinstance(v, str) and (":" in v or "#" in v or " " in v or "[" in v or "{" in v or not v):
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
                                    if isinstance(v, str) and (":" in v or "#" in v or " " in v or "[" in v or "{" in v or not v):
                                        val = f'"{v}"'
                                    lines.append(f"{item_prefix}{k}: {val}")
                    else:
                        val = str(item)
                        if isinstance(item, str) and (":" in item or "#" in item or " " in item or "[" in item or "{" in item or not item):
                            val = f'"{item}"'
                        lines.append(f"{prefix}- {val}")
            return "\n".join(lines)
        yaml_str = _to_yaml(clash_config)

    with open(os.path.join(output_dir, "clash.yaml"), "w", encoding="utf-8") as f:
        f.write(yaml_str)

    # --------------------------------------------------------------------------
    # 4. 输出 Sing-box 客户端开箱即用完整配置 (singbox.json)
    # --------------------------------------------------------------------------
    sb_outbounds = [
        {
            "type": "selector",
            "tag": "🎯 手动选择",
            "outbounds": ["🚀 极速原生 (自动优选)", "🏠 住宅家宽 (自动优选)", "⚡ 故障转移"] + all_proxy_names,
            "default": "🚀 极速原生 (自动优选)"
        },
        {
            "type": "urltest",
            "tag": "🚀 极速原生 (自动优选)",
            "outbounds": direct_proxy_names,
            "url": "https://www.gstatic.com/generate_204",
            "interval": "3m"
        },
        {
            "type": "urltest",
            "tag": "🏠 住宅家宽 (自动优选)",
            "outbounds": resi_proxy_names,
            "url": "https://www.gstatic.com/generate_204",
            "interval": "3m"
        },
        {
            "type": "urltest",
            "tag": "⚡ 故障转移",
            "outbounds": all_proxy_names,
            "url": "https://www.gstatic.com/generate_204",
            "interval": "3m"
        },
        # Outbounds - VLESS
        {
            "type": "vless", "tag": node_names["vless_direct"], "server": public_ip, "server_port": vless_port,
            "uuid": direct_uuid, "flow": "xtls-rprx-vision", "network": "tcp",
            "tls": {"enabled": True, "server_name": camouflage_sni, "reality": {"enabled": True, "public_key": public_key, "short_id": short_id}, "utls": {"enabled": True, "fingerprint": "chrome"}}
        },
        {
            "type": "vless", "tag": node_names["vless_resi"], "server": public_ip, "server_port": vless_port,
            "uuid": resi_uuid, "flow": "xtls-rprx-vision", "network": "tcp",
            "tls": {"enabled": True, "server_name": camouflage_sni, "reality": {"enabled": True, "public_key": public_key, "short_id": short_id}, "utls": {"enabled": True, "fingerprint": "chrome"}}
        },
        # Outbounds - Hysteria 2
        {
            "type": "hysteria2", "tag": node_names["hy2_direct"], "server": public_ip, "server_port": hy2_port,
            "password": direct_uuid, "tls": {"enabled": True, "server_name": domain if domain else camouflage_sni, "insecure": bool(not domain)}
        },
        {
            "type": "hysteria2", "tag": node_names["hy2_resi"], "server": public_ip, "server_port": hy2_port,
            "password": resi_uuid, "tls": {"enabled": True, "server_name": domain if domain else camouflage_sni, "insecure": bool(not domain)}
        },
        # Outbounds - TUIC
        {
            "type": "tuic", "tag": node_names["tuic_direct"], "server": public_ip, "server_port": tuic_port,
            "uuid": direct_uuid, "password": short_id, "congestion_control": "bbr",
            "tls": {"enabled": True, "server_name": domain if domain else camouflage_sni, "alpn": ["h3"], "insecure": bool(not domain)}
        },
        {
            "type": "tuic", "tag": node_names["tuic_resi"], "server": public_ip, "server_port": tuic_port,
            "uuid": resi_uuid, "password": short_id, "congestion_control": "bbr",
            "tls": {"enabled": True, "server_name": domain if domain else camouflage_sni, "alpn": ["h3"], "insecure": bool(not domain)}
        },
        {"type": "direct", "tag": "direct"},
        {"type": "dns", "tag": "dns-out"}
    ]

    sb_client_config = {
        "log": {"level": "warn", "timestamp": True},
        "dns": {
            "servers": [
                {"tag": "remote-dns", "address": "https://8.8.8.8/dns-query", "detour": "🎯 手动选择"},
                {"tag": "local-dns", "address": "223.5.5.5", "detour": "direct"}
            ],
            "rules": [
                {"outbound": ["any"], "server": "local-dns", "disable_cache": True},
                {"geosite": ["cn"], "server": "local-dns"},
                {"clash_mode": ["Direct"], "server": "local-dns"}
            ],
            "final": "remote-dns",
            "strategy": "prefer_ipv4"
        },
        "inbounds": [
            {"type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": 2080}
        ],
        "outbounds": sb_outbounds,
        "route": {
            "rules": [
                {"protocol": "dns", "outbound": "dns-out"},
                {"ip_is_private": True, "outbound": "direct"},
                {"geoip": ["cn", "private"], "outbound": "direct"},
                {"geosite": ["cn"], "outbound": "direct"}
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
    print(f"成功生成 {res['nodes_count']} 个多协议节点订阅文件！")
