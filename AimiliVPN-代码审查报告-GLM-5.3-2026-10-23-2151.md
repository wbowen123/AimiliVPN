# AimiliVPN 代码审查报告（GLM-5.3）

- 审查模型：GLM-5.3
- 审查时间：2026-10-23 21:51
- 审查对象：仓库 `HEAD` = `9d5b5c2`（main）**+ 5 个文件的未提交工作区改动**（`scripts/code_gate.py`、`scripts/generate_subs.py`、`scripts/nginx/aimilivpn-production.conf`、`scripts/setup_singbox.sh`、`scripts/setup_warp.sh`）
- 版本号：`VERSION` = `V1.4.8`
- 审查性质：**只读分析，未修改任何仓库源码**（测试均在系统临时目录进行）
- 对照基线：`AimiliVPN-代码审查报告-qwen3.8-flash-2026-10-23-2114.md`、`AimiliVPN-代码审查报告-2026-10-22.md`（MiniMax 轮）

审查方式（与前几轮的关键差异）：

| 动作 | 结果 | 证据级别 |
|---|---|---|
| `python aimili_cli.py` / `sub` / `web` / `status` | 全部 exit 0，无崩溃 | 实测 |
| `python scripts/code_gate.py`（Code Gate V2.0） | 全绿 | 实测 |
| 调用 `generate_subscriptions()` 5 组输入场景 | CDN 条件注入已修、IPv6 已进 singbox.json | 实测 |
| **`sing-box 1.14.3 check`（真实内核）** | 两份生成配置全部通过 | 实测 |
| **`sing-box 1.14.3 run`（真实内核启动）** | **全部 FATAL，无法启动** | 实测 ← 本轮核心增量 |
| PyYAML 解析生成的 `clash.yaml` | 结构合法、无悬空引用 | 实测 |
| rule-set 下载失败模拟（URL 指向 NXDOMAIN 域名） | **FATAL：拒绝启动** | 实测 |

> 结论先行：上一轮（qwen3.8-flash）报告的 6 项 P1 在当前工作区已全部落地修复；但本轮用 **run 级实机验证** 发现了前几轮（包括 CI 门禁）都漏掉的两个致命问题——`check` 通过、`run` 必挂。**"门禁全绿"与"客户端开箱即用"之间隔着一条 check ≠ run 的鸿沟。**

---

## 一、结论摘要

| 级别 | 数量 | 说明 |
| :-- | :-- | :-- |
| P0 阻断（新发现，已实锤） | 2 | 生成的 `singbox.json` 在 sing-box 1.14.3 上 `run` 必然 FATAL（两处独立原因） |
| P2 功能/一致性 | 5 | CDN 域名推导不一致、IPv6 CDN 硬编码、WARP 无二进制时状态分裂、Clash 无 AnyTLS、遗留安全默认值 |
| P3 杂项 | 4 | heredoc 缺 `import sys`、门禁含个人路径、Argo 命名误导、本机测试数据残留 |

上轮 6 项 P1 **全部确认已修复**（见第二节复核表）。未提交改动整体方向正确、质量不错，但引入/暴露了上述两个 run 级 P0，**建议修完 P0 再提交**。

---

## 二、上轮缺陷复核（qwen3.8-flash 报告逐条对账）

