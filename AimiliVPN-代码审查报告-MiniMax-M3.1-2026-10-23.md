# AimiliVPN 代码审查报告（MiniMax-M3.1 独立复核）

| 项目 | 内容 |
|---|---|
| **审查模型** | MiniMax-M3.1 |
| **审查时间** | 2026-10-23 20:07 ~ 20:20 (UTC+8) |
| **审查对象** | `I:/Aimili VPN` @ commit `f469c12`（分支工作区干净） |
| **项目版本** | V1.4.8 |
| **上一版报告** | `AimiliVPN-代码审查报告-2026-10-22.md`（V1.4.7 时代） |
| **审查性质** | 纯静态+动态审查，**未修改任何源码** |
| **审查基线** | 项目 `AGENTS.md` 红队规则（Guilty Until Proven Innocent / Tool-First Verification） |

---

## 摘要

本轮由 MiniMax-M3.1 模型基于 **V1.4.8 当前代码**独立复核，不沿用上一版结论。结论如下：

- 上一版报告的 **3 个 P0 已全部修复**，属实。
- 但发现 **4 个新的 P0**，其中 **P0-1 / P0-2 属于"配置生成即失败"级别** —— 服务端与客户端配置在目标 sing-box 版本上**根本无法启动**，属于"装完即废"的致命缺陷。
- 另发现 **9 个 P1、14 个 P2、8 个 P3**。
- **项目自带质量门禁 `scripts/code_gate.py` 实测输出"全绿通过"，但本报告所有 P0/P1 缺陷均未被其捕获** —— 门禁存在严重的结构性漏报。

> ⚠️ **给非技术读者的一句话总结**：这个项目"看起来功能齐全、菜单漂亮、文档齐全"，但**服务器端的核心配置在当前默认安装的 sing-box 版本上会被内核直接拒绝**，装完之后节点全废；客户端生成的订阅配置同样无法被 sing-box 客户端加载；此外还有 4 个"小黄云 CDN"节点协议写错、连上去必然失败。**当前版本不具备可交付生产使用的条件。**

---

## 一、缺陷总览

| 级别 | 数量 | 定义 |
|---|---|---|
| **P0** | 4 | 阻断性：功能完全不可用 / 配置无法加载 / 静默失效且伴随虚假成功提示 |
| **P1** | 9 | 严重：功能降级、状态不一致、静默错误 |
| **P2** | 14 | 中等：安全弱化、可用性缺陷、文档与实现不符 |
| **P3** | 8 | 轻微：代码规范、样式、日志文案 |

### 缺陷速查表

| 编号 | 级别 | 文件:行 | 问题 |
|---|---|---|---|
| P0-1 | P0 | `scripts/setup_singbox.sh:254-255` | 服务端 `sniff` 字段在 sing-box ≥1.13 **已被移除**，配置硬失败 |
| P0-2 | P0 | `scripts/setup_warp.sh:198-207` | WARP outbound 使用 1.12 的 legacy 字段，1.14 已不兼容 |
| P0-3 | P0 | `scripts/generate_subs.py:309,314,579` | VLESS-WS 节点协议错配（客户端 VLESS ↔ 服务端 VMess） |
| P0-4 | P0 | `scripts/setup_argo.sh:249-250` | `$SCRIPT_DIR` 未定义 → Argo 订阅刷新静默失效 + 虚假成功日志 |
| P1-1 | P1 | `scripts/generate_subs.py:636,658` | 客户端 `dns` outbound 在 1.13 已移除，客户端配置无法加载 |
| P1-2 | P1 | `scripts/generate_subs.py:646-647` | 客户端 DNS rule 用 legacy `geosite`/`server` 字段 |
| P1-3 | P1 | `scripts/generate_subs.py:660-661` | 客户端 route rule 用 legacy `geoip`/`geosite` |
| P1-4 | P1 | `install.sh:15`、`setup_singbox.sh:624` | 8446 端口全链路未放行 |
| P1-5 | P1 | `scripts/setup_cron.sh:138-152` | IP 漂移只改 txt 不改 json → 订阅 IP 不更新 + 虚假告警 |
| P1-6 | P1 | `scripts/setup_warp.sh:244-253` | `custom:` 模式把 geosite 名当 `domain_suffix` 用 |
| P1-7 | P1 | `scripts/tg_bot.sh` / `install.sh:292,361` | TG Bot 常驻 systemd unit 从未创建 |
| P1-8 | P1 | `install.sh:67-97` | `aimili_apt_update` 的 `set -e` 与 `rc=$?` 冲突 |
| P1-9 | P1 | `scripts/generate_subs.py:275` | Argo 域名覆盖 CDN 域名，CDN 节点 Host/SNI 错位 |
| P2-1 | P2 | `scripts/generate_subs.py:40-58` | CDN 主机名靠推导，无校验无引导 |
| P2-2 | P2 | `install.sh`（多处） | `${BOLD}` 变量从未定义 |
| P2-3 | P2 | `install.sh:1296,1303` | 面板路径后缀硬编码 `EJsW2EeBo9lY` |
| P2-4 | P2 | `install.sh:868,912,1343` + `setup_https.sh:245` | 默认密码 `ilovestudy` + 8500 端口公网放行 |
| P2-5 | P2 | `scripts/setup_https.sh:189` | `nginx -t` 失败即中断安装 |
| P2-6 | P2 | `scripts/manage_cert.sh:361` | `sed` 全局替换误改 80 端口伪装站 `server_name` |
| P2-7 | P2 | `scripts/manage_cert.sh:51-292` | `$HOME` 在 `set -u` 下未设即退出 |
| P2-8 | P2 | `scripts/setup_cron.sh:79` | `drop_caches` 反模式 |
| P2-9 | P2 | `scripts/tg_bot.sh:216` | 告警发送失败被吞 |
| P2-10 | P2 | `scripts/tg_bot.sh:180-183` | HTML 用 `\\n` 字面量，非真换行 |
| P2-11 | P2 | `vpngate_manager.py:157-158` | 面板更新检测硬编码 `has_update: False` |
| P2-12 | P2 | `README.md:8` vs 实测 | 宣称 18 节点，clash.yaml 实际 16 proxies、anytls 缺失 |
| P2-13 | P2 | `scripts/code_gate.py` | 门禁作用域/覆盖度缺陷（详见第五节） |
| P2-14 | P2 | `.github/workflows/ci.yml` | CI 缺 shellcheck / pyflakes / sing-box 校验 |
| P3-1 | P3 | `aimili_cli.py`（10 处） | f-string 无占位符 |
| P3-2 | P3 | `scripts/setup_argo.sh:174,197-198,331-332` | `$C_CYAN` 未定义 |
| P3-3 | P3 | `scripts/setup_https.sh:60-62` | 样式变量未定义（仅样式） |
| P3-4 | P3 | `scripts/setup_singbox.sh:70` | 版本来源双重不确定（`latest` vs `1.14.3`） |
| P3-5 | P3 | `scripts/generate_subs.py:77` | CF 优选 IP 硬编码兜底 |
| P3-6 | P3 | `scripts/generate_subs.py:435-479` | 自研 YAML 序列化与 PyYAML 双路径 |
| P3-7 | P3 | `aimili_cli.py:334-346` | `except SystemExit: pass` 吞子命令退出码 |
| P3-8 | P3 | `aimili_cli.py:181-200` | QR 打印双份回退逻辑 |

