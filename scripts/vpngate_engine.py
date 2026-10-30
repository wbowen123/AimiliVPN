#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
AimiliVPN 工业级家宽落地与网络命名空间 (netns) 隔离调度引擎
融合 byJoey/fanout 与 vioIetMiku/miku-gate 核心工程精髓：
  1. 真实家宽判定算法 (is_residential)：精确剔除筑波大学自营学术机房 (public-vpn-* 与 219.100.37.0/24)
  2. 多源与 Cloudflare Worker 镜像容灾池 (Multi-Source Node Pool)
  3. 并发多候选竞发建连 (Race Condition Provisioning)
  4. Linux Network Namespace (netns) 线程级隔离，彻底杜绝母机默认路由劫持
  5. 出口真实 IP 巡检与无感自动漂移自愈
"""

import os
import sys
import json
import base64
import csv
import time
import socket
import ipaddress
import urllib.request
import urllib.error
import subprocess
import threading
import tempfile
import shutil
import ctypes
import ctypes.util
import concurrent.futures
from typing import List, Optional, Tuple

# Linux 系统常量
CLONE_NEWNET = 0x40000000

# 官方源与镜像源定义
VPNGATE_OFFICIAL_API = "https://www.vpngate.net/api/iphone/"
VPNGATE_WORKER_MIRROR = "https://p.xy.kg/vpngate"
VPNGATE_MIRROR_KEY = "8rhIFzFKRJMFAe-xP5OQPclDEvSjKlHo"

# VPN Gate 官方学术网络/自营服务器 IP 段 (筑波大学机房)
VPNGATE_OWN_NETS = [
    ipaddress.ip_network("219.100.37.0/24")
]

# OpenVPN 配置文件安全白名单指令 (借鉴 OpenMili 生产级安全加固规范)
# 严格过滤 up, down, script-security, plugin 等高危执行指令，杜绝不可信节点提权或 RCE 漏洞
SAFE_OVPN_DIRECTIVES = {
    "auth", "cipher", "client", "comp-lzo", "compress",
    "connect-retry", "connect-retry-max", "connect-timeout",
    "data-ciphers", "data-ciphers-fallback", "dev", "dev-type",
    "explicit-exit-notify", "keepalive",
    "key-direction", "mute", "nobind", "persist-key", "persist-tun",
    "ping", "ping-restart", "ping-timer-rem", "proto", "pull",
    "rcvbuf", "remote", "remote-cert-tls", "remote-random",
    "remote-random-hostname", "reneg-sec", "resolv-retry",
    "route-delay", "sndbuf", "tls-cipher", "tls-ciphersuites",
    "tls-client", "tls-version-min", "verb", "verify-x509-name",
    "topology", "float", "fast-io", "hand-window", "tran-window",
    "link-mtu", "tun-mtu", "mssfix", "fragment", "redirect-gateway",
    "redirect-private", "route-gateway", "route-metric", "route-nopull"
}

SAFE_OVPN_INLINE_BLOCKS = {"ca", "cert", "key", "tls-auth", "tls-crypt", "extra-certs"}

DANGEROUS_OVPN_DIRECTIVES = {
    "up", "down", "script-security", "plugin", "route-up", "route-pre-down",
    "auth-user-pass-verify", "client-connect", "client-disconnect",
    "tls-verify", "ipchange", "management", "management-user-pass"
}


def sanitize_ovpn_config(raw_ovpn: str) -> str:
    """
    OpenVPN 配置文件安全白名单清洗器 (借鉴 OpenMili 安全架构)：
    严格剔除任何包含命令执行、脚本挂钩 (up/down/script-security/plugin) 的高危指令，
    仅放行 SAFE_OVPN_DIRECTIVES 与 SAFE_OVPN_INLINE_BLOCKS，
    从物理层面杜绝恶意 VPNGate 节点在 VPS 上进行任意代码执行 (RCE) 提权！
    """
    if not raw_ovpn:
        return ""

    lines = raw_ovpn.splitlines()
    sanitized: list[str] = []
    in_block: Optional[str] = None
    block_is_safe = False

    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue

        # 检查是否为内联块标签 <tag> 或 </tag>
        if stripped.startswith("<") and stripped.endswith(">"):
            tag_content = stripped[1:-1].strip()
            if tag_content.startswith("/"):
                # 块结束 </tag>
                closing_tag = tag_content[1:].strip().lower()
                if in_block == closing_tag:
                    if block_is_safe:
                        sanitized.append(line)
                    in_block = None
                    block_is_safe = False
                continue
            else:
                # 块开始 <tag>
                opening_tag = tag_content.lower()
                in_block = opening_tag
                block_is_safe = opening_tag in SAFE_OVPN_INLINE_BLOCKS
                if block_is_safe:
                    sanitized.append(line)
                continue

        # 如果当前在内联块内部
        if in_block is not None:
            if block_is_safe:
                sanitized.append(line)
            continue

        # 注释与空行跳过
        if stripped.startswith(("#", ";")):
            continue

        # 提取指令首词
        tokens = stripped.split()
        if not tokens:
            continue
        directive = tokens[0].lower()

        # 明确黑名单或非白名单字段，坚决剔除
        if directive in DANGEROUS_OVPN_DIRECTIVES:
            continue
        if directive not in SAFE_OVPN_DIRECTIVES:
            continue

        # 避免启动冲突指令 (dhcp-option 等在 netns 内无需使用)
        if directive in ("dhcp-option",):
            continue

        sanitized.append(line)

    # 规范化追加 Netns 隔离运行必须参数
    sanitized.append("nobind")
    sanitized.append("persist-tun")
    sanitized.append("persist-key")
    sanitized.append("verb 3")

    return "\n".join(sanitized) + "\n"


class ConnRegistry:
    """
    下游客户端连接注册中心 (借鉴 Guli-Joy 生产实践)：
    跟踪某个代理监听实例当前活跃的下游客户端 Socket 连接，支持一次性强制切断。
    用途：主节点切换/重连成功后，强制切断下游(如 Clash/Sing-box/Xray)连接，
    使其连接池立即感知 EOF 并重连到新隧道，彻底消除死连接导致的黑洞卡顿。
    """

    def __init__(self) -> None:
        self._conns: set[socket.socket] = set()
        self._lock = threading.Lock()

    def register(self, sock: socket.socket) -> None:
        with self._lock:
            self._conns.add(sock)

    def unregister(self, sock: socket.socket) -> None:
        with self._lock:
            self._conns.discard(sock)

    def close_all(self) -> int:
        """主节点切换成功后调用：强制 shutdown 并 close 所有下游 Socket"""
        with self._lock:
            conns = list(self._conns)
            self._conns.clear()
        closed = 0
        for s in conns:
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            try:
                s.close()
                closed += 1
            except OSError:
                pass
        return closed



class VpnGateNode:
    """VPN Gate 节点数据结构"""
    def __init__(self, hostname: str, ip: str, score: int, ping: int, speed: int,
                 country_long: str, country_short: str, sessions: int,
                 ovpn_config_b64: str):
        self.hostname = hostname.strip()
        self.ip = ip.strip()
        self.score = score
        self.ping = ping
        self.speed = speed  # bps
        self.speed_mbps = round(speed / (1024 * 1024), 2)
        self.country_long = country_long.strip()
        self.country_short = country_short.strip().upper()
        self.sessions = sessions
        self.ovpn_config_b64 = ovpn_config_b64.strip()
        self.is_residential = self.check_residential()
        self.quality_score = self.calc_quality_score()

    def check_residential(self) -> bool:
        """
        判断节点是否属于真实居民家庭宽带 (Residential)。
        借鉴 fanout 算法：
          1. 排除以 public-vpn- 开头的主机名 (官方机房)
          2. 排除 219.100.37.0/24 官方自营机房网段
        """
        lower_host = self.hostname.lower()
        if lower_host.startswith("public-vpn-"):
            return False
        try:
            addr = ipaddress.ip_address(self.ip)
            for net in VPNGATE_OWN_NETS:
                if addr in net:
                    return False
        except ValueError:
            pass
        return True

    def calc_quality_score(self) -> float:
        """综合质量加权评分 (速度权重高，Ping 适中，家宽加分)"""
        s = self.speed_mbps * 2.0
        if self.ping > 0:
            s -= min(self.ping / 10.0, 50.0)
        if self.is_residential:
            s += 30.0  # 真实住宅加权
        return max(s, 0.0)

    def decode_ovpn_config(self) -> str:
        """解码 .ovpn 原始配置文本"""
        try:
            return base64.b64decode(self.ovpn_config_b64).decode("utf-8", errors="ignore")
        except Exception:
            return ""

    def parse_connection_info(self) -> Tuple[str, int]:
        """从 ovpn 配置中提取传输协议 (tcp/udp) 与端口"""
        proto = "udp"
        port = 1194
        try:
            cfg = self.decode_ovpn_config()
            for line in cfg.splitlines():
                parts = line.strip().split()
                if not parts:
                    continue
                cmd = parts[0].lower()
                if cmd == "proto" and len(parts) >= 2:
                    proto = parts[1].lower().replace("-client", "")
                elif cmd == "remote" and len(parts) >= 3 and parts[2].isdigit():
                    port = int(parts[2])
                    if len(parts) >= 4 and parts[3].lower() in ("tcp", "udp"):
                        proto = parts[3].lower()
        except Exception:
            pass
        return proto, port

    def __repr__(self):
        res_str = "🏠家宽" if self.is_residential else "🏢机房"
        return f"<Node [{self.country_short}] {self.ip} ({self.hostname[:16]}) {self.speed_mbps}Mbps {res_str}>"


def tcp_prescreen_nodes(nodes: List[VpnGateNode], max_workers: int = 60, timeout: float = 0.8) -> List[VpnGateNode]:
    """
    分层测速第一层：非阻塞并发 TCP 握手极速预筛 (借鉴 Guli-Joy 生产优化经验)
    在启动昂贵的 OpenVPN 进程前，用轻量级 TCP 握手 (0.8s) 瞬间淘汰端口不可达、被墙或关机的死节点。
    仅对 proto 为 tcp 的节点进行淘汰过滤；UDP 节点由于无连接握手，默认保留。
    返回存活的节点列表。
    """
    if not nodes:
        return []

    dead_endpoints = set()
    dead_lock = threading.Lock()

    def probe_worker(node: VpnGateNode):
        proto, port = node.parse_connection_info()
        if not proto.startswith("tcp"):
            return  # UDP 节点不在此层预筛，直接放行

        # 发起非阻塞快速 TCP 探测
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(timeout)
        endpoint = f"{node.ip}:{port}"
        try:
            res = s.connect_ex((node.ip, port))
            if res != 0:
                with dead_lock:
                    dead_endpoints.add(endpoint)
        except Exception:
            with dead_lock:
                dead_endpoints.add(endpoint)
        finally:
            try:
                s.close()
            except Exception:
                pass

    workers = min(max_workers, max(1, len(nodes)))
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        list(executor.map(probe_worker, nodes))

    survived = []
    for n in nodes:
        proto, port = n.parse_connection_info()
        if proto.startswith("tcp") and f"{n.ip}:{port}" in dead_endpoints:
            continue
        survived.append(n)
    return survived


BAD_NODE_COOLDOWN_SEC = 1800  # 30 分钟冷却期


class NodeCooldownPool:
    """假活/僵尸节点冷却惩罚池 (借鉴 Guli-Joy 生产防卡死机制)"""

    def __init__(self, cooldown_sec: int = BAD_NODE_COOLDOWN_SEC):
        self.cooldown_sec = cooldown_sec
        self._bad_nodes: dict[str, float] = {}  # ip -> expire_timestamp
        self._lock = threading.Lock()

    def mark_bad(self, ip: str, reason: str = ""):
        """将假活/异常节点加入冷却池并惩罚 1800 秒"""
        with self._lock:
            expire_at = time.time() + self.cooldown_sec
            self._bad_nodes[ip] = expire_at
            if reason:
                sys.stdout.write(f"[!] 节点 {ip} 判定为假活/异常: {reason}，已施加 30 分钟冷却惩罚。\n")

    def is_in_cooldown(self, ip: str) -> bool:
        """检查节点是否处于冷却期"""
        with self._lock:
            now = time.time()
            if ip in self._bad_nodes:
                if now < self._bad_nodes[ip]:
                    return True
                else:
                    del self._bad_nodes[ip]
        return False

    def filter_candidates(self, nodes: List[VpnGateNode]) -> List[VpnGateNode]:
        """过滤掉所有仍处于冷却期内的假活节点"""
        with self._lock:
            now = time.time()
            # 清理过期项
            expired = [k for k, exp in self._bad_nodes.items() if now >= exp]
            for k in expired:
                del self._bad_nodes[k]
            active_bad = set(self._bad_nodes.keys())

        return [n for n in nodes if n.ip not in active_bad]

    def count(self) -> int:
        with self._lock:
            return len(self._bad_nodes)


class VpnGateFetcher:
    """VPN Gate 节点多源抓取与容灾解析器"""

    @staticmethod
    def fetch_raw_csv(timeout: int = 15) -> str:
        """
        多源抓取：优先直连官方 API，超时或失败自动切换 Cloudflare Worker 镜像源
        """
        sources = [
            ("Official", os.environ.get("VPNGATE_API", VPNGATE_OFFICIAL_API), {}),
            ("Mirror", os.environ.get("VPNGATE_MIRROR", VPNGATE_WORKER_MIRROR), {"X-Access-Key": VPNGATE_MIRROR_KEY})
        ]

        last_err = None
        for name, url, headers in sources:
            if not url:
                continue
            try:
                req = urllib.request.Request(
                    url,
                    headers={
                        "User-Agent": "Mozilla/5.0 (compatible; AimiliVPN/2.0; +https://github.com/wbowen123/AimiliVPN)",
                        **headers
                    }
                )
                with urllib.request.urlopen(req, timeout=timeout) as resp:
                    content = resp.read().decode("utf-8", errors="ignore")
                    # 校验是否为合法的 VPN Gate CSV 格式
                    if "*vpn_servers" in content or "#HostName" in content:
                        return content
            except Exception as e:
                last_err = e
                continue

        raise RuntimeError(f"所有 VPN Gate 节点数据源均无法访问: {last_err}")

    @classmethod
    def parse_nodes(cls, csv_text: str, residential_only: bool = True,
                    target_country: Optional[str] = None) -> List[VpnGateNode]:
        """解析 CSV 并应用家宽过滤及地区筛选"""
        nodes: List[VpnGateNode] = []
        lines = [line.strip() for line in csv_text.splitlines() if line.strip()]
        
        # 寻找数据头
        header_idx = -1
        for i, line in enumerate(lines):
            if line.startswith("#HostName") or line.startswith("HostName"):
                header_idx = i
                break
        
        if header_idx == -1:
            return nodes

        csv_reader = csv.reader(lines[header_idx:])
        headers = next(csv_reader, None)
        if not headers:
            return nodes

        # 映射列索引
        col_map = {col.lstrip("#").strip(): idx for idx, col in enumerate(headers)}
        req_cols = ["HostName", "IP", "Score", "Ping", "Speed", "CountryLong", "CountryShort", "NumVpnSessions", "OpenVPN_ConfigData_Base64"]
        if not all(c in col_map for c in req_cols):
            return nodes

        for row in csv_reader:
            if not row or row[0].startswith("*"):
                continue
            try:
                hostname = row[col_map["HostName"]]
                ip = row[col_map["IP"]]
                score = int(row[col_map["Score"]]) if row[col_map["Score"]].isdigit() else 0
                ping = int(row[col_map["Ping"]]) if row[col_map["Ping"]].isdigit() else 999
                speed = int(row[col_map["Speed"]]) if row[col_map["Speed"]].isdigit() else 0
                country_long = row[col_map["CountryLong"]]
                country_short = row[col_map["CountryShort"]].upper()
                sessions = int(row[col_map["NumVpnSessions"]]) if row[col_map["NumVpnSessions"]].isdigit() else 0
                ovpn_b64 = row[col_map["OpenVPN_ConfigData_Base64"]]

                if not ip or not ovpn_b64:
                    continue

                node = VpnGateNode(
                    hostname=hostname,
                    ip=ip,
                    score=score,
                    ping=ping,
                    speed=speed,
                    country_long=country_long,
                    country_short=country_short,
                    sessions=sessions,
                    ovpn_config_b64=ovpn_b64
                )

                # 住宅家宽过滤
                if residential_only and not node.is_residential:
                    continue

                # 地区筛选
                if target_country and node.country_short != target_country.upper():
                    continue

                nodes.append(node)
            except Exception:
                continue

        # 按综合质量评分降序排序
        nodes.sort(key=lambda n: n.quality_score, reverse=True)
        return nodes

    @classmethod
    def get_nodes(cls, timeout: int = 15, residential_only: bool = True,
                  target_country: Optional[str] = None,
                  prescreen_tcp: bool = True) -> List[VpnGateNode]:
        """一站式抓取、过滤并排序好的节点池 (集成 TCP 极速分层预筛)"""
        raw = cls.fetch_raw_csv(timeout=timeout)
        nodes = cls.parse_nodes(raw, residential_only=residential_only, target_country=target_country)
        if prescreen_tcp and os.environ.get("AIMILI_TCP_PRESCREEN", "1") == "1":
            nodes = tcp_prescreen_nodes(nodes)
        return nodes


class LinuxNetnsManager:
    """Linux Network Namespace (netns) 物理隔离与虚拟网线 (veth) 调度器"""

    @staticmethod
    def is_supported() -> bool:
        """检查系统是否支持 Linux netns 及具备 root 权限"""
        if sys.platform != "linux":
            return False
        if os.geteuid() != 0:
            return False
        return os.path.exists("/proc/self/ns/net") and os.path.exists("/dev/net/tun")

    @classmethod
    def _get_slot_from_name(cls, ns_name: str) -> int:
        """从命名空间提取槽位编号以分配独立子网 10.99.X.0/24"""
        import re
        nums = re.findall(r"\d+", ns_name)
        return int(nums[-1]) % 200 if nums else 0

    @classmethod
    def create_netns(cls, ns_name: str) -> bool:
        """创建独立的网络命名空间、配置 veth-pair 互联及 NAT 转发"""
        try:
            slot = cls._get_slot_from_name(ns_name)
            veth_h = f"vh_{slot}"
            veth_ns = f"vp_{slot}"
            subnet = f"10.99.{slot}"

            # 开启内核 IP 转发
            subprocess.call(["sysctl", "-w", "net.ipv4.ip_forward=1"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            # 检查是否已存在
            existing = subprocess.check_output(["ip", "netns", "list"], stderr=subprocess.DEVNULL).decode()
            if ns_name not in existing.split():
                subprocess.check_call(["ip", "netns", "add", ns_name], stderr=subprocess.DEVNULL)

            # 启用 netns 内的 loopback
            subprocess.check_call(["ip", "netns", "exec", ns_name, "ip", "link", "set", "lo", "up"], stderr=subprocess.DEVNULL)

            # 清理可能残留的同名旧 veth
            subprocess.call(["ip", "link", "del", veth_h], stderr=subprocess.DEVNULL)

            # 创建 veth-pair 并将一端移入 netns
            subprocess.check_call(["ip", "link", "add", veth_h, "type", "veth", "peer", "name", veth_ns], stderr=subprocess.DEVNULL)
            subprocess.check_call(["ip", "link", "set", veth_ns, "netns", ns_name], stderr=subprocess.DEVNULL)

            # 配置宿主机端 veth IP
            subprocess.check_call(["ip", "addr", "add", f"{subnet}.1/24", "dev", veth_h], stderr=subprocess.DEVNULL)
            subprocess.check_call(["ip", "link", "set", veth_h, "up"], stderr=subprocess.DEVNULL)

            # 配置 netns 端 veth IP 与默认路由
            subprocess.check_call(["ip", "netns", "exec", ns_name, "ip", "addr", "add", f"{subnet}.2/24", "dev", veth_ns], stderr=subprocess.DEVNULL)
            subprocess.check_call(["ip", "netns", "exec", ns_name, "ip", "link", "set", veth_ns, "up"], stderr=subprocess.DEVNULL)
            subprocess.check_call(["ip", "netns", "exec", ns_name, "ip", "route", "add", "default", "via", f"{subnet}.1"], stderr=subprocess.DEVNULL)

            # 确保 netns 内有 DNS
            dns_dir = f"/etc/netns/{ns_name}"
            os.makedirs(dns_dir, exist_ok=True)
            with open(f"{dns_dir}/resolv.conf", "w", encoding="utf-8") as f:
                f.write("nameserver 8.8.8.8\nnameserver 1.1.1.1\n")

            # 配置 iptables NAT 转发规则
            subprocess.call(["iptables", "-t", "nat", "-A", "POSTROUTING", "-s", f"{subnet}.0/24", "-j", "MASQUERADE"], stderr=subprocess.DEVNULL)
            subprocess.call(["iptables", "-I", "FORWARD", "1", "-i", veth_h, "-j", "ACCEPT"], stderr=subprocess.DEVNULL)
            subprocess.call(["iptables", "-I", "FORWARD", "1", "-o", veth_h, "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"], stderr=subprocess.DEVNULL)

            return True
        except Exception:
            return False

    @classmethod
    def delete_netns(cls, ns_name: str):
        """清理删除网络命名空间、veth 虚拟网卡与 iptables 规则"""
        try:
            slot = cls._get_slot_from_name(ns_name)
            veth_h = f"vh_{slot}"
            subnet = f"10.99.{slot}"

            subprocess.call(["ip", "link", "del", veth_h], stderr=subprocess.DEVNULL)
            subprocess.call(["iptables", "-t", "nat", "-D", "POSTROUTING", "-s", f"{subnet}.0/24", "-j", "MASQUERADE"], stderr=subprocess.DEVNULL)
            subprocess.call(["iptables", "-D", "FORWARD", "-i", veth_h, "-j", "ACCEPT"], stderr=subprocess.DEVNULL)
            subprocess.call(["iptables", "-D", "FORWARD", "-o", veth_h, "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"], stderr=subprocess.DEVNULL)

            subprocess.call(["ip", "netns", "del", ns_name], stderr=subprocess.DEVNULL)
            shutil.rmtree(f"/etc/netns/{ns_name}", ignore_errors=True)
        except Exception:
            pass

    @classmethod
    def execute_in_netns(cls, ns_name: str, cmd_list: List[str], timeout: int = 15) -> Tuple[int, str, str]:
        """在指定的 netns 内执行命令"""
        full_cmd = ["ip", "netns", "exec", ns_name] + cmd_list
        proc = subprocess.Popen(full_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            out, err = proc.communicate(timeout=timeout)
            return proc.returncode, out, err
        except subprocess.TimeoutExpired:
            proc.kill()
            return -1, "", "Command timed out"


class NetnsOpenVpnRunner:
    """在隔离 netns 内管理 OpenVPN 进程与健康监测"""

    def __init__(self, ns_name: str = "aimili_ns0"):
        self.ns_name = ns_name
        self.proc: Optional[subprocess.Popen] = None
        self.conf_file: Optional[str] = None
        self.current_node: Optional[VpnGateNode] = None
        self.assigned_ip: Optional[str] = None

    def start_tunnel(self, node: VpnGateNode, timeout: int = 15) -> bool:
        """在 netns 内启动 OpenVPN 并等待出口连通"""
        self.stop_tunnel()
        if not LinuxNetnsManager.create_netns(self.ns_name):
            return False

        ovpn_content = node.decode_ovpn_config()
        if not ovpn_content:
            return False

        # 应用白名单安全清洗 (剔除远程恶意注入指令) 并适配 Netns 隔离
        cleaned_ovpn = sanitize_ovpn_config(ovpn_content)

        fd, path = tempfile.mkstemp(prefix=f"ovpn_{self.ns_name}_", suffix=".ovpn")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(cleaned_ovpn)
        self.conf_file = path

        self.log_file = f"/tmp/ovpn_{self.ns_name}.log"
        self._log_fp = open(self.log_file, "w", encoding="utf-8")

        cmd = [
            "ip", "netns", "exec", self.ns_name,
            "openvpn",
            "--config", self.conf_file
        ]

        self.proc = subprocess.Popen(
            cmd,
            stdout=self._log_fp,
            stderr=subprocess.STDOUT
        )

        # 获取母机公网 IP 用于防泄露比对
        self.host_ip = os.environ.get("PUBLIC_IP", "")
        if not self.host_ip:
            try:
                ip_f = "/opt/aimilivpn/vpngate_data/public_ip.txt"
                if os.path.exists(ip_f):
                    with open(ip_f, "r") as f:
                        self.host_ip = f.read().strip()
            except Exception:
                pass

        # 轮询探测连通性
        start_t = time.time()
        while time.time() - start_t < timeout:
            if self.proc.poll() is not None:
                # 进程异常退出
                err_tail = self._read_log_tail()
                sys.stderr.write(f"[!] OpenVPN 异常退出 (code: {self.proc.poll()}):\n{err_tail}\n")
                self.stop_tunnel()
                return False
            
            # 1. 检查 tun 默认路由是否已被 OpenVPN 注入 (0.0.0.0/1)
            code, out, _ = LinuxNetnsManager.execute_in_netns(
                self.ns_name,
                ["ip", "route", "show", "0.0.0.0/1"],
                timeout=1
            )
            if code == 0 and "tun" in out:
                # 2. 必须成功获取公网出口 IP 且必须不同于母机原生 IP
                ip = self.get_egress_ip(timeout=3)
                if ip and (not self.host_ip or ip != self.host_ip):
                    self.current_node = node
                    self.assigned_ip = ip
                    return True
            time.sleep(1)

        err_tail = self._read_log_tail()
        sys.stderr.write(f"[!] OpenVPN 握手超时 (15s):\n{err_tail}\n")
        self.stop_tunnel()
        return False

    def _read_log_tail(self, lines: int = 10) -> str:
        try:
            if hasattr(self, "log_file") and os.path.exists(self.log_file):
                with open(self.log_file, "r", encoding="utf-8", errors="ignore") as f:
                    all_lines = f.readlines()
                    return "".join(all_lines[-lines:])
        except Exception:
            pass
        return ""

    def get_egress_ip(self, timeout: int = 3) -> Optional[str]:
        """通过该 netns 测试实际公网出站 IP"""
        ip_apis = [
            "https://api.ipify.org",
            "https://ip.sb",
            "https://icanhazip.com"
        ]
        for api in ip_apis:
            code, out, _ = LinuxNetnsManager.execute_in_netns(
                self.ns_name,
                ["curl", "-s4", "--connect-timeout", str(timeout), "--max-time", str(timeout), api],
                timeout=timeout + 1
            )
            if code == 0 and out.strip():
                try:
                    ip = out.strip().splitlines()[0]
                    ipaddress.ip_address(ip)
                    return ip
                except ValueError:
                    continue
        return None

    def is_alive(self) -> bool:
        """检查隧道是否健康 (进程在且 IP 未漂移)"""
        if not self.proc or self.proc.poll() is not None:
            return False
        cur_ip = self.get_egress_ip(timeout=3)
        return bool(cur_ip and cur_ip == self.assigned_ip)

    def stop_tunnel(self):
        """停止隧道并清理资源"""
        if self.proc:
            try:
                self.proc.terminate()
                self.proc.wait(timeout=2)
            except Exception:
                try:
                    self.proc.kill()
                except Exception:
                    pass
        if hasattr(self, "_log_fp") and self._log_fp and not self._log_fp.closed:
            try:
                self._log_fp.close()
            except Exception:
                pass
            self._log_fp = None

        if self.conf_file and os.path.exists(self.conf_file):
            try:
                os.remove(self.conf_file)
            except Exception:
                pass
            self.conf_file = None

        self.current_node = None
        self.assigned_ip = None


class NetnsBridgeServer:
    """
    在宿主机运行的 SOCKS5 代理网桥：
    监听在 127.0.0.1:8500，针对入站的 TCP 请求，
    通过 setns 系统调用将出站 socket 切入指定 netns 发起连接，
    实现宿主机 Sing-box 零改造直通 netns 家宽出口！
    """

    def __init__(self, ns_name: str, host: str = "127.0.0.1", port: int = 8500):
        self.ns_name = ns_name
        self.host = host
        self.port = port
        self.server_sock: Optional[socket.socket] = None
        self.running = False
        self.conn_registry = ConnRegistry()
        self._libc = None
        if sys.platform == "linux":
            try:
                self._libc = ctypes.CDLL("libc.so.6", use_errno=True)
            except Exception:
                pass

    def _dial_in_netns(self, target_host: str, target_port: int, timeout: int = 10) -> socket.socket:
        """在指定的 netns 内创建并连接目标 socket"""
        # 如果不支持或非 Linux，直接用常规 socket
        if not self._libc or not os.path.exists(f"/var/run/netns/{self.ns_name}"):
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(timeout)
            s.connect((target_host, target_port))
            return s

        # 保存母机原始 namespace
        orig_fd = os.open("/proc/self/ns/net", os.O_RDONLY)
        target_fd = os.open(f"/var/run/netns/{self.ns_name}", os.O_RDONLY)
        s = None
        try:
            # 切换到目标 netns
            if self._libc.setns(target_fd, CLONE_NEWNET) != 0:
                errno = ctypes.get_errno()
                raise OSError(errno, f"setns failed: {os.strerror(errno)}")

            # 在该 netns 内创建 socket 并拨号
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(timeout)
            s.connect((target_host, target_port))
        finally:
            # 无论成功失败，必须切回母机原始 namespace
            self._libc.setns(orig_fd, CLONE_NEWNET)
            os.close(orig_fd)
            os.close(target_fd)

        return s

    def _handle_client(self, client: socket.socket):
        """极简高效 SOCKS5 协议处理 (集成 ConnRegistry 下游连接追踪)"""
        self.conn_registry.register(client)
        try:
            client.settimeout(15)
            # 1. 协商认证
            ver, nmethods = client.recv(1), client.recv(1)
            if not ver or ver[0] != 0x05:
                client.close()
                return
            client.recv(nmethods[0])
            client.sendall(b"\x05\x00")  # 无需认证

            # 2. 读取连接请求
            data = client.recv(4)
            if len(data) < 4 or data[1] != 0x01:  # 仅支持 CONNECT (0x01)
                client.sendall(b"\x05\x07\x00\x01\x00\x00\x00\x00\x00\x00")  # Command not supported
                client.close()
                return

            atyp = data[3]
            if atyp == 0x01:  # IPv4
                dest_addr = socket.inet_ntoa(client.recv(4))
            elif atyp == 0x03:  # Domain
                d_len = client.recv(1)[0]
                dest_addr = client.recv(d_len).decode("utf-8", errors="ignore")
            elif atyp == 0x04:  # IPv6
                dest_addr = socket.inet_ntop(socket.AF_INET6, client.recv(16))
            else:
                client.close()
                return

            port_bytes = client.recv(2)
            dest_port = (port_bytes[0] << 8) | port_bytes[1]

            # 3. 在 netns 内拨号建立出站
            try:
                remote = self._dial_in_netns(dest_addr, dest_port)
            except Exception:
                client.sendall(b"\x05\x04\x00\x01\x00\x00\x00\x00\x00\x00")  # Host unreachable
                client.close()
                return

            # 回复成功
            client.sendall(b"\x05\x00\x00\x01\x00\x00\x00\x00\x00\x00")

            # 4. 双向中继
            self._forward(client, remote)
        except Exception:
            pass
        finally:
            self.conn_registry.unregister(client)
            try:
                client.close()
            except Exception:
                pass

    @staticmethod
    def _forward(sock1: socket.socket, sock2: socket.socket):
        """双向数据管道中继"""
        def pipe(src, dst):
            try:
                while True:
                    data = src.recv(32768)
                    if not data:
                        break
                    dst.sendall(data)
            except Exception:
                pass
            finally:
                try:
                    dst.shutdown(socket.SHUT_WR)
                except Exception:
                    pass

        t1 = threading.Thread(target=pipe, args=(sock1, sock2), daemon=True)
        t2 = threading.Thread(target=pipe, args=(sock2, sock1), daemon=True)
        t1.start()
        t2.start()
        t1.join()
        t2.join()

    def start(self):
        """启动监听"""
        self.server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_sock.bind((self.host, self.port))
        self.server_sock.listen(128)
        self.running = True

        def loop():
            while self.running:
                try:
                    client, _ = self.server_sock.accept()
                    threading.Thread(target=self._handle_client, args=(client,), daemon=True).start()
                except Exception:
                    break

        threading.Thread(target=loop, daemon=True, name="netns-bridge").start()

    def stop(self):
        """停止服务并强制切断存量下游连接"""
        self.running = False
        if hasattr(self, "conn_registry") and self.conn_registry:
            self.conn_registry.close_all()
        if self.server_sock:
            try:
                self.server_sock.close()
            except Exception:
                pass
            self.server_sock = None


class RaceConditionScheduler:
    """
    并发竞发调度器 (Race Condition Provisioning)：
    借鉴 miku-gate 核心工程亮点，同时并发尝试 Top N 个候选节点，
    先连通、先测速通过者胜出，其余候选立即优雅回收，实现 5~10 秒内极速建立隧道！
    """

    def __init__(self, ns_prefix: str = "aimili_ns", max_workers: int = 5):
        self.ns_prefix = ns_prefix
        self.max_workers = max_workers
        self.active_runner: Optional[NetnsOpenVpnRunner] = None
        self.lock = threading.Lock()

    def provision_fast(self, candidates: List[VpnGateNode], timeout: int = 15) -> Optional[NetnsOpenVpnRunner]:
        """并发竞发拉起最快可用节点"""
        if not candidates:
            return None

        # 选取前 max_workers 个候选节点
        test_nodes = candidates[:self.max_workers]
        winner_runner: Optional[NetnsOpenVpnRunner] = None
        stop_event = threading.Event()
        runners_lock = threading.Lock()
        active_runners: List[NetnsOpenVpnRunner] = []

        def worker(idx: int, node: VpnGateNode):
            nonlocal winner_runner
            tmp_ns = f"{self.ns_prefix}_{idx}"
            runner = NetnsOpenVpnRunner(tmp_ns)
            with runners_lock:
                active_runners.append(runner)

            # 在临时 netns 启动并尝试连通
            success = runner.start_tunnel(node, timeout=timeout)
            if success and not stop_event.is_set():
                with self.lock:
                    if not stop_event.is_set():
                        stop_event.set()
                        winner_runner = runner
                        return
            # 未胜出或失败，立即回收
            if runner != winner_runner:
                runner.stop_tunnel()
                LinuxNetnsManager.delete_netns(tmp_ns)

        threads = []
        for i, node in enumerate(test_nodes):
            t = threading.Thread(target=worker, args=(i, node), daemon=True)
            threads.append(t)
            t.start()

        # 等待首个获胜者或全部超时
        start_wait = time.time()
        while time.time() - start_wait < timeout + 2:
            if stop_event.is_set() and winner_runner:
                break
            time.sleep(0.5)

        # 清理所有非获胜者
        with runners_lock:
            for r in active_runners:
                if r != winner_runner:
                    r.stop_tunnel()
                    LinuxNetnsManager.delete_netns(r.ns_name)

        if winner_runner:
            # 停止之前的旧 runner
            if self.active_runner:
                self.active_runner.stop_tunnel()
                LinuxNetnsManager.delete_netns(self.active_runner.ns_name)
            self.active_runner = winner_runner
            return winner_runner

        return None


class AimiliResidentialDaemon:
    """
    AimiliVPN 动态住宅家宽守护总控服务：
    统合多源抓取、竞发建连、SOCKS5 代理网桥与出口 IP 巡检自愈
    """

    def __init__(self, bridge_port: int = 8500, target_country: Optional[str] = None, ns_prefix: str = "aimili_ns"):
        self.bridge_port = bridge_port
        self.target_country = target_country.upper() if target_country else None
        self.ns_prefix = ns_prefix
        self.scheduler = RaceConditionScheduler(ns_prefix=self.ns_prefix)
        self.bridge_server: Optional[NetnsBridgeServer] = None
        self.cooldown_pool = NodeCooldownPool()
        self.running = False
        self.current_ip: Optional[str] = None
        self.fail_count = 0

    def start(self):
        """启动守护总控服务"""
        self.running = True
        print(f"[*] AimiliVPN 住宅网桥启动中，监听本地端口: 127.0.0.1:{self.bridge_port} [命名空间: {self.ns_prefix}, 目标国家: {self.target_country or '全球最优'}]")
        
        # 首次拉起
        self.rotate_node()

        # 启动巡检线程
        threading.Thread(target=self._health_loop, daemon=True, name=f"health-check-{self.bridge_port}").start()

    def stop(self):
        """停止服务并释放网络命名空间与 SOCKS5 代理网桥"""
        self.running = False
        if self.bridge_server:
            self.bridge_server.stop()
            self.bridge_server = None
        if self.scheduler and self.scheduler.active_runner:
            self.scheduler.active_runner.stop_tunnel()
            LinuxNetnsManager.delete_netns(self.scheduler.active_runner.ns_name)
            self.scheduler.active_runner = None

    def get_status(self) -> dict:
        """获取当前槽位守护实例运行状态"""
        runner = self.scheduler.active_runner if self.scheduler else None
        current_node_str = str(runner.current_node) if (runner and runner.current_node) else None
        return {
            "bridge_port": self.bridge_port,
            "target_country": self.target_country,
            "ns_prefix": self.ns_prefix,
            "running": self.running,
            "current_ip": self.current_ip,
            "current_node": current_node_str,
            "fail_count": self.fail_count
        }

    def rotate_node(self) -> bool:
        """执行换线操作"""
        country_label = self.target_country or "全球最优"
        print(f"[*] 正在抓取最新住宅节点池 [{country_label}] 并启动竞发建连...")
        try:
            candidates = VpnGateFetcher.get_nodes(
                timeout=12,
                residential_only=True,
                target_country=self.target_country,
                prescreen_tcp=True
            )
            # 过滤掉处于冷却惩罚期内的假活/异常节点
            candidates = self.cooldown_pool.filter_candidates(candidates)
            if not candidates:
                print(f"[!] 未获取到符合条件的家宽节点 [{country_label}]（可能节点暂时处于冷却惩罚期）！")
                return False

            print(f"[+] 筛选出 {len(candidates)} 个优质存活家宽节点 [{country_label}]，并发拉起竞发测试...")
            runner = self.scheduler.provision_fast(candidates, timeout=12)
            if runner:
                self.current_ip = runner.assigned_ip
                print(f"[√] 竞发胜出！成功建立住宅隧道 [{country_label}]: {runner.current_node} -> 出口IP: {self.current_ip}")

                # 建立/重启 SOCKS5 网桥 (主动切断旧下游 Socket，促成客户端立即重连新隧道)
                if self.bridge_server:
                    if hasattr(self.bridge_server, "conn_registry"):
                        closed_cnt = self.bridge_server.conn_registry.close_all()
                        if closed_cnt > 0:
                            print(f"[*] 节点已切换，主动切断 {closed_cnt} 个存量下游黑洞连接，促成客户端重连新隧道！")
                    self.bridge_server.stop()
                self.bridge_server = NetnsBridgeServer(runner.ns_name, port=self.bridge_port)
                self.bridge_server.start()
                self.fail_count = 0
                return True
            else:
                print(f"[!] 竞发候选建连均未成功 [{country_label}]，稍后重试。")
                return False
        except Exception as e:
            print(f"[!] 换线失败 [{country_label}]: {e}")
            return False

    def _health_loop(self):
        """定期巡检与自愈守护循环"""
        while self.running:
            time.sleep(15)
            if not self.scheduler.active_runner:
                self.rotate_node()
                continue

            alive = self.scheduler.active_runner.is_alive()
            if not alive:
                self.fail_count += 1
                bad_node = self.scheduler.active_runner.current_node
                print(f"[!] 隧道健康检查未通过 (端口 {self.bridge_port}, 第 {self.fail_count} 次检测)...")
                if self.fail_count >= 2:
                    if bad_node and bad_node.ip:
                        self.cooldown_pool.mark_bad(bad_node.ip, "健康检查连续两次失败或出口IP漂移")
                    print(f"[!] 判定当前家宽节点已失效或 IP 漂移 (端口 {self.bridge_port})，自动触发无感换线自愈！")
                    self.rotate_node()
            else:
                self.fail_count = 0


class ResidentialSlot:
    """
    单个 Netns 住宅网桥槽位实例：
    封装独立网络命名空间、本地 SOCKS5 监听端口、目标过滤国家与守护进程。
    """

    def __init__(self, slot_id: str, port: int = 8500, target_country: Optional[str] = None, name: Optional[str] = None):
        self.slot_id = str(slot_id)
        self.port = int(port)
        self.target_country = target_country.upper() if target_country else None
        self.name = name or (f"{self.target_country}住宅" if self.target_country else "全球最优")
        self.ns_name = f"aimili_ns_{slot_id}"
        self.daemon: Optional[AimiliResidentialDaemon] = None

    def to_dict(self) -> dict:
        current_ip = self.daemon.current_ip if (self.daemon and self.daemon.current_ip) else None
        current_node = str(self.daemon.scheduler.active_runner.current_node) if (self.daemon and self.daemon.scheduler and self.daemon.scheduler.active_runner and self.daemon.scheduler.active_runner.current_node) else None
        running = self.daemon.running if self.daemon else False
        return {
            "slot_id": self.slot_id,
            "tag": f"resi_{self.slot_id}" if self.slot_id != "0" else "resi_global",
            "name": self.name,
            "port": self.port,
            "target_country": self.target_country,
            "ns_name": self.ns_name,
            "current_ip": current_ip,
            "current_node": current_node,
            "status": "running" if running else "stopped"
        }


class AimiliMultiSlotManager:
    """
    Sing-box 原生多国家住宅出口多槽位矩阵管理器 (Phase 3)：
    统一调度与编排多个独立的 Netns 家宽隧道槽位：
      - 槽位 0: SOCKS5 8500 (默认全球最优家宽，向后 100% 兼容)
      - 槽位 1: SOCKS5 8502 (目标国: US 美国住宅家宽)
      - 槽位 2: SOCKS5 8503 (目标国: JP 日本住宅家宽)
    支持槽位状态持久化输出与读取 (slots_state.json)，无缝供给 Sing-box 与订阅生成器。
    """
    DEFAULT_STATE_FILE = "/opt/aimilivpn/vpngate_data/slots_state.json"

    def __init__(self, state_file: Optional[str] = None):
        self.state_file = state_file or self.DEFAULT_STATE_FILE
        self.slots: dict[str, ResidentialSlot] = {}
        self.lock = threading.Lock()

    def add_slot(self, slot_id: str, port: int, target_country: Optional[str] = None, name: Optional[str] = None) -> ResidentialSlot:
        with self.lock:
            slot = ResidentialSlot(slot_id, port, target_country, name)
            self.slots[str(slot_id)] = slot
            return slot

    def remove_slot(self, slot_id: str) -> bool:
        with self.lock:
            slot_id = str(slot_id)
            if slot_id in self.slots:
                slot = self.slots[slot_id]
                if slot.daemon and slot.daemon.running:
                    slot.daemon.stop()
                del self.slots[slot_id]
                return True
            return False

    def configure_default_matrix(self):
        """配置推荐的多国家住宅矩阵：0: 8500 (全球最优), 1: 8502 (US), 2: 8503 (JP)"""
        self.add_slot("0", 8500, None, "全球最优")
        self.add_slot("1", 8502, "US", "美国住宅")
        self.add_slot("2", 8503, "JP", "日本住宅")

    def start_slot(self, slot_id: str) -> bool:
        with self.lock:
            slot_id = str(slot_id)
            if slot_id not in self.slots:
                return False
            slot = self.slots[slot_id]
            if slot.daemon and slot.daemon.running:
                return True
            daemon = AimiliResidentialDaemon(
                bridge_port=slot.port,
                target_country=slot.target_country,
                ns_prefix=slot.ns_name
            )
            slot.daemon = daemon
            daemon.start()
            return True

    def stop_slot(self, slot_id: str) -> bool:
        with self.lock:
            slot_id = str(slot_id)
            if slot_id in self.slots:
                slot = self.slots[slot_id]
                if slot.daemon:
                    slot.daemon.stop()
                    slot.daemon = None
                return True
            return False

    def start_all(self):
        for slot_id in list(self.slots.keys()):
            self.start_slot(slot_id)

    def stop_all(self):
        for slot_id in list(self.slots.keys()):
            self.stop_slot(slot_id)

    def get_state(self) -> dict:
        with self.lock:
            slot_list = [slot.to_dict() for slot in self.slots.values()]
            return {
                "slots": slot_list,
                "total_slots": len(slot_list),
                "updated_at": int(time.time())
            }

    def save_state(self, filepath: Optional[str] = None) -> bool:
        target_path = filepath or self.state_file
        try:
            data = self.get_state()
            dir_name = os.path.dirname(os.path.abspath(target_path))
            if dir_name:
                os.makedirs(dir_name, exist_ok=True)
            tmp_file = f"{target_path}.tmp.{os.getpid()}"
            with open(tmp_file, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
            shutil.move(tmp_file, target_path)
            return True
        except Exception as e:
            print(f"[!] 保存槽位状态失败 ({target_path}): {e}")
            return False

    def load_state(self, filepath: Optional[str] = None) -> bool:
        target_path = filepath or self.state_file
        if not os.path.isfile(target_path):
            return False
        try:
            with open(target_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            slots_info = data.get("slots", [])
            with self.lock:
                self.slots.clear()
                for s in slots_info:
                    slot = ResidentialSlot(
                        slot_id=s["slot_id"],
                        port=int(s["port"]),
                        target_country=s.get("target_country"),
                        name=s.get("name")
                    )
                    self.slots[str(s["slot_id"])] = slot
            return True
        except Exception as e:
            print(f"[!] 加载槽位状态失败 ({target_path}): {e}")
            return False


if __name__ == "__main__":
    print("=== AimiliVPN VpnGate 现代化引擎诊断 ===")
    print(f"Linux netns 支持状态: {LinuxNetnsManager.is_supported()}")
    try:
        print("正在获取 VPN Gate 节点列表 (带镜像容灾与住宅过滤)...")
        nodes = VpnGateFetcher.get_nodes(timeout=10, residential_only=True)
        print(f"获取成功！共筛选出 {len(nodes)} 个真实住宅家宽节点。")
        for n in nodes[:5]:
            print(f"  * {n}")
    except Exception as e:
        print(f"获取节点失败: {e}")

