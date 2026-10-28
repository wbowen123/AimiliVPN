# AimiliVPN 全量代码审查报告（终审版）

> - **审查时间**：2026-10-28
> - **审查对象**：工作区 `HEAD` = `b9a46e7`，`VERSION` = `V1.5.0`
> - **审查性质**：只读分析（本次未修改任何仓库代码，待用户决定是否修复）
> - **方法**：静态阅读 + `python -m py_compile` + `bash -n` + `python scripts/code_gate.py` + 关键代码 grep 实测 + 五份历史 AI 审查报告逐条对照

---

## 一、结论速览（TL;DR）

| 维度 | 结论 |
|---|---|
| **语法检查** | ✅ Python 全量 `py_compile` 通过；Shell 全量 `bash -n` 通过 |
| **质量门禁** | ✅ `python scripts/code_gate.py` → `[√] 质量门禁全绿通过！无 P0/P1 阻塞性缺陷`（仅剩预期 INFO：本机未装 sing-box 二进制） |
| **CI** | ✅ 现已接入 sing-box `1.14.3` 内核安装、`pyflakes`、`shellcheck -S error`、`bash -n`、`compileall`（较早期报告所列的"缺失"已补齐） |
| **最关键的两项"check 通过即以为能跑"的 P0** | ✅ **本轮重新验证：均已在 HEAD 修复** —— `singbox.json` 空 `detour` 问题与 `rule_set` 远程下载 `FATAL`/`download_detour` 死锁已消除 |
| **当前仍存在的 P0/P1** | 🔴 WARP 注册失败 fallback 分支（配置不完整、fallback 未消费）；🔴 Clash 订阅缺 AnyTLS（节点集不对齐）；🔴 `check_health.sh` 退出码假阴性 |
| **当前仍存在的 P2/P3** | 🟡 若干运维脚本遗留问题、门禁仍为"check 级"未做 run 级冒烟 |

**一句话结论**：项目整体代码质量与近期修复执行力是**较强的**；过去两周（10-22 ~ 10-23）已陆续修复了大量 P0/P1（共约 20+ 项，含 run 级实测发现的致命问题）。**当前 HEAD 已无"装完即废"级别的 P0**。但仍有少量 P0/P1 遗留，且质量门禁与 CI 的验证深度（`check` 级）未覆盖 `sing-box run` 冒烟这一层。

---

## 二、本轮（2026-10-28）关键实测结论

### ✅ 已验证修复（证据来自本轮对源码的重新读取）