---

## 二、P0 缺陷详解（阻断性）

### P0-1　服务端配置 `sniff` 字段已被 sing-box 移除 —— 配置硬失败，服务端起不来

**位置**：`scripts/setup_singbox.sh:254-255`（写入 `vless-in` inbound）

```bash
      "listen_port": 443,
      "sniff": true,
      "sniff_override_destination": false,
```

**证据链（官方源码，sing-box v1.14.3 `option/inbound.go`）**：

```go
func (h *Inbound) UnmarshalJSONContext(ctx context.Context, content []byte) error {
    ...
    if listenWrapper, isListen := options.(ListenOptionsWrapper); isListen {
        if listenWrapper.TakeListenOptions().InboundOptions != (InboundOptions{}) {
            return E.New("legacy inbound fields are deprecated in sing-box 1.11.0 and removed in sing-box 1.13.0, checkout migration: ...")
        }
    }
```

且 `option/inbound.go` 中：

```go
// Deprecated: Use rule action instead
type InboundOptions struct {
    SniffEnabled              bool               `json:"sniff,omitempty" schema:"omit"`
    SniffOverrideDestination  bool               `json:"sniff_override_destination,omitempty" schema:"omit"`
    ...
}
```

**关键点**：`sniff` 字段在 1.13.0 起**不是"弃用警告"，而是直接返回 error 拒绝加载**。而 `sniff: true` 恰好使 `InboundOptions != (InboundOptions{})` 成立 → 命中该分支 → **整个配置文件加载失败**。

**版本关联**：`scripts/setup_singbox.sh:70` 走 `manage_core.sh "${SINGBOX_VERSION:-latest}"`，`:72` 兜底 `1.14.3`。两条路径都 ≥1.13.0。

**影响面**：**整个服务端 sing-box 无法启动**。所有 5 种协议（VLESS-Reality / Hysteria 2 / TUIC / AnyTLS / VMess）全部不可用。这是"装完即废"级别的故障。

**修复方向**：删除 inbound 中的 `sniff` / `sniff_override_destination`，改为在 `route.rules` 中添加
```json
{ "action": "sniff", "sniffer": ["tls","http","quic","dns"] }
```
并显式声明 `route` 的 `default_domain_resolver`（1.12+ 必需）。

---

### P0-2　WARP outbound 使用已废弃字段结构 —— WARP 功能整体不可用

**位置**：`scripts/setup_warp.sh:197-207`

```python
    warp_out = {
        "type": "wireguard",
        "tag": "warp-out",
        "server": server_host,           # ← 1.14 已无此字段
        "server_port": server_port,       # ← 1.14 已无此字段
        "local_address": addrs,          # ← 1.14 改名为 address
        "private_key": warp.get("private_key", ""),
        "peer_public_key": warp.get("peer_pub", "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="),
        "reserved": [0, 0, 0],
        "mtu": 1420
    }
```

**证据链（官方源码对比）**：

sing-box **v1.12.0** `option/wireguard.go` 同时存在两个结构：
```go
type WireGuardEndpointOptions struct { ... }              // 新式
type LegacyWireGuardOutboundOptions struct {               // legacy（项目用的就是这个）
    LocalAddress    badoption.Listable[netip.Prefix] `json:"local_address"`
    PrivateKey      string `json:"private_key"`
    Peers           []LegacyWireGuardPeer `json:"peers,omitempty"`
    ServerOptions                                     // → server / server_port
    PeerPublicKey string `json:"peer_public_key"`
    Reserved      []uint8    `json:"reserved,omitempty"`
    MTU           uint32     `json:"mtu,omitempty"`
}
```

