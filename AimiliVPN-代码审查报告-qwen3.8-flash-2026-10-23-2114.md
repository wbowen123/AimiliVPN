# AimiliVPN 代码审查报告

- 审查模型：`qwen3.8-flash`（monkeycode-basic）
- 审查时间：2026-10-23 21:14
- 审查对象：仓库 `HEAD` `9d5b5c2`（`main`，工作区干净）
- 版本号：`V1.4.8`
- 审查性质：**只读分析，未修改任何代码**
- 对照基线：`AimiliVPN-代码审查报告-MiniMax-M3.1-2026-10-23.md` 所列缺陷，以及当前提交宣称的「P0/P1/P2 全修 + Code Gate V2.0」

---

## 1. 怎么审的

本次只做静态阅读 + 本地可复现实验，不改仓库、不部署到 VPS。

| 动作 | 结果 | 证据级别 |
|---|---|---|
| `python scripts/code_gate.py` | 全绿；仅 `[INFO-SB-BIN]`（本机无 sing-box 二进制） | 实测 |
| 对照 MiniMax 报告逐条回看当前源码 | 原 P0 五项均已落地 | 静态对照 |
| 用临时脚本调用 `generate_subscriptions()` 四组输入 | 确认 CDN 无条件注入、IPv6 不进 `singbox.json`、`direct.` 不会改写成 `cdn.` | 实测 |
| 阅读 `setup_warp.sh` / `setup_singbox.sh` / nginx / CLI | 发现分流顺序、WARP reserved、防火墙缺口 | 静态；标为未上机 |

未做：真机 `sing-box check`、WARP 握手、Cloudflare 橙云回源、Hy2 端口跳跃、Telegram Bot 联调。

---

## 2. 总评

这是一套 **Linux 一键部署的 Sing-box 多协议 VPN 脚本套件**（安装器 + 住宅网桥 + 订阅生成 + 面板），不是传统单体应用。

MiniMax 报告里的崩溃级问题（CLI 吞掉 `SystemExit`、nginx 正则 `proxy_pass`、WARP 扁平 WireGuard、CDN 节点仍发 VLESS、客户端 `geosite`/`dns-out`、cron 只改 txt）**当前源码里已经对上了**。本地 Code Gate V2.0 也全绿。

但「门禁全绿」不等于「线上节点都能用」。门禁主要抓的是 **已知旧伤的字符串指纹** 和 **语法/拓扑清单**，对订阅矩阵语义、WARP 分流顺序、IPv6 数据链路几乎没有覆盖。下面列出的是 **修完 MiniMax 之后仍然存在、且会影响真实用户** 的问题。

一句话：内核配置从「会直接起不来」变成了「能起来，但订阅和分流有几处会静默给用户死节点」。

---

## 3. MiniMax 旧伤复核（避免把已修问题再报一遍）

| 原编号 | 原结论 | 当前状态 |
|---|---|---|
| P0-1 CLI `SystemExit` | 已修：非 0 会再抛出 | 已关闭 |
| P0-2 nginx 正则 `proxy_pass` 带 URI | 已改为前缀 `location /vmess`、`/vmess-ws` | 已关闭 |
| P0-3 WARP 仍写 1.14 禁止的扁平 `type:wireguard` | 已改为 `endpoints` + `peers` | 结构已修；见下文残留 |
| P0-4 `SCRIPT_DIR` 未定义 | `setup_argo.sh` 已定义 | 已关闭 |
| P0-5 CDN 节点协议仍是 VLESS | 已改为 VMess-xHTTP / VMess-WS | 协议已对齐；域名逻辑仍错 |
| P1-1/P1-2 客户端 `geosite` + `dns-out` | 已删 | 已关闭；但没补 rule-set，见 P1-4 |
| P1-3 `sniff` 放 inbound | 已改为 route 第一条 `action:sniff` | 基线配置已修；WARP 注入会打乱顺序 |
| P1-5 cron 只改 txt | 已同步改 `singbox_nodes.json` 并重生订阅 | 已关闭 |
| P1-6 TUIC `tls=false` | 已按有无域名决定 | 已关闭 |
| P1-7/P1-8 防火墙 8500、`set -e` + `PIPESTATUS` | 已按当前源码关闭 | 已关闭 |
| P2-1 CDN 域名推导 | **未真正修好**，见 P1-1 | 仍开 |
| P2-2 `${BOLD}` | `install.sh` 已定义 | 已关闭 |
| P2-3 硬编码 `EJsW2EeBo9lY` | 已改为随机 | 已关闭 |
| P2-6 `manage_cert.sh` 全局 sed | 已改为只改 8443 块 | 已关闭；`setup_singbox.sh` 仍有同类写法 |