| 原编号 | 原问题 | 当前状态 | 本轮验证证据 |
|---|---|---|---|
| P1-1 | CDN 节点无条件注入、`direct.` 推不出 `cdn.` | ✅ 已修 | 实测 5 场景：无域名/裸域名（cdn. 无 DNS 记录）→ **不再生成 CDN 节点**；`direct.` 前缀 → 正确推导 `cdn.`；显式 `cdn_domain` → 正常出节点 |
| P1-2 | IPv6 不进 `singbox.json` | ✅ 已修 | 实测：带 `public_ipv6` 时 singbox 出站含 4 条 IPv6 节点（VLESS/Hy2/TUIC/VMess），与 nodes.txt/clash.yaml 对齐 |
| P1-3 | WARP 重建规则把 sniff 挤到后面 | ✅ 已修 | `setup_warp.sh:324` `final_rules = [sniff_rule] + dns_rules + [priv_rule, resi_rule]`，sniff 与 DNS 劫持规则固定置顶 |
| P1-4 | WARP 缺 `reserved`/`client_id`、公钥兜底=私钥、PATH 探测 | ✅ 已修 | `client_id` base64 解码为 3 字节 `reserved` 并持久化到 `warp_account.json`；openssl 失败改用 `cryptography` 生成，再失败 `sys.exit(1)`（不再公私钥相同）；`SB_BIN` 三路径探测；无二进制时保留 `.bak` |
| P1-5 | 客户端 DNS 无 CN 直连、DoH 无 server_name | ✅ 已修 | `remote-dns` 补 `tls.server_name: dns.google`；新增 `geosite-cn`/`geoip-cn` remote rule_set + `default_domain_resolver`；`congestion_controller`→`congestion_control`（TUIC 字段名纠正） |
| P1-6 | AnyTLS `padding_scheme: "random"` 非法 | ✅ 已修 | 该字段已从 `setup_singbox.sh` 服务端配置中删除（grep 确认无残留） |
| P2-3 | nginx 8443/18443 只听 IPv4 | ✅ 已修 | 两个 server 均补 `listen [::]:8443 ssl` / `[::]:18443 ssl` |
| P2-2 | Hy2 跳跃无 ip6tables | ✅ 已修 | ip6tables nat REDIRECT + INPUT 放行已加；firewall-cmd TCP 列表已含 8446 |

**更早的 P0 复核**（2026-10-22 报告）：CLI 崩溃（NameError）已修——`get_web_auth_data()`/`print_web_dashboard()` 已有实现（`aimili_cli.py:90/203`），四个命令实测全部正常；`install.sh` 函数外 `local` 已修（`mem_mb=$((...))`，现存 `local` 均在函数内）；nginx 正则 `proxy_pass` 带 URI 已改为前缀 location（合法），且新增 8446 VMess-WS 入站与 C3 节点对齐；cron 的 `generate_subs.py` 已带参调用（`setup_cron.sh:153`）。

---

## 三、新发现缺陷

### P0-A 生成的 `singbox.json` 在 sing-box 1.14.3 上无法启动：`check` 通过、`run` FATAL ✅已实机复现

**位置**：`scripts/generate_subs.py:707`（`local-dns` 定义）+ `:700`（末尾追加的空 direct 出站）

```json
{"tag": "local-dns", "type": "udp", "server": "223.5.5.5", "detour": "direct"}   // ← detour 指向空 direct 出站
...
[{"type": "direct", "tag": "direct"}]                                            // ← 零配置 direct 出站
```

**实机复现**（sing-box 1.14.3，Windows 本地，2026-10-23）：

```
$ sing-box check -c singbox.json     → exit 0（语法/结构校验通过）
$ sing-box run   -c singbox.json
FATAL[0000] start service: start dns-transport: start dns/udp[local-dns]:
detour to an empty direct outbound makes no sense
```

所有 5 个测试场景（有/无域名、有/无 IPv6）**无一例外全部 FATAL**。

**影响链**：`generate_subs.py` 生成的 `singbox.json` 是 README 宣称"Sing-box 原生开箱即用"的核心交付物；用户下载导入 1.14.x 客户端后**直接启动失败**。而项目 CI 与 Code Gate V2.0 只跑 `check`，**恰好测不出这一层**——这解释了为什么三轮审查、门禁全绿，问题却一直存在。

**注**：`detour: "direct"` 是 HEAD 已有代码（非本次未提交改动引入），即 9d5b5c2 及更早提交生成的配置在 1.14.3 上同样 run 不了。

