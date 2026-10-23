#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
AimiliVPN 自动化架构与代码质量门禁 (Code Gate) - V2.0 深度加固版
- 零第三方依赖，纯原生 Python 3 实现
- 深度覆盖：
  1. Sing-box 1.13+ / 1.14+ 内核破坏性变更 (sniff, WireGuard endpoint, dns-out, DNS rules)
  2. 端到端协议与拓扑闭环 (客户端 ↔ 服务端协议匹配, Argo 域名隔离, 端口映射)
  3. 防火墙与安全策略 (8500 公网放行拦截, 8446 端口放行闭环)
  4. Shell 静态语义与作用域 (未定义致命变量, set -e 陷阱, 函数外 local, sed 配置污染)
  5. Python AST 作用域感知符号分析
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


# ==============================================================================
# 1. Sing-box 1.13+ / 1.14+ 内核规范与破坏性变更检查 (Sing-box Kernel Spec)
# ==============================================================================
def check_singbox_confs():
    # 1.1 检查 setup_singbox.sh 服务端 inbound 是否包含已废弃被移除的 sniff
    sb_sh = os.path.join(ROOT_DIR, "scripts", "setup_singbox.sh")
    if os.path.isfile(sb_sh):
        with open(sb_sh, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
            lines = content.splitlines()

        for idx, line in enumerate(lines, 1):
            if re.search(r'"sniff"\s*:\s*true', line) or re.search(r'"sniff_override_destination"', line):
                report_error(sb_sh, idx, "Sing-box ≥1.13 已彻底移除 inbound 内部的 sniff 字段，加载直接返回 error 终止！必须迁移至 route.rules 中的 {\"action\": \"sniff\"}", "P0-SB-SNIFF")

    # 1.2 检查 setup_warp.sh 是否包含 1.12 legacy WireGuard outbound 扁平字段
    warp_sh = os.path.join(ROOT_DIR, "scripts", "setup_warp.sh")
    if os.path.isfile(warp_sh):
        with open(warp_sh, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()

        if '"type": "wireguard"' in content:
            # 检查是否有 legacy 字段直接写在 outbound 里
            legacy_fields = ["server_port", "local_address", "peer_public_key"]
            for lf in legacy_fields:
                if f'"{lf}"' in content:
                    report_error(warp_sh, None, f"Sing-box 1.14+ 已移除 Legacy WireGuard outbound 扁平结构中的 '{lf}' 字段，必须改用 1.14+ 标准的 endpoints + peers 嵌套结构！", "P0-SB-WARP-LEGACY")
                    break

    # 1.3 检查 generate_subs.py 客户端 singbox.json
    subs_py = os.path.join(ROOT_DIR, "scripts", "generate_subs.py")
    if os.path.isfile(subs_py):
        with open(subs_py, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()

        # 检查废弃的 dns outbound
        if '"type": "dns"' in content and '"dns-out"' in content:
            report_error(subs_py, None, "Sing-box ≥1.13 客户端配置已彻底移除 'dns' outbound，加载即报错！DNS 必须交由 route.rules 中的 {\"action\": \"hijack-dns\"} 处理", "P1-SB-DNS-OUT")

        # 检查废弃的 dns rule geosite
        if re.search(r'\{"geosite":\s*\["cn"\]\s*,\s*"server":\s*"local-dns"\}', content):
            report_error(subs_py, None, "Sing-box 1.14+ 客户端 DNS 规则中的 'geosite' 字段已被移除，必须使用 rule_set 引用！", "P1-SB-DNS-RULE")

        # 检查 clash_mode 是否误写为数组
        if '"clash_mode": ["Direct"]' in content or '"clash_mode": ["direct"]' in content:
            report_error(subs_py, None, "Sing-box 客户端 DNS 规则中 'clash_mode' 必须为字符串类型 (如 \"Direct\")，误写为数组会导致客户端类型解析报错！", "P1-SB-CLASH-MODE")


# ==============================================================================
# 2. 端到端协议与拓扑一致性闭环核查 (Topology & Protocol Invariant)
# ==============================================================================
def check_topology_consistency():
    subs_py = os.path.join(ROOT_DIR, "scripts", "generate_subs.py")
    sb_sh = os.path.join(ROOT_DIR, "scripts", "setup_singbox.sh")

    if os.path.isfile(subs_py):
        with open(subs_py, "r", encoding="utf-8", errors="ignore") as f:
            subs_content = f.read()

        # 拓扑核对 1: VMess 直连 (8445) 必须是明文传输 (非 TLS)
        if 'port": 8445' in subs_content and ('"tls": True' in subs_content or '"tls": "tls"' in subs_content):
            report_error(subs_py, None, "8445 直连 VMess 节点设置了 TLS=True，但本地 8445 是明文 HTTP 监听，握手将必定失败！", "P1-TOPOLOGY-TLS")

        # 拓扑核对 2: 客户端 /vmess-ws 节点协议必须与服务端 inbound 协议严格匹配 (P0-3)
        # 服务端 /vmess-ws (8446) 是 vmess，客户端若写了 vless，则握手必败
        if re.search(r'vless://[^\s"\']*vmess-ws', subs_content) or re.search(r'"type":\s*"vless"[^}]*vmess-ws', subs_content):
            if os.path.isfile(sb_sh):
                with open(sb_sh, "r", encoding="utf-8", errors="ignore") as sf:
                    sb_content = sf.read()
                if '"vmess-ws-in"' in sb_content and '"type": "vmess"' in sb_content:
                    report_error(subs_py, None, "客户端 /vmess-ws CDN 节点配置为 VLESS 协议，但服务端 8446 (vmess-ws-in) 监听的是 VMess 协议！协议不匹配握手必然失败！", "P0-PROTOCOL-MISMATCH")

        # 拓扑核对 3: Argo 域名严禁污染小黄云 CDN 节点 (P1-9)
        if re.search(r'cdn_target_domain\s*=\s*argo_domain\s+if\s+argo_domain\s+else\s+cdn_host', subs_content):
            report_error(subs_py, None, "generate_subs.py 中 Argo 域名直接覆盖了 cdn_target_domain，导致小黄云 CDN 节点 SNI/Host 错位全废！", "P1-ARGO-POLLUTION")

        # 拓扑核对 4: Sing-box 客户端 DNS 是否仍有劫持全局全部域名的规则
        if '"outbound": ["any"], "server": "local-dns"' in subs_content:
            report_error(subs_py, None, "Sing-box 订阅 DNS 包含通配劫持 'outbound: [\"any\"] -> local-dns'，会导致节点分流失效！", "P1-DNS-HIJACK")

    # 拓扑核对 5: 8446 端口全链路放行与监控 (P1-4)
    inst_sh = os.path.join(ROOT_DIR, "install.sh")
    if os.path.isfile(inst_sh):
        with open(inst_sh, "r", encoding="utf-8", errors="ignore") as f:
            inst_c = f.read()
        if 'AIMILI_FW_PORTS=' in inst_c and '8446' not in inst_c.split('AIMILI_FW_PORTS=')[1].split('\n')[0]:
            report_error(inst_sh, None, "AIMILI_FW_PORTS 中遗漏了 8446 端口！", "P1-FW-8446")

    health_sh = os.path.join(ROOT_DIR, "scripts", "check_health.sh")
    if os.path.isfile(health_sh):
        with open(health_sh, "r", encoding="utf-8", errors="ignore") as f:
            h_c = f.read()
        if '8446' not in h_c:
            report_warning(health_sh, None, "check_health.sh 端口巡检列表未包含 8446 端口，无法自愈监听故障", "P2-HEALTH-8446")

    # 拓扑核对 6: 本地动态住宅 8500 端口公网放行安全审查 (P2-4)
    https_sh = os.path.join(ROOT_DIR, "scripts", "setup_https.sh")
    if os.path.isfile(https_sh):
        with open(https_sh, "r", encoding="utf-8", errors="ignore") as f:
            ht_c = f.read()
        if "ufw allow 8500" in ht_c or "add-port=8500" in ht_c:
            report_error(https_sh, None, "setup_https.sh 将本地动态家宽 SOCKS5 8500 端口放行到公网，存在严重未授权代理盗用风险！", "P2-SECURITY-8500")

    # 拓扑核对 7: IP 漂移 json 同步审查 (P1-5)
    cron_sh = os.path.join(ROOT_DIR, "scripts", "setup_cron.sh")
    if os.path.isfile(cron_sh):
        with open(cron_sh, "r", encoding="utf-8", errors="ignore") as f:
            cr_c = f.read()
        if 'echo "${cur_ip}" > "${ip_file}"' in cr_c and 'singbox_nodes.json' in cr_c:
            # 检查是否有更新 json public_ip 字段的代码
            if 'public_ip' not in cr_c:
                report_error(cron_sh, None, "setup_cron.sh 检测到公网 IP 变动时只更新了 txt 文件，未同步修改 singbox_nodes.json，导致订阅 IP 实际未更新！", "P1-CRON-JSON-DRIFT")


# ==============================================================================
# 3. Shell 脚本语义、变量未定义与作用域检查 (Shell Linter)
# ==============================================================================
def check_shell_scripts():
    sh_files = glob.glob(os.path.join(ROOT_DIR, "**", "*.sh"), recursive=True)
    sh_files.append(os.path.join(ROOT_DIR, "install.sh"))
    sh_files = sorted(list(set(sh_files)))

    for sh in sh_files:
        if not os.path.isfile(sh):
            continue
        with open(sh, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()

        content = "".join(lines)
        in_func = False
        brace_depth = 0

        # 检查 setup_argo.sh 中是否存在 SCRIPT_DIR 未定义使用 (P0-4)
        if os.path.basename(sh) == "setup_argo.sh":
            if "${SCRIPT_DIR}" in content and "SCRIPT_DIR=" not in content:
                report_error(sh, None, "脚本使用了未定义变量 '${SCRIPT_DIR}'，导致 Argo 订阅刷新静默跳过！", "P0-SHELL-SCRIPTDIR")

        # 检查 install.sh 中 ${BOLD} 是否未定义 (P2-2)
        if os.path.basename(sh) == "install.sh":
            if "${BOLD}" in content and "BOLD=" not in content:
                report_warning(sh, None, "install.sh 多处使用了 '${BOLD}' 格式化变量，但未在脚本头部定义！", "P2-SHELL-BOLD")

        for idx, raw_line in enumerate(lines, 1):
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue

            # 检测函数声明
            if re.match(r"^[a-zA-Z0-9_-]+\s*\(\)\s*\{", line) or re.match(r"^function\s+[a-zA-Z0-9_-]+", line):
                in_func = True

            # 计算括号深度
            unquoted = re.sub(r"\"[^\"]*\"|'[^']*'", "", line)
            brace_depth += unquoted.count("{") - unquoted.count("}")

            if brace_depth <= 0:
                in_func = False
                brace_depth = 0

            # 致命规则 P0: 禁止在函数外部使用 local
            if not in_func and re.match(r"^local\s+[a-zA-Z0-9_-]+", line):
                report_error(sh, idx, f"关键字 'local' 必须在函数体内使用，在全局执行会导致 bash 运行时报错: '{line}'", "P0-SHELL")

            # 检查 set -e 下的 command substitution 退出码被吞问题 (P1-8)
            if re.search(r"out=\$\(LC_ALL=C\s+apt-get\s+update[^)]*\)\s*;\s*rc=", line):
                report_error(sh, idx, "在 set -e 下执行 'out=$(apt-get update); rc=$?'，分号分隔会导致命令失败时脚本被 set -e 立即中止！必须使用 '|| rc=$?' 保护！", "P1-SHELL-SETE")

            # 检查 drop_caches 反模式 (P2-8)
            if "drop_caches" in line and not line.startswith("#"):
                report_warning(sh, idx, "检测到 'drop_caches' 内存释放反模式，容易造成虚假内存优化及磁盘 IO 剧烈颠簸", "P2-DROP-CACHES")

            # 检查 sed 全局替换污染 80 端口伪装站 (P2-6)
            if 'sed -i "s/server_name .*;' in line or "sed -i 's/server_name .*;" in line:
                report_error(sh, idx, "sed 全局替换 server_name 会误改 80 端口伪装站配置，破坏 ACME 与默认回退！必须针对特定 server 块替换！", "P2-SED-POLLUTION")


# ==============================================================================
# 4. Nginx 语法与配置规范检查 (Nginx Validator)
# ==============================================================================
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
                report_error(conf, None, f"Nginx 正则匹配 location 中不允许 proxy_pass 带有 URI 路径: '{uri_pass.group(1)}'", "P0-NGINX")

        # 检查是否包含 80 端口到 80 端口的无限死循环重定向
        if re.search(r"listen\s+80;[^{]*server_name\s+([^;]+);[^{]*return\s+301\s+http://\1", content):
            report_error(conf, None, "检测到端口 80 重定向到 http:// 同域名（会导致 301 无限重定向死循环）", "P1-NGINX-LOOP")


# ==============================================================================
# 5. Python 静态符号与作用域感知检查 (Python AST Scope Analysis)
# ==============================================================================
class ScopeVisitor(ast.NodeVisitor):
    """AST 词法作用域访问器：严格区分全局、函数局部、嵌套函数与推导式作用域，杜绝未定义符号与扁平化漏报"""
    def __init__(self, filename):
        self.filename = filename
        self.scopes = [set(dir(builtins)) | {"__file__", "__name__", "__doc__", "__package__"}]
        self.errors = []

    def current_scope(self):
        return self.scopes[-1]

    def add_name(self, name):
        if name:
            self.scopes[-1].add(name)

    def extract_targets(self, node, target_set):
        if isinstance(node, ast.Name):
            target_set.add(node.id)
        elif isinstance(node, (ast.Tuple, ast.List)):
            for elt in node.elts:
                self.extract_targets(elt, target_set)
        elif isinstance(node, ast.Starred):
            self.extract_targets(node.value, target_set)

    def pre_scan_scope(self, body):
        names = set()
        for node in body:
            for child in ast.walk(node):
                if isinstance(child, ast.Assign):
                    for target in child.targets:
                        self.extract_targets(target, names)
                elif isinstance(child, (ast.AnnAssign, ast.AugAssign)):
                    self.extract_targets(child.target, names)
                elif isinstance(child, ast.For):
                    self.extract_targets(child.target, names)
                elif isinstance(child, ast.With):
                    for item in child.items:
                        if item.optional_vars:
                            self.extract_targets(item.optional_vars, names)
                elif isinstance(child, ast.Import):
                    for alias in child.names:
                        names.add(alias.asname or alias.name.split(".")[0])
                elif isinstance(child, ast.ImportFrom):
                    for alias in child.names:
                        names.add(alias.asname or alias.name)
                elif isinstance(child, ast.ExceptHandler) and child.name:
                    names.add(child.name)
                elif isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                    names.add(child.name)
        return names

    def visit_Module(self, node):
        module_names = self.pre_scan_scope(node.body)
        self.scopes[0].update(module_names)
        self.generic_visit(node)

    def visit_FunctionDef(self, node):
        self.add_name(node.name)
        func_scope = self.pre_scan_scope(node.body)
        for arg in node.args.args + getattr(node.args, "posonlyargs", []) + getattr(node.args, "kwonlyargs", []):
            func_scope.add(arg.arg)
        if node.args.vararg:
            func_scope.add(node.args.vararg.arg)
        if node.args.kwarg:
            func_scope.add(node.args.kwarg.arg)

        self.scopes.append(func_scope)
        for stmt in node.body:
            self.visit(stmt)
        self.scopes.pop()

    visit_AsyncFunctionDef = visit_FunctionDef

    def visit_ListComp(self, node):
        comp_scope = set()
        for gen in node.generators:
            self.extract_targets(gen.target, comp_scope)
        self.scopes.append(comp_scope)
        self.generic_visit(node)
        self.scopes.pop()

    visit_SetComp = visit_ListComp
    visit_DictComp = visit_ListComp
    visit_GeneratorExp = visit_ListComp

    def visit_Name(self, node):
        if isinstance(node.ctx, ast.Load):
            name = node.id
            found = any(name in s for s in self.scopes)
            if not found and not name.startswith("_"):
                self.errors.append((node.lineno, name))


def check_python_scripts():
    py_files = glob.glob(os.path.join(ROOT_DIR, "**", "*.py"), recursive=True)

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

        visitor = ScopeVisitor(py)
        visitor.visit(tree)
        for lineno, name in visitor.errors:
            report_error(py, lineno, f"引用了未定义的作用域符号: '{name}'", "P0-PY-UNDEFINED")

        # 检查 vpngate_manager.py 中是否有写死 has_update: False 的情况
        if os.path.basename(py) == "vpngate_manager.py":
            if '"has_update": False' in code and '"relation": "up_to_date"' in code:
                report_warning(py, None, "vpngate_manager.py 中 /api/github_update/check 仍硬编码 has_update: False，面板更新检测形同虚设！", "P2-UPDATE-CHECK")


def check_singbox_binary_validation():
    """若运行环境中安装了官方 sing-box 二进制，自动接入真实内核预检 (sing-box check)"""
    import shutil
    import subprocess
    import tempfile
    import json

    sb_bin = os.environ.get("SING_BOX_BIN")
    if not sb_bin or not os.path.isfile(sb_bin):
        sb_bin = shutil.which("sing-box") or shutil.which("sing-box.exe")
    if not sb_bin:
        for cand in [
            "/usr/local/bin/sing-box",
            "/usr/bin/sing-box"
        ]:
            if os.path.isfile(cand) and (os.access(cand, os.X_OK) or sys.platform == "win32"):
                sb_bin = cand
                break

    subs_py = os.path.join(ROOT_DIR, "scripts", "generate_subs.py")
    if os.path.isfile(subs_py):
        def _run_smoke_test(cfg_path, scenario):
            if not sb_bin:
                return
            try:
                proc = subprocess.Popen([sb_bin, "run", "-c", cfg_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, cwd=os.path.dirname(cfg_path))
                try:
                    _, err = proc.communicate(timeout=2)
                    err_clean = err.strip() or f"进程异常退出，退出码: {proc.returncode}"
                    report_error(subs_py, None, f"sing-box run 进程启动冒烟失败 ({scenario})，check 虽通过但运行时崩溃: {err_clean}", "P0-SB-RUN-FATAL")
                except subprocess.TimeoutExpired:
                    proc.kill()
                    try:
                        proc.wait(timeout=1)
                    except Exception:
                        pass
            except Exception as e:
                report_error(subs_py, None, f"sing-box run 冒烟测试执行异常 ({scenario}): {e}", "P0-SB-RUN-EXCEPTION")

        # 场景 1: 纯 IPv4、无 CDN 域名 (严禁误出 CDN 节点)
        with tempfile.TemporaryDirectory() as tmpdir:
            test_nodes_v4 = {
                "public_ip": "1.2.3.4",
                "data_dir": tmpdir,
                "direct_uuid": "11111111-1111-1111-1111-111111111111",
                "resi_uuid": "22222222-2222-2222-2222-222222222222",
                "public_key": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
                "short_id": "0123456789abcdef",
                "vless_port": 443,
                "hy2_port": 443,
                "tuic_port": 8443,
                "anytls_port": 8444,
                "vmess_port": 8445
            }
            nodes_path = os.path.join(tmpdir, "singbox_nodes.json")
            with open(nodes_path, "w", encoding="utf-8") as f:
                json.dump(test_nodes_v4, f)

            try:
                subprocess.run([sys.executable, subs_py, nodes_path, tmpdir], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
                sb_json = os.path.join(tmpdir, "singbox.json")
                if os.path.isfile(sb_json):
                    with open(sb_json, "r", encoding="utf-8") as f:
                        cfg = json.load(f)
                    cdn_tags = [o.get("tag", "") for o in cfg.get("outbounds", []) if "CDN" in o.get("tag", "")]
                    if cdn_tags:
                        report_error(subs_py, None, f"无 CDN 域名配置时违规注入了 CDN 节点: {cdn_tags}", "P1-CDN-INJECTION")
                    if sb_bin:
                        res = subprocess.run([sb_bin, "check", "-c", sb_json], capture_output=True, text=True)
                        if res.returncode != 0:
                            report_error(subs_py, None, f"sing-box 内核校验客户端配置失败 (IPv4 基础模式)：{res.stderr.strip()}", "P0-SB-CHECK-CLIENT")
                        else:
                            _run_smoke_test(sb_json, "IPv4 基础模式")
            except Exception as e:
                report_warning(subs_py, None, f"模拟纯 IPv4 客户端配置生成出现异常: {e}", "P2-SB-MOCK")

        # 场景 2: 双栈 IPv4 + IPv6 (必须生成对应 IPv6 出站)
        with tempfile.TemporaryDirectory() as tmpdir:
            test_nodes_v6 = {
                "public_ip": "1.2.3.4",
                "public_ipv6": "2001:db8::1",
                "data_dir": tmpdir,
                "direct_uuid": "11111111-1111-1111-1111-111111111111",
                "resi_uuid": "22222222-2222-2222-2222-222222222222",
                "public_key": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
                "short_id": "0123456789abcdef",
                "vless_port": 443,
                "hy2_port": 443,
                "tuic_port": 8443,
                "anytls_port": 8444,
                "vmess_port": 8445
            }
            nodes_path = os.path.join(tmpdir, "singbox_nodes.json")
            with open(nodes_path, "w", encoding="utf-8") as f:
                json.dump(test_nodes_v6, f)

            try:
                subprocess.run([sys.executable, subs_py, nodes_path, tmpdir], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
                sb_json = os.path.join(tmpdir, "singbox.json")
                if os.path.isfile(sb_json):
                    with open(sb_json, "r", encoding="utf-8") as f:
                        cfg = json.load(f)
                    v6_tags = [o.get("tag", "") for o in cfg.get("outbounds", []) if "IPv6" in o.get("tag", "")]
                    if len(v6_tags) < 4:
                        report_error(subs_py, None, f"提供 public_ipv6 后 singbox.json 漏生成 IPv6 原生出站 (仅有 {len(v6_tags)} 个)", "P1-IPV6-MISMATCH")
                    if sb_bin:
                        res = subprocess.run([sb_bin, "check", "-c", sb_json], capture_output=True, text=True)
                        if res.returncode != 0:
                            report_error(subs_py, None, f"sing-box 内核校验客户端配置失败 (双栈 IPv6 模式)：{res.stderr.strip()}", "P0-SB-CHECK-CLIENT")
                        else:
                            _run_smoke_test(sb_json, "双栈 IPv6 模式")
            except Exception as e:
                report_warning(subs_py, None, f"模拟双栈客户端配置生成出现异常: {e}", "P2-SB-MOCK")

        # 场景 3: 域名模式校验 (无 DNS 时不得误出 CDN 节点，显式指定 cdn_domain 时必须生成且 SNI 正确)
        with tempfile.TemporaryDirectory() as tmpdir:
            test_nodes_domain = {
                "public_ip": "1.2.3.4",
                "domain": "direct.example.com",
                "cdn_domain": "cdn.example.com",
                "data_dir": tmpdir,
                "direct_uuid": "11111111-1111-1111-1111-111111111111",
                "resi_uuid": "22222222-2222-2222-2222-222222222222",
                "public_key": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
                "short_id": "0123456789abcdef",
                "vless_port": 443,
                "hy2_port": 443,
                "tuic_port": 8443,
                "anytls_port": 8444,
                "vmess_port": 8445
            }
            nodes_path = os.path.join(tmpdir, "singbox_nodes.json")
            with open(nodes_path, "w", encoding="utf-8") as f:
                json.dump(test_nodes_domain, f)

            try:
                subprocess.run([sys.executable, subs_py, nodes_path, tmpdir], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
                sb_json = os.path.join(tmpdir, "singbox.json")
                if os.path.isfile(sb_json):
                    with open(sb_json, "r", encoding="utf-8") as f:
                        cfg = json.load(f)
                    cdn_obs = [o for o in cfg.get("outbounds", []) if "CDN" in o.get("tag", "") and o.get("type") == "vmess"]
                    for o in cdn_obs:
                        sni = o.get("tls", {}).get("server_name")
                        if sni != "cdn.example.com":
                            report_error(subs_py, None, f"direct. 域名的 CDN 节点 SNI 未正确推导为 cdn. 域 (得到: {sni})", "P1-CDN-DERIVATION")
                    if sb_bin:
                        res = subprocess.run([sb_bin, "check", "-c", sb_json], capture_output=True, text=True)
                        if res.returncode != 0:
                            report_error(subs_py, None, f"sing-box 内核校验客户端配置失败 (双域名模式)：{res.stderr.strip()}", "P0-SB-CHECK-CLIENT")
                        else:
                            _run_smoke_test(sb_json, "双域名模式")
            except Exception as e:
                report_warning(subs_py, None, f"模拟双域名客户端配置生成出现异常: {e}", "P2-SB-MOCK")

        # 场景 4: 服务端配置模板 (setup_singbox.sh) 渲染与内核级 sing-box check 验证
        setup_sh = os.path.join(ROOT_DIR, "scripts", "setup_singbox.sh")
        if os.path.isfile(setup_sh):
            try:
                with open(setup_sh, "r", encoding="utf-8", errors="ignore") as f:
                    sh_c = f.read()
                m_sb = re.search(r'cat\s*>\s*"\$SB_CONFIG_TMP"\s*<<EOF\s*\n(.*?)\nEOF', sh_c, re.DOTALL)
                if m_sb:
                    tmpl_sb = m_sb.group(1)
                    with tempfile.TemporaryDirectory() as tmpdir:
                        cert_path = os.path.join(tmpdir, "cert.pem").replace("\\", "/")
                        key_path = os.path.join(tmpdir, "key.pem").replace("\\", "/")
                        with open(cert_path, "w", encoding="utf-8") as f_c:
                            f_c.write("-----BEGIN CERTIFICATE-----\nMIICtDCCAZygAwIBAgIUTDQj+Vp9UqZd7eUUNoLiiqKvd8EwDQYJKoZIhvcNAQEL\nBQAwFDESMBAGA1UEAwwJbG9jYWxob3N0MB4XDTI2MTAyMzE0MzYwNVoXDTI3MTAy\nMzE0MzYwNVowFDESMBAGA1UEAwwJbG9jYWxob3N0MIIBIjANBgkqhkiG9w0BAQEF\nAAOCAQ8AMIIBCgKCAQEA3DxUT9xDAJP76Jhim4zzPg8E3na8wpi8WnajFRLCVR4a\nYVsP6ApztFPZC/YraVDGu/TRHpz4b0IjMvqMSN5SAXFangP4d5nubEvu8YSG8tM9\npmtRuriXx+AZGkvdMB4NvTPow948CsnhbLZS8ObRQoJyZm69/yfp3oI67plJ1/5i\nZPA/C7jVb6fV5a2coGSWjak6JfYw1pbYhSqM36J0C5eyLimmYWXmTduwaSx6pQl+\nCO+HPNfudZXMVGsfv8lf+YSHHsLMJPobUJwEIBkLjJBM5nVjeP66AObqCoXJk+D5\nKmZr94SyweYpWXBtWnXoFHC6tUokpK0gjPAAFVrO7QIDAQABMA0GCSqGSIb3DQEB\nCwUAA4IBAQByXm44m8iZurYhS303FsVQvdkWK3e42FI5u7UIe2ra0sprLLIMDyfD\ncepnZf06WqpO1cYzHYlMUQITO6gkVPcTTspEhqa6bwCnDquSgHZgw8+PqYb3xXZN\nNQ6rKuOwJzfYgV157Dmfyu5/HNPD8S0ABCddRjmC5R//HKRW4PvTTXj9uXfTqHxr\nvZEgBgr0bzTvk7frkCx4j1w3DFdOnQj/cE492KJ1dL5ebdwso/geKQKJ3vqiyW5M\nZ5TG0pIoXHvn7rnrln48WsSkn/p8RsdRk3b2JgTbIQwCEM7MOUK2KKNIe7f6aELw\nGbMczhLFy8K7E4Arde8cBDA9nad2nWPK\n-----END CERTIFICATE-----")
                        with open(key_path, "w", encoding="utf-8") as f_k:
                            f_k.write("-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEA3DxUT9xDAJP76Jhim4zzPg8E3na8wpi8WnajFRLCVR4aYVsP\n6ApztFPZC/YraVDGu/TRHpz4b0IjMvqMSN5SAXFangP4d5nubEvu8YSG8tM9pmtR\nuriXx+AZGkvdMB4NvTPow948CsnhbLZS8ObRQoJyZm69/yfp3oI67plJ1/5iZPA/\nC7jVb6fV5a2coGSWjak6JfYw1pbYhSqM36J0C5eyLimmYWXmTduwaSx6pQl+CO+H\nPNfudZXMVGsfv8lf+YSHHsLMJPobUJwEIBkLjJBM5nVjeP66AObqCoXJk+D5KmZr\n94SyweYpWXBtWnXoFHC6tUokpK0gjPAAFVrO7QIDAQABAoIBAAmFd4UBr3PgR00a\n/shdePap4jqr73qKQo+2qVOekqrouO3p6Jojjt+w8E/wE0MOVvPb9bPZHXR8liun\nYVaVJf53TsTzbv6HYni+ylRut6wv2G56x/cb8T6W6v7pYLqqfKA9akbC3jL+igcP\n1YN3YdH6ScUxQc2SMC41Jc8YRB+uWd018VboHGSpBzMRPyTq1kKMCnwFmXiiztIw\ncivbnsgFdJ15GK3iBqE82f2+rN7Z/v/OAno32fGqtuPEt81LoWkVgfZVeQMUos3X\ndNtzQbDkwcVt1toCqSbhpSmsdJ3tswKIzLmcQQhBf09h4bd8tlTb4b9Qgp06sfbn\nU9dbPxECgYEA/S0RssL7V7Rr3ioHonagaOYI3tG6KiC2Sbauvtxv3UZQodpHwWaE\n0sua7wsSX1C6XMO1fGmsaWktu0ewxQQ/gDDEFEa84pUtFySqVy1i5H3u+55k9E4F\nb1Gksrlo2oCQfXRU3G6M5nhcIQNZezErg7ORX9qdnHEMvCHKwsGUMmsCgYEA3rEz\nXqtlIQUTJA67lSI9Fa0zeoZ2j3vI/qI3dyAwix4LAw1feKYQfstOE6fFDyTyM0x7\n+XTfP0d/ghFXXc2pEo7nNLIBZMDNz01Z4TXsgI2gO8K9CxIFLG14TapbIXUrDXWi\nUBH5m3Na2OlwHYcJxqkyH6fAefMOdGrJrMLPygcCgYBQNKj4suChZl0N4s7MXzxu\nPwHsZRDPK9HUBHXTrU4bEZ2VyOsWj/3gMfSBakaFv7Nqk+243llqg5GjVRDhOXlM\niSZ1LfvE5HGGdW0pdQ1xSZweRo3A/76lB35fyHE5V6VuuR3xP2yPzu2Q39jHOEqK\nzKZvcXihCQd5ylLL5DuoxQKBgAEJUBTjtU/HB0TGsMbL5v7f1HqAf7LBP7k3pgxu\n4Or009ZKzKPyGeeNKKrcwAUHBf2JIJaTnapcudIwJHjySRQmCBttrKX8Y7jQQlfS\n+WvLvPAqQtj3V4DSbZnm7g+kzPN+FahLvR6lFcomo/fvNfNvvCT7keC/adTO3mto\naLEnAoGBAI6389VswUDhGhoX+H+PlNuBRkol4GRHIrgkznsVoyqhmi1KtWOXCPUm\n9Mvshlkx/FdY9X52u7xBS9ZD97mhTD67U1PV6AZt7/lfDiUUnUmjQ9wRb+XKHo+2\nVAkCGg/t/wpd8SFbj5ZNGfPiTRbrcNdnXGIY080BuB5Wsuza12zf\n-----END RSA PRIVATE KEY-----")
                        subs_server = {
                            "${DIRECT_UUID}": "11111111-1111-1111-1111-111111111111",
                            "${RESI_UUID}": "22222222-2222-2222-2222-222222222222",
                            "${CAMOUFLAGE_DOMAIN}": "gateway.icloud.com",
                            "${PRIVATE_KEY}": "gKgD-XCLpFvAyqHtw5XgJyCeDIjIIL-EuLo4lYtQ_kc",
                            "${SHORT_ID}": "0123456789abcdef",
                            "${HY2_OBFS}": "testpass",
                            "${CERT_FILE}": cert_path,
                            "${KEY_FILE}": key_path,
                            "${RESI_PROXY_HOST}": "127.0.0.1",
                            "${RESI_PROXY_PORT}": "8500",
                            "${RESI_PROXY_USER}": "socks5",
                            "${RESI_PROXY_PASS}": "ilovestudy"
                        }
                        rendered_sb = tmpl_sb
                        for k, v in subs_server.items():
                            rendered_sb = rendered_sb.replace(k, str(v))
                        
                        server_json = os.path.join(tmpdir, "server.json")
                        with open(server_json, "w", encoding="utf-8") as f_out:
                            f_out.write(rendered_sb)
                        
                        # 先行 JSON 语法解析验证
                        json.loads(rendered_sb)
                        
                        if sb_bin:
                            res_s = subprocess.run([sb_bin, "check", "-c", server_json], capture_output=True, text=True)
                            if res_s.returncode != 0:
                                report_error(setup_sh, None, f"sing-box 内核校验服务端配置模板失败：{res_s.stderr.strip()}", "P0-SB-CHECK-SERVER")
            except Exception as e:
                report_error(setup_sh, None, f"setup_singbox.sh 服务端模板校验异常: {e}", "P0-SB-SERVER-JSON")

    if not sb_bin:
        report_warning(os.path.join(ROOT_DIR, "scripts/code_gate.py"), None, "当前环境未安装 sing-box 二进制程序，跳过内核级真机校验 (CI 与部署环境会自动执行)", "INFO-SB-BIN")


# ==============================================================================
# 主入口
# ==============================================================================
def main():
    print(f"{Color.CYAN}===================================================={Color.RESET}")
    print(f"{Color.CYAN}  AimiliVPN 自动化架构与代码质量门禁 (Code Gate V2.0) {Color.RESET}")
    print(f"{Color.CYAN}===================================================={Color.RESET}")

    check_singbox_confs()
    check_topology_consistency()
    check_shell_scripts()
    check_nginx_configs()
    check_python_scripts()
    check_singbox_binary_validation()

    if warnings:
        print(f"\n{Color.YELLOW}[!] 检测到 {len(warnings)} 个警告项 (P2/P3):{Color.RESET}")
        for w in warnings:
            print(f"  {Color.YELLOW}* {w}{Color.RESET}")

    if errors:
        print(f"\n{Color.RED}[X] 门禁精准拦截！检测到 {len(errors)} 个致命或阻断性缺陷 (P0/P1):{Color.RESET}")
        for e in errors:
            print(f"  {Color.RED}* {e}{Color.RESET}")
        print(f"\n{Color.RED}质量门禁拦截生效，严禁带病发布。请逐一修复上述缺陷！{Color.RESET}\n")
        sys.exit(1)
    else:
        print(f"\n{Color.GREEN}[√] 质量门禁全绿通过！无 P0/P1 阻塞性缺陷，Sing-box 1.14 与网络拓扑完全健康。{Color.RESET}\n")
        sys.exit(0)

if __name__ == "__main__":
    main()