sing-box **v1.14.3** `option/wireguard.go` 中 `LegacyWireGuardOutboundOptions` **已被整个删除**，只剩：
```go
type WireGuardEndpointOptions struct {
    System     bool
    Name       string
    MTU        uint32
    Address    badoption.Listable[netip.Prefix] `json:"address"`
    PrivateKey string `json:"private_key"`
    ListenPort uint16
    Peers      []WireGuardPeer `json:"peers,omitempty"`   // ← peers 数组
    ...
}
type WireGuardPeer struct {
    Address     string  `json:"address,omitempty"`
    Port        uint16  `json:"port,omitempty"`
    PublicKey   string  `json:"public_key,omitempty"`
    AllowedIPs  badoption.Listable[netip.Prefix] `json:"allowed_ips,omitempty"`
    Reserved    []uint8 `json:"reserved,omitempty"`
}
```

**结论**：1.14 的 WireGuard 出站必须写成 `address: [...]` + `peers: [{address, port, public_key, allowed_ips}]` 的嵌套结构，且**必须放在 `endpoints` 数组而非 `outbounds`**。项目写的是 1.12 的 legacy 平铺结构，放在 `outbounds` 数组里。

同时 `option/options.go` 顶层解析开启了严格校验：
```go
decoder.DisallowUnknownFields()
```
→ `server` / `server_port` / `local_address` / `peer_public_key` 会被判为未知字段而报错。

**修正说明（重要）**：官方构建标签文件 `release/DEFAULT_BUILD_TAGS` 确认含 `with_wireguard`：
```
with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,...
```
即**官方发行版二进制是带 WireGuard 的**，本项目下载的官方包不会因"未编译"而失败。**真正的失败原因是字段结构版本不匹配**。（此处纠正了"WireGuard outbound 已被移除"的流行说法——官方文档中"1.13.0 移除"指的是 legacy outbound 形态，WireGuard 本身改以 endpoint 形态保留。）

**影响面**：WARP「自适应流媒体/AI 解锁」为项目主打卖点之一，该功能在默认版本上**必然失败**。

**修复方向**：改写为 1.14 endpoint 形态：
```json
"endpoints": [{
  "type": "wireguard", "tag": "warp-out",
  "address": ["172.16.0.2/32"],
  "private_key": "...",
  "peers": [{ "address": "162.159.192.1", "port": 2408,
              "public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
              "allowed_ips": ["0.0.0.0/0", "::/0"], "reserved": [0,0,0] }],
  "mtu": 1420
}]
```
并把 `route.rules` 里的 `outbound: "warp-out"` 改为 `action: "route"` + 引用 endpoint。

---

### P0-3　VLESS-WS 节点协议错配 —— CDN 节点握手必然失败

**位置**：`scripts/generate_subs.py:309`（sub.txt）、`:311-316`（clash.yaml）、`:576-581`（singbox.json）

```python
vless_cdn_link = f"vless://{direct_uuid}@{clean_ip}:8443?encryption=none&security=tls&sni={active_cdn_host}&type=ws&host={active_cdn_host}&path=%2Fvmess-ws#..."
```

**服务端对应实现**：`scripts/setup_singbox.sh:378-397`

```bash
    {
      "type": "vmess",          # ← 服务端是 VMess
      "tag": "vmess-ws-in",
      "listen_port": 8446,
      "transport": { "type": "ws", "path": "/vmess-ws" }
    }
```

**链路对照**：
```
客户端: vless + ws + path=/vmess-ws  →  Cloudflare:8443  →  Nginx /vmess-ws
                                                              →  127.0.0.1:8446
                                                              →  sing-box vmess-ws-in (VMess 协议)
```
VLESS 客户端发 VLESS 握手包，VMess 服务端等 VMess 握手包 → **协议不匹配，握手必失败**。

**实机验证**（本轮重跑 `generate_subs.py`，产物 `nodes.txt` 第 17 条）：
```
17 VLESS  net=ws path=/vmess-ws add=104.16.160.10:8443 sni=... host=... 
   ps=⛅ [CDN-小黄云·IPv4] VLESS-WS-TLS【Cloudflare-CDN·小黄云破墙】
```
clash.yaml 同源节点：
```
⛅ [CDN-小黄云·IPv4] VLESS-WS-TLS【Cloudflare-CDN·小黄云破墙】 | type= vless | server= 104.16.160.10 : 8443 | net= ws | tls= True
```
singbox.json 同源节点（`:576-581`）同样声明 `"type": "vless"` + `transport.type: ws` + `path: /vmess-ws`。

**影响面**：3 种订阅格式中的「小黄云 VLESS-WS 破墙」节点全部不可用。注意 `nginx/aimilivpn-production.conf:27-28` 的 `/vmess-ws` → 8446 代理本身是通的，**问题纯在协议层**。

**修复方向**：二选一 —— (a) 客户端改为 `"type": "vmess"` + `net: ws`；或 (b) 服务端在 8446 增设真正的 VLESS inbound 并同步更新 nginx 与防火墙。推荐 (a)，改动面最小。

---

### P0-4　`$SCRIPT_DIR` 未定义 —— Argo 订阅刷新静默失效，且打印虚假成功日志

**位置**：`scripts/setup_argo.sh:249-250`

```bash
        elif [[ -f "${SCRIPT_DIR}/generate_subs.py" ]]; then
            python3 "${SCRIPT_DIR}/generate_subs.py" "${DATA_DIR}/singbox_nodes.json" /var/www/aimilivpn-sub >/dev/null 2>&1 || true
        fi
        log_info "订阅已更新完成，包含 Argo Anycast 优选节点！"
```

**证据链**：
- `scripts/setup_argo.sh` 全文只定义了 `INSTALL_DIR`（`:10`）与 `DATA_DIR`（`:11`），**`SCRIPT_DIR` 从未定义**（`grep -n "SCRIPT_DIR" scripts/setup_argo.sh` 仅命中 249、250 两行使用处）。
- 脚本使用 `set -e`（`:8`），但**未启用 `set -u`**，故 `${SCRIPT_DIR}` 静默展开为空串 → 路径变成 `/generate_subs.py` → 文件不存在 → 分支不进入。
- `/usr/local/bin/aimilivpn-generate-subs`（`:247`）经**全仓库检索确认无任何创建点**（仅 `setup_argo.sh:247-248` 两处引用）→ 第一个分支同样落空。
- **两分支全部落空后，第 251 行仍无条件打印「订阅已更新完成，包含 Argo Anycast 优选节点！」**