---

## 4. 残留与新发现缺陷

严重级别约定：

- **P0**：部署后核心服务起不来，或把生产配置写坏且无法回滚
- **P1**：用户拿到的节点/分流在常见路径上不可用，或双栈承诺落空
- **P2**：功能降级、安全默认值偏弱、文档与实现不一致
- **P3**：体验与可维护性

### P1-1 CDN 节点无条件生成，且 `direct.` / 裸域名永远推不出 `cdn.`

**位置**：`scripts/generate_subs.py:38-65`、`:298-325`、`:579-591`

**发生了什么**：只要 `cdn_host` 有值就生成两条（IPv6 时三条）「小黄云」节点。而 `cdn_host` 一开始就被赋成 `domain or public_ip`，后面 `if not cdn_host` **永远进不去**。

**实测（2026-10-23，本机调用 `generate_subscriptions()`）**：

| 输入 | CDN 节点 server | CDN SNI / Host |
|---|---|---|
| 无域名，仅 `203.0.113.10` | `104.16.160.10:8443` | `203.0.113.10`（IP 当 SNI） |
| `domain=example.com` | 同上 | `example.com`（与直连共用 apex） |
| `domain=direct.example.com` | 同上 | **仍是 `direct.example.com`，没有变成 `cdn.example.com`** |
| 显式 `cdn_domain=cdn.example.com` | 同上 | `cdn.example.com`（这条路径才对） |

无 Cloudflare 橙云、证书也不匹配时，用户订阅里会固定出现 2～3 个 **注定握手失败** 的 CDN 节点，还被放进 `⛅ CDN破墙 (自动优选)` urltest，拖垮自动选路。

README / `cf_speedtest.sh` 写的「直连灰云 + CDN 橙云」双域名模型，默认安装路径走不通。`setup_singbox.sh` 写出的 `singbox_nodes.json` 也不含 `cdn_domain`。

**建议**：没有显式 CDN 域名就不要出 CDN 节点；`direct.` 前缀时无条件推导 `cdn.`；裸域名仅在 DNS 真能解析到 `cdn.` 时才启用。

---

### P1-2 双栈承诺落空：IPv6 节点在生产路径上基本不会出现，即便出现也不进 `singbox.json`

**位置**：

- 生产写入：`scripts/setup_singbox.sh:571-591`（`singbox_nodes.json` **没有** `public_ipv6`）
- 读取：`scripts/generate_subs.py:20-28`（只认 json 字段或 `/opt/aimilivpn/vpngate_data/public_ipv6.txt`）
- 全仓库无任何脚本写入 `public_ipv6.txt`（已 grep）
- `install.sh:1316-1317` 会探测 IPv6，但只用来打印面板 URL

**实测**：手工塞入 `public_ipv6=2001:db8::1` 后：

- `nodes.txt` / `clash.yaml`：17 条（含 4 条 IPv6 直连 + 1 条 IPv6 CDN）
- `singbox.json` 出站：**仍是 12 条，全部 IPv4，`has_ipv6_sb=False`**

也就是：即使用户自己补了 IPv6 字段，Sing-box 原生客户端订阅仍然缺 IPv6。Clash / 通用订阅和 Sing-box 订阅矩阵不一致。

**建议**：`setup_singbox.sh` 写入 `public_ipv6`；`generate_subs.py` 把 IPv6 出站同样追加进 `sb_outbounds_list`。

---

### P1-3 WARP 智能分流把 `sniff` 挤到域名规则后面

**位置**：`scripts/setup_warp.sh:287-291`

基线 `setup_singbox.sh` 已经把 `{"action":"sniff"}` 放在 route 第一条，这是对的。但 `apply_warp_to_singbox()` 重建规则时顺序变成：

1. `ip_is_private → direct`
2. `residential-user → resi-out`
3. **WARP 的 `domain_suffix` 规则（需要已嗅探到域名）**
4. 被清洗后残留的规则（**`sniff` 在这里**）
5. `direct-user → direct-out`

`ai` / `stream` / `custom:` 模式全靠 `domain_suffix`。sniff 还没跑，域名匹配不到，流量会掉进默认 `direct-out`，表现为「开了 WARP 分流，ChatGPT/Netflix 仍走机房 IP」。

