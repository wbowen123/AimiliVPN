# AimiliVPN 红蓝军对抗式代码审查报告

- **审查角色**：Qoder Agent（敌对审查者模式 / Red-Team Auditor）
- **审查时间**：2026-10-23
- **代码基线**：`main` @ **`a46da64`**（审查期间由并行会话提交，见 §0.2）
- **审查范围**：`install.sh`、`aimili_cli.py`、`vpngate_manager.py`、`proxy_server.py`、`github_update.sh`、`scripts/`（21 个脚本）、`scripts/nginx/*.conf`、`.github/workflows/ci.yml`、`README.md`
- **约束遵守**：本次审查 **未修改任何代码**，仅新建本报告文件。

---

## 0. 审查前提与方法论

### 0.1 AGENTS.md 门禁执行结果（Tool-First Verification）

按 `AGENTS.md` 强制要求，第一步与最后一步各执行一次质量门禁：

```
$ python scripts/code_gate.py
====================================================
  AimiliVPN 自动化架构与代码质量门禁 (Code Gate V2.0)
====================================================

[√] 质量门禁全绿通过！无 P0/P1 阻塞性缺陷，Sing-box 1.14 与网络拓扑完全健康。
```

**门禁全绿，但结论是假的。** 本次审查在门禁之外确认了 **3 个 P0、14 个 P1** 级活缺陷，其中 3 个是门禁自身的结构性缺陷导致其"必然绿灯"（见 §5）。

这印证了 `AGENTS.md` 的核心原则——**默认有罪假定**。`scripts/code_gate.py` 不是通用静态分析器，而是一份**针对历史已修复 Bug 的硬编码回归清单**：它只能证明"上次修过的问题没有复发"，无法证明"当前代码没有新问题"。把门禁绿灯当作交付依据，是本仓库当前最大的流程性风险。

### 0.2 重要：审查期间代码被并行会话修改并提交

本次审查开始时工作区处于 `9d5b5c2`。审查过程中，另一个并行会话（产出 `AimiliVPN-代码审查报告-qwen3.8-flash-2026-10-23-2114.md`）先修改了 3 个文件，随后在 **21:48** 提交为 `a46da64`：

```
$ git show --stat a46da64
 install.sh                                  |   9 +-
 scripts/code_gate.py                        | 122 ++++++--
 scripts/generate_subs.py                    | 133 ++++++--
 scripts/nginx/aimilivpn-production.conf     |   2 +
 scripts/setup_singbox.sh                    |  43 ++-
 scripts/setup_warp.sh                       |  62 +++-
```

**本报告的全部结论、行号与实测数据，均已针对提交后的 `a46da64` 逐条重新验证。** 该提交修复了 7 项缺陷（§6.1），同时**引入了 3 项新缺陷**（P0-3 的新增实例、P1-13、P1-14）。

> 由于基线在审查中途变动，§6.1 明确区分了"我审计时确实存在、现已被修复"与"当前仍然活着"的缺陷，避免报告失真。

---

## 1. 总体结论

| 维度 | 评级 | 说明 |
|---|---|---|
| 架构设计 | ★★★★☆ | 双出站分流、事务快照+原子回滚、GOMEMLIMIT 动态配额、容器权能自适应等设计成熟 |
| 代码实现 | ★★☆☆☆ | 大量"静默失败 + 无条件报成功"模式，错误被 `\|\| true` / `except: pass` / `2>/dev/null` 系统性吞掉 |
| 一致性 | ★★☆☆☆ | 端口矩阵、产物文件名、节点数量、`server_name` 替换策略四处存在**跨文件互相矛盾** |
| 安全性 | ★★☆☆☆ | root 级供应链风险、凭据世界可读、非 CSPRNG 生成面板密码、订阅端点零鉴权 |
| 可交付性 | ★★★☆☆ | 全新安装主链路可用，但**证书续期链路已断**，6 天内 HTTPS 面板必然失效 |

**一句话结论**：项目的工程骨架是好的，但它系统性地"把失败报告为成功"。这导致绝大多数故障不会在安装时暴露，而是在数天后（证书过期）、或用户切换到某个客户端时（节点不通）才爆发；且此时所有诊断工具（`check_health.sh` 恒退出 0、门禁恒绿灯、每个安装步骤恒报成功）都会告诉用户"一切正常"。

---

## 2. P0 级缺陷（致命 / 阻断性）

### P0-1 证书自动续期机制完全是死代码，6 天内 HTTPS 面板必然失效

**位置**：`scripts/setup_https.sh:14, 203, 224, 238, 240, 246`

```bash
14:  ACME_ISSUED=0
...
203:  if certbot certonly --webroot -w "$ACME_ROOT" --preferred-profile shortlived --ip-address "$PUBLIC_IP" ...
...
238: if [ "$ACME_ISSUED" = "1" ] && command -v systemctl ... ; then
239:   systemctl enable --now certbot.timer >/dev/null 2>&1 || true
240: elif [ "$ACME_ISSUED" = "1" ] && [ -d /etc/cron.daily ]; then
241:   cat > /etc/cron.daily/aimilivpn-certbot-renew <<'EOF'
246: elif [ "$ACME_ISSUED" = "1" ] && [ -d /etc/periodic/daily ]; then
```

**证据链**（全仓库 grep，含 `core/*.so` 二进制）：

```
$ grep -rn "ACME_ISSUED" . --include=*.sh --include=*.py
./scripts/setup_https.sh:14:ACME_ISSUED=0        <- 唯一的赋值，值为 0
./scripts/setup_https.sh:224:... "$ACME_ISSUED" != "1" ...
./scripts/setup_https.sh:238/240/246:... "$ACME_ISSUED" = "1" ...

$ grep -n "ACME_ISSUED=1" scripts/setup_https.sh
(无输出)
```

`ACME_ISSUED` **从未被置为 1**。三个续期安装分支（systemd timer / cron.daily / periodic.daily）**永久不可达**。

**致命性放大**：第 203 行使用了 `--preferred-profile shortlived`，签发的是 Let's Encrypt **短生命周期证书（6 天有效期）**。两者叠加：

> 走 IP 证书路径的安装，**6 天后 HTTPS 管理面板与订阅入口全部因证书过期而失效**，且系统内不存在任何续期任务。

第 224 行 `[ "$ACME_AVAILABLE" = "1" ] && [ "$ACME_ISSUED" != "1" ]` 的后半个条件恒为真，属装饰性判断。

**修复方向**：在 203 行签发成功的 `then` 分支内立即 `ACME_ISSUED=1`（或把三个分支的判据改为 `ACME_AVAILABLE`）；并确认短生命周期证书是否为本意，若不是则移除 `--preferred-profile shortlived`。

---

### P0-2 root 权限下从未受信任的第三方镜像安装 VPN 核心二进制，仅校验 gzip 完整性

**位置**：`scripts/manage_core.sh:64-80, 132`；同样存在于 `scripts/setup_singbox.sh:79-96`

```bash
64:    local mirrors=(
65:        "$download_url"
66:        "https://ghfast.top/${download_url}"
67:        "https://mirror.ghproxy.com/${download_url}"
68:    )
...
72:        if curl -fSL --connect-timeout 8 --max-time 120 "$m" -o "$tmp_tar" 2>/dev/null; then
73:            if tar -tzf "$tmp_tar" >/dev/null 2>&1; then
74:                downloaded=1
75:                echo -e "${GREEN}  -> 下载完成并校验通过！${PLAIN}"
...
132:    install -m 755 "$extracted_bin" "$SB_BIN"
```

**问题**：
1. 第 73 行 `tar -tzf` **只验证 gzip 归档能否解开**，不验证内容来源。任何能返回合法 tar.gz 的服务器都能通过。
2. 第 75 行输出 **"下载完成并校验通过！"** —— 虚假陈述，根本没有做校验。
3. `ghfast.top` / `mirror.ghproxy.com` 是**不受信任的第三方反代**，可任意替换载荷。
4. 第 132 行 `install -m 755` 到 `/usr/local/bin/sing-box`，随后由 systemd 以 **root** 运行并持有 `CAP_NET_ADMIN`（`setup_singbox.sh:514-515`）。

**攻击面**：任一镜像被投毒 = 服务器完全失陷。这不是理论风险——本项目全部流量（含住宅出口凭据、Reality 私钥）都经过该二进制。

```
$ grep -c "ghfast.top\|ghproxy.com" scripts/manage_core.sh scripts/setup_singbox.sh
scripts/manage_core.sh:2
scripts/setup_singbox.sh:2
```

**修复方向**：镜像下载后与**官方 GitHub 源**取得的摘要比对；或维护钉死版本的 SHA256 表。至少把第 75 行的"校验通过"改为"下载完成"。

**附带**：`manage_core.sh:47` `[ -z "$tag" ] && tag="1.14.3"` 在 GitHub API 限流时静默回退到硬编码版本，却在第 172 行以 **"GitHub 最新稳定版"** 的名义展示给用户。

---