**影响面**：用户配置 Argo 隧道后，订阅文件**不会**被刷新，Argo 节点不会注入；但界面/日志显示"成功"。这是**带虚假成功提示的静默失效**，是最危险的一类缺陷——用户完全无从察觉。

**修复方向**：
1. 将 `${SCRIPT_DIR}` 改为 `${INSTALL_DIR}/scripts`（与 `setup_cron.sh:143` 的写法保持一致：`"${INSTALL_DIR}/scripts/generate_subs.py"`）；
2. **移除 `|| true`**，让失败可见；
3. 成功日志改为**在命令成功后**才打印；
4. 补建 `/usr/local/bin/aimilivpn-generate-subs` 包装脚本，或直接删除该死分支。

---

## 三、P1 缺陷详解（严重）

### P1-1　客户端 `dns` outbound 已被移除 —— 客户端 singbox.json 无法加载

**位置**：`scripts/generate_subs.py:636`（outbounds）、`:658`（route rule）

```python
sb_final_outbounds = singbox_selectors + sb_outbounds_list + [{"type": "direct", "tag": "direct"}, {"type": "dns", "tag": "dns-out"}]
...
{"protocol": "dns", "outbound": "dns-out"},
```

**官方源码证据（v1.14.3 `option/outbound.go`）**：
```go
	switch h.Type {
	case C.TypeDNS:
		return E.New("dns outbound is deprecated in sing-box 1.11.0 and removed in sing-box 1.13.0, use rule actions instead")
	}
```

**影响面**：客户端 `singbox.json` 订阅在 sing-box ≥1.13 客户端上**加载即报错**。

**修复方向**：删除 `dns-out` outbound，DNS 流量交由 `route.rules` 的 `{"protocol": "dns", "action": "hijack-dns"}` 处理。

---

### P1-2　客户端 DNS rule 使用 legacy 字段

**位置**：`scripts/generate_subs.py:646-647`

```python
{"geosite": ["cn"], "server": "local-dns"},
{"clash_mode": ["Direct"], "server": "local-dns"}
```

**官方源码证据（v1.14.3 `option/rule_dns.go`）**：
```go
	// Deprecated: removed in sing-box 1.12.0
	Geosite     badoption.Listable[string] `json:"geosite,omitempty" schema:"omit"`
	SourceGeoIP badoption.Listable[string] `json:"source_geoip,omitempty" schema:"omit"`
	GeoIP       badoption.Listable[string] `json:"geoip,omitempty" schema:"omit"`
```
且 `ClashMode` 在 DNS rule 中是 `string`（非数组），项目写的是 `["Direct"]` —— 类型也不匹配。

**修复方向**：改用 `"action": "route"` + `"server": "local-dns"` + `rule_set` 引用 geosite。

---

### P1-3　客户端 route rule 使用 legacy `geoip`/`geosite`

**位置**：`scripts/generate_subs.py:660-661`
```python
{"geoip": ["cn", "private"], "outbound": "direct"},
{"geosite": ["cn"], "outbound": "direct"}
```
sing-box 1.12+ 推荐用 `rule_set`（需 `geosite-cn` / `geoip-cn` 规则集）。旧写法在新版中降级或失效。

---

### P1-4　8446（vmess-ws）端口全链路未放行

| 位置 | 内容 |
|---|---|
| `install.sh:15` | `AIMILI_FW_PORTS="${AIMILI_FW_PORTS:-8443 80 443 8444 8445 18443}"` — **无 8446** |
| `scripts/setup_singbox.sh:624` | `for p in 443 8444 8445 18443; do` — **无 8446** |
| `scripts/setup_singbox.sh:628` | `for p in 443 8443; do` — 仅 UDP，无 8446 |
| `scripts/check_health.sh:88-96` | 端口检查列表同样**缺 8446** |

而 `nginx/aimilivpn-production.conf:27-28` 的 `/vmess-ws` 需要经 8446 转发到 sing-box。虽然 Nginx 与 sing-box 同机（127.0.0.1）通常不受防火墙影响，但若 sing-box 绑 `::` 且有其它链路，缺口会成为隐患；**更关键的是健康检查漏检**，故障时无法自愈告警。

---

### P1-5　IP 漂移只更新 txt 不更新 json —— 订阅 IP 不更新 + 虚假告警

**位置**：`scripts/setup_cron.sh:138-152`

```bash
    cur_ip=$(curl -s --connect-timeout 4 https://api.ipify.org || true)
    if [[ -n "${cur_ip}" && -n "${old_ip}" && "${cur_ip}" != "${old_ip}" && ... ]]; then
        echo "${cur_ip}" > "${ip_file}"                    # ← 只更新 public_ip.txt
        if [[ -f "${INSTALL_DIR}/scripts/generate_subs.py" && -f "${DATA_DIR}/singbox_nodes.json" ]]; then
            python3 "${INSTALL_DIR}/scripts/generate_subs.py" "${DATA_DIR}/singbox_nodes.json" "/var/www/aimilivpn-sub" ...
```

**证据链**：`generate_subs.py:17` 的 IP 来源是
```python
public_ip = nodes_data.get("public_ip", "127.0.0.1")
```
即从 `singbox_nodes.json` 读取，**而非 `public_ip.txt`**。cron 只写了 txt，json 里的 `public_ip` 仍是旧值 → 重新生成的订阅 **IP 完全没变**。