`global` 模式用的是 `network: [tcp,udp]`，不依赖 sniff，这条相对能工作。

**未上机验证 WARP 握手**；规则顺序从源码即可判定。

**建议**：重建时把 `sniff`（以及 `protocol:dns / hijack-dns`）固定插回最前，再挂 WARP 规则。

---

### P1-4 WARP 账号缺 `reserved` / `client_id`，失败时公钥等于私钥

**位置**：`scripts/setup_warp.sh:85-89`、`:119-128`、`:210`

1. Cloudflare WARP 注册接口会返回 `config.client_id`，需要解码成 WireGuard `reserved` 三字节。当前写死 `"reserved": [0, 0, 0]`，且账号 json 根本没存 `client_id`。这是 WARP 握手失败的常见原因。
2. openssl 生成公钥失败时：`pub_key = priv_key`。x25519 公私钥不能相同；随后注册必失败，走 fallback 假账号，对端不认识这把私钥。
3. 成功路径用的是 `endpoint.host`（多为 `engage.cloudflareclient.com:2408`），服务端配置没有 DNS 段。能否解析依赖内核默认行为，属于隐患。
4. `command -v sing-box` 找不到时（二进制实际在 `/usr/local/bin/sing-box` 但 PATH 不含）：**直接删 `.bak`，不 check、不 restart**（`:321-323`）。配置已写盘，回滚件没了。

**建议**：持久化并写入 `reserved`；openssl 失败就中止而不是用私钥冒充公钥；check 时显式调用 `/usr/local/bin/sing-box`；PATH 缺失时保留备份。

---

### P1-5 客户端 `singbox.json` 去掉 geosite 后没有国内直连，DoH 指向 `8.8.8.8`

**位置**：`scripts/generate_subs.py:648-673`

MiniMax 要求删掉 1.14 已废弃的 `geosite` / `dns-out`，当前确实删了。Clash 配置仍保留 `GEOIP,CN,DIRECT`，但 Sing-box 客户端只剩：

- DNS：`https` 到 `8.8.8.8`，`detour` 指向手动选择器
- 路由：dns hijack、私网直连、clash Direct，**没有 CN 直连，也没有 `default_domain_resolver`**

后果：

1. 用 `singbox.json` 的用户，国内站点也全部进代理，和 Clash 行为不一致。
2. Google DoH 证书 CN 是 `dns.google`，把 `server` 写成 `8.8.8.8` 且不设 `server_name`，TLS 校验很容易失败，表现为 DNS 全挂。[逻辑推断，未跑 sing-box]

**建议**：改用 1.14 的 `rule_set`（`geoip-cn` / `geosite-cn`）或至少补 `ip_is_cn` 替代方案；DoH 用 `dns.google` 或给 `8.8.8.8` 配 `tls.server_name`。

---

### P1-6 AnyTLS `padding_scheme` 类型很可能非法，校验失败会被静默删掉

**位置**：`scripts/setup_singbox.sh:349`、`:449-462`

```json
"padding_scheme": "random"
```

Sing-box AnyTLS 该字段类型是 **字符串数组**（官方默认方案表），不是 `"random"` 这个标量。`sing-box check` 一旦失败，脚本会：

1. 删掉整个 `anytls` inbound
2. 再去掉 Hy2 的 `obfs`
3. 再 check 一次；通过就把残缺配置提交

用户看到订阅里仍有 AnyTLS 节点，服务器 8444 却没人听。本机无 sing-box，**此项未做内核实测**，但类型与自愈逻辑从源码可直接读出。

**建议**：改成官方数组方案，或干脆省略该字段用默认值；降级时必须同步改订阅，不能只改服务端。

---

### P2-1 `setup_singbox.sh` 仍全局替换 nginx `server_name _`

**位置**：`scripts/setup_singbox.sh:611-614`

`manage_cert.sh` 已改为只改 8443 块，但每次部署 Sing-box 仍：

```bash
sed -i "s/server_name _;/server_name ${DOMAIN};/g"
```

80 端口伪装站 / ACME `server_name _;` 会被一起改掉。有域名时，未匹配该域名的 HTTP-01 或默认伪装可能失效。

---

### P2-2 Hy2 端口跳跃防火墙口径不一致