### P0-3 `re.sub` 替换串注入，可损坏 nginx 配置且被静默吞掉（现有 2 处实例）

**实例 A**：`scripts/manage_cert.sh:360-369`

```python
361:        python3 -c "
362: p = '$ng_conf'
363: dom = '${domain:-_}'
366: # 仅精确替换 8443 ssl 块内的 server_name，坚决不触碰 80 端口伪装站 server_name _;
367: c = re.sub(r'(listen\s+8443\s+ssl;[^{]*?server_name\s+)[^;]+;', r'\g<1>' + dom + ';', c)
368: with open(p, 'w', encoding='utf-8') as f: f.write(c)
369: " || true
```

**实例 B（`a46da64` 新引入）**：`scripts/setup_singbox.sh:624-634`

```python
624:        python3 -c "
625: import sys, re
626: path = sys.argv[1]
627: dom = sys.argv[2]
630: c = re.sub(r'(listen\s+(?:\[::\]:)?8443\s+ssl;[^{]*?server_name\s+)[^;]+;', r'\g<1>' + dom + ';', c)
633: " "$NGINX_CONF_DEST" "$DOMAIN" 2>/dev/null || true
```

**缺陷**：`dom` 被拼接进 **替换串（replacement）**，而 `re.sub` 的替换串中 `\1`、`\g<1>` 是**活的反向引用**，未做转义、未改用 lambda。

并行审查子代理已执行复现：
- `dom='x\1y.com'` → 输出 `server_name xlisten 8443 ssl;`（反向引用被展开，配置损坏）
- `dom='a\gb.com'` → `re.PatternError: missing <`

两种情况下 `|| true`（A:369 / B:633）都会吞掉错误，B 还额外加了 `2>/dev/null`。随后 `manage_cert.sh:374` 的 `nginx -t >/dev/null 2>&1 && (...)` 短路，第 387 行仍打印 **`🎉 证书与订阅配置同步完成！`**。

**实例 A 的附带缺陷**：第 363 行 `dom = '${domain:-_}'` 把 shell 变量直接插进 Python 源码字符串，含单引号的输入即为 **root 权限下的任意代码注入**。（实例 B 已正确改用 `sys.argv`，这点值得肯定。）

**修复方向**（两处同样适用）：
```python
repl = lambda m: m.group(1) + dom + ';'
c = re.sub(r'(listen\s+(?:\[::\]:)?8443\s+ssl;[^{]*?server_name\s+)[^;]+;', repl, c)
```

---

## 3. P1 级缺陷（严重 / 功能失效）

### P1-1 `ml sub` 节点分组恒为空——用户看不到任何节点链接

**位置**：`aimili_cli.py:153-155`

```python
153:    direct_links = [l for l in all_links if "直连" in l or "原生" in l]
154:    resi_links = [l for l in all_links if "住宅" in l or "家宽" in l]
155:    argo_links = [l for l in all_links if "Argo" in l or "CDN" in l]
```

**根因**：`all_links` 是 **URI 形态**的节点。节点名（含中文）位于 `#` fragment，而 `generate_subs.py:143` 等处用 `urllib.parse.quote(...)` 做了百分号编码；`vmess://` 则是整段 JSON 的 base64。**中文明文根本不出现在链接字符串里。**

**实测复现**（基线 `a46da64`，`generate_subs.py` 真实产物，域名 + IPv6 场景）：

```
成功生成 14 个多协议双栈节点订阅文件！
links: 14
CLI keyword matches (aimili_cli.py:153-155):
   '直连': 0
   '住宅': 0
   '原生': 0
   '家宽': 0
   'Argo': 0
   'CDN' : 0
```

fragment 的实际形态：`%F0%9F%9A%80%20%5B%E7%9B%B4%E8%BF%9E-...`

**后果**：
- `print_subscription_card()` 的 **【2】直连节点**、**【3】住宅节点**、**【4】CDN 节点** 三个区块**全部空白**（`for` 遍历空列表）。
- `direct_url` 静默退化为 `all_links[0]`，`resi_url` 恒为空串。
- 该函数被 `setup_singbox.sh:714`（`python3 "$ROOT_DIR/aimili_cli.py" sub`）与 `install.sh` 末尾调用 —— **每次安装结束时，用户看到的就是一张没有节点的卡片。**

**修复方向**：先 `urllib.parse.unquote(l.split("#")[-1])` 解码 fragment 再匹配；`vmess://` 需 base64 解码后取 `ps` 字段。

---

### P1-2 防火墙端口矩阵仍有多处不一致：8443/tcp 在 `setup_singbox.sh` 三套逻辑中全部缺失

`a46da64` 已修复 8446 与 40000-50000（见 §6.1），但矩阵仍不一致。

**权威定义**：`install.sh:16-17`
```bash
16: AIMILI_FW_PORTS="${AIMILI_FW_PORTS:-8443 80 443 8444 8445 8446 18443}"
17: AIMILI_FW_UDP_PORTS="${AIMILI_FW_UDP_PORTS:-443 8443 40000:50000}"
```

**当前交叉核对矩阵**：

| 端口 | install.sh:16-17<br>(权威) | setup_singbox.sh:646/678<br>iptables·nft | setup_singbox.sh:658-665<br>ufw | setup_singbox.sh:668-670<br>firewalld | setup_https.sh:255/258<br>ufw·firewalld | check_health.sh:122<br>审计循环 | check_health.sh:206<br>用户提示 |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| 443/tcp | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ |
| **8443/tcp** | ✓ | **✗** | **✗** | **✗** | ✓ | ✓ | **✗** |
| 8444/tcp | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ |
| 8445/tcp | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ |
| 8446/tcp | ✓ | ✓ | ✓ | ✓ | ✗ | **✗** | **✗** |
| 18443/tcp | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 80/tcp | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| 443/udp | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ |
| 8443/udp | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ |
| 40000-50000/udp | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ |

**两个仍然存在的实际故障**：

1. **8443/tcp（HTTPS 管理面板）在 `setup_singbox.sh` 的 iptables(646/678)、ufw(658-665)、firewalld(668) 三套逻辑中全部缺失**，只由 `setup_https.sh:255/258` 覆盖。若 `setup_https.sh` 在第 184 行 sed 处因 `set -euo pipefail` 中止（见 P1-4），**面板端口将永不放行**。

2. **`check_health.sh:122` 的 ufw 审计循环 `for p in 443 8443 8444 8445 18443` 缺 8446** → 8446 被防火墙拦截时（VMess-WS CDN 回源端口），健康检查仍报全绿。而同一文件第 93 行**确实**检查了 8446 的监听状态 —— 即"服务在听，但防火墙没放，检查说没问题"。

3. `check_health.sh:206` 的用户提示文案 `TCP 端口: 443, 8444, 8445, 18443` 缺 8443 与 8446。

**修复方向**：删除所有重复的端口列表，统一从 `install.sh:16-17` 或共享的 `ports.conf` 读取，单一事实来源。目前 7 处独立维护已产生 4 处不一致。

---

### P1-3 `singbox_nodes.json` 与实际生效的服务端配置不一致，降级后仍生成不可用节点

**位置**：`scripts/setup_singbox.sh:461-469` vs `:582-602`

```bash
460: if ! "$SB_BIN" check -c "$SB_CONFIG_TMP" >/dev/null 2>&1; then
461:     echo -e "${YELLOW}  -> 检测到部分前沿特性在当前内核受限，执行自愈降级处理...${PLAIN}"
466: cfg['inbounds'] = [ib for ib in cfg['inbounds'] if ib.get('type') != 'anytls']
468:     if ib.get('type') == 'hysteria2' and 'obfs' in ib:
469:         del ib['obfs']
```

```bash
# NODES_JSON 无条件写入（降级后依然写）
590:   "hy2_obfs": "${HY2_OBFS}",
600:   "anytls_port": 8444,
```

**缺陷**：降级分支**删除了服务端的 anytls 入站与 hy2 混淆**，但 NODES_JSON 仍写入 `hy2_obfs` 与 `anytls_port: 8444`。下游 `generate_subs.py` 据此：
- 继续生成 2 个 **AnyTLS 节点**（`:203-204`）→ 服务端无监听 → 全部不通
- 继续在 hy2 链接附加 `obfs=salamander&obfs-password=...`（`:161`）与 `singbox.json` 的 `"obfs":{...}`（`:557-559`）→ 与无混淆的服务端**握手失败**

**实测**（`a46da64`，无域名场景）确认这两个协议族确实被无条件生成：
```
scheme counts:  2 anytls://  2 hysteria2://  2 tuic://  2 vless://  2 vmess://
```