随后 `:149` 仍向 Telegram 推送：
> "检测到服务器 IP 从 X 变更至 Y，**已自动更新全部协议订阅配置！**"

—— **虚假成功提示**（与 P0-4 同类问题）。

**修复方向**：更新 txt 的同时，用 `python3 -c` 或 `jq` 同步修改 `singbox_nodes.json` 的 `public_ip` 字段，再触发生成。

---

### P1-6　`custom:` 模式把 geosite 名当 `domain_suffix` 使用

**位置**：`scripts/setup_warp.sh:244-253`

```python
    if mode.startswith("custom:"):
        raw_sites = mode.split(":", 1)[1]
        sites = [s.strip() for s in raw_sites.split(",") if s.strip()]
        warp_rule = {
            "auth_user": ["direct-user"],
            "domain_suffix": sites,          # ← geosite 名不是域名后缀
            "outbound": "warp-out"
        }
```

`custom:netflix,openai` 会生成 `domain_suffix: ["netflix", "openai"]` —— `netflix` 不是任何域名的后缀（真实域名是 `netflix.com`），规则**永远匹配不到**。而 `ai` / `stream` 模式用的是正确的完整域名列表（`netflix.com` 等），可见 `custom` 模式是语义不一致的实现。

**修复方向**：`custom` 模式应直接接受域名后缀（如 `custom:netflix.com,openai.com`），或改用 `rule_set` 引用 geosite。

---

### P1-7　TG Bot 常驻 systemd unit 从未创建

**证据链（全仓库检索）**：
```
install.sh:292:  for u in aimilivpn aimilivpn-github-update.timer ... aimilivpn-tgbot; do
install.sh:361:  rm -rf .../aimilivpn-tgbot.service ...
```
**仅在卸载（stop/disable/rm）时被引用，全仓库无任何写入该 unit 文件的位置**（`grep -rn "aimilivpn-tgbot" scripts/` 无结果）。

**影响面**：`scripts/tg_bot.sh` 目前只能被 cron 一次性调用（`setup_cron.sh:116-117,148-150`），**没有常驻进程**，因此 `/start` 等交互式命令**永远无人应答**。项目文档中描述的 Bot 交互能力实际不存在。

---

### P1-8　`aimili_apt_update` 的 `set -e` 与 `rc=$?` 冲突

**位置**：`install.sh:67-97`

```bash
aimili_apt_update() {
    local out rc urls u f changed=0 disabled="" ad="${AIMILI_APT_DIR:-/etc/apt}"
    out=$(LC_ALL=C apt-get update -q 2>&1); rc=$?
```

函数设计意图（注释 `:65-66`）是"apt-get update 遇到坏源**不中断安装**"：识别报错源 → 临时停用 → 重试。但 `out=$(...)` 是**赋值语句**，其退出码即 `apt-get update` 的退出码；在 `set -e` 下**非零退出直接终止整个安装脚本**，`rc=$?` 永远拿不到非零值（因为脚本已死）。

> 注：此处 `out=$(cmd)` 后紧跟 `rc=$?` 的写法本身是取到 `cmd` 的退出码的，问题纯粹在于 `set -e` 抢先中止。

**修复方向**：`if ! out=$(LC_ALL=C apt-get update -q 2>&1); then rc=$?; ...` 或 `out=$(... ) || true` 后手动判断。

---

### P1-9　Argo 域名覆盖 CDN 域名，CDN 节点 Host/SNI 错位

**位置**：`scripts/generate_subs.py:275`

```python
cdn_target_domain = argo_domain if argo_domain else cdn_host
```

**问题**：一旦配置了 Argo，`active_cdn_host`（`:278`）就变成 Argo 域名。于是 **C2/C3/C4 三个"小黄云 CDN"节点的 Host / SNI 全部被写成 Argo 域名**（`trycloudflare.com`）。但 Argo 隧道回源到的是本机 **8445**（`setup_argo.sh:93,186,334` → `cloudflared tunnel --url http://127.0.0.1:8445`），而 C2/C3/C4 声明的是 **8443 端口**—— Argo 隧道根本不监听 8443。**这 3 个节点在启用 Argo 后 100% 失效。**

**实机验证**（本轮产物）：设置 `argo_domain` 后，clash.yaml 中 4 个 CDN 节点 SNI 全部被改写为同一值：
```
⛅ [CDN-优选IP·IPv4] VMess-WS-Argo...       | server= 104.16.160.10 : 443  | sni= <argo域名>
⛅ [CDN-小黄云·IPv4] VMess-xHTTP...          | server= 104.16.160.10 : 8443 | sni= <argo域名>
⛅ [CDN-小黄云·IPv4] VLESS-WS-TLS...         | server= 104.16.160.10 : 8443 | sni= <argo域名>
⛅ [CDN-小黄云·IPv6] VMess-xHTTP...          | server= 2606:4700::6810:a00a : 8443 | sni= <argo域名>
```

**修复方向**：CDN 组节点应使用 `cdn_host`，仅 Argo 节点使用 `argo_domain`，二者不应共用 `active_cdn_host`。

---

## 四、P2 / P3 缺陷清单

### P2 级

