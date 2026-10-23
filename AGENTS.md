# AimiliVPN - AI Agent 协作与质量审查全局规则 (AGENTS.md)

所有在此项目中工作的 AI Agent（无论是开发辅助、代码重构、代码审查或排错）必须强制且无条件遵循以下规则：

---

## 核心原则：红蓝军隔离与对抗性代码审计 (Red-Team Adversarial Audit Protocol)

严禁在同一会话中以“作者心态”自圆其说。开发与复检必须严格实行两阶段分离：

### 阶段一：开发者模式（Blue-Team Developer）
* 专注于用户需求的架构落地、算法设计与业务逻辑实现。
* 编写清晰、符合规范的生产级代码，保留必要的上下文和防御性日志。

### 阶段二：敌对审查者模式（Red-Team Auditor）
在功能开发完毕、提交代码或用户要求“复检/检查是否有bug”时，必须强制立即切换为**【敌对审查者（Red-Team Auditor）】**角色：

1. **默认有罪假定（Guilty Until Proven Innocent）**：
   * 假定刚刚编写或修改的代码中，**至少潜伏着 3 个致命缺陷或边界崩溃（P0/P1 级 Bug）**。
   * 绝对不允许说“经过检查代码没有问题”、“逻辑非常清晰”等空洞套话，审查必须产出具体证据链。

2. **硬性工具门禁第一（Tool-First Verification）**：
   * 绝对禁止仅凭肉眼“顺着自己刚才的逻辑浏览一遍”。
   * 必须在终端中首先执行质量门禁命令：
     ```bash
     python scripts/code_gate.py
     ```
   * 检查是否触发：
     * `P0-SHELL`: 函数体外调用 `local` 导致运行时崩溃；
     * `P0-PY-UNDEFINED`: 引用或调用了未在当前文件定义或导入的函数/变量；
     * `P0-NGINX`: 正则 `location ~` 块中 `proxy_pass` 带有 URI 路径；
     * `P1-TOPOLOGY`: 端口、协议与出入站映射错位（如明文端口误配 TLS，CDN 回源端口被 Reality 抢占等）。

3. **拓扑与依赖链全景对照（Topological & Dependency Cross-Check）**：
   * 对涉及网络与端口的文件（`setup_singbox.sh`, `generate_subs.py`, `aimilivpn-production.conf`, `setup_argo.sh`）：
     * 画出“端口入出站流向图”（Inbound -> Nginx -> Sing-box -> Outbound）；
     * 逐一核验所有端口号、路径（`/vmess`, `/vmess-ws`）是否 100% 一致。
   * 对涉及函数调用的文件（`aimili_cli.py`, `vpngate_manager.py`）：
     * 逐个追踪被调用函数在哪个模块定义、传参格式是否完全匹配。

4. **审查未通过绝不交付（Zero Tolerance）**：
   * 发现任何缺陷立即就地修复，重新运行 `python scripts/code_gate.py`，直至门禁全绿输出 `[√] 质量门禁全绿通过！`。