**触发路径（现实且常见）**：`setup_singbox.sh:60-67`
```bash
60:    if [ -x "$SB_BIN" ] && [ -z "${FORCE_SINGBOX_UPDATE:-}" ]; then
63:        if [ -n "$cur_ver" ]; then
64:            echo -e "${GREEN}  -> 检测到已安装 Sing-box (${cur_ver}) (如需升级请运行: ml core)${PLAIN}"
65:            return 0        <- 已存在即跳过，永不升级
```
`anytls` 是 sing-box 1.11+ 才有的入站类型。老机器残留 1.9/1.10 二进制时，**升级安装会保留旧内核 → `sing-box check` 必然失败 → 静默降级 → 全部 hy2 + anytls 节点报废**，而安装日志只显示一行黄色"自愈降级"，汇总卡片照样宣称全协议就绪。

**修复方向**：降级时把实际生效的能力写回 NODES_JSON（`hy2_obfs=""`、`anytls_port=0`），让 `generate_subs.py` 据此跳过对应节点；`install_singbox_bin` 应做最低版本比较而非"存在即跳过"。

---

### P1-4 `setup_https.sh:184` 的 sed 全局替换污染 80 端口伪装站，且遇 `/` 直接中止安装

**位置**：`scripts/setup_https.sh:2, 181-185`

```bash
2:   set -euo pipefail
...
181: install -m 0644 "$ROOT_DIR/scripts/nginx/aimilivpn-production.conf" "$NGINX_CONF"
182: NGINX_SERVER_NAME="${ADOPTED_DOMAIN:-${AIMILIVPN_DOMAIN:-}}"
183: if [ -n "$NGINX_SERVER_NAME" ]; then
184:   sed -i "s/server_name _;/server_name ${NGINX_SERVER_NAME};/g" "$NGINX_CONF"
185: fi
```

**缺陷 A（越界替换）**：模板中有 **3 处** `server_name _;`：
```
$ grep -n "server_name" scripts/nginx/aimilivpn-production.conf
4:    server_name _;     <- listen 8443 ssl / [::]:8443 ssl  (面板)
51:   server_name _;     <- listen 18443 ssl / [::]:18443    (订阅)
88:   server_name _;     <- listen 80 / [::]:80              (伪装站 / ACME webroot)
```
`/g` 把三处全改，第 88 行的 80 端口伪装站也被改名。

**这与另外两个脚本的明确约定直接矛盾**：
- `manage_cert.sh:366` 注释：`# 仅精确替换 8443 ssl 块内的 server_name，坚决不触碰 80 端口伪装站 server_name _;`
- `setup_singbox.sh:630`（`a46da64` 已修正）：`re.sub(r'(listen\s+(?:\[::\]:)?8443\s+ssl;[^{]*?server_name\s+)...`

即：仓库里已有**两份正确实现**，`setup_https.sh:184` 是唯一残留的退化实现。

**缺陷 B（sed 注入 → 安装中止）**：替换串未转义，分隔符是 `/`。
- `AIMILIVPN_DOMAIN` 含 `/` → `sed: unknown option to 's'` → 非零退出 → `set -euo pipefail` 在**第 184 行杀死整个脚本**。
- 此时尚未执行：`nginx -t`、ACME 签发、防火墙放行（254-260）、以及**第 263-287 行全部凭据与访问地址输出**。
- 域名格式校验在 `install.sh:684` 附近，但 `AIMILI_SKIP_DOMAIN_CHECK=1` 可跳过。

**修复方向**：直接复用 `setup_singbox.sh:624-633` 的 `sys.argv` + 限定作用域 `re.sub` 写法（并按 P0-3 改用 lambda 替换）。

---

### P1-5 `install.sh:1397` 是全流程唯一无 `|| true` 保护的关键步骤，失败即导致用户拿不到面板凭据

**位置**：`install.sh:2, 1168, 1397, 1475`

```bash
2:     set -e
...
1168:    bash "${INSTALL_DIR}/scripts/setup_https.sh"      <- 无保护
1170: aimili_fw_open || true                                <- 有保护
...
1397:        bash "${INSTALL_DIR}/scripts/setup_singbox.sh" "${SINGBOX_CAMOUFLAGE:-gateway.icloud.com}"   <- 无保护
...
1475: aimili_print_summary
```

**后果链**：`setup_singbox.sh` 内部有多处 `exit 1`（配置校验失败、服务启动失败回滚后）。一旦触发：
- `set -e` 使 `install.sh` 在 1397 行**立即终止**
- 后续的 WARP 探测、CF 优选测速、伪装站、cron 全部不执行
- nginx 8443 连通性自检不执行
- **第 1475 行 `aimili_print_summary` 不执行** → 用户永远看不到面板 URL、`SECRET_PATH`、用户名、密码

`setup_https.sh`（1168 行）同样无保护，且运行在 `aimili_fw_open`（1170 行）**之前** → 若它中止，防火墙永不放行。

**修复方向**：这两处应捕获退出码、打印明确诊断，并用 `trap 'aimili_print_summary' EXIT` 保证凭据无论如何都会输出。

---

### P1-6 面板防扫描后缀与账号密码使用非密码学安全随机数

**位置**：`install.sh:1012, 1017, 1026`

```python
1012:    SECRET_PATH=$(python3 -c "import random, string; print(''.join(random.choices(string.ascii_letters + string.digits, k=12)))")
1017:    pwd = ''.join(random.choices(chars, k=12))
1026:    uname = ''.join(random.choices(chars, k=12))
```

`random` 是 **Mersenne Twister，非 CSPRNG**，内部状态可从输出反推。这三个值写入 `ui_auth.json`，是 HTTPS 面板的**唯一防线**（`secret_path` 防扫描 + 账号 + 密码）。

**同一文件内已有正确写法**（第 1298 行）：
```bash
1298: RAND_PATH=$(python3 -c "import secrets, string; print(''.join(secrets.choice(...) for _ in range(12)))" ...)
```
→ **同文件自我矛盾**，第 1012 行是遗漏未改的旧代码。

**修复方向**：三处统一改用 `secrets.choice` / `secrets.token_urlsafe`。

---

### P1-7 `curl` 缺少 `-f` 与 `-4`，错误响应体会被当作公网 IP 写入全部节点

**位置**：`install.sh:1314-1315`

```bash
1314: PUBLIC_IP=$(curl -s --max-time 3 https://api.ipify.org || curl -s --max-time 3 https://ifconfig.me || curl -s --max-time 3 icanhazip.com || echo "您的服务器公网IP")
1315: echo -n "$PUBLIC_IP" > "${INSTALL_DIR}/vpngate_data/public_ip.txt"
```

**缺陷**：
- 缺 `-f`：HTTP 429/503 时 curl **退出码仍为 0**，`||` 链不触发，**HTML 错误页正文被当成 IP** 写入 `public_ip.txt`。
- 缺 `-4`：双栈主机上 `api.ipify.org` 可能返回 IPv6。

**传播链**：`public_ip.txt` → `setup_singbox.sh:141-146` → `singbox_nodes.json` → `generate_subs.py:143/164/187/203` 直接拼进 URI：
```python
143: f"vless://{direct_uuid}@{public_ip}:{vless_port}?..."
```
`public_ip` **从不加方括号**（只有 IPv6 分支 `:236` 做了 `ip6_url_host = f"[{public_ipv6}]"`）。→ 若 `public_ip.txt` 里是 IPv6 或 HTML，生成的所有 URI **语法非法**，客户端导入即报错。

**同仓库已有两份正确实现**：`install.sh:658-669` 的 `aimili_public_ips()` 用 `curl -4 -fsS --max-time 6` 且 IPv4/IPv6 分开循环；`setup_singbox.sh:145` 用 `curl -4fsS`。**第 1314 行是唯一的退化实现。**

**附带**：`install.sh:1318` 的 `PUBLIC_IPV6` 计算后从未持久化（`a46da64` 已让 `setup_singbox.sh:148-157` 独立获取并持久化，故此行现为悬空死变量）。

---

### P1-8 `setup_warp.sh` 重启后不复核服务状态，且备份路径与 `setup_singbox.sh` 冲突

**位置**：`scripts/setup_warp.sh:17, 339-369`；`scripts/setup_singbox.sh:20, 248, 545-554`

```bash
# setup_warp.sh
349:        if "$SB_BIN" check -c "${SINGBOX_CONFIG}" >/dev/null 2>&1; then
350:            rm -f "${SINGBOX_CONFIG}.bak"
351:            systemctl restart sing-box.service || true      <- 重启失败也继续
...
358:            log_info "Sing-box 规则应用成功，服务已平滑重启！"   <- 无条件报成功
```

**缺陷 A（假成功）**：第 351 行 `|| true` 之后，第 358 行**无条件**打印"服务已平滑重启！"，全程无 `systemctl is-active` 复核。`sing-box check` 通过 ≠ 服务能起来（端口占用、密钥失效、容器权能不足）。→ **代理已死仍报成功。**