| 编号 | 位置 | 问题与影响 |
|---|---|---|
| **P2-1** | `generate_subs.py:40-58` | CDN 主机名靠字符串推导（`direct.example.com` → `cdn.example.com`），**该主机名必须由用户自建 DNS 记录 + 证书**，否则 4 个 CDN 节点全废，而订阅照常下发。项目无任何校验或引导文案。 |
| **P2-2** | `install.sh:455,457-490,592,602,616,623,633,640,647,1359` | `${BOLD}` **从未定义**（脚本只定义 `RED/GREEN/YELLOW/BLUE/PLAIN`），所有菜单粗体样式失效。因未启用 `set -u` 故不致命。 |
| **P2-3** | `install.sh:1296,1303` | 面板路径后缀硬编码 `SECRET_PATH="EJsW2EeBo9lY"` 兜底。公开仓库中的固定弱后缀，`ui_auth.json` 缺失时直接生效，管理后台可被公开猜中。 |
| **P2-4** | `install.sh:868,912,1343` + `setup_https.sh:245,249` | 默认 SOCKS5 密码 `ilovestudy` 硬编码；且 `ufw allow 8500/tcp` 把本应"仅监听 127.0.0.1"的 SOCKS5 端口**放行到公网**，与注释描述的安全模型直接矛盾。 |
| **P2-5** | `setup_https.sh:189` | `nginx -t` 在 `set -euo pipefail` 下失败会**中断整个安装**，无降级路径。 |
| **P2-6** | `manage_cert.sh:361` | `sed -i "s/server_name .*;/server_name ${domain};/g"` 是**全局替换**，会把 80 端口伪装站的 `server_name _;` 一并改掉，导致伪装站域名错乱。 |
| **P2-7** | `manage_cert.sh:51,57,58,176,234,292` | 大量使用 `$HOME`，脚本启用 `set -u` 时若 HOME 未设置会**直接退出**。 |
| **P2-8** | `setup_cron.sh:77-79` | 每日 `echo 3 > /proc/sys/vm/drop_caches` —— drop_caches 是公认反模式（清空页缓存导致后续读全部走磁盘、显著增加 IO 抖动），对小内存 VPS 是负优化。 |
| **P2-9** | `tg_bot.sh:216` | `send_tg_message "${msg}" >/dev/null 2>&1 \|\| true` —— 告警发送失败也被吞，`send_alert` 永远返回成功，TG 静默失效无感知。 |
| **P2-10** | `tg_bot.sh:180-183` | 内嵌 Python 用 `\\n` 字面量拼 HTML，**实际输出是字面 `\n` 而非换行**，TG 消息排版错乱。 |
| **P2-11** | `vpngate_manager.py:157-158` | `/api/github_update/check` 硬编码 `"has_update": False`、`"relation": "up_to_date"`，**面板更新检测形同虚设**。 |
| **P2-12** | `README.md:8,158-184` | 宣称「18 节点双栈矩阵」，**实测 clash.yaml 只有 16 个 proxies**，`anytls` 节点数为 **0**。nodes.txt 有 18 条链接但 clash 侧丢失 2 个 AnyTLS —— 生成逻辑存在平台分支遗漏。 |
| **P2-13** | `scripts/code_gate.py` | 详见第五节 |
| **P2-14** | `.github/workflows/ci.yml` | CI 仅跑 `code_gate.py` + `bash -n` + `compileall`，**无 shellcheck / pyflakes / sing-box check**，因此本报告全部 P0/P1 都无法在 CI 阶段拦截。 |

### P3 级

| 编号 | 位置 | 问题 |
|---|---|---|
| **P3-1** | `aimili_cli.py:219,220,237,248,250,252,449,451,499,796` | 10 处 `f-string is missing placeholders`（pyflakes 实测，无 undefined name） |
| **P3-2** | `setup_argo.sh:174,197,198,331,332` | `$C_CYAN` 未定义（仅影响着色输出） |
| **P3-3** | `setup_https.sh:60-62` | `PLAIN`/`YELLOW` 引用但定义在别处（有 `${VAR:-}` 兜底，仅样式） |
| **P3-4** | `setup_singbox.sh:70` vs `:72` | `manage_core.sh latest` 与本地兜底 `1.14.3` **双重不确定**，实际安装版本不可预测 |
| **P3-5** | `generate_subs.py:77` | `clean_ip = "104.16.160.10"` 硬编码 CF 优选 IP 兜底 |
| **P3-6** | `generate_subs.py:435-479` | 自研 YAML 序列化与 PyYAML 路径双实现，可能产出格式不一致 |
| **P3-7** | `aimili_cli.py:334-346` | `except SystemExit: pass` 吞掉子命令退出码，脚本化调用无法感知失败 |
| **P3-8** | `aimili_cli.py:181-200` + `scripts/print_qr.py` | `print_terminal_qr` 两处实现，回退逻辑重复；Windows 下 `qrencode` 不存在，只打印文本 |

---

## 五、质量门禁自身的缺陷（为什么 CI 是绿的）

**实测输出**（本轮重跑 `python scripts/code_gate.py`）：
```
====================================================
  AimiliVPN 自动化架构与代码质量门禁 (Code Gate)
====================================================
[√] 质量门禁全绿通过！无 P0/P1 阻塞性缺陷，代码与拓扑结构健康。
```

**但本报告的 4 个 P0、9 个 P1 无一被捕获。** 根因有三：

### 5.1 作用域不区分，未定义引用被"自我定义"掩盖

`check_python_scripts()` 用 `ast.walk` 收集**所有** `FunctionDef`/`ClassDef`/`Assign` 名到同一个 `defined_names` 集合，**不区分作用域**。结果是：函数体内引用的名字，只要在文件任意位置出现过赋值，就会被判为"已定义"。本轮我用自研 AST 扫描器复核时发现，`setup_argo.sh` 的 `$SCRIPT_DIR` 类问题（Shell 侧）同理——门禁的 shell 检查只看大写变量是否"出现过"，**不检查是否在本文件定义过**。

### 5.2 拓扑规则覆盖面极窄

`check_topology_consistency()` 只覆盖 3 条规则：
1. 8445 必须是 TLS
2. 任意 DNS 劫持
3. `"address": "local"`

本报告发现的全部真实拓扑缺陷（协议错配、端口未放行、Argo 覆盖 CDN 域名）**全部不在其覆盖范围内**。