**修复方向**：删除 `local-dns` 的 `"detour": "direct"`（DNS 查询默认即直连，显式 detour 到空 direct 出站被 1.14 拒绝）。验证时必须用 `run`（或至少 `sing-box check --all` 若未来支持），不能只 `check`。

---

### P0-B rule_set 远程下载失败 = 拒绝启动，大陆客户端"鸡生蛋"死锁 ✅已实机复现

**位置**：`scripts/generate_subs.py:722-737`（`route.rule_set` 两个 remote 条目）

```json
{"tag": "geosite-cn", "type": "remote", "format": "binary",
 "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs",
 "download_detour": "direct"}
```

**实机复现**（修掉 P0-A 后继续 run，1.14.3）：

```
WARN[0000] legacy `download_detour` remote rule-set option is deprecated in sing-box 1.14.0
            and will be removed in sing-box 1.16.0.
FATAL[0000] start service: start router: (initialize rule-set[1]: initial rule-set: geoip-cn:
Get "https://raw.githubusercontent.com/.../geoip-cn.srs": read tcp ...->185.199.108.133:443:
wsarecv: An existing connection was forcibly closed by the remote host ...)
```

两个独立事实：

1. **下载失败是 FATAL 而非降级**——即使在我这台可正常上网的机器上，GitHub raw 连接被重置一次就整体启动失败；配置未启用 `cache_file`，**每次启动都强制重新下载**。
2. **`download_detour: "direct"` 要求客户端在建立任何代理隧道之前直连 `raw.githubusercontent.com`**——该域名在大陆长期被封锁。用户装 VPN 的前提是连不上，而客户端启动的前提是连得上：**逻辑死锁，目标用户群基本 100% 触发**。

附带问题：`download_detour` 已被 1.14.0 标记废弃（1.16.0 移除，见上方 WARN），当前写法是明知即将失效的 legacy 字段。

**修复方向**（三选一或组合）：
- 启用 `"experimental": {"cache_file": {"enabled": true}}`，首次成功后断网可启动（治标）；
- 改用 `type: "local"` 规则集，把 `.srs` 随订阅/面板一并分发（治本，订阅服务已挂在 18443，顺手就能带）；
- 至少把 URL 换成大陆可达镜像，并迁移到 1.14 的新写法。

---

### P2-1 `direct.` 前缀推导 `cdn.` 不做 DNS 校验，与裸域名分支行为不一致 🔍（实测确认行为）

**位置**：`scripts/generate_subs.py:45-52`

裸域名分支（`:53-67`）会先 `socket.gethostbyname("cdn.example.com")` 探测，解析失败则 `cdn_host=""`（不出 CDN 节点）；但 `direct.` / `cdn.` 前缀分支**无条件推导**。实测：`domain=direct.example.com` 时 `cdn.example.com` 并不存在 DNS 记录，仍然生成了 3 条 CDN 节点（含硬编码 IPv6 那条）并进入 `⛅ CDN破墙` urltest 组。

**影响**：只给 `direct.` 建了 A 记录（灰云直连）的用户——这正是 README 推荐的最常见部署形态——订阅里仍会固定出现握手必败的 CDN 死节点，拖累自动优选组。qwen 建议"direct. 无条件推导 cdn."被采纳了，但推导之后缺了"解析得到才启用"的最后一道闸。

**修复方向**：前缀分支推导出的 `cdn.` 候选同样过一遍 `gethostbyname`，失败则置空（约 4 行改动，与裸域名分支对齐）。

---

### P2-2 IPv6 CDN 节点硬编码 `2606:4700::6810:a00a`，与优选 IP 配置脱钩 🔍

**位置**：`scripts/generate_subs.py:332 / :639`

```python
cf_ipv6_clean = "2606:4700::6810:a00a"   # 硬编码
```