**缺陷 B（备份路径冲突）**：
```
$ grep -n 'SB_CONFIG_BAK=\|^SINGBOX_CONFIG=' scripts/setup_singbox.sh scripts/setup_warp.sh
scripts/setup_singbox.sh:20:SB_CONFIG_BAK="$SB_CONFIG_DIR/config.json.bak"
scripts/setup_warp.sh:17:SINGBOX_CONFIG="/etc/sing-box/config.json"     -> .bak 同一路径
```
`setup_warp.sh:350/363` 的 `rm -f "${SINGBOX_CONFIG}.bak"` 会摧毁 `setup_singbox.sh:546` 唯一的回滚副本；反之 `setup_singbox.sh:554` 也会删掉 warp 的备份。两个脚本互相破坏对方的事务快照。

（`a46da64` 已修复此前提出的"无 sing-box 时销毁备份"问题——现在第 367-368 行会 `log_warn` 并**保留**备份，且增加了 `/usr/local/bin`、`/usr/bin` 探测回退。这两点值得肯定，但缺陷 A、B 仍在。）

**修复方向**：备份文件名加脚本前缀（如 `config.json.warp.bak` / `config.json.setup.bak`）；第 358 行前补 `systemctl is-active --quiet sing-box` 复核。

---

### P1-9 `manage_cert.sh` certbot 续期路径永不部署新证书，且失败返回 0

**位置**：`scripts/manage_cert.sh:12, 310-319, 340-346`

```bash
310:    if command -v certbot >/dev/null 2>&1; then
311:        if certbot renew --force-renewal; then
312:            echo -e "${GREEN}  -> Certbot 证书续期成功！${PLAIN}"
313:            sync_cert_and_reload "$domain"
314:            return 0
...
318:    echo -e "${RED}续期失败，请检查 80 端口连通性。${PLAIN}"
319: }                                        <- 无 return 1，echo 退出码 0
```

```bash
# sync_cert_and_reload 的拷贝方向
12: CERT_FILE="$TLS_DIR/fullchain.pem"        (= /etc/aimilivpn/tls/fullchain.pem)
340: sync_cert_and_reload() {
342:     cp -f "$CERT_FILE" "$SB_CERT"        <- 从 /etc/aimilivpn/tls 拷到 sing-box
343:     cp -f "$KEY_FILE" "$SB_KEY"
```

**缺陷 A**：`certbot renew` 把新证书写到 `/etc/letsencrypt/live/$domain/`，但 `sync_cert_and_reload` 是**从 `/etc/aimilivpn/tls/` 往外拷**，没有任何环节把 certbot 的新证书搬进 `/etc/aimilivpn/tls/`。→ **它把过期旧证书重新拷了一遍给 sing-box，然后宣布"续期成功"。**

（对比：acme.sh 路径是正确的 —— `:203-205` 与 `:278-280` 用 `--install-cert --key-file "$KEY_FILE" --fullchain-file "$CERT_FILE"` 直接写入。缺陷仅限 certbot 回退路径。）

**缺陷 B**：第 318-319 行，函数以 `echo` 结尾，退出码 0。→ `manage_cert.sh renew` **永远返回成功**，`setup_cron.sh:90` 的 `manage_cert.sh renew || true` 永远无法感知失败。

**修复方向**：certbot 分支改用 `--deploy-hook` 或显式 `cp /etc/letsencrypt/live/$domain/{fullchain,privkey}.pem`；第 318 行后补 `return 1`。

---

### P1-10 `setup_cron.sh` IP 漂移自愈顺序颠倒 + 全静默失败 → 陈旧 IP 永久固化

**位置**：`scripts/setup_cron.sh:137-157`

```bash
137:    cur_ip=$(curl -s --connect-timeout 4 https://api.ipify.org || true)
138:    if [[ -n "${cur_ip}" && -n "${old_ip}" && "${cur_ip}" != "${old_ip}" ... ]]; then
140:        echo "${cur_ip}" > "${ip_file}"          <- ① 先更新 txt
141:        if [[ -f "${DATA_DIR}/singbox_nodes.json" ]]; then
142:            python3 -c "...
145:    d['public_ip'] = '${cur_ip}'
149: except Exception: pass                          <- ② JSON 更新失败被吞
150: " || true
153:            python3 ".../generate_subs.py" ... || true   <- ③ 订阅重建失败被吞
```

**缺陷**：
1. **顺序颠倒**：第 140 行先把 `public_ip.txt` 改成新 IP，之后 ② ③ 若失败（python3 缺失、权限、磁盘满），下一个 15 分钟周期 `old_ip == cur_ip` → **漂移永不再被检测到** → `singbox_nodes.json` 与全部订阅**永久保留陈旧 IP**，所有客户端断连且无法自愈。
2. **第 137 行 curl 缺 `-f` 与总超时**：只有 `--connect-timeout`，无 `--max-time`（可挂死）；无 `-f`（HTTP 错误页正文被当作 IP）。该值随后写入 `public_ip.txt`、**注入 Python 源码字符串**（第 145 行）、并进入订阅。
3. **`|| true` + `except: pass` 三重静默**：整条自愈链无任何失败可观测性。

**修复方向**：改为"全部产物更新成功后，最后才写 `public_ip.txt`"；curl 加 `-4f --max-time 8`；Python 通过 `argv` 传参；失败时写日志并保留 `old_ip` 以便下轮重试。

---

### P1-11 `upgrade_script.sh` / `github_update.sh` 无条件 `git reset --hard`，可摧毁本地提交且无回滚

**位置**：`scripts/upgrade_script.sh:91, 145-151`；`github_update.sh:36-52`

```bash
# upgrade_script.sh
145: tar -czf "$BACKUP_TAR" -C "$ROOT_DIR" "vpngate_data" 2>/dev/null || true
146: echo -e "  -> 备份完成: ${BACKUP_TAR}"        <- 备份失败也宣称完成
150: git checkout main >/dev/null 2>&1 || true
151: git reset --hard origin/main                  <- 无条件硬重置
```

```bash
# github_update.sh —— 完全没有备份
36: git fetch --prune origin main
39: git checkout main
40: git reset --hard origin/main
47: python3 -m py_compile $modules                 <- 若此处失败，树已被重置，无回滚
52: systemctl restart aimilivpn                    <- 只重启 aimilivpn
```

**缺陷**：
1. 升级判据仅为 `LOCAL_COMMIT != REMOTE_COMMIT`（`upgrade_script.sh:91`），**没有 `git merge-base --is-ancestor`**。本地领先于 `origin/main`（用户打了热修复）的机器会被**静默降级，本地提交被销毁**；已跟踪文件的未提交改动一并丢失。
2. `github_update.sh` **完全不做备份**，且 `py_compile`（47 行）失败时树已重置，无回滚路径。
3. `github_update.sh:52` 只 `systemctl restart aimilivpn`，**sing-box 与 nginx 从不重载** → 更新后的 sing-box 配置/脚本不生效，需人工干预。
4. `upgrade_script.sh:146` 在 `tar ... || true` 之后无条件打印"备份完成"——又一处"失败报成功"。

**修复方向**：先 `git merge-base --is-ancestor HEAD origin/main` 判定能否快进，领先时中止并提示；备份失败必须中止；`github_update.sh` 补 sing-box/nginx 重载与备份。

---

### P1-12 `check_health.sh` 恒以 0 退出，且住宅网桥探测使用了非法的 curl 语法

**位置**：`scripts/check_health.sh:6, 47-52, 139-140`

```bash
6:   set -euo pipefail
...
47: S_SINGBOX=0
50: check_svc "sing-box" "Sing-box 分流代理核心" || S_SINGBOX=1
51: check_svc "aimilivpn" "AimiliVPN 动态住宅网桥" || S_AIMILI=1
52: check_svc "nginx" "Nginx 管理与订阅入口" || S_NGINX=1
```

**缺陷 A（恒退出 0）**：`S_SINGBOX` / `S_AIMILI` / `S_NGINX` 被赋值后**从未参与退出码计算**；全文无任何 `exit` 语句 → 脚本以最后一条 `echo` 的状态（0）退出。所有端口检查也都是 `check_port_listen ... || true`。

```
$ grep -n "^exit\|exit " scripts/check_health.sh
(无输出)
```

→ **10 个端口与 3 个服务全部宕机时，`check_health.sh` 依然返回成功。** 任何依赖它做判断的自动化（含 `tg_bot.sh:320-326` 的 `/status`）都会得到"健康"结论。这与 §0.1 的门禁问题同源：**诊断工具被设计成永远通过。**

**缺陷 B（非法 curl 语法）**：
```bash
139: RESI_IP_RES=$(curl -s4 --connect-timeout 5 --max-time 8 --socks5-hostname socks5:ilovestudy@127.0.0.1:8500 https://api.ipify.org 2>/dev/null || \
140:               curl -s4 --connect-timeout 5 --max-time 8 --socks5-hostname 127.0.0.1:8500 https://api.ipify.org 2>/dev/null || echo "")
```
`--socks5-hostname` 只接受 `host[:port]`，**不支持 `user:pass@` 内联认证**（那是 `--proxy` 的语法）。第 139 行必然失败；第 140 行的回退**不带任何凭据**。若 8500 网桥要求 `socks5:ilovestudy` 认证，则两行都失败 → **完全健康的住宅隧道被报告为 "NOT READY"**，直接破坏该脚本自称的核心能力（"-1 根因排查"）。此外明文凭据硬编码在源码中。