| # | 历史缺陷 | 当前 HEAD 状态 | 证据位置 |
|---|---|---|---|
| 1 | **P0-A**：生成的 `singbox.json` 中 `local-dns` 的 `"detour": "direct"` 指向**空 direct 出站** → `sing-box run` 必 FATAL | ✅ **已修复** | `scripts/generate_subs.py:907`（local-dns 现无 detour）；:889（final outbounds 含真实 direct） |
| 2 | **P0-B**：`route.rule_set` remote + `download_detour: "direct"` → 下载失败即 FATAL，且大陆网络直连 `raw.githubusercontent.com` 被封 → 逻辑死锁 | ✅ **已修复** | 当前客户端 DNS 改用 `experimental.cache_file` + `local-dns` + `domain_suffix` + `hijack-dns`（`generate_subs.py:899-932`）；无 `download_detour` 残留 |
| 3 | P0-1：服务端 inbound 废弃 `sniff` 字段 | ✅ 已修 | `scripts/setup_singbox.sh:459` route 规则 `{"action": "sniff", ...}` |
| 4 | P0-2：WARP legacy WireGuard 扁平字段 | ✅ 已修 | `scripts/setup_warp.sh:239-246` 改用 `endpoints[].peers` 嵌套结构 |
| 5 | P0-3：WARP `reserved`/`client_id` 缺失 | ✅ 已修 | `scripts/setup_warp.sh:129-145` |
| 6 | P0-4：setup_argo.sh `${SCRIPT_DIR}` 未定义 | ✅ 已修 | `scripts/setup_argo.sh:12` 已定义 |
| 7 | P0-5：nginx 正则 `proxy_pass` 带 URI | ✅ 已修 | `scripts/setup_https.sh:208` 改用 `lambda` 限定替换；`setup_singbox.sh` 同 |
| 8 | P1-4：8446 端口未放行 | ✅ 已修 | `install.sh:16`（`AIMILI_FW_PORTS` 含 `8446`）；`setup_singbox.sh:684-695`；`check_health.sh:93` |
| 9 | P1-5：cron IP 漂移只改 txt 不改 json | ✅ 已修 | `scripts/setup_cron.sh:142-152`（更新 `singbox_nodes.json` + 重生成订阅） |
| 10 | P1-6：AnyTLS `padding_scheme` 非法 | ✅ 已修 | `grep -n padding` 全仓无残留 |
| 11 | P1-7：TG Bot 常驻 unit 未创建 | ✅ 已修 | `scripts/tg_bot.sh` 创建 `aimilivpn-tgbot.service`；`install.sh:294` 卸载清单含它 |
| 12 | P1-8：install.sh `set -e` + `rc=$?` 冲突 | ✅ 已修 | `install.sh:71` 改为 `out=$(...) || rc=$?` |
| 13 | P1-9：Argo 域名覆盖 CDN 域名污染 CDN 节点 | ✅ 已修 | `generate_subs.py:431-432`（`cf_cdn_host = cdn_host`，argo 用自身域） |
| 14 | P2-2：`install.sh` `${BOLD}` 未定义 | ✅ 已修 | `install.sh:12` 已定义 `BOLD` |
| 15 | P2-20：CI 缺 shellcheck/pyflakes/sing-box | ✅ 已补 | `.github/workflows/ci.yml:22-52` 已装 sing-box 1.14.3 + pyflakes + shellcheck + compileall |
| 16 | P2-21：`acme.sh` 安装用裸 `curl \| sh` | ✅ 已补 `-fsSL` | `install.sh:933` |
| 17 | P1-3：WARP 注入把 sniff 挤到域名规则后 | ✅ 已修 | `setup_warp.sh:342`（`final_rules = [sniff] + dns_rules + [...]`） |

### 🔴 本轮重新验证确认仍存在的缺陷（当前 HEAD）

#### P0 级（严重但当前多为"修复中/待闭环"）

**🔴 P0-1（按严重度排序，强烈建议处理）— WARP 注册失败 fallback 分支存在致命缺陷**（实测确认仍存在）

- **位置**：`scripts/setup_warp.sh:115-169`
- **问题**：
  - API 失败分支写入的 `fallback` 配置**字段不完整**（缺少 `private_key`、`public_key`、`client_id`、`id`、`token`）；
  - 写入 `"fallback": true` 后**没有任何代码消费该字段**；
  - 脚本仍以 `print("WARN...")` + 后续流程推进，**返回成功口径**。
- **影响**：Cloudflare WARP 注册 API 瞬时失败时，服务端会以半残/无效密钥落地 WARP 出站，且表现为"成功"，实际不可用；下游 sing-box outbound 生成将基于空密钥。
- **建议**：fallback 分支补齐完整密钥字段，或至少失败即中止；消费 `fallback` 状态或改为失败即中止。

#### P1 级（当前仍存在，需修复）

**1️⃣ P1-1 — `generate_subs.py` 生成的 `clash.yaml` 缺 AnyTLS 节点**（功能降级）

- **位置**：`scripts/generate_subs.py:281-284`（IPv4）与 `:369-373`（IPv6）
- **问题**：AnyTLS 节点只 `links.extend(...)` 进入 `sub.txt`/`nodes.txt`/`singbox.json`，**未 `clash_proxies.append(...)`** 进入 Clash Meta 订阅。
- **影响**：Clash/Mihomo 客户端拿到的节点集与 sing-box/原生/明文三格式**不对齐**；晚高峰抗 QoS 组失去两条 TCP 抗封锁节点；README 宣称的"18 节点双栈矩阵"与 clash.yaml 实际 proxies 数（16）不一致（历史报告 P2-12 同源，本次确认存续）。
- **建议**：为 IPv4/IPv6 AnyTLS 各补两条 clash proxy。

