#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
AimiliVPN 质量门禁与全自动静态代码审查工具 (Code Quality Gate)
- 零第三方依赖，纯原生 Python 3 实现
- 覆盖 Shell 作用域、Python 静态符号分析、Nginx 语法规范、Sing-box 拓扑一致性

运行方式:
    python scripts/code_gate.py
"""

import os
import sys
import re
import glob
import ast
import builtins

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

class Color:
    GREEN = "\033[92m" if sys.platform != "win32" or "WT_SESSION" in os.environ else ""
    RED = "\033[91m" if sys.platform != "win32" or "WT_SESSION" in os.environ else ""
    YELLOW = "\033[93m" if sys.platform != "win32" or "WT_SESSION" in os.environ else ""
    CYAN = "\033[96m" if sys.platform != "win32" or "WT_SESSION" in os.environ else ""
    RESET = "\033[0m" if sys.platform != "win32" or "WT_SESSION" in os.environ else ""

errors = []
warnings = []

def report_error(file_path, line_no, message, code="P0"):
    rel = os.path.relpath(file_path, ROOT_DIR)
    loc = f"{rel}:{line_no}" if line_no else rel
    errors.append(f"[{code}] {loc} -> {message}")

def report_warning(file_path, line_no, message, code="P2"):
    rel = os.path.relpath(file_path, ROOT_DIR)
    loc = f"{rel}:{line_no}" if line_no else rel
    warnings.append(f"[{code}] {loc} -> {message}")


# ==========================================
# 1. Shell 脚本规约检查 (Shell Scope & Syntax)
# ==========================================
def check_shell_scripts():
    sh_files = glob.glob(os.path.join(ROOT_DIR, "**", "*.sh"), recursive=True)
    sh_files.append(os.path.join(ROOT_DIR, "install.sh"))
    sh_files = sorted(list(set(sh_files)))

    for sh in sh_files:
        if not os.path.isfile(sh):
            continue
        with open(sh, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()

        in_func = False
        brace_depth = 0

        for idx, raw_line in enumerate(lines, 1):
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue

            # 检测函数声明
            if re.match(r"^[a-zA-Z0-9_-]+\s*\(\)\s*\{", line) or re.match(r"^function\s+[a-zA-Z0-9_-]+", line):
                in_func = True

            # 计算括号深度
            # 过滤掉双引号或单引号内的花括号
            unquoted = re.sub(r"\"[^\"]*\"|'[^']*'", "", line)
            brace_depth += unquoted.count("{") - unquoted.count("}")

            if brace_depth <= 0:
                in_func = False
                brace_depth = 0

            # 致命规则 P0: 禁止在函数外部使用 local
            if not in_func and re.match(r"^local\s+[a-zA-Z0-9_-]+", line):
                report_error(sh, idx, f"关键字 'local' 必须在函数体内使用，在全局执行会导致 bash 运行时报错: '{line}'", "P0-SHELL")

            # 警告规则 P2: 弱密码或硬编码高危变量
            if "chmod 777" in line:
                report_warning(sh, idx, "检测到 chmod 777 高权限赋值，建议降为 755 或 600", "P2-SECURITY")

            # 检查脚本是否存在 Windows CRLF 换行符
            if "\r\n" in raw_line and idx == 1:
                report_warning(sh, idx, "检测到 CRLF 换行符，在 Linux VPS 执行可能会抛出 '\r: command not found'，建议转为 LF", "P2-ENCODING")


# ==========================================
# 2. Python 静态符号与未定义变量检查 (Python AST Analysis)
# ==========================================
def check_python_scripts():
    py_files = glob.glob(os.path.join(ROOT_DIR, "**", "*.py"), recursive=True)
    builtin_names = set(dir(builtins))

    for py in py_files:
        if not os.path.isfile(py):
            continue
        with open(py, "r", encoding="utf-8", errors="ignore") as f:
            code = f.read()

        try:
            tree = ast.parse(code, filename=py)
        except SyntaxError as e:
            report_error(py, e.lineno, f"Python 语法错误: {e.msg}", "P0-PY-SYNTAX")
            continue

        # 收集顶级与局部已定义符号
        defined_names = set(builtin_names)
        defined_names.update(["__file__", "__name__", "__doc__", "__package__"])

        # 第一遍：收集所有 import 和定义的类与函数
        for node in ast.walk(tree):
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                defined_names.add(node.name)
            elif isinstance(node, ast.Import):
                for alias in node.names:
                    defined_names.add(alias.asname or alias.name.split(".")[0])
            elif isinstance(node, ast.ImportFrom):
                for alias in node.names:
                    defined_names.add(alias.asname or alias.name)
            elif isinstance(node, ast.Assign):
                for target in node.targets:
                    if isinstance(target, ast.Name):
                        defined_names.add(target.id)

        # 第二遍：扫描顶级或函数内的直接函数调用 node.func (类型为 Name)
        # 例如 get_web_auth_data() -> Name(id='get_web_auth_data')
        for node in ast.walk(tree):
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
                func_name = node.func.id
                if func_name not in defined_names:
                    report_error(py, node.lineno, f"调用了未定义的函数或符号: '{func_name}()'，运行时会抛出 NameError！", "P0-PY-UNDEFINED")


# ==========================================
# 3. Nginx 语法与反向代理规范检查 (Nginx Validator)
# ==========================================
def check_nginx_configs():
    conf_files = glob.glob(os.path.join(ROOT_DIR, "**", "*.conf"), recursive=True)

    for conf in conf_files:
        if not os.path.isfile(conf):
            continue
        with open(conf, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()

        # 检查正则 location 中包含 URI 的 proxy_pass (Nginx emerg 致命崩溃)
        regex_locations = re.finditer(r"location\s+~[^{]*\{([^}]+)\}", content)
        for loc in regex_locations:
            block = loc.group(1)
            uri_pass = re.search(r"proxy_pass\s+(https?://[^;/\s]+/[^;\s]+);", block)
            if uri_pass:
                report_error(conf, None, f"Nginx 正则匹配 location 中不允许 proxy_pass 带有 URI 路径 (会引发 [emerg] cannot have URI part): '{uri_pass.group(1)}'", "P0-NGINX")

        # 检查是否包含 80 端口到 80 端口的无限死循环重定向
        if re.search(r"listen\s+80;[^{]*server_name\s+([^;]+);[^{]*return\s+301\s+http://\1", content):
            report_error(conf, None, "检测到端口 80 重定向到 http:// 同域名（会导致 301 无限重定向死循环）", "P1-NGINX-LOOP")


# ==========================================
# 4. Sing-box 与订阅配置拓扑一致性核对 (Topology Consistency)
# ==========================================
def check_topology_consistency():
    subs_py = os.path.join(ROOT_DIR, "scripts", "generate_subs.py")
    if not os.path.isfile(subs_py):
        return

    with open(subs_py, "r", encoding="utf-8") as f:
        content = f.read()

    # 拓扑核对 1: VMess 直连 (8445) 必须是明文传输 (非 TLS)
    if 'port": 8445' in content and ('"tls": True' in content or '"tls": "tls"' in content):
        report_error(subs_py, None, "8445 直连 VMess 节点设置了 TLS=True，但本地 8445 是明文 HTTP 监听，握手将必定失败！", "P1-TOPOLOGY")

    # 拓扑核对 2: Sing-box 客户端 DNS 是否仍有劫持全局全部域名的规则
    if '"outbound": ["any"], "server": "local-dns"' in content:
        report_error(subs_py, None, "Sing-box 订阅 DNS 包含通配劫持 'outbound: [\"any\"] -> local-dns'，会导致节点分流失效！", "P1-DNS-HIJACK")

    # 拓扑核对 3: Sing-box 1.14+ 废弃协议检查
    if '"address": "local"' in content:
        report_warning(subs_py, None, "Sing-box DNS 规则中 'address: local' 已废弃，建议使用 'type: local' 或 'type: udp'", "P2-DEPRECATION")


# ==========================================
# 主入口
# ==========================================
def main():
    print(f"{Color.CYAN}===================================================={Color.RESET}")
    print(f"{Color.CYAN}  AimiliVPN 自动化架构与代码质量门禁 (Code Gate)      {Color.RESET}")
    print(f"{Color.CYAN}===================================================={Color.RESET}")

    check_shell_scripts()
    check_python_scripts()
    check_nginx_configs()
    check_topology_consistency()

    if warnings:
        print(f"\n{Color.YELLOW}[!] 检测到 {len(warnings)} 个警告项 (P2/P3):{Color.RESET}")
        for w in warnings:
            print(f"  {Color.YELLOW}* {w}{Color.RESET}")

    if errors:
        print(f"\n{Color.RED}[X] 门禁拦截！检测到 {len(errors)} 个致命或功能阻断错误 (P0/P1):{Color.RESET}")
        for e in errors:
            print(f"  {Color.RED}* {e}{Color.RESET}")
        print(f"\n{Color.RED}质量门禁未通过，请修复上述问题后再提交或发布。{Color.RESET}\n")
        sys.exit(1)
    else:
        print(f"\n{Color.GREEN}[√] 质量门禁全绿通过！无 P0/P1 阻塞性缺陷，代码与拓扑结构健康。{Color.RESET}\n")
        sys.exit(0)

if __name__ == "__main__":
    main()