**修复方向**：改用 `--proxy socks5h://socks5:ilovestudy@127.0.0.1:8500`；凭据从 `/etc/default/aimilivpn` 读取；脚本末尾依据 `S_*` 变量 `exit` 非零。

---

### P1-13 【`a46da64` 引入】`code_gate.py` 硬编码开发者本机路径，并移除了可执行位校验

**位置**：`scripts/code_gate.py:373-380`

```python
373:    sb_bin = shutil.which("sing-box") or shutil.which("sing-box.exe")
374:    if not sb_bin:
375:        for cand in [
376:            "/usr/local/bin/sing-box",
377:            "/usr/bin/sing-box",
378:            os.path.expanduser(r"~\.gemini\antigravity-ide\scratch\sing-box.exe")
379:        ]:
380:            if os.path.isfile(cand):          <- 原本是 os.path.isfile(cand) and os.access(cand, os.X_OK)
```

```
$ grep -n "antigravity\|os.access" scripts/code_gate.py
378:            os.path.expanduser(r"~\.gemini\antigravity-ide\scratch\sing-box.exe")
(os.access 已无任何命中)
```

**缺陷**：
1. 第 378 行是**某位开发者本机的 IDE 临时目录**，已随 `a46da64` **提交进版本库**。它对其他所有人与 GitHub Actions 都是死路径，且泄露本地环境信息。
2. 第 380 行**删除了 `os.access(cand, os.X_OK)` 可执行位校验** → 一个不可执行的残留文件会被当作内核去跑 `sing-box check`，产生误导性校验结果。

**修复方向**：删除第 378 行；恢复 `os.access(..., os.X_OK)`。本机调试需求改用环境变量（如 `SING_BOX_BIN`）。

---

### P1-14 【`a46da64` 引入】单域名安装下全部 CDN 节点静默消失，且无任何提示

**位置**：`scripts/generate_subs.py:39-67, 300-302`

```python
 39:    cdn_host = ""
 40:    explicit_cdn = nodes_data.get("cdn_domain") or nodes_data.get("cf_cdn_host", "")
 41:    if explicit_cdn:
 42:        cdn_host = explicit_cdn.strip()
 43:    elif domain:
...
 62:            try:
 63:                import socket
 64:                socket.gethostbyname(cand_cdn)      # cand_cdn = f"cdn.{clean_d}"
 65:                cdn_host = cand_cdn
 66:            except Exception:
 67:                cdn_host = ""                       <- a46da64 由 "domain" 改为 ""
...
300:    # C2, C3, C4: Cloudflare CDN 小黄云代理节点 (严格使用 cdn_host，严禁被 argo_domain 或主域名污染)
301:    cf_cdn_host = cdn_host                          <- 原为 cdn_host if cdn_host else domain
302:    if cf_cdn_host:
```

**实测复现**（同一份 `nodes.json`，仅基线不同）：

| 基线 | domain | 生成节点数 | `104.16.160.10`（CDN 优选 IP）出现次数 |
|---|---|---|---|
| `a46da64` 之前 | `example.com` | **12** | 2 |
| `a46da64`（当前） | `example.com` | **10** | **0** |

**根因**：`cdn.example.com` 无 DNS 记录时，`cdn_host` 现为空串，且第 301 行移除了 `else domain` 回退 → `if cf_cdn_host:` 为假 → **C2/C3/C4 三类 CDN 节点全部不生成**。

**这是有意的设计修正**（第 300 行注释明确"严禁被主域名污染"，且修复了我此前提出的"CDN 节点以 IP 或未代理的顶点域作 SNI 而静默不可用"问题），方向是对的。**但落地不完整，形成新的功能缺口**：

```
$ grep -rn "cdn_domain\|cf_cdn_host" --include=*.sh --include=*.py . | grep -v generate_subs.py
  NO producer anywhere
```

- `cdn_domain` / `cf_cdn_host` **全仓库无任何生产者**；`setup_singbox.sh:582-602` 的 NODES_JSON 也不含该键。
- 因此 `cdn_host` 只可能通过两条路径非空：域名本身以 `direct.` / `cdn.` 开头，或 `cdn.<domain>` 恰好可解析。
- **默认的单域名安装（绝大多数用户）下，"⛅ CDN破墙" 这一整个宣传特性彻底消失**，节点数从宣传的 18 降到 10-14，且：
  - 无任何日志/警告说明原因
  - 无任何文档告知用户需要额外创建 `cdn.` 子域名并开启小黄云
  - `README.md` 与 `aimili_cli.py:226` 仍宣称"18 节点矩阵"

（值得肯定：`generate_subs.py:364/395/406` 对 `clash_cdn_names` 为空做了 `if` 守卫，Clash 配置不会因空列表而崩溃。）

**修复方向**：三选一并补文档——
(a) 在 `setup_singbox.sh` 的 NODES_JSON 写入 `cdn_domain`，由安装流程询问/探测；
(b) `cdn.<domain>` 不可解析时打印明确警告，告知用户如何启用 CDN 节点；
(c) 若决定默认不提供 CDN 节点，同步修正 README/CLI 的"18 节点"口径。

---

## 4. P2 级缺陷（重要 / 边界与安全加固）