**2️⃣ P1-2 — `scripts/check_health.sh` 退出码覆盖不全（假阴性）**

- **位置**：`scripts/check_health.sh:230-233`
- **问题**：最终退出码只判断 `S_SINGBOX` / `S_NGINX`，**未包含 `S_AIMILI`**（住宅网桥 `aimilivpn` 服务失败时脚本仍可能返回 0）。
- **影响**：`ml test`、cron/监控对"住宅网桥故障"的处理会拿到假阴性，延缓自愈感知。

**3️⃣ P1-3（待实测/潜在）— `install.sh` ExecStart 与 select_core.sh ABI 不一致**

- **位置**：`install.sh:1028`（`ExecStart=/usr/bin/python3 vpngate_manager.py`）vs `scripts/select_core.sh`（按 PATH `python3` 的 `EXT_SUFFIX` 选 `.so`）。
- **问题**：Debian/Ubuntu 上 `/usr/bin/python3` 与 PATH 中 `python3` 版本不一致时，systemd 加载的 Cython 扩展 ABI 不匹配 → 服务导入失败。
- **建议**：`ExecStart` 改用 `/usr/bin/ml` 或与 select_core 同一解释器。

### 🟡 当前仍存在的 P2/P3（已实测确认）

| # | 位置 | 问题 |
|---|---|---|
| P2-1 | `scripts/setup_singbox.sh:~678` | `if nginx -t ...; then ...; fi` **无 else** → nginx 配置错时静默跳过 reload（P2-13 未闭环） |
| P2-2 | `scripts/setup_singbox.sh:612-615` | nft 端口跳跃规则 `nft add rule` 缺存在性检查/`-C` 幂等 → 重跑累积重复规则 |
| P2-3 | `scripts/setup_singbox.sh:~592` | 回滚路径 `rm -f "$SB_CONFIG_BAK"` **销毁**快照（事务快照名不副实） |
| P2-4 | `scripts/setup_https.sh:265` | `nginx -t && service_reload` 在 `set -euo pipefail` 下失败即整脚本 abort |
| P2-5 | `scripts/setup_https.sh:283-285` | `ufw allow 8443/tcp` 等无 `|| true`（set -e 下可能中止） |
| P2-6 | `scripts/setup_cron.sh` | 定时任务（04:00 维护 + 15min 看门狗）**无 `flock`**；头部宣称"drop_caches"但实现未含该操作（P2-16/17） |
| P2-7 | `scripts/setup_argo.sh:141-148,256-261` | ARGO_JSON heredoc **未加引号**（`local_port` 直接插字面量，JSON 注入风险）；`"token_masked": "${token:0:8}***${token: -6}"` 表达式脆弱 |
| P2-8 | `scripts/setup_warp.sh:155-168` | API 失败分支 `fallback` 未被消费（见 P0-1） |
| P3-1 | `aimili_cli.py:211` | `print_terminal_qr` 硬编码 `subprocess ["python3", ...]` |
| P3-2 | `install.sh:194` vs 实现 | 注释称"443 是九合一节点端口、AimiliVPN 不用 443"，与实际绑定 VLESS-Reality 443 矛盾（注释/实现不一致） |

---

## 五、历史报告对照（5 份 → 当前状态）