- `install.sh:15` 注释写了 UDP `40000:50000`，但 `AIMILI_FW_UDP_PORTS` 默认只有 `443 8443`
- `setup_singbox.sh` 的 iptables/ufw 会放行跳跃段；`firewall-cmd` 的 TCP 列表漏了 **8446**
- 跳跃只做了 **IPv4** `iptables -t nat REDIRECT`，没有 `ip6tables`；同时可能再写一条 nft 规则，nft/iptables-nft 混用时有双重 NAT 风险
- 云安全组（甲骨文等）不会被脚本打开 40000-50000，跳跃在这类机器上默认无效

---

### P2-3 nginx 8443 / 18443 只听 IPv4

`scripts/nginx/aimilivpn-production.conf`：80 有 `listen [::]:80`，8443/18443 只有 `listen 8443 ssl`。纯 IPv6 客户端打不开面板和订阅，CDN 回源若走 IPv6 也会 miss。

---

### P2-4 Clash 订阅故意不含 AnyTLS，Mihomo 实际已支持

`clash.yaml` 实测 10 个 IPv4 代理（缺 2 条 AnyTLS），`nodes.txt` 有 12 条。README 写明 Clash 不含 AnyTLS。对旧 Clash 合理，对现在的 Mihomo 是功能缺口。自动选路组因此少了两条 TCP 抗 QoS 节点。

---

### P2-5 默认凭据与面板安全

- 内置 SOCKS5 默认密码仍是 `ilovestudy`（`install.sh` / `setup_singbox.sh`）
- 管理面板依赖 `secret_path` + 口令，但 8443 的 `/` 反代到 8501，路径爆破面仍在
- `vpngate_manager.py` 是 `.so` 闭源核心，本次无法审计鉴权、会话、SSRF

安装结束会提示改密码，默认值本身偏弱。

---

### P2-6 Argo 节点名与真实传输不一致

Argo 隧道指向 `http://127.0.0.1:8445`（VMess **HTTP/xHTTP**），订阅里节点名却是 `VMess-WS-Argo`，客户端配置用的是 `transport.type=http`。功能上可能通，名称会误导排障。

---

### P2-7 Telegram Bot 仍无独立 systemd 单元

`install.sh` 卸载时会扫 `aimilivpn-tgbot.service`，仓库里仍没有对应 unit。Bot 进程模型与文档/卸载脚本不对齐。

---

### P2-8 更新检测仍有误报空间

`vpngate_manager.py` 已改为打 GitHub API，不再写死 `has_update: False`。但比较的是 **8 位短 SHA**，shallow clone、fork、以及 `latest_version` 仍拼当前 `VERSION_TAG` 而不是远端 tag，面板会把「同版本不同 commit」或「超前本地」显示乱。

---

### P3-1 门禁是「旧伤指纹机」，不是语义机

`scripts/code_gate.py` 能抓住 MiniMax 那批字符串，抓不住本次 P1-1～P1-6。例如：

- 客户端 mock 节点 **不含 IPv6、不含 CDN 域名**，所以测不出 IPv6 丢失和 CDN 误注入
- 不解析 `generate_subs.py` 的 `if not cdn_host` 死代码
- 不检查 WARP 规则数组顺序
- 本机无 sing-box 时直接跳过内核 check（本次即如此）

CI 装了 sing-box 1.14.3，能测客户端 json 能否 `check`，仍然测不到「CDN 节点该不该出现」。

---

### P3-2 其它边角

- 自定义 YAML 序列化器对嵌套结构可用，但无 PyYAML 时对 `None`、多行字符串、锚点不完整；缺依赖环境生成的 `clash.yaml` 有风险
- `GOMEMLIMIT` 在 ≤256MB 机器上设为 `64MiB`，再叠加 6 个 inbound + WARP endpoint，有 OOM 风险
- `aimili_cli.py` 住宅模式菜单写 `[0-2]`，需人工核对选项编号是否与分支一致
- 仓库仍有多份历史审查报告，门禁/文档没有「以哪份为准」的索引

---

## 5. 优化建议（按收益排序）

1. **订阅生成做成「有证据才出节点」**  
   CDN、IPv6、Argo、AnyTLS 都根据真实配置开关输出。死节点不要进 urltest。三种订阅格式（txt / clash / singbox）节点集合必须对齐。

2. **把双域名写成强制向导，而不是注释**  
   安装时分别收集 `direct.`（灰云）和 `cdn.`（橙云）；证书 SAN 覆盖两者；nginx `server_name` 按端口拆开。不要用 apex 同时扛 Reality 和橙云。

3. **WARP 做成可验证模块**  
   注册成功必须有 `reserved`；应用后用一次 `curl --interface` 或 sing-box 出站探测 `openai.com` / `netflix.com`，失败则自动回滚并告诉用户「分流未生效」。