| # | 位置 | 缺陷 | 后果 |
|---|---|---|---|
| P2-1 | `scripts/nginx/aimilivpn-production.conf:49-84` | **18443 订阅服务无任何鉴权/token** | `sub.txt` 含全部 UUID、Reality 公钥、hy2 混淆密码。任何端口扫描器可直接拉走全套凭据。而 8443 面板却有 `secret_path` 防扫描——防护强度严重不对称 |
| P2-2 | `aimili_cli.py:370` | `out_lines.append(f'{k}="{key_values[k]}"\n')` 未转义 `"` `$` `\` | 经 `ml egress`（`:441-465`）用户手输的 SOCKS5 主机/账号/密码写入 `/etc/default/aimilivpn`。含 `$` 的密码被破坏；在 Alpine 上（`install.sh:965-967` 的 `. /etc/default/aimilivpn` 会被 shell 展开）构成 **root 命令注入** |
| P2-3 | `scripts/setup_singbox.sh:188` vs `:197` | 复用域名证书时 `cp -f .../privkey.pem "$KEY_FILE"` **后无 `chmod 600`**（`chmod` 只在自签分支） | `/etc/sing-box/key.pem` 继承 umask（通常 644）→ **TLS 私钥世界可读** |
| P2-4 | `scripts/setup_argo.sh:210-228` | `cat > "${SERVICE_FILE}"` 写入含 `--token ${token}` 的 unit 文件，**无 chmod** | `/etc/systemd/system/cloudflared-argo.service` 为 0644，任何本地用户可读取**能完全控制隧道的凭据**；token 同时暴露于 `ps` |
| P2-5 | `scripts/setup_argo.sh:126-151` | `start_quick_tunnel` 开头不清理旧 `ARGO_JSON`；抓取失败时（137 行）仅警告 | 上次运行残留的 `*.trycloudflare.com` 域名被 `show_status`（291-301）当作在线状态展示，`start_token_tunnel`（251）据此重建订阅。quick tunnel 域名每次重启都变，**这是常态而非边界情况** |
| P2-6 | `install.sh:940` vs `:859` | `ExecStart=/usr/bin/python3 vpngate_manager.py` 钉死解释器，而 `select_core.sh` 按 **PATH 中 `python3`** 的 `sysconfig EXT_SUFFIX` 拷贝 `.so` | 当 `/usr/bin/python3` 与 PATH 的 `python3` 版本不一致（Debian 上极常见），systemd 加载的 `.so` ABI 不匹配 → **服务导入失败** |
| P2-7 | `install.sh:194` vs `:14`, `setup_singbox.sh:274/297` | `443:*) echo "端口 ${p}: ${owner}（九合一节点端口，AimiliVPN 不用 443）"` | **陈述与实现相反**：`setup_singbox.sh` 明确绑定 TCP 443（VLESS-Reality）与 UDP 443（Hysteria2）。冲突探测（187 行）覆盖 443，但命中时被这条消息解释为"不影响"→ 443 冲突永不告警 |
| P2-8 | `scripts/generate_subs.py:58, 64` | `socket.gethostbyname(cand_direct)` / `(cand_cdn)` **阻塞式 DNS，无超时** | 每次订阅重建（含 `setup_cron.sh` 的 15 分钟周期）都可能挂死；DNS 不可达时 cron 任务堆积。且现在**每次都要跑 2 次**（原为 1 次） |
| P2-9 | `scripts/generate_subs.py:270-271` | IPv6 vmess 节点 `"add": public_ipv6` 但 `"host": host`；无域名时 `host = public_ip`（IPv4） | Host 头与连接地址不一致。**实测确认**（域名场景下 host=example.com 尚可，无域名场景即为 IPv4） |
| P2-10 | `scripts/generate_subs.py:445-489` | `_to_yaml` 回退实现：`None` 在 dict 分支（454 行）转为 `''`，但**列表项分支（468、479 行）用 `str(v)` 产出字面量 `"None"`**；且不转义内嵌 `"` | 无 PyYAML 的机器上生成的 `clash.yaml` 含 `None` 与破损引号 → Clash 解析失败 |
| P2-11 | `scripts/setup_singbox.sh:575-578` | `nft add rule ip aimilivpn prerouting udp dport 40000-50000 redirect to :443` **无存在性检查**；`nft add table ip` 仅 IPv4 | 每次重跑累积一条重复规则；hy2 监听 `::` 但**IPv6 无端口跳跃**。（对比 iptables 分支 646/678 行有 `-C` 幂等检查，nft 分支没有） |
| P2-12 | `scripts/setup_singbox.sh:545-554` | 回滚 `mv -f "$SB_CONFIG_BAK" "$SB_CONFIG_FILE"` **消耗**备份；成功路径 `rm -f "$SB_CONFIG_BAK"` **销毁**快照 | "事务快照"名不副实：任何时刻最多只有一份，成功后归零。与 P1-8 的路径冲突叠加 |
| P2-13 | `scripts/setup_singbox.sh:638-642` | `if nginx -t >/dev/null 2>&1; then ... fi`，**无 else 分支** | nginx 配置错误时静默跳过 reload，不打印任何诊断，用户看到"已就绪"却仍在跑旧配置 |
| P2-14 | `scripts/tg_bot.sh:251-254` vs `:160-167` | `send_alert` 用 `msg+="...\n"`（双引号内 bash **不解释** `\n`），而 `send_test_message` 正确地用 `%0A` + `echo -e "${msg//%0A/\\n}"` | **所有自动告警**（`setup_cron.sh:116, 159`）在 Telegram 里显示为一行带字面量 `\n` 的乱码 |
| P2-15 | `scripts/tg_bot.sh:320-326` | `check_health.sh` 输出（含 ANSI 转义、`->`、`&`）**未做 HTML 转义**即以 `parse_mode: HTML` 发送 | Telegram 返回 "can't parse entities"，`send_msg` 的 `except: pass` 吞掉 → `/status` **静默无响应且无日志** |
| P2-16 | `scripts/setup_cron.sh:5, 77-78` | 头注释与菜单宣称"内存页面释放 (drop_caches)"，实现里**只有 `sync`**，全文无 `drop_caches` | 面向 512M/1G 小内存 VPS 的**核心卖点功能是空操作** |
| P2-17 | `scripts/setup_cron.sh` 全文 | crontab 任务（15 分钟看门狗 + 04:00 维护）**无 `flock`** | 两个任务可重叠，竞争同一批订阅文件与 `MAINT_LOG` |
| P2-18 | `scripts/setup_https.sh:97-99, 142-152, 188` | 重跑时无条件用自签证书覆盖 `$KEY_FILE/$CERT_FILE`；领养循环要求 **DNS SAN**（143-144 行）而 IP 证书只有 `IP:` SAN → 拒收；`ENABLE_IP_ACME` 默认 0 且 `AIMILIVPN_ENABLE_ACME_IP_CERT` 全仓库无处置位；188 行的 80 端口空闲判据因 `aimilivpn-production.conf:86-87` 常驻监听 80 而恒为假 | **重跑安装会把一张有效的 CA 证书降级为自签证书**，且无法重新签发 |
| P2-19 | `scripts/setup_https.sh:255` | `ufw allow 8443/tcp >/dev/null; ufw allow 18443/tcp >/dev/null` **无 `|| true`**（脚本为 `set -euo pipefail`） | ufw 命令失败即中止脚本，跳过后续凭据输出 |
| P2-20 | `.github/workflows/ci.yml` | **安装了 shellcheck 却从未调用**；sing-box 内核校验只跑客户端 `singbox.json` | 全部 shell 脚本（6221 行）在 CI 中零静态检查；**服务端配置从未经内核校验**（见 §5.2） |
| P2-21 | `install.sh:845` | `curl -fsSL https://get.acme.sh \| sh -s email=admin@ilovestudycn.com` | `curl \| sh` 无摘要校验；且用**上游作者的邮箱域名**注册 ACME，而 `vpngate_manager.py` 正在费力把该品牌全部改写掉——自我矛盾 |
| P2-22 | `install.sh:1088-1098, 1131-1136` | 全接口 `rp_filter=2`（松散反向路径校验）、`ip_forward=1`、`forwarding=1` | 策略路由需要 `rp_filter=2`，但**全接口**施加削弱了反欺骗防护；转发开启后若无配套 FORWARD 策略，本机可被用作转发跳板 |
| P2-23 | `scripts/setup_warp.sh:133-160` | API 失败分支写入 `"fallback": True` 并退出 0，而**无任何代码读取 `fallback`** | 硬编码的 `peer_pub` / `172.16.0.2` 端点被无条件安装并报告成功，实际不连通 |
| P2-24 | `scripts/setup_argo.sh:5 vs :110` | 头部宣称可穿透 `8445/8443`，第 370 行接受任意端口，但第 110 行硬编码 `--url http://127.0.0.1:${local_port}` | 传入 8443（nginx HTTPS）会产生 "400 The plain HTTP request was sent to HTTPS port" |
| P2-25 | `scripts/setup_argo.sh:236-239` | `"domain": "${domain}"`（`read -r` 原样输入）与 `"local_port": ${local_port}`（无引号数值）直接插入 heredoc JSON | 含 `"` 的输入损坏 `argo_info.json`（下游 `generate_subs.py:96` 解析失败）；非数值端口产出非法 JSON。另 `:238` 的 `${token:0:8}***${token: -6}` 在 `len(token) < 14` 时泄露完整 token |

---

## 5. 质量门禁与 CI 的盲区分析

### 5.1 `code_gate.py` 是回归清单，不是静态分析器

它由一组**硬编码字符串匹配**构成，只覆盖历史上修过的具体 Bug。三个结构性盲区：

1. **`:216` 是一条死门禁**
   ```python
   216:  if os.path.basename(sh) == "manage_cert.sh" and 'sed -i "s/server_name .*;/server_name ${domain};/g"' in line:
   217:      report_error(..., "P2-SED-POLLUTION")
   ```
   ```
   $ grep -c 'sed -i "s/server_name' scripts/manage_cert.sh
   0
   ```
   目标字符串**在 `manage_cert.sh` 中已不存在**（该文件改用 `re.sub`）。而**真正的现行犯 `setup_https.sh:184`（P1-4）根本没有被检查**。→ 门禁在活缺陷上保持绿灯。

2. **`:132-137` 的告警按构造永被抑制**
   ```python
   if '443 8443 8444 8445 18443' in h_c and '8446' not in h_c:
   ```
   `8446` 确实出现在 `check_health.sh`（第 93 行的端口监听检查），所以 `'8446' not in h_c` **恒为假**，该告警永久静默。而真正缺 8446 的是**第 122 行的 ufw 审计循环**——门禁检查的是错误的字符串。

3. **`:104` 的字符串匹配脆弱**
   ```python
   '"tls": True'
   ```
   对 `json.dump` 产物（`true`）不匹配，只对 Python 源码字面量有效。

### 5.2 服务端 sing-box 配置从未经内核校验

`code_gate.py` 的 `check_singbox_binary_validation()` 只执行 `generate_subs.py` 并 `sing-box check` **客户端** `singbox.json`。

**由 `setup_singbox.sh:247-442` 生成的服务端配置从未进入校验范围。** 这正是 P0-2（旧内核不认 `anytls`）与 P1-3（静默降级）能长期潜伏的原因——CI 里那个 1.14.3 内核，从来没有检查过真正跑在用户服务器上的那份配置。

### 5.3 CI 装了 shellcheck 却不用

`.github/workflows/ci.yml` 安装 `shellcheck`，但后续步骤只有 `code_gate.py`、`pyflakes`、`bash -n`、`compileall`。**6221 行 shell 代码在 CI 中零静态检查。** `bash -n` 只验语法，不验语义。

本次报告中至少 8 个缺陷（P1-4、P1-5、P1-8、P1-10、P1-11、P2-2、P2-13、P2-19）属于 shellcheck 的常规检出范围。

---

## 6. 与既有报告 / 并行修复的关系

### 6.1 `a46da64` 在本次审查期间已修复的 7 项（均已实测确认）

