#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
阶段三 (Phase 3) 独立第三方对抗性测试套件：
深度核验：
  1. AimiliMultiSlotManager 多槽位编排、端口隔离、状态持久化与恢复 (slots_state.json)
  2. Sing-box 服务端多出站与多用户动态注入 (resi-us-out, resi-jp-out, residential-*-user)
  3. 客户端聚合订阅引擎多国家矩阵生成 (Base64 / Clash Meta / Sing-box 客户端配置)
  4. 无多槽位配置时的 100% 向后兼容性保证
"""

import os
import sys
import json
import base64
import tempfile
import unittest

# 引入被测模块
ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT_DIR, "scripts"))

from vpngate_engine import AimiliMultiSlotManager, ResidentialSlot, AimiliResidentialDaemon
from generate_subs import generate_subscriptions


class TestPhase3MultiSlotSubs(unittest.TestCase):
    """阶段三：多槽位住宅网桥矩阵与订阅协同对抗测试"""

    def test_multi_slot_manager_lifecycle_and_persistence(self):
        """测试 1: MultiSlotManager 槽位注册、状态提取、原子保存与无损加载"""
        with tempfile.TemporaryDirectory() as tmpdir:
            state_file = os.path.join(tmpdir, "slots_state.json")
            mgr = AimiliMultiSlotManager(state_file=state_file)

            # 配置推荐三槽位矩阵
            mgr.configure_default_matrix()
            self.assertEqual(len(mgr.slots), 3)
            self.assertIn("0", mgr.slots)
            self.assertIn("1", mgr.slots)
            self.assertIn("2", mgr.slots)

            # 验证各槽位属性
            slot0 = mgr.slots["0"]
            self.assertEqual(slot0.port, 8500)
            self.assertIsNone(slot0.target_country)
            self.assertEqual(slot0.ns_name, "aimili_ns_0")

            slot1 = mgr.slots["1"]
            self.assertEqual(slot1.port, 8502)
            self.assertEqual(slot1.target_country, "US")
            self.assertEqual(slot1.ns_name, "aimili_ns_1")

            slot2 = mgr.slots["2"]
            self.assertEqual(slot2.port, 8503)
            self.assertEqual(slot2.target_country, "JP")
            self.assertEqual(slot2.ns_name, "aimili_ns_2")

            # 导出状态
            state = mgr.get_state()
            self.assertEqual(state["total_slots"], 3)
            self.assertEqual(len(state["slots"]), 3)

            # 保存到磁盘
            saved = mgr.save_state()
            self.assertTrue(saved)
            self.assertTrue(os.path.isfile(state_file))

            with open(state_file, "r", encoding="utf-8") as f:
                disk_data = json.load(f)
            self.assertEqual(len(disk_data["slots"]), 3)

            # 验证新 manager 加载
            mgr2 = AimiliMultiSlotManager(state_file=state_file)
            loaded = mgr2.load_state()
            self.assertTrue(loaded)
            self.assertEqual(len(mgr2.slots), 3)
            self.assertEqual(mgr2.slots["1"].target_country, "US")
            self.assertEqual(mgr2.slots["1"].port, 8502)

            # 移除槽位测试
            removed = mgr2.remove_slot("1")
            self.assertTrue(removed)
            self.assertEqual(len(mgr2.slots), 2)
            self.assertNotIn("1", mgr2.slots)

    def test_generate_subs_with_multi_country_slots(self):
        """测试 2: 订阅引擎多国家住宅矩阵生成 (Base64 + Clash Meta + Singbox)"""
        with tempfile.TemporaryDirectory() as tmpdir:
            out_dir = os.path.join(tmpdir, "output")
            data_dir = os.path.join(tmpdir, "data")
            os.makedirs(out_dir, exist_ok=True)
            os.makedirs(data_dir, exist_ok=True)

            direct_uuid = "11111111-1111-1111-1111-111111111111"
            resi_uuid = "22222222-2222-2222-2222-222222222222"
            resi_us_uuid = "33333333-3333-3333-3333-333333333333"
            resi_jp_uuid = "44444444-4444-4444-4444-444444444444"

            nodes_data = {
                "public_ip": "192.0.2.1",
                "direct_uuid": direct_uuid,
                "resi_uuid": resi_uuid,
                "resi_us_uuid": resi_us_uuid,
                "resi_jp_uuid": resi_jp_uuid,
                "public_key": "TestPublicKeyVal1234567890=",
                "short_id": "0123456789abcdef",
                "vless_port": 443,
                "hy2_port": 443,
                "tuic_port": 8443,
                "anytls_port": 8444,
                "vmess_port": 8445,
                "data_dir": data_dir,
                "resi_slots": [
                    {"slot_id": "0", "port": 8500, "target_country": None, "name": "全球最优", "uuid": resi_uuid},
                    {"slot_id": "1", "port": 8502, "target_country": "US", "name": "美国住宅", "uuid": resi_us_uuid},
                    {"slot_id": "2", "port": 8503, "target_country": "JP", "name": "日本住宅", "uuid": resi_jp_uuid}
                ]
            }

            generate_subscriptions(nodes_data, out_dir)

            # 1. 验证 sub.txt
            sub_file = os.path.join(out_dir, "sub.txt")
            self.assertTrue(os.path.isfile(sub_file))
            with open(sub_file, "r", encoding="utf-8") as f:
                b64_content = f.read().strip()
            decoded = base64.b64decode(b64_content).decode("utf-8")
            import urllib.parse
            unquoted_decoded = urllib.parse.unquote(decoded)

            # 必须包含美国和日本独立住宅节点链接
            self.assertIn("住宅-家宽·美国住宅", unquoted_decoded)
            self.assertIn("住宅-家宽·日本住宅", unquoted_decoded)
            self.assertIn(resi_us_uuid, decoded)
            self.assertIn(resi_jp_uuid, decoded)

            # 2. 验证 clash.yaml
            clash_file = os.path.join(out_dir, "clash.yaml")
            self.assertTrue(os.path.isfile(clash_file))
            with open(clash_file, "r", encoding="utf-8") as f:
                clash_content = f.read()

            self.assertIn("住宅-家宽·美国住宅", clash_content)
            self.assertIn("住宅-家宽·日本住宅", clash_content)
            self.assertIn(resi_us_uuid, clash_content)
            self.assertIn(resi_jp_uuid, clash_content)

            # 3. 验证 singbox.json 客户端配置
            sb_file = os.path.join(out_dir, "singbox.json")
            self.assertTrue(os.path.isfile(sb_file))
            with open(sb_file, "r", encoding="utf-8") as f:
                sb_cfg = json.load(f)

            outbounds = sb_cfg.get("outbounds", [])
            sb_tags = [o.get("tag", "") for o in outbounds]

            us_nodes = [t for t in sb_tags if "美国住宅" in t]
            jp_nodes = [t for t in sb_tags if "日本住宅" in t]

            self.assertTrue(len(us_nodes) >= 2, f"未检测到足够的美国住宅出站: {us_nodes}")
            self.assertTrue(len(jp_nodes) >= 2, f"未检测到足够的日本住宅出站: {jp_nodes}")

            # 验证选流组中包含国家节点
            resi_group = next((o for o in outbounds if o.get("tag") == "🏠 住宅家宽 (自动优选)"), None)
            self.assertIsNotNone(resi_group)
            self.assertTrue(any("美国住宅" in t for t in resi_group.get("outbounds", [])))
            self.assertTrue(any("日本住宅" in t for t in resi_group.get("outbounds", [])))

    def test_singbox_server_multi_slot_dynamic_injection(self):
        """测试 3: 服务端 Sing-box 配置多国家住宅出站与入站用户动态注入逻辑"""
        base_cfg = {
            "inbounds": [
                {
                    "type": "vless",
                    "tag": "vless-in",
                    "users": [
                        {"name": "direct-user", "uuid": "direct-uuid-1", "flow": "xtls-rprx-vision"},
                        {"name": "residential-user", "uuid": "resi-uuid-0", "flow": "xtls-rprx-vision"}
                    ]
                },
                {
                    "type": "hysteria2",
                    "tag": "hy2-in",
                    "users": [
                        {"name": "direct-user", "password": "direct-uuid-1"},
                        {"name": "residential-user", "password": "resi-uuid-0"}
                    ]
                }
            ],
            "outbounds": [
                {"type": "direct", "tag": "direct-out"},
                {"type": "socks", "tag": "resi-out", "server": "127.0.0.1", "server_port": 8500, "version": "5"}
            ],
            "route": {
                "rules": [
                    {"auth_user": ["residential-user"], "outbound": "resi-out"},
                    {"auth_user": ["direct-user"], "outbound": "direct-out"}
                ],
                "final": "direct-out"
            }
        }

        # 模拟动态注入逻辑
        slots = [
            {"slot_id": "0", "port": 8500, "target_country": None},
            {"slot_id": "1", "port": 8502, "target_country": "US"},
            {"slot_id": "2", "port": 8503, "target_country": "JP"}
        ]
        country_uuids = {
            "US": "us-uuid-1234",
            "JP": "jp-uuid-5678"
        }

        for slot in slots:
            s_id = str(slot.get("slot_id"))
            if s_id in ("", "0"):
                continue
            s_port = int(slot.get("port", 8500))
            s_country = (slot.get("target_country") or "").upper()
            s_tag = f"resi-{s_country.lower() if s_country else s_id}-out"
            user_name = f"residential-{s_country.lower() if s_country else s_id}-user"
            u_uuid = country_uuids.get(s_country, "fallback-uuid")

            if not any(o.get("tag") == s_tag for o in base_cfg["outbounds"]):
                base_cfg["outbounds"].append({
                    "type": "socks",
                    "tag": s_tag,
                    "server": "127.0.0.1",
                    "server_port": s_port,
                    "version": "5"
                })

            for ib in base_cfg["inbounds"]:
                users = ib.get("users", [])
                if any(u.get("name") == user_name for u in users):
                    continue
                ib_type = ib.get("type")
                if ib_type == "vless":
                    users.append({"name": user_name, "uuid": u_uuid, "flow": "xtls-rprx-vision"})
                elif ib_type == "hysteria2":
                    users.append({"name": user_name, "password": u_uuid})

            rules = base_cfg["route"]["rules"]
            if not any(r.get("outbound") == s_tag for r in rules):
                insert_idx = len(rules) - 1 if len(rules) > 0 else 0
                rules.insert(insert_idx, {
                    "auth_user": [user_name],
                    "outbound": s_tag
                })

        # 验证注入结果
        outbound_tags = [o["tag"] for o in base_cfg["outbounds"]]
        self.assertIn("resi-us-out", outbound_tags)
        self.assertIn("resi-jp-out", outbound_tags)

        # 验证端口严格隔离
        us_ob = next(o for o in base_cfg["outbounds"] if o["tag"] == "resi-us-out")
        jp_ob = next(o for o in base_cfg["outbounds"] if o["tag"] == "resi-jp-out")
        self.assertEqual(us_ob["server_port"], 8502)
        self.assertEqual(jp_ob["server_port"], 8503)

        # 验证入站用户全协议注入
        vless_users = [u["name"] for u in base_cfg["inbounds"][0]["users"]]
        self.assertIn("residential-us-user", vless_users)
        self.assertIn("residential-jp-user", vless_users)

        # 验证分流规则正确插入且映射精准
        rule_map = {r["auth_user"][0]: r["outbound"] for r in base_cfg["route"]["rules"] if "auth_user" in r}
        self.assertEqual(rule_map["residential-us-user"], "resi-us-out")
        self.assertEqual(rule_map["residential-jp-user"], "resi-jp-out")
        self.assertEqual(rule_map["residential-user"], "resi-out")
        self.assertEqual(rule_map["direct-user"], "direct-out")

    def test_backward_compatibility_single_slot(self):
        """测试 4: 无多国家槽位配置时，严格保持原有单住宅节点行为"""
        with tempfile.TemporaryDirectory() as tmpdir:
            out_dir = os.path.join(tmpdir, "output")
            data_dir = os.path.join(tmpdir, "data")
            os.makedirs(out_dir, exist_ok=True)
            os.makedirs(data_dir, exist_ok=True)

            nodes_data = {
                "public_ip": "192.0.2.1",
                "direct_uuid": "11111111-1111-1111-1111-111111111111",
                "resi_uuid": "22222222-2222-2222-2222-222222222222",
                "public_key": "TestPublicKeyVal1234567890=",
                "short_id": "0123456789abcdef",
                "vless_port": 443,
                "hy2_port": 443,
                "tuic_port": 8443,
                "anytls_port": 8444,
                "vmess_port": 8445,
                "data_dir": data_dir
            }

            generate_subscriptions(nodes_data, out_dir)

            sb_file = os.path.join(out_dir, "singbox.json")
            with open(sb_file, "r", encoding="utf-8") as f:
                sb_cfg = json.load(f)

            outbounds = sb_cfg.get("outbounds", [])
            sb_tags = [o.get("tag", "") for o in outbounds]

            # 严禁出现未经配置的国家住宅节点
            self.assertFalse(any("美国住宅" in t for t in sb_tags))
            self.assertFalse(any("日本住宅" in t for t in sb_tags))
            # 基础住宅节点必须正常存在
            self.assertTrue(any("住宅-家宽" in t for t in sb_tags))


if __name__ == "__main__":
    unittest.main()
