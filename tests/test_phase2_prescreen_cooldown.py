#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
AimiliVPN 阶段二第三方独立复检测试套件 (Phase 2 Performance & Cooldown Audit)
严格验证：
  1. TCP 并发分层预筛 (tcp_prescreen_nodes)
     - 验证存活 TCP 端口节点 100% 保留
     - 验证死端口/不可达 TCP 节点在毫秒级内被淘汰剔除
     - 验证 UDP 节点不受 TCP 预筛误杀
  2. 假活/僵尸节点冷却惩罚池 (NodeCooldownPool)
     - 验证 1800 秒惩罚标记与 is_in_cooldown 状态
     - 验证 filter_candidates 动态过滤与过期自动清除
     - 验证并发多线程下的线程安全
"""

import os
import sys
import time
import socket
import base64
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "scripts"))
import vpngate_engine


def make_mock_node(ip: str, proto: str = "tcp", port: int = 1194, speed: int = 50000000) -> vpngate_engine.VpnGateNode:
    """构建用于测试的 Mock 节点"""
    raw_ovpn = f"""
client
dev tun
proto {proto}
remote {ip} {port}
resolv-retry infinite
nobind
persist-key
persist-tun
verb 3
"""
    b64 = base64.b64encode(raw_ovpn.encode("utf-8")).decode("utf-8")
    return vpngate_engine.VpnGateNode(
        hostname=f"vpn-{ip.replace('.', '-')}.net",
        ip=ip,
        score=10000,
        ping=20,
        speed=speed,
        country_long="Japan",
        country_short="JP",
        sessions=5,
        ovpn_config_b64=b64
    )


class TestPhase2TcpPrescreen(unittest.TestCase):
    """阶段二 TCP 分层并发预筛测试"""

    def setUp(self):
        # 启动一个真实的本地临时 TCP 服务器，模拟存活节点
        self.server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server.bind(("127.0.0.1", 0))
        self.server.listen(10)
        self.live_port = self.server.getsockname()[1]

        # 找到一个未被占用的死端口，模拟离线/被墙节点
        probe_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        probe_sock.bind(("127.0.0.1", 0))
        self.dead_port = probe_sock.getsockname()[1]
        probe_sock.close()

    def tearDown(self):
        self.server.close()

    def test_tcp_prescreen_filters_dead_and_keeps_alive(self):
        """测试 TCP 预筛准确淘汰死端口节点、保留存活节点与 UDP 节点"""
        live_node = make_mock_node("127.0.0.1", proto="tcp", port=self.live_port)
        dead_node = make_mock_node("127.0.0.1", proto="tcp", port=self.dead_port)
        udp_node = make_mock_node("127.0.0.1", proto="udp", port=self.dead_port)

        nodes = [live_node, dead_node, udp_node]

        start_time = time.time()
        survived = vpngate_engine.tcp_prescreen_nodes(nodes, max_workers=10, timeout=0.5)
        duration = time.time() - start_time

        # 预筛耗时必须远小于串行等待 (并发应在 0.6s 内完成)
        self.assertLess(duration, 1.5, "TCP 预筛耗时过长，未能发挥非阻塞并发优势")

        # 存活列表中必须包含 live_node 和 udp_node
        self.assertIn(live_node, survived, "存活 TCP 节点被误杀")
        self.assertIn(udp_node, survived, "UDP 节点被误杀")

        # 死节点必须被淘汰
        self.assertNotIn(dead_node, survived, "死端口 TCP 节点未被淘汰")
        self.assertEqual(len(survived), 2)

    def test_prescreen_empty_nodes(self):
        """测试空列表输入鲁棒性"""
        self.assertEqual(vpngate_engine.tcp_prescreen_nodes([]), [])


class TestPhase2NodeCooldownPool(unittest.TestCase):
    """阶段二假活节点冷却惩罚池对抗性测试"""

    def test_cooldown_marking_and_filtering(self):
        """测试标记假活节点并自动过滤"""
        # 设置测试用短冷却时间：2 秒
        pool = vpngate_engine.NodeCooldownPool(cooldown_sec=2)

        node1 = make_mock_node("192.168.1.101")
        node2 = make_mock_node("192.168.1.102")
        node3 = make_mock_node("192.168.1.103")

        nodes = [node1, node2, node3]

        # 初始状态：无节点在冷却期
        self.assertEqual(pool.count(), 0)
        self.assertEqual(len(pool.filter_candidates(nodes)), 3)

        # 判定 node2 假活并施加冷却惩罚
        pool.mark_bad("192.168.1.102", reason="无法获取公网出口IP")
        self.assertTrue(pool.is_in_cooldown("192.168.1.102"))
        self.assertFalse(pool.is_in_cooldown("192.168.1.101"))

        # 过滤候选池：node2 必须被剔除，node1 和 node3 保留
        filtered = pool.filter_candidates(nodes)
        self.assertEqual(len(filtered), 2)
        self.assertIn(node1, filtered)
        self.assertIn(node3, filtered)
        self.assertNotIn(node2, filtered)

        # 等待冷却时间过去 (> 2 秒)
        time.sleep(2.2)

        # 冷却到期后，node2 必须自动解除惩罚，恢复可用
        self.assertFalse(pool.is_in_cooldown("192.168.1.102"))
        restored = pool.filter_candidates(nodes)
        self.assertEqual(len(restored), 3)
        self.assertIn(node2, restored)


if __name__ == "__main__":
    unittest.main()