| 修复项 | 位置 | 验证方式 |
|---|---|---|
| **IPv6 双栈全链路死亡**（原 `public_ipv6.txt` 零生产者、NODES_JSON 无该键） | `setup_singbox.sh:148-157, 585` | `grep` 确认新增生产者 + `"public_ipv6"` 键；实测节点数 12 → **14**，4 个 IPv6 直连节点已生成 |
| `cdn_host` 死分支（原 `cdn_host = domain if domain else public_ip` 使 `if not cdn_host` 永假） | `generate_subs.py:39-67` | 实测 CDN 节点 SNI 由 `203.0.113.9`（IP 当 SNI）变为正确域名/空 |
| anytls `"padding_scheme": "random"` 非法字段 | `setup_singbox.sh` 原 349 行 | 已删除。**证实了我此前"疑似非法 schema 且是降级触发器"的判断** |
| hy2 `server_ports` 格式错误 | `generate_subs.py:528-541` | 实测输出 `['443:443', '40000:50000']` |
| tuic `congestion_controller` → `congestion_control` | `generate_subs.py` | 实测 outbound 键为 `congestion_control` |
| 路由缺 `default_domain_resolver` | `generate_subs.py:680` | 实测 `route.default_domain_resolver = local-dns` |
| **WARP 密钥对伪造**（原 `except: pub_key = priv_key`，把私钥当公钥注册给 Cloudflare） | `setup_warp.sh:83-95` | 改为 `cryptography` x25519，失败则 `sys.exit(1)` |
| **WARP 重建时 sniff 规则被降级到索引 ≥3** | `setup_warp.sh:241+` | 现将 sniff/DNS 规则重新置顶 |
| nginx 无 IPv6 监听 | `aimilivpn-production.conf:3, 50` | 新增 `listen [::]:8443 ssl;` / `listen [::]:18443 ssl;` |
| UDP 40000-50000 未在权威端口表 + 8446 未放行 | `install.sh:17`、`setup_singbox.sh:661/668` | 均已补齐（firewalld 范围语法 `:`→`-` 转换正确） |
| `setup_warp.sh` 无 sing-box 时销毁备份且返回 0 | `setup_warp.sh:339-368` | 现探测 3 个路径，失败时 `log_warn` 并**保留**备份 |
| `setup_singbox.sh` 的 `server_name` 全局 sed | `setup_singbox.sh:630` | 改为限定作用域 `re.sub` + `sys.argv` 传参 |
| 门禁 dummy 密钥导致内核校验假失败 | `code_gate.py:395-396` | 改为合法 base64 公钥与 16 位 hex short_id |

**但同一次提交引入了 3 项新缺陷**：P0-3 实例 B（`setup_singbox.sh:630` 复制了同样的替换串注入）、P1-13（硬编码本机路径 + 删除可执行位校验）、P1-14（CDN 节点静默消失）。

### 6.2 上一份 MiniMax 报告 §7.3 的根因已定位并修复

MiniMax 报告指出"clash.yaml 节点矩阵 16 ≠ README 宣称的 18"但未给出根因。**根因是 IPv6 产物断链**（`public_ipv6.txt` 无生产者 + NODES_JSON 缺键），已由 `a46da64` 修复。

**但差距并未消除**：当前实测 **无域名 10 个 / 有域名+IPv6 14 个**，仍少于宣称的 18 个。剩余缺口由 **P1-14**（CDN 节点在单域名安装下全消失）与 Argo 节点（需 `argo_info.json`）构成。README:8/158/174-184/224 与 `aimili_cli.py:226` 的"18 节点矩阵"口径仍需修正。

### 6.3 上一份报告（2026-10-22）的 P0 项复核

| 原缺陷 | 当前状态 |
|---|---|
| P0-1 `aimili_cli.py` 调用未定义函数 | ✅ 已修复（全文复核，无未定义引用） |
| P0-2 函数体外使用 `local` | ✅ 已修复（门禁 `P0-SHELL` 持续覆盖） |
| P0-3 nginx `location ~` 块中 `proxy_pass` 带 URI | ✅ 已修复（门禁 `P0-NGINX` 持续覆盖） |

### 6.4 死产物：`singbox_links.txt` 有 4 个消费者、0 个生产者

```
$ grep -rn "singbox_links.txt" . --include=*.sh --include=*.py
./aimili_cli.py:18:LINKS_FILE = os.path.join(DATA_DIR, "singbox_links.txt")
./aimili_cli.py:145:        nodes_txt_path = os.path.join(DATA_DIR, "singbox_links.txt")
./scripts/show_nodes.sh:13:    cat "$ROOT_DIR/vpngate_data/singbox_links.txt" 2>/dev/null || echo "暂无节点数据，请先运行 setup_singbox.sh"
./scripts/tg_bot.sh:190:links_file = os.path.join(data_dir, 'singbox_links.txt')
```
对 `core/x86_64/*.so` 的二进制 grep 亦为 **0 命中**。

- `show_nodes.sh:13` 的兜底分支**必然**打印"暂无节点数据，请先运行 setup_singbox.sh"（误导性提示——实际是文件名错了，正确产物是 `/var/www/aimilivpn-sub/nodes.txt`）。
- `aimili_cli.py:145`、`tg_bot.sh:190` 的回退分支为死代码（主分支读 `nodes.txt`，可用）。

---

## 7. 待真机验证事项（明确标注为 UNVERIFIED）

以下项**本地无 sing-box 1.14 内核，无法确证**，不作为缺陷断言，仅列为上线前必须验证的清单：

1. **DNS 服务器对象字段名**：`generate_subs.py:667-674` 生成
   ```json
   {"tag":"remote-dns","type":"https","server":"8.8.8.8","detour":"🎯 手动选择"}
   ```
   官方文档页仅列出 `type` 与 `tag` 两个键，`server`（vs 旧版 `address`）未在抓取到的文档中确认。**需在 1.14.3 内核上 `sing-box check` 验证。**
   （已验证的部分：`detour` 引用的 `🎯 手动选择` **确实是** `singbox.json` 中存在的 outbound tag —— 实测确认。）

2. **`dns.strategy: "prefer_ipv4"`** 在 1.14 中是否仍为合法字段（1.12+ 的 DNS 重构可能已迁移）。

3. **`hijack-dns`** 动作在当前内核版本的支持情况。

4. **`setup_warp.sh` 的 `warp-out` 路由规则**是否无条件追加、而 endpoint 以 `os.path.exists(warp_file)` 为条件 → 可能产生引用不存在 outbound tag 的配置。`a46da64` 改动了该区域，需重新在真机确认 `sing-box check` 是否通过。

5. **`setup_warp.sh` 对 IPv6 peer endpoint 的处理**：若存在 `ep.split(":")` 后 `int()` 的写法，IPv6 endpoint 会抛 `ValueError`，在 `set -e` 下中止且 `.bak` 已创建未清理。需确认 Cloudflare API 是否可能返回 IPv6 endpoint。

6. **`setup_argo.sh:110` 的明文隧道指向 TLS 端口**（P2-24）需实测确认 nginx 返回 400。

---

## 8. 优化建议（按投入产出比排序）

### 8.1 立即执行（半天内，收益最高）

1. **修 P0-1**：`ACME_ISSUED=1` 一行即可恢复整条续期链路。这是**当前唯一会让已部署服务器在可预期时间内必然故障**的缺陷。
2. **修 P1-1**：`aimili_cli.py:153-155` 改为先解码 fragment 再匹配。**这是用户每次安装结束时第一眼看到的东西**，当前是一张空卡片。
3. **修 P1-14**：让 CDN 节点可被发现——在 NODES_JSON 写入 `cdn_domain`，或在 `cdn.<domain>` 不可解析时打印明确警告。当前是一整个宣传特性静默消失。
4. **修 P0-3**：两处 `re.sub` 改用 lambda 替换（3 行改动，消除 root 权限下损坏 nginx 配置的可能）。
5. **删 P1-13**：移除 `code_gate.py:378` 的本机路径，恢复 `os.access(..., os.X_OK)`。
6. **修 P2-3 / P2-4**：两处 `chmod 600`（TLS 私钥、cloudflared unit 文件）。凭据世界可读不可接受。

### 8.2 一周内（消除系统性风险）

7. **建立端口单一事实来源**（解 P1-2）
   新建 `scripts/ports.conf`，内容即 `install.sh:16-17` 的两行；`install.sh`、`setup_singbox.sh`（iptables/nft/ufw/firewalld 四套逻辑）、`setup_https.sh`、`check_health.sh`（审计循环 + 用户提示文案）**全部改为 source/读取该文件**。目前 7 处独立维护已产生 4 处不一致，这是唯一能根治的办法。

8. **消灭"失败报成功"模式**（解 P1-8、P1-9、P1-10、P1-12、P2-13、`upgrade_script.sh:146`）
   这是本仓库**最系统性的问题**，至少 9 处。建议立一条硬性规约并加入门禁：
   - 禁止 `systemctl restart X || true` 后无条件打印成功 → 必须 `systemctl is-active --quiet X` 复核
   - 禁止函数以 `echo` 结尾表达失败 → 必须显式 `return 1`
   - 禁止 `nginx -t >/dev/null 2>&1 && (...)` 无 else 分支
   - `check_health.sh` 必须依据 `S_*` 变量 `exit` 非零
   > 该模式的危害在于：它把**所有诊断信号都变成常量**。当 `check_health.sh` 恒返回 0、门禁恒绿灯、每个安装步骤恒报成功时，运维者失去了全部可观测性——这正是 P0-1 能潜伏至今的原因。