### 5.3 nginx 正则写得脆弱

`check_nginx_configs()` 仅检测正则 `location ~` 块，且正则 `location\s+~[^{]*\{([^}]+)\}` **无法匹配含嵌套 `}` 的块**，实际几乎不可能命中。

### 5.4 CI 无独立校验层

`.github/workflows/ci.yml` 只跑 `code_gate.py` + `bash -n` + `compileall`：
- **无 shellcheck**（Shell 变量/作用域问题无人发现）
- **无 pyflakes**（Python 未定义引用无人发现）
- **无 sing-box `check`**（配置与内核版本不兼容无人发现）—— **这是最关键的一条**，只需在 CI 里加一步 `sing-box check -c config.json` 即可拦下 P0-1、P0-2、P1-1、P1-2、P1-3

---

## 六、上一版（V1.4.7）问题的修复状态复核

| 上一版问题 | 状态 | 复核依据 |
|---|---|---|
| `aimili_cli.py` 中 `get_web_auth_data` / `print_web_dashboard` 未定义 → `ml` 主命令 NameError 崩溃 | ✅ **已修复** | 两函数现定义于 `aimili_cli.py:90-124` 与 `203-222`；pyflakes 实测无 undefined name |
| `install.sh:646` 函数外使用 `local` | ✅ **已修复** | 用真实作用域解析器复核 `aimili_fw_open()`，无函数外 `local` |
| nginx 正则 location 的 `proxy_pass` 带 URI 非法 | ✅ **已修复** | `nginx/aimilivpn-production.conf:17-28` 现为**前缀 location**（`location /vmess` + `location /vmess-ws`），前缀 location 带 URI 本身合法 |
| `setup_cron.sh` 调用 `generate_subs.py` 无参 | ✅ **已修复** | `setup_cron.sh:142-143` 已传 `<json> <dir>` 两参数 |
| `vpngate_manager.py` 版本号硬编码 `V1.2.0` | ✅ **已修复** | `vpngate_manager.py:55-63` 改为读 `VERSION` 文件 |
| nginx 伪装站 `root` 未被引用 | ✅ **已修复** | `aimilivpn-production.conf:89` 已 `root /var/www/camouflage;` |
| `setup_cron.sh` IP 漂移不更新订阅 | ⚠️ **部分修复** | 补上了 `generate_subs.py` 调用，但**未更新 `singbox_nodes.json`**，IP 实际不变（详见 P1-5） |
| `vpngate_manager.py` 更新检测硬编码 False | ❌ **未修复** | `vpngate_manager.py:157-158` 仍在硬编码（详见 P2-11） |

---

## 七、实测验证记录（可复现）

### 7.1 订阅生成器实机运行

```bash
python3 scripts/generate_subs.py <singbox_nodes.json> <输出目录>
# 输出：成功生成 18 个多协议双栈节点订阅文件！  RC=0
```

产物清单：
```
clash.yaml   11112 bytes
nodes.txt     6085 bytes
singbox.json 13127 bytes
sub.txt       8092 bytes
```

### 7.2 18 条节点逐条协议解析（nodes.txt）

```
 1 VLESS  net=tcp    add=203.0.113.10:443     sni=gateway.icloud.com   直连·VLESS-Reality
 2 VLESS  net=tcp    add=203.0.113.10:443     sni=gateway.icloud.com   住宅·VLESS-Reality
 3 HY2    port=443   add=203.0.113.10
 4 HY2    port=443   add=203.0.113.10
 5 TUIC   port=8443  add=203.0.113.10
 6 TUIC   port=8443  add=203.0.113.10
 7 ANYTLS port=8444  add=203.0.113.10
 8 ANYTLS port=8444  add=203.0.113.10
 9 VMESS  net=http path=/vmess    add=203.0.113.10:8445
10 VMESS  net=http path=/vmess    add=203.0.113.10:8445
11 VLESS  net=tcp    add=2001:db8::1:443
12 HY2    port=443   add=2001:db8::1
13 TUIC   port=8443  add=2001:db8::1
14 VMESS  net=http path=/vmess    add=2001:db8::1:8445
15 VMESS  net=http path=/vmess    add=104.16.160.10:443      ← Argo
16 VMESS  net=http path=/vmess    add=104.16.160.10:8443     ← CDN
17 VLESS  net=ws   path=/vmess-ws add=104.16.160.10:8443     ← CDN  ★ P0-3 协议错配
18 VMESS  net=http path=/vmess    add=2606:4700::6810:a00a:8443 ← CDN IPv6
```

### 7.3 clash.yaml 节点矩阵（**16 ≠ README 宣称的 18**）

```
proxies 总数: 16
按类型: {'vless': 4, 'hysteria2': 3, 'tuic': 3, 'vmess': 6}
anytls 节点数: 0        ← sub.txt/nodes.txt 里有 2 个 AnyTLS，clash 侧全丢
悬空策略组引用: 无
```
类型分布可交叉验证：IPv4/IPv6 各 2 个 AnyTLS（4 个）+ IPv4 2 个 TUIC + IPv6 1 个 TUIC（3 个），与实测 `tuic: 3` 一致。

### 7.4 端口拓扑对照表