两个问题：
1. 该值不随 `cf_clean_ip.txt`（用户优选 IP）变化——IPv4 侧换优选 IP 后，IPv6 CDN 节点仍指向这个固定地址，两端不一致；
2. 该地址是把 IPv4 优选 `104.16.160.10` 的十六进制嵌入 `2606:4700::/32` 拼出来的，**是否为有效可路由的 CF Anycast 地址未经任何验证**（本机无法实测 IPv6 路由）。[未实机测试]

**修复方向**：从配置文件读取（如 `cf_clean_ipv6.txt`），或按优选 IPv4 系统性换算并文档化；至少加一条连通性探测。

---

### P2-3 WARP 在"找不到 sing-box 二进制"时进入状态分裂 🔍

**位置**：`scripts/setup_warp.sh:367-369`

```bash
else
    log_warn "未探测到 sing-box 二进制，已更新配置文件但保留备份 ${SINGBOX_CONFIG}.bak"
fi
```

该路径下：磁盘配置已更新（含 WARP 出站）、`.bak` 保留、**服务未重启**（运行中进程仍是旧配置）、**`warp_mode.json` 未写**（`ml warp` 状态显示与实际不符）、函数返回 0（调用方认为成功）。下一次看门狗/升级/人工 restart 时 WARP 才突然生效，且此时 `.bak` 已成陈旧快照。

**修复方向**：无二进制时要么直接 `return 1` 明确失败，要么把"未应用"状态写入 `warp_mode.json`（如 `"mode": "pending-restart"`），三处状态（磁盘/进程/模式文件）必须同源。

---

### P2-4 Clash 订阅仍无 AnyTLS 节点 🔍（遗留，实测确认）

实测生成的 `clash.yaml` 代理类型统计：`{'vless': 3, 'hysteria2': 3, 'tuic': 3, 'vmess': 4}`——AnyTLS 只进 `nodes.txt`/`sub.txt`/`singbox.json`。Mihomo 已支持 `anytls` 类型，`晚高峰抗QoS (TCP优先)` 组因此少了两条 TCP 抗封锁节点，三种订阅格式节点集合不对齐（qwen P2-4 原样遗留）。

---

### P2-5 遗留安全默认值（未处理，仅登记）

- SOCKS5 默认密码仍为 `ilovestudy`（`install.sh` / `setup_singbox.sh`）；
- `tg_bot.sh` 定义了 `aimilivpn-tgbot.service` 路径但仓库内仍无该 unit，卸载脚本会去 stop 一个不存在的服务；
- `setup_singbox.sh:611` 仍全局 `sed s/server_name _;/...`（会波及 80 端口伪装站/ACME 块）。

---

### P3 杂项