9. **启用 shellcheck**（解 P2-20）
   CI 已经安装它了，只差一行：
   ```yaml
   - run: shellcheck -S warning -e SC1091 scripts/*.sh install.sh
   ```
   预计能一次性覆盖本报告 8 个以上缺陷类别，且能防住未来同类回归。

10. **把服务端配置纳入内核校验**（解 §5.2）
    在 `code_gate.py` 的 `check_singbox_binary_validation()` 中增加：用固定 dummy 变量渲染 `setup_singbox.sh:247-442` 的配置模板，然后 `sing-box check`。这是唯一能提前发现 P1-3 类降级问题的手段。

11. **供应链加固**（解 P0-2、P2-21）
    sing-box 与 acme.sh 的第三方镜像下载，改为"官方源取摘要 → 镜像取载荷 → 比对摘要"；或维护钉死版本的摘要表。移除 `curl | sh`。

### 8.3 中期（架构层面）

12. **订阅入口加鉴权**（解 P2-1）
    18443 的 `sub.txt` / `clash.yaml` / `singbox.json` 目前对全网开放，含全部 UUID 与 hy2 混淆密码。建议复用面板已有的 `secret_path` 机制，把订阅挂在 `https://host:18443/<secret_path>/sub.txt`。

13. **`generate_subs.py` 的节点生成改为数据驱动**
    当前 700+ 行里，每种协议 × 每种出站 × 每个地址族都是**手写的重复代码块**（IPv4 直连、IPv4 住宅、IPv6 直连、CDN 各写一遍），这正是 IPv6 组曾整块死亡无人察觉、P2-9（IPv6 vmess host 字段错配）、`node_names["vless_cdn_v4"]` 键名指向 "VMess-WS-TLS" 标签这类问题的温床。改为"协议 × 出站 × 地址族"三重循环 + 单一模板函数，代码量可减半且不可能再漏掉某一族。

14. **`deploy/aimilivpn-production.conf` 已与在用的那份漂移（已证实，非推测）**
    全仓库只有两处安装 nginx 配置，且都只认 `scripts/nginx/`：
    ```bash
    $ grep -rn "aimilivpn-production.conf" --include=*.sh | grep install
    scripts/setup_https.sh:181:    install -m 0644 "$ROOT_DIR/scripts/nginx/aimilivpn-production.conf" "$NGINX_CONF"
    scripts/setup_singbox.sh:622:  install -m 0644 "$ROOT_DIR/scripts/nginx/aimilivpn-production.conf" "$NGINX_CONF_DEST"
    ```
    `deploy/aimilivpn-production.conf` **零引用**（无任何 `.sh` / `.py` / CI 引用它），是一份纯死文件。`a46da64` 只给 `scripts/nginx/` 那份加了 IPv6 监听，于是两份现在实测不一致：
    ```bash
    $ diff -q deploy/aimilivpn-production.conf scripts/nginx/aimilivpn-production.conf
    Files deploy/aimilivpn-production.conf and scripts/nginx/aimilivpn-production.conf differ

    $ diff -u deploy/aimilivpn-production.conf scripts/nginx/aimilivpn-production.conf
    @@ -1,5 +1,6 @@
     server {
         listen 8443 ssl;
    +    listen [::]:8443 ssl;
    @@ -47,6 +48,7 @@
     server {
         listen 18443 ssl;
    +    listen [::]:18443 ssl;
    ```
    危害不是"多一个文件"，而是**误导后续维护者**：`2026-10-22` 那份旧审查报告正是读了 `deploy/` 副本，得出了"无 18443 细分 location、有 timeout 参数"的结论——而那是过期内容，与线上实际生效的配置无关。建议直接删除 `deploy/aimilivpn-production.conf`；若确有打包分发需求，改为构建时从 `scripts/nginx/` 复制生成，禁止手写第二份。

15. **`vpngate_manager.py:11-31` 的 `_sync_core_if_needed()` 只同步 `vpngate_manager<EXT_SUFFIX>`**
    不同步 `aimili_ml`、`proxy_server` 等其他 `.so` → `git pull` 后模块间版本错配。且 `except Exception: pass` 会掩盖 Linux 上的 `ETXTBSY`（文件正在执行时无法覆盖）——这是真实会发生且需要重试的情况。

16. **`manage_cert.sh` 与 `setup_https.sh` 的证书状态机需要重写**
    P0-1、P1-4、P1-9、P2-18 四项都源于同一处设计问题：证书来源（acme.sh / certbot / 自签 / 领养既有）与部署目标（`/etc/aimilivpn/tls` → `/etc/sing-box`）之间没有单一状态机，每个脚本各自用局部标志位（`ACME_ISSUED`、`ACME_AVAILABLE`、`ENABLE_IP_ACME`）猜测当前状态，而这些标志位互相不可见且部分是死变量。建议抽出 `cert_state.json` 作为单一事实来源。

---

## 9. 值得肯定的实现

审查中发现多处质量明显高于平均水平的代码，应在后续重构中作为范式保留：

- **`install.sh:26-65` `aimili_fw_open()`**：`iptables -C` 幂等检查后再 `-I`，把添加的规则记录到 `/etc/aimilivpn-fw.added` 供卸载时精确回收。`a46da64` 还正确补上了 firewalld 的范围语法转换（`40000:50000` → `40000-50000`）。这是本仓库**唯一**做对了幂等防火墙的地方（对比 P2-11 的 nft 分支）。
- **`install.sh:68-98` `aimili_apt_update()`**：正确使用 `|| rc=$?` 与 `${PIPESTATUS[0]}` 处理管道退出码，而非依赖被 `pipefail` 掩盖的末段状态。
- **`install.sh:281-443` `aimili_uninstall()`**：带完整的卸载后验证清单，逐项确认残留。
- **`install.sh:658-669` `aimili_public_ips()`**：IPv4/IPv6 分开循环、`curl -4 -fsS --max-time 6`、curl/wget/ip-addr 三级回退。**这是正确的公网 IP 探测实现**——可惜 P1-7 的 `:1314` 没有复用它。
- **`setup_singbox.sh:624-633`**：用 `sys.argv` 传参给内联 Python（而非字符串插值）+ 限定作用域 `re.sub`，是正确的做法（只差 P0-3 的 lambda 替换）。
- **`setup_singbox.sh:207-240` GOMEMLIMIT 动态配额**：按物理内存分档（256M→64MiB / 512M→160MiB / 1G→380MiB / 其余 40%），对低配 VPS 的 OOM 防护是实打实有效的工程细节。
- **`setup_singbox.sh:447-457` 配置清洗**：先移除空 `username`/`password` 再校验，避免了 SOCKS 无认证场景的常见坑。
- **`setup_warp.sh:83-95`（`a46da64` 新）**：密钥生成失败时 `sys.exit(1)` 而非降级成无效值——这正是本报告反复呼吁的"失败就要失败"的正确范式。
- **`generate_subs.py:364/395/406`**：对 `clash_cdn_names` 为空做了 `if` 守卫，CDN 节点缺失时 Clash 配置不会崩溃。
- **`setup_cron.sh:41-51` crontab 生成**：正确设置 `PATH` 与 `SHELL`、全部使用绝对路径（仅缺 P2-17 的 `flock`）。

---

## 10. 缺陷汇总表

| 级别 | 数量 | 编号 |
|---|---|---|
| **P0** | 3 | P0-1 证书续期死代码 / P0-2 供应链 root 二进制 / P0-3 re.sub 替换串注入（2 处实例） |
| **P1** | 14 | P1-1 CLI 节点分组恒空 / P1-2 端口矩阵矛盾 / P1-3 降级后配置不一致 / P1-4 sed 全局污染+注入 / P1-5 无保护关键步骤 / P1-6 非 CSPRNG 凭据 / P1-7 curl 缺 -f/-4 / P1-8 WARP 假成功+备份冲突 / P1-9 certbot 续期不部署 / P1-10 IP 漂移顺序颠倒 / P1-11 无条件 reset --hard / P1-12 健康检查恒 0 + 非法 curl / **P1-13 门禁硬编码本机路径（新引入）** / **P1-14 CDN 节点静默消失（新引入）** |
| **P2** | 25 | P2-1 … P2-25（见 §4 表格） |
| **UNVERIFIED** | 6 | 见 §7，需 sing-box 1.14 真机确认 |
| **审查期间已被并行修复** | 13 | 见 §6.1 |

**门禁状态**：`[√] 质量门禁全绿通过！`
**实际状态**：3 个 P0 + 14 个 P1 在门禁之外。

---

*本报告由 Qoder Agent 以敌对审查者模式生成，遵循 `AGENTS.md` 红蓝军对抗式审计协议。全部结论均附 `文件:行号` 与可复现证据；未标注为 UNVERIFIED 的项均已通过代码核验或实际执行验证。行号基线为 `a46da64`。本次审查未修改任何源代码。*