| 端口 | 协议 | 监听方 | 防火墙放行 | 健康检查 |
|---|---|---|---|---|
| 443 | TCP | sing-box vless-in (Reality) | ✅ `install.sh:15` | ✅ |
| 443 | UDP | sing-box hysteria2-in | ✅ `setup_singbox.sh:628` | ✅ |
| 8443 | TCP | **nginx** (TLS 面板) | ✅ | ✅ |
| 8443 | UDP | sing-box tuic-in | ✅ | ✅ |
| 8444 | TCP | sing-box anytls-in | ✅ | ✅ |
| 8445 | TCP | sing-box vmess-in (http) | ✅ | ✅ |
| **8446** | TCP | sing-box vmess-ws-in (ws) | ❌ **缺** | ❌ **缺** |
| 18443 | TCP | nginx (TLS 订阅) | ✅ | ✅ |
| 80 | TCP | nginx (伪装站) | ✅ | ✅ |
| 8500/8501 | TCP | 家宽 SOCKS5/管理 | ⚠️ **公网放行**（P2-4） | — |

### 7.5 官方 sing-box 源码取证清单（本轮 WebFetch 核实）

| 取证项 | 来源 | 关键结论 |
|---|---|---|
| legacy inbound 字段 | `v1.14.3/option/inbound.go` | `sniff` 等 **1.13.0 起直接 return error** |
| legacy DNS server | `v1.14.3/option/dns.go` | `legacyDNSServerRemovedMessage`：**1.12.0 弃用 / 1.14.0 移除**；`Type == ""` 直接报错 |
| DNS rule 结构 | `v1.14.3/option/rule_dns.go` | `geosite/geoip` 标注 **removed in 1.12.0**；`clash_mode` 为 `string` 非数组 |
| DNS/route action | `v1.14.3/option/rule_action.go` | `server` 属于 `action:"route"` 变体下的 `DNSRouteActionOptions` |
| dns outbound | `v1.14.3/option/outbound.go` | `dns` outbound **1.13.0 移除** |
| WireGuard 结构 | `v1.14.3/option/wireguard.go` vs `v1.12.0/option/wireguard.go` | legacy 平铺结构在 1.14 已删除，改为 `address`+`peers[]` |
| 未知字段策略 | `v1.14.3/option/options.go` | 顶层 `decoder.DisallowUnknownFields()` → 旧字段直接报错 |
| 官方构建标签 | `v1.14.3/release/DEFAULT_BUILD_TAGS` | **含 `with_wireguard`**（官方二进制带 WireGuard，问题在字段结构而非缺失编译） |
| WireGuard stub | `v1.14.3/include/wireguard_stub.go` | 非 `with_wireguard` 构建时报 "rebuild with -tags with_wireguard" |

> **未实机测试项**：本轮尝试下载 sing-box 1.14.3 官方二进制以执行 `sing-box check -c` 做**内核级实机校验**，但因网络限制（gh-proxy.com 多次超时/502、ghfast.top 502、github.moeyy.xyz 502）**未能取得完整二进制**，因此 P0-1/P0-2/P1-1/P1-2/P1-3 的判定**基于官方源码逐字核对**而非本地 `sing-box check` 输出。此为本报告唯一的证据链缺口，结论可靠性高但未达 100% 实机确认。

---

## 八、修复优先级建议

### 第一阶段（阻断发布，必须先修）

| 顺序 | 缺陷 | 理由 |
|---|---|---|
| 1 | **P0-1** `sniff` 移除 | 服务端完全起不来，最高优先级 |
| 2 | **P0-2** WARP outbound 结构 | 主打功能失效 |
| 3 | **P0-3** VLESS-WS 协议错配 | CDN 节点必败 |
| 4 | **P0-4** `$SCRIPT_DIR` + 虚假日志 | 静默失效且误导用户 |
| 5 | **P1-1 / P1-2 / P1-3** 客户端 legacy 字段 | 客户端订阅无法加载 |

### 第二阶段（发布前必须修）

- **P1-5** IP 漂移不生效 + 虚假告警
- **P1-7** TG Bot unit 补建
- **P1-9** Argo 域名覆盖 CDN 域名
- **P2-3 / P2-4** 弱后缀与默认密码、8500 公网放行（安全）
- **P2-12** 节点数与文档对齐

### 第三阶段（工程化改进）

- **P2-13 / P2-14 门禁与 CI 升级** —— 建议在 CI 中增加：
  ```bash
  shellcheck scripts/*.sh install.sh
  pyflakes aimili_cli.py scripts/*.py *.py
  sing-box check -c /etc/sing-box/config.json    # 关键：可直接拦下全部 P0-1/P0-2
  ```
  并重写 `code_gate.py` 的 Python 作用域分析（区分函数/模块作用域）与 shell 变量定义检查（验证"是否在本文件定义"而非"是否出现过"）。

---

## 九、审查方法论说明

本轮遵循项目 `AGENTS.md` 的红队规则执行：

1. **Guilty Until Proven Innocent**：任何"看起来正常"的代码一律先假设有缺陷，再逐项证伪。
2. **Tool-First Verification**：先执行项目自带 `code_gate.py`（已执行，全绿），再用独立工具交叉复核：
   - `pyflakes`（Python 未定义引用）
   - 自研 AST 扫描器（作用域感知）
   - 自研 Shell 变量未定义扫描器（大写变量 + heredoc/brace-depth 作用域解析）
   - `generate_subs.py` 实机运行 + 产物逐条协议解析
   - `yaml` 解析 clash.yaml 并交叉验证节点矩阵
   - GitHub API + `raw.githubusercontent.com` 拉取 sing-box v1.12/v1.14.3 官方源码逐字比对
3. **拓扑与依赖链全景对照**：建立端口表 + 协议表 + 链路表三层对照，再逐节点核对 add/port/net/path/tls/sni/host 六元组。
4. **审查未通过不交付**：因此本报告判定当前版本**不具备发布条件**。

**本次审查未修改任何源码文件**，唯一新增文件即本报告。

---

*报告生成模型：MiniMax-M3.1　|　生成时间：2026-10-23 20:07~20:20 (UTC+8)　|　审查对象：AimiliVPN V1.4.8 @ f469c12*
