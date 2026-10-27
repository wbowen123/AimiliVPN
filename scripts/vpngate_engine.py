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

    def __repr__(self):
        res_str = "🏠家宽" if self.is_residential else "🏢机房"
        return f"<Node [{self.country_short}] {self.ip} ({self.hostname[:16]}) {self.speed_mbps}Mbps {res_str}>"


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
                  target_country: Optional[str] = None) -> List[VpnGateNode]:
        """一站式抓取、过滤并排序好的节点池"""
        raw = cls.fetch_raw_csv(timeout=timeout)
        return cls.parse_nodes(raw, residential_only=residential_only, target_country=target_country)


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

        # 调整 ovpn 配置以适配 netns
        cleaned_lines = []
        for line in ovpn_content.splitlines():
            l_str = line.strip()
            # 避免启动冲突指令
            if l_str.startswith(("up ", "down ", "dhcp-option")):
                continue
            cleaned_lines.append(line)
        cleaned_lines.append("nobind")
        cleaned_lines.append("persist-tun")
        cleaned_lines.append("persist-key")
        cleaned_lines.append("verb 3")

        fd, path = tempfile.mkstemp(prefix=f"ovpn_{self.ns_name}_", suffix=".ovpn")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write("\n".join(cleaned_lines) + "\n")
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
        """极简高效 SOCKS5 协议处理"""
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
        """停止服务"""
        self.running = False
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

    def __init__(self, bridge_port: int = 8500, target_country: Optional[str] = None):
        self.bridge_port = bridge_port
        self.target_country = target_country
        self.scheduler = RaceConditionScheduler()
        self.bridge_server: Optional[NetnsBridgeServer] = None
        self.running = False
        self.current_ip: Optional[str] = None
        self.fail_count = 0

    def start(self):
        """启动守护总控服务"""
        self.running = True
        print(f"[*] AimiliVPN 住宅网桥启动中，监听本地端口: 127.0.0.1:{self.bridge_port}")
        
        # 首次拉起
        self.rotate_node()

        # 启动巡检线程
        threading.Thread(target=self._health_loop, daemon=True, name="health-check").start()

    def rotate_node(self) -> bool:
        """执行换线操作"""
        print("[*] 正在抓取最新住宅节点池并启动竞发建连...")
        try:
            candidates = VpnGateFetcher.get_nodes(
                timeout=12,
                residential_only=True,
                target_country=self.target_country
            )
            if not candidates:
                print("[!] 未获取到符合条件的家宽节点！")
                return False

            print(f"[+] 筛选出 {len(candidates)} 个优质家宽节点，并发拉起竞发测试...")
            runner = self.scheduler.provision_fast(candidates, timeout=12)
            if runner:
                self.current_ip = runner.assigned_ip
                print(f"[√] 竞发胜出！成功建立住宅隧道: {runner.current_node} -> 出口IP: {self.current_ip}")

                # 建立/重启 SOCKS5 网桥
                if self.bridge_server:
                    self.bridge_server.stop()
                self.bridge_server = NetnsBridgeServer(runner.ns_name, port=self.bridge_port)
                self.bridge_server.start()
                self.fail_count = 0
                return True
            else:
                print("[!] 竞发候选建连均未成功，稍后重试。")
                return False
        except Exception as e:
            print(f"[!] 换线失败: {e}")
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
                print(f"[!] 隧道健康检查未通过 (第 {self.fail_count} 次检测)...")
                if self.fail_count >= 2:
                    print("[!] 判定当前家宽节点已失效或 IP 漂移，自动触发无感换线自愈！")
                    self.rotate_node()
            else:
                self.fail_count = 0


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
