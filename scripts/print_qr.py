#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
AimiliVPN 终端 ASCII / ANSI 二维码渲染器
支持调用 qrencode 原生生成高保真终端双色二维码，并提供跨平台安全回退
"""
import sys
import shutil
import subprocess

def print_terminal_qr(content, title="全生态聚合订阅二维码 (手机扫码一键导入)"):
    if not content:
        return

    print(f"\n\033[1m\033[36m📱 ========== 【{title}】 ==========\033[0m")
    
    # 优先尝试系统的 qrencode 工具
    if shutil.which("qrencode"):
        # 1. 尝试 ANSIUTF8 (最美观、体积小、半高字符)
        try:
            res = subprocess.run(
                ["qrencode", "-t", "ANSIUTF8", content],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True
            )
            if res.returncode == 0 and res.stdout.strip():
                print(res.stdout)
                print("\033[1m\033[32m💡 扫码技巧:\033[0m 支持 iOS 小火箭 (Shadowrocket)、Sing-box、Clash Verge 直接扫码识别！")
                print("\033[1m\033[36m======================================================================\033[0m\n")
                return
        except Exception:
            pass

        # 2. 尝试标准 ANSI
        try:
            res = subprocess.run(
                ["qrencode", "-t", "ANSI", content],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True
            )
            if res.returncode == 0 and res.stdout.strip():
                print(res.stdout)
                print("\033[1m\033[32m💡 扫码技巧:\033[0m 支持 iOS 小火箭 (Shadowrocket)、Sing-box、Clash Verge 直接扫码识别！")
                print("\033[1m\033[36m======================================================================\033[0m\n")
                return
        except Exception:
            pass

    # 若未安装 qrencode 或终端不支持
    print(f"\033[33m  * 订阅/节点 URL: \033[36m{content}\033[0m")
    print("\033[33m  * 提示: 当前 VPS 未安装 qrencode，已安全回退到文本展示。\033[0m")
    print("    如需在终端直接扫码，可执行: \033[1m\033[32mapt-get install -y qrencode\033[0m (或 yum/apk install qrencode)")
    print("\033[1m\033[36m======================================================================\033[0m\n")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        text = sys.argv[1].strip()
        header = sys.argv[2].strip() if len(sys.argv) > 2 else "全生态聚合订阅二维码 (手机扫码一键导入)"
        print_terminal_qr(text, header)
    else:
        print("用法: python3 print_qr.py <content> [title]")