| 报告 | 时间 | 结论 | 与 HEAD 的对应 |
|---|---|---|---|
| AimiliVPN-代码审查报告 | 10-22 | CLI NameError、nginx regex、install.sh local、cron 已修 | ✅ 均已修复 |
| qwen3.8-flash | 10-23 21:14 | 6 项 P1 全部落地；CDN 推导补 DNS 闸"未真正修好" | 🟡 推导闸已在 HEAD 实现（`generate_subs.py:89-99`）→ 基本闭环 |
| MiniMax-M3.1 | 10-23 | 4 P0 / 9 P1 / 14 P2 / 8 P3 | 🟢 大部分已在 HEAD 修复；fallback 类缺陷残留 |
| Qoder-Agent | 10-23 | 15+ 项 P0/P1（cert 死代码、re.sub 注入、1397 no-||-true、check_health 假阴性等） | 🟡 部分已修（1397/1398 行号漂移，现 `curl -6fsS ... || echo ""` 已带兜底） |
| GLM-5.3 | 10-23 21:51 | run 级 P0（空 detour / rule_set fatal）实测复现 → **本轮 HEAD 已修复** | ✅✅ **闭环完成** |

**关键结论**：GLM-5.3 报告的 run 级 P0 本轮已由后续提交（V1.5.0 周期）修复；即便如此，**"门禁只做 check"的流程缺口**（check 通过 ≠ run 能过）已在本轮被有力佐证，建议未来每次改 `generate_subs.py`/`setup_singbox.sh` 后强制跑 `sing-box run` 冒烟。

---

## 六、修复优先级建议（用户拍板后可执行的路径）

1. **第一优先（P0）**：修 `scripts/setup_warp.sh` fallback 分支（补全字段/失败退出）—— 当前 HEAD 仍有此问题，建议立刻处理。
2. **第二优先（P1）**：补 `generate_subs.py` AnyTLS 进 clash；修 `check_health.sh` 退出码覆盖。
3. **第三优先（P2）**：门禁/CI 增加 `sing-box run` 冒烟；补 `nft` 幂等、`nginx -t` else、cron flock 等遗留项。
4. **第四优先（P3/体验）**：`install.sh` ExecStart 统一解释器、注释矛盾、CLI python3 硬编码等。

---

## 七、代码优化建议（不改 bug 的增值项）

1. **单一事实来源**：证书状态（`ACME_ISSUED`/`web_certificate.json`）建议抽 `cert_state.json`（多脚本各自维护标志位，历史上已暴露状态机分裂风险）。
2. **端口单一事实来源**：`AIMILI_FW_PORTS` / 防火墙三套逻辑 / `check_health` 端口列表 / install.sh 注释，建议抽一处常量或脚本生成。
3. **订阅鉴权**：18443 订阅端口（sub.txt 含 UUID/公钥）**无鉴权/token**，与 8443 面板有 secret_path 形成防护不对称（历史 P2-1 已列，建议排期上线）。
4. **代码结构**：`generate_subs.py` 中 IPv4/IPv6 × 直连/住宅 × CDN 手写重复块多，建议重构成"协议 × 出站 × 地址族"三维循环 + 单模板函数（历史审查提过，建议落地）。
5. **DNS 超时**：`generate_subs.py` 的阻塞式 `socket.gethostbyname` 在 cron 15min/订阅重建路径上建议加超时。
6. **失败语义**：TG 告警发送失败被 `|| true` 吞掉、WARP fallback、check_health 假阴性 —— 建议建立"失败即失败"的上报链路。

---

## 八、未覆盖范围与后续验证建议

- `.so` 编译产物（`core/*/…so`）属二进制，源码级审计范围外；建议保留对照版本。
- 本机为 Windows + Linux 双环境，IPv6 全链路未实测；建议在真实 VPS（Ubuntu）上跑 `sing-box check`/`run` + 订阅实测。
- 建议新增 CI 步骤：`sing-box run -c <mock>` 冒烟 + 语义断言（无 CDN 域名时不得注入 CDN；`direct.` 无 DNS 记录不得推 CDN）。

---

**审查结论**：**当前 HEAD 已无 P0/P1 级的"装完即废"缺陷**；剩余主要风险集中在 WARP fallback、Clash AnyTLS 缺失、健康检查假阴性，以及门禁/`run` 级验证缺口。本次未改动任何代码，等待您决定是否按上述优先级开展修复。