4. **客户端路由跟上 1.14**  
   `rule_set` 远程 geoip/geosite、`default_domain_resolver`、DoH 用域名。Clash 与 Sing-box 的国内直连策略保持一致。

5. **自愈降级必须双向**  
   服务端删 AnyTLS / 去 obfs 时，同步改 `singbox_nodes.json` 再生成订阅，避免「订阅有、端口没人听」。

6. **门禁补 4 条语义断言**（不必上 VPS）  
   - 无 `cdn_domain` 时 `singbox.json` 不得出现 `104.16.160.10`  
   - `domain=direct.example.com` 时 CDN SNI 必须是 `cdn.example.com`  
   - 给了 `public_ipv6` 则 `singbox.json` 必须有 IPv6 出站  
   - 注入 WARP 后 `action=sniff` 必须位于任意 `domain_suffix` 规则之前  

   这 4 条就能锁死本次 P1-1/P1-2/P1-3。

7. **IPv6 补齐**  
   探测、落盘、nginx `listen [::]:8443 ssl`、Hy2 跳跃的 ip6tables、订阅出站，四件事一起做；只做探测没有意义。

8. **安全默认值**  
   首次安装强制改 SOCKS 密码；8443 反代不要把 8501 裸露在 `/`；证书私钥权限保持 `600`（当前逻辑基本如此，需避免后续 `chmod 644` 误伤 key）。

9. **文档与菜单减负**  
   安装 8 套餐、CLI 22 项、Argo/CDN/WARP/证书多条入口，失败时用户不知道该跑哪条。建议 `ml doctor` 一条命令输出：证书、端口、sniff 顺序、CDN 域名是否橙云、WARP reserved、订阅节点死活。

---

## 6. 拓扑备忘（当前设计，不是新 bug）

```
客户端
  ├─ VLESS Reality TCP 443     → sing-box vless-in → direct-out / resi-out / warp-out
  ├─ Hy2 UDP 443 (+ hop 40000-50000 REDIRECT) → hy2-in
  ├─ TUIC UDP 8443             → tuic-in          （与 nginx TCP 8443 同端口不同协议，可共存）
  ├─ AnyTLS TCP 8444           → anytls-in
  ├─ VMess-xHTTP TCP 8445      → vmess-in（明文 HTTP，靠 VMess AEAD）
  └─ CDN/面板 TCP 8443         → nginx
        ├─ /vmess    → 127.0.0.1:8445
        ├─ /vmess-ws → 127.0.0.1:8446
        └─ /         → 127.0.0.1:8501 面板
订阅 TCP 18443 → nginx 静态文件
Argo → http://127.0.0.1:8445
```

8443 TCP(nginx) + 8443 UDP(TUIC) 同端口双栈协议是合法的。风险在 **CDN 客户端 SNI/Host 与橙云域名是否一致**，不在端口冲突本身。

---

## 7. 建议修复顺序（本次不改代码，仅排序）

| 批次 | 项 | 理由 |
|---|---|---|
| 第一批 | P1-1 CDN 误注入与域名推导 | 每个订阅用户都能立刻看到死节点 |
| 第一批 | P1-3 WARP sniff 顺序 | 「智能解锁」主卖点会失效 |
| 第一批 | P1-2 IPv6 写入 + singbox.json 对齐 | 双栈是 v1.4.8 宣传点 |
| 第二批 | P1-4 WARP reserved / 公钥 fallback / PATH | 否则 WARP 整模块不可信 |
| 第二批 | P1-5 客户端 DNS/CN 直连 | 修完 geosite 后的功能空洞 |
| 第二批 | P1-6 AnyTLS padding 类型 | 避免静默砍协议 |
| 第三批 | P2 防火墙、nginx IPv6、server_name、门禁语义断言 | 巩固，防止回归 |

---

## 8. 结论

当前 `9d5b5c2` 已经把 MiniMax 报告里的 **启动即崩 / 配置直接非法** 一类问题收干净，Code Gate V2.0 对那批指纹有效。

仍然值得优先处理的是 **订阅语义** 和 **WARP 分流顺序**：CDN 节点会无条件进订阅且推不出 `cdn.` 主机名；IPv6 在生产写入链上是断的，即便手工补也不进 `singbox.json`；WARP 域名分流把 sniff 放错位置。这三件都不需要上 VPS 就能在生成器/规则数组上复现。

本报告只记录问题与建议，**未修改任何代码**。
