# Aimili VPN + Sing-box 双出站节点管理系统 🌐

Bilingual: [中文](#中文) | [English](#english)

本项目基于 AimiliVPN 深度定制，原生整合 **Sing-box** 现代化代理核心，在 Linux VPS 上实现：
1. **多协议公共住宅池管理**：统一采集与管理 OpenVPN、SoftEther、SSTP、L2TP 等多协议节点，提供持续可用性检测、真实连接延迟检测与 Web 管理；
2. **全协议双出站分流架构 (Dual-Outbound Matrix)**：单节点支持 **VLESS-Reality、Hysteria 2、TUIC v5、AnyTLS、VMess-xHTTP** 5 大主流协议，一键下发包含 **“原生 VPS 高速直连”** 与 **“Aimili 动态住宅家宽穿透”** 的 10 大节点完整订阅；
3. **全平台多格式订阅支持**：原生输出通用 Base64 (`sub.txt`)、Clash Meta / Mihomo (`clash.yaml` 内置自动延迟优选策略组)、以及 Sing-box 客户端开箱即用规则 (`singbox.json`)；
4. **Cloudflare 全生态无缝集成**：
   - ☁️ **Argo 隧道穿透**：支持 Quick Tunnel (免CF账号临时穿透) 与 Named Token 固定隧道，破除 NAT、无公网 IP 限制；
   - 🛡️ **WARP 双栈网络与流媒体解锁**：基于 Sing-box 原生 WireGuard 用户态出站，零侵入 VPS 主路由表，绝不影响 SSH，原生解锁 Netflix、Disney+、OpenAI/ChatGPT；
   - ⚡ **CDN 三网优选 IP 测速**：内置电信/联通/移动亚太低延迟 Anycast 测速算法，一键替换 CDN 节点连接 IP，彻底告别晚高峰减速；
5. **主动探测防御与自动化运维**：
   - 🎭 **HTML5 高保真本地伪装库**：内置科技云 SaaS、开发者工具箱/计算器、极客博客、2048 小游戏等 4 套可交互模板，完美抵御主动嗅探；
   - 🤖 **Telegram Bot 即时推送**：支持节点订阅一键下发至 TG、公网 IP 漂移告警、核心进程崩溃拉起告警；
   - ⏰ **定时系统自愈与内存清理**：每日凌晨 4 点强制内核缓存释放 (`drop_caches`)、权威 HTTPS 时钟校准、15分钟进程看门狗；
6. **工业级可靠性加固**：
   - 🛡️ **GOMEMLIMIT 软内存限制**：针对 128MB/512MB/1GB 等小内存/NAT VPS，动态测算 Go 堆内存配额，根除 OOM 崩溃；
   - 🔄 **事务快照与原子回滚**：配置更新遵循“备份 $\to$ 临时写入 $\to$ sing-box check 预检 $\to$ 原子替换 $\to$ 健康监控 $\to$ 异常秒级回滚”闭环；
   - ⏱️ **高精度时间同步与补偿**：内置 `check_time_sync.sh` 对齐权威 HTTPS 响应头，消除 $>15$ 秒时钟漂移导致的握手超时；
   - 🌪️ **端口跳跃与 Salamander 混淆**：Hysteria 2 支持 UDP 40000-50000 端口范围映射与 Salamander 混淆，破解晚高峰运营商 QoS 限速。

<a name="中文"></a>

## 中文

### 1. 系统名称与定位

**Aimili VPN + Sing-box｜全协议双出站节点管理系统**

系统由两大核心组成：
- **前端多协议代理矩阵（Sing-box）**：监听 443 (TCP Reality & UDP Hy2)、8443 (UDP TUIC)、8444 (TCP AnyTLS)、8445 (TCP VMess)，通过用户鉴权（`auth_user`）实现毫秒级双出站分流。
- **后端住宅网桥（AimiliVPN）**：持续维护全球公共/住宅节点池，拨号建立虚拟隧道，并在 `127.0.0.1:8500` 提供 SOCKS5 出站网桥；亦可外接第三方住宅/落地代理。

### 2. 端口与协议架构

| 协议 / 服务 | 端口 | 传输载体 | 说明 |
| :--- | :--- | :--- | :--- |
| **VLESS-Reality** | `443/tcp` | TCP + TLS Vision | 核心伪装入口，借用大厂证书免个人证书 |
| **Hysteria 2** | `443/udp` (跳跃: 40000-50000) | UDP (Brutal + Salamander) | 恶劣线路暴力加速，支持端口跳跃与混淆防 QoS |
| **TUIC v5** | `8443/udp` | UDP / QUIC (BBR) | 原生 BBR 拥塞控制，0-RTT 极速秒开 |
| **AnyTLS** | `8444/tcp` | TCP (包长混淆) | 动态数据包长度填充，防主动探测特征 |
| **VMess-xHTTP** | `8445/tcp` | TCP (HTTP/3 分块) | 标准分段 HTTP 流，防封锁与审查 |
| **HTTPS 管理后台** | `8443/tcp` | TCP, Nginx 反代 8501 | 可视化管理面板，支持国家/节点切换 |
| **全格式订阅入口** | `18443/tcp` | TCP, Nginx 静态托管 | 提供 `sub.txt`、`clash.yaml`、`singbox.json` |
| **住宅出站网桥** | `8500/tcp` | 本机 `127.0.0.1` | 内置 Aimili 动态家宽池或外部第三方 SOCKS5 落地 |

### 3. 一键部署与管理

仓库地址：[wbowen123/AimiliVPN](https://github.com/wbowen123/AimiliVPN)

以 root 用户在 Linux VPS（Ubuntu / Debian / CentOS / Alpine 等）上执行：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/wbowen123/AimiliVPN/main/install.sh)
```

#### 常用管理命令

系统提供全局快捷命令 `ml` 随时管理：
```bash
ml          # 启动全新交互式双核心管理控制台（支持 20 项专业运维）
ml sub      # 终端快速打印 10 大节点矩阵与 HTTPS 全生态订阅卡片
ml web      # 查看网页控制面板地址、安全后缀、管理员账号与密码
ml test     # 全自动节点连通性与健康诊断（排查 -1 超时、端口监听与阻断根因）
ml core     # Sing-box 内核管理（一键升级最新稳定版、选择历史版本）
ml cert     # 域名 SSL 证书管理（申请/续期/ZeroSSL/Cloudflare DNS API 免80端口）
ml argo     # Cloudflare Argo 隧道穿透（免CF账号临时穿透/固定Token穿透）
ml warp     # Cloudflare WARP 双栈网络管理（流媒体/OpenAI原生分流解锁）
ml cf       # Cloudflare Anycast CDN 三网优选 IP 测速与替换
ml camo     # HTML5 本地高保真伪装网站模版库切换（4 套交互式模版）
ml tg       # Telegram Bot 节点下发与异常实时告警配置
ml cron     # 定时系统自愈、凌晨内存释放与 15 分钟看门狗管理
ml dns      # 📖 Cloudflare IPv4/IPv6 双栈解析与子域名隔离配置向导
ml egress   # 配置住宅出口模式（内置Aimili家宽池 / 外接第三方商业SOCKS5）
ml status   # 查看 AimiliVPN 运行状态与当前活跃住宅节点
ml logs     # 查看 AimiliVPN 实时拨号与隧道日志
ml restart  # 重启 AimiliVPN 住宅网关
ml singbox  # Sing-box 核心管理（start/stop/restart/logs/status）
```

### 4. 节点命名规范与订阅详情（导入客户端一目了然）

为了让用户在任何客户端（v2rayN、Clash Verge、Sing-box、Shadowrocket 等）导入后一目了然，所有节点名称均严格遵循**【出站属性 + 协议名称 + 传输特征】**三维规范：

```
[出站属性] ──+── 🚀 [直连-极速] (走 VPS 物理公网网卡，极速千兆带宽，适合 4K、下载、游戏)
            └── 🏠 [住宅-家宽] (走 Aimili 动态家宽池/SOCKS5，住宅纯净 IP，适合 ChatGPT、风控业务)

[协议架构] ──+── VLESS-Reality   ──> 【TCP-Vision·原生千兆】     借用顶级大厂证书，免申请免维护
            ├── Hysteria 2      ──> 【H3-UDP-Brutal·暴力抗丢包】 暴力抗丢包，端口跳跃防晚高峰QoS
            ├── TUIC v5         ──> 【H3-QUIC-0RTT·秒开首选】   原生BBR，移动端秒开首选
            ├── AnyTLS          ──> 【TCP-Padding·动态包长防探测】动态包长混淆，专防主动探测特征
            ├── VMess-xHTTP     ──> 【H2/H3-分块·分段防审查】    分段防审查，抗封锁利器
            └── VMess-WS-Argo   ──> 【CDN-Anycast·全球破墙】     Cloudflare 隧道穿透，终极破墙急救
```

客户端订阅后展示的 10 大节点完整名称：
1. `🚀 [直连-极速] VLESS-Reality【TCP-Vision·原生千兆】`
2. `🏠 [住宅-家宽] VLESS-Reality【TCP-Vision·Aimili动态家宽】`
3. `🌪️ [直连-极速] Hysteria 2【H3-UDP-Brutal·暴力抗丢包】`
4. `🏘️ [住宅-家宽] Hysteria 2【H3-UDP-Brutal·恶劣线路家宽加速】`
5. `⚡ [直连-极速] TUIC v5【H3-QUIC-0RTT·秒开首选】`
6. `🏡 [住宅-家宽] TUIC v5【H3-QUIC-0RTT·晚高峰家宽流媒体】`
7. `🛡️ [直连-极速] AnyTLS【TCP-Padding·动态包长防探测】`
8. `🌐 [住宅-家宽] AnyTLS【TCP-Padding·特征防探测家宽】`
9. `☁️ [直连-极速] VMess-xHTTP【H2/H3-分块·分段防审查】`
10. `🛋️ [住宅-家宽] VMess-xHTTP【H2/H3-分块·动态家宽流】`
11. `⛅ [CDN-穿透] VMess-WS-Argo【CDN-Anycast·Cloudflare全球破墙】` (开启 Argo 隧道时自动追加)

---

### 5. Cloudflare DNS 双栈与子域名傻瓜式配置指南 (`ml dns`)

#### Q1: 为什么不能把所有节点都开“小黄云”？
开启小黄云 (Proxied) 后，Cloudflare 会终结 TLS 握手，导致 **VLESS-Reality 彻底报废**、**Hysteria 2 / TUIC v5 无法连接**，且国内晚高峰被调度到美西导致**延迟暴涨**！

#### Q2: IPv4 / IPv6 双栈 VPS 如何在 Cloudflare 添加 4 条 DNS 记录？
如果您的 VPS 具有 IPv4 和 IPv6 地址，请在 Cloudflare 仪表盘添加以下 4 条记录：

| 组别 | 记录类型 | 名称 (Subdomain) | 内容 (Content) | 代理状态 (Proxy Status) | 用途说明 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **组一：直连与住宅极速域名** | `A` | `direct` | 您的 IPv4 地址 | **仅 DNS (灰云 / 必须关闭小黄云)** | 专供 Reality / Hy2 / TUIC / 住宅直连，享受 VPS 原生千兆极速 |
| **组一：直连与住宅极速域名** | `AAAA` | `direct` | 您的 IPv6 地址 | **仅 DNS (灰云 / 必须关闭小黄云)** | 专供 IPv6 极速直连 |
| **组二：破墙与CDN逃生域名** | `A` | `cdn` | 您的 IPv4 地址 | **已代理 (橙色小黄云 / 开启)** | 专供 VMess-WS、xHTTP、Argo 隧道，VPS 被封时 100% 救急 |
| **组二：破墙与CDN逃生域名** | `AAAA` | `cdn` | 您的 IPv6 地址 | **已代理 (橙色小黄云 / 开启)** | 专供 CDN IPv6 穿透 |

#### Q3: 测速三网优选 IP (`ml cf`) 是否会覆盖我的 VPS 物理直连 IP？
**绝对不会！**
- 优选 IP 仅用于替换组二中**走 Cloudflare CDN / Argo 的穿透节点**的客户端连接地址；
- 组一中的**所有直连节点与住宅节点依然直接连接您的 VPS 真实物理 IP**，延迟不受任何影响，兼顾极速与破墙。

---

### 6. Sing-box 原生 WireGuard 用户态出站原理科普

#### Q1: 传统 WARP 脚本为什么容易导致 VPS 失联（SSH 连不上）？
传统脚本（如官方 `warp-cli` 或 `wg-quick wg0`）直接在 Linux 操作系统内核创建虚拟网卡，并篡改 Linux 全局路由表 (`ip route default`)。一旦网络波动或配置异常，服务器的 SSH 22 端口流量也会被误吸入 WARP 隧道，造成**无法挽回的远程失联（VPS 变砖）**。

#### Q2: Sing-box 原生用户态 WireGuard 是如何做到绝对安全的？
- **纯软件进程内实现**：Sing-box 使用内部编写的 WireGuard Go 协议栈，仅作为类似 SOCKS5 的普通出站通道；
- **100% 不改动 Linux 宿主机路由表**，系统主网络与 SSH 端口完全不受干扰；
- **精准域名分流**：只有访问 OpenAI/ChatGPT、Netflix、Disney+、TikTok 时才在 Sing-box 内部走 WARP 出口，其余网页依然跑原生千兆直连！

---

### 7. Cloudflare Argo 临时与固定 Token 隧道配置指南 (`ml argo`)

- **临时隧道 (Quick Tunnel - 选项 [1])**：
  无需注册 Cloudflare 账号，脚本自动拉起并分配临时域名（如 `https://xxx.trycloudflare.com`），即开即用。
- **固定隧道 (Named Tunnel - 选项 [2]) 4 步获取 Token**：
  1. 登录 Cloudflare Zero Trust 仪表盘：`https://one.dash.cloudflare.com`；
  2. 点击左侧 **Networks** -> **Tunnels** -> **Add a tunnel**；
  3. 选择 **Cloudflared**，输入任意隧道名（如 `my-tunnel`）并保存；
  4. 在 *Install and run a connector* 页面选择 Linux，下方会出现安装命令：
     `cloudflared service install eyJh...`
     **复制其中以 `eyJh` 开头的长串 Token，粘贴到 `ml argo` 选项 [2] 即可常驻运行！**

---

<a name="english"></a>

## English

### 1. System Overview

**Aimili VPN + Sing-box | Full-Protocol Dual-Outbound Node Management Matrix**

This system combines the cutting-edge ingress of **Sing-box** with the global residential egress of **AimiliVPN**:
- **Ingress Proxy Matrix (Sing-box)**: Delivers 5 major protocols on ports 443 (TCP Reality & UDP Hy2), 8443 (UDP TUIC), 8444 (TCP AnyTLS), and 8445 (TCP VMess). Uses user-level authentication (`auth_user`) to achieve instantaneous zero-downtime dual-outbound routing.
- **Residential Egress Bridge (AimiliVPN)**: Dynamically maintains global public/residential relay tunnels, providing a local SOCKS5 bridge on `127.0.0.1:8500` or integrating third-party commercial residential proxies.

### 2. Port & Protocol Architecture

| Protocol / Service | Port | Transport | Description |
| :--- | :--- | :--- | :--- |
| **VLESS-Reality** | `443/tcp` | TCP + TLS Vision | Steals authoritative TLS certs, zero domain required |
| **Hysteria 2** | `443/udp` (Hopping: 40000-50000) | UDP (Brutal + Salamander) | Extreme line acceleration with port hopping & obfs |
| **TUIC v5** | `8443/udp` | UDP / QUIC (BBR) | Native BBR congestion control, 0-RTT instant handshake |
| **AnyTLS** | `8444/tcp` | TCP (Padding Obfs) | Dynamic packet size randomization against active probing |
| **VMess-xHTTP** | `8445/tcp` | TCP (HTTP/3 Chunks) | Segmented HTTP/3 stream bypassing deep packet inspection |
| **HTTPS Web Admin** | `8443/tcp` | TCP, Nginx reverse proxy | Visual control panel for country & node switching |
| **Full Subscriptions** | `18443/tcp` | TCP, Nginx static host | Serves `sub.txt`, `clash.yaml`, `singbox.json` |
| **Residential Bridge** | `8500/tcp` | `127.0.0.1` | Local Aimili dynamic residential bridge or external SOCKS5 |

### 3. One-Click Installation & Management

Repository: [wbowen123/AimiliVPN](https://github.com/wbowen123/AimiliVPN)

Run as root on your Linux VPS:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/wbowen123/AimiliVPN/main/install.sh)
```

#### Management Commands

Manage your server at any time with `ml`:
```bash
ml          # Launch interactive dual-core management console (20 options)
ml sub      # Print 10-node matrix and HTTPS subscription URLs
ml web      # Display web dashboard URL, secret path, and credentials
ml test     # Run automated health check & troubleshooting for -1 errors
ml core     # Sing-box core manager (upgrade to latest, switch versions)
ml cert     # SSL/TLS cert manager (HTTP-01, Cloudflare DNS API, force renew)
ml argo     # Cloudflare Argo tunnel manager (Quick tunnel & Named Token)
ml warp     # Cloudflare WARP dual-stack manager (Streaming/AI unlock)
ml cf       # Cloudflare Anycast CDN clean IP tester and selector
ml camo     # HTML5 local high-fidelity camouflage templates switcher
ml tg       # Telegram Bot notifications & alerts dispatcher
ml cron     # Automated self-healing, cache flush, and 15-min watchdog
ml dns      # 📖 Cloudflare IPv4/IPv6 dual-stack DNS setup guide
ml egress   # Toggle residential egress (internal pool vs external SOCKS5)
ml status   # View AimiliVPN status and active residential IP
ml logs     # Tail real-time VPN dialer and tunnel logs
ml restart  # Restart AimiliVPN residential daemon
ml singbox  # Sing-box service management (start/stop/restart/logs/status)
```

### 4. Node Matrix Naming Architecture

All nodes are formatted with three distinct dimensions: **[Egress Property + Protocol + Transport Characteristics]**:
1. `🚀 [直连-极速] VLESS-Reality【TCP-Vision·原生千兆】` (Direct Gigabit)
2. `🏠 [住宅-家宽] VLESS-Reality【TCP-Vision·Aimili动态家宽】` (Residential ISP)
3. `🌪️ [直连-极速] Hysteria 2【H3-UDP-Brutal·暴力抗丢包】` (Brutal Congestion)
4. `🏘️ [住宅-家宽] Hysteria 2【H3-UDP-Brutal·恶劣线路家宽加速】` (Residential Brute)
5. `⚡ [直连-极速] TUIC v5【H3-QUIC-0RTT·秒开首选】` (QUIC 0-RTT)
6. `🏡 [住宅-家宽] TUIC v5【H3-QUIC-0RTT·晚高峰家宽流媒体】` (Residential QUIC)
7. `🛡️ [直连-极速] AnyTLS【TCP-Padding·动态包长防探测】` (Packet Padding)
8. `🌐 [住宅-家宽] AnyTLS【TCP-Padding·特征防探测家宽】` (Residential Padding)
9. `☁️ [直连-极速] VMess-xHTTP【H2/H3-分块·分段防审查】` (Chunked HTTP)
10. `🛋️ [住宅-家宽] VMess-xHTTP【H2/H3-分块·动态家宽流】` (Residential Chunked)
11. `⛅ [CDN-穿透] VMess-WS-Argo【CDN-Anycast·Cloudflare全球破墙】` (Argo Tunnel)

### 5. Cloudflare Dual-Stack DNS 4-Record Guide (`ml dns`)

To avoid CDN throttling on direct nodes, configure 4 separate DNS records on Cloudflare:
- **Direct Domain (`direct.yourdomain.com`)**:
  - `A` record -> VPS IPv4 (**DNS Only / Grey Cloud**)
  - `AAAA` record -> VPS IPv6 (**DNS Only / Grey Cloud**)
  - *Purpose*: Uncapped gigabit speed for Reality, Hy2, TUIC, and Residential egress.
- **CDN Proxied Domain (`cdn.yourdomain.com`)**:
  - `A` record -> VPS IPv4 (**Proxied / Orange Cloud**)
  - `AAAA` record -> VPS IPv6 (**Proxied / Orange Cloud**)
  - *Purpose*: 100% censorship bypass fallback for WebSocket, xHTTP, and Argo tunnels.

*Note: Clean Anycast IP (`ml cf`) ONLY applies to CDN nodes and NEVER overwrites or affects your VPS physical direct IP.*

### 6. Sing-box User-Space WireGuard Principle

Unlike legacy `warp-cli` tools that modify kernel routing tables (`ip route default via wg0`) and risk locking you out of SSH, Sing-box implements WireGuard entirely in Go user-space:
- Zero kernel route modifications;
- Zero risk of SSH disconnects;
- Granular routing rules: Only OpenAI/ChatGPT, Netflix, Disney+, and TikTok exit via WARP, while other traffic retains native gigabit bandwidth.

---

**Version: V1.4.1 (Sing-box Dual-Outbound Enterprise Full-Stack Suite)**