1. **`setup_warp.sh:93` heredoc 缺 `import sys`**：密钥生成兜底分支 `sys.stderr.write(...)` 会抛 `NameError` 而非预期的清晰报错（外层 import 列表为 `urllib.request/json/base64/os/subprocess`）。触发概率低（需 openssl 与 cryptography 同时缺失），但一旦触发日志是一段 traceback。
2. **`code_gate.py:377` 硬编码开发者个人路径** `~\.gemini\antigravity-ide\scratch\sing-box.exe`：进仓库的门禁脚本依赖个人机器路径，他人环境永远走不到这个分支（无害但脏，且暴露开发环境细节）。
3. **Argo 节点名仍为 "VMess-WS-Argo" 而实际传输是 `net: http`**（`generate_subs.py:129/286-289`）：功能可通，名称误导排障（qwen P2-6 原样遗留）。
4. **本机测试环境污染**（非项目缺陷，提醒后续审查者）：`I:\opt\aimilivpn\vpngate_data\` 残留了上轮会话的测试产物（`argo_info.json`→`test.trycloudflare.com`、`public_ipv6.txt`→`2001:db8::1`、`cf_clean_ip.txt`）。由于 Windows 下 Python 把 `/opt/...` 解析到当前盘符，本机跑 `generate_subscriptions()` 会被这些文件污染输入，复现问题时先清点该目录。

---

## 四、门禁盲区分析（为什么三轮审查+CI 都没拦住 P0-A/P0-B）

Code Gate V2.0 与 CI 的验证层次是 **`check` 级**（结构/语法/指纹），而本次两个 P0 都在 **`run` 级**（启动时序）：

1. `sing-box check` 不做 detour 合法性校验、不实际发起 rule-set 下载 → P0-A/P0-B 双双漏过；
2. 门禁是"旧伤指纹机"（qwen P3-1 结论维持）：本轮新报的 CDN 推导不一致、硬编码 IPv6、`import sys` 缺失，门禁同样抓不到。

**建议的最小增强**（不必上 VPS，本机 10 分钟可完成）：

```bash
# 门禁新增第 4 层：run 级冒烟（坏 URL 快速失败，好 URL 验证 detour）
sing-box run -c mock_singbox.json & sleep 2; kill %1   # 启动 2 秒不 FATAL 即过
# 另加 3 条语义断言：
#   - domain=direct.x 时，cdn.x 无 DNS 记录则 singbox.json 不得出现 CDN 出站
#   - singbox.json 不得含 "detour": "direct"（指向空 direct 出站）
#   - rule_set 若为 remote，必须启用 cache_file 或使用本地 .srs
```

---

## 五、修复优先级建议（本次不改代码，仅排序）

| 批次 | 项 | 理由 |
|---|---|---|
| 第一批 | P0-A 删 `local-dns` 的 `detour` | 1 行改动，直接决定"开箱即用"承诺成立与否 |
| 第一批 | P0-B rule_set 本地化/cache_file | 与 P0-A 同一文件，大陆用户启动死锁 |
| 第二批 | P2-1 CDN 推导补 DNS 闸 | 约 4 行，消灭最常见的死节点来源 |
| 第二批 | P2-3 WARP 状态分裂 | 状态同源，防"幽灵生效" |
| 第三批 | P2-2 IPv6 CDN 硬编码、P2-4 Clash AnyTLS、P3 清单、门禁 run 级冒烟 | 巩固与对齐 |

---

## 六、10 分钟自检清单（部署/开发机可执行）

```bash
# 1) P0-A/P0-B 一条命令定生死（在生成产物上执行，而非仓库）
sing-box check -c /var/www/aimilivpn-sub/singbox.json && \
sing-box run -c /var/www/aimilivpn-sub/singbox.json   # run 能过日志初始化才算数

# 2) P0-A 定位
grep -n '"detour": "direct"' scripts/generate_subs.py

# 3) P2-1 行为验证（无 cdn. DNS 记录的域名）
python3 -c "…generate_subscriptions({'domain':'direct.你的域名', …})" 后检查输出中 CDN 出站数

# 4) 上轮修复回归（防止改新代码弄坏旧修复）
python3 -m pyflakes aimili_cli.py scripts/generate_subs.py
grep -n "final_rules = \[sniff_rule\]" scripts/setup_warp.sh
```

---

## 七、总体评价

- **修复执行力：强**。qwen 报告 6 项 P1 全部真实落地，且多数修复质量高（WARP reserved 持久化、sniff 置顶、CDN 条件闸、IPv6 对齐都是正确实现，实测通过）。
- **验证深度：仍不足**。三轮审查 + Code Gate V2.0 全绿，但验证停在 `check` 层；本轮把验证推进到 `run` 层后，立即暴露两个"开箱即用"承诺的直接否定项。**这是本项目当前最重要的流程教训：门禁需要一条 run 级冒烟。**
- **本次未提交改动的处置建议**：方向正确、可提交，但建议先补上 P0-A（1 行）与 P0-B（rule_set 策略），否则把这批改动连同两个 run 级 FATAL 一起带进主分支。

本报告只记录问题与建议，**未修改任何仓库代码**。
