# Aimili VPN + Sing-box 双出站节点管理系统 🌐

Bilingual: [中文](#中文) | [English](#english)

本项目基于 AimiliVPN 深度定制，原生整合 **Sing-box** 现代化代理核心，在 Linux VPS 上实现：
1. **多协议公共住宅池管理**：统一采集与管理 OpenVPN、SoftEther、SSTP、L2TP 等多协议节点，提供持续可用性检测、真实连接延迟检测与 Web 管理；
2. **全协议双栈双出站分流架构 (Dual-Stack Dual-Outbound Matrix)**：单节点支持 **VLESS-Reality、Hysteria 2、TUIC v5、AnyTLS、VMess-xHTTP** 5 大主流协议，全面支持 **IPv4 与 IPv6 原生双栈**，一键下发包含 **“原生 VPS 高速直连”**、**“Aimili 动态住宅家宽穿透”** 与 **“Cloudflare CDN/Argo 优选穿透”** 的多维矩阵完整订阅；
3. **全平台多格式订阅支持**：原生输出通用 Base64 (`sub.txt`)、Clash Meta / Mihomo (`clash.yaml` 内置自动延迟优选策略组)、以及 Sing-box 客户端开箱即用规则 (`singbox.json`)；
4. **Cloudflare 全生态无缝集成**：
   - ☁️ **Argo 隧道穿透**：支持 Quick Tunnel (免CF账号临时穿透) 与 Named Token 固定隧道，破除 NAT、无公网 IP 限制；
   - 🛡️ **WARP 双栈网络与流媒体解锁**：基于 Sing-box 原生 WireGuard 用户态出站，**严格隔离住宅出口（家宽节点 100% 走纯正家宽，绝不被机房 WARP 劫持）**，绝不碰 Linux 宿主机路由表，SSH 零断联风险，原生解锁 Netflix、Disney+、OpenAI/ChatGPT；
   - ⚡ **CDN 三网优选 IP 测速**：内置电信/联通/移动亚太低延迟 Anycast 测速算法，**仅对 CDN 穿透节点生效，物理直连节点 100% 保持原生千兆 IP 直连**，彻底告别晚高峰减速；
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
ml sub      # 终端快速打印全协议节点矩阵与 HTTPS 全生态订阅卡片
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

### 4. 节点命名规范与完整订阅矩阵（导入客户端一目了然）

为了让用户在任何客户端（v2rayN、Clash Verge、Sing-box、Shadowrocket、Loon、Surge）导入后一目了然，所有节点名称均严格遵循**【出站属性 + 协议名称 + 传输特征 + 网络栈】**四维规范：

```
[出站属性] ──+── 🚀 [直连-极速] (走 VPS 物理公网网卡，极速千兆带宽，适合 4K、下载、游戏)
            ├── 🏠 [住宅-家宽] (走 Aimili 动态家宽池/SOCKS5，住宅纯净 IP，适合 ChatGPT、风控业务)
            └── ⛅ [CDN-优选/小黄云] (走 Cloudflare Anycast CDN，专供被封救急与全球免流破墙)

[协议架构] ──+── VLESS-Reality   ──> 【TCP-Vision·原生千兆】     借用顶级大厂证书，免申请免维护
            ├── Hysteria 2      ──> 【H3-UDP-Brutal·暴力抗丢包】 暴力抗丢包，端口跳跃防晚高峰QoS
            ├── TUIC v5         ──> 【H3-QUIC-0RTT·秒开首选】   原生BBR，移动端秒开首选
            ├── AnyTLS          ──> 【TCP-Padding·动态包长防探测】动态包长混淆，专防主动探测特征
            ├── VMess-xHTTP     ──> 【H2/H3-分块·分段防审查】    分段防审查，抗封锁利器
            └── VMess-WS-Argo   ──> 【Anycast优选·Cloudflare全球破墙】 隧道穿透，终极破墙急救
```

#### 完整节点矩阵清单：

##### 【A 组：IPv4 原生直连与住宅节点】（直连 VPS 物理 IPv4）
1. `🚀 [直连-极速·IPv4] VLESS-Reality【TCP-Vision·原生千兆】`
2. `🏠 [住宅-家宽·IPv4] VLESS-Reality【TCP-Vision·Aimili动态家宽】`
3. `🌪️ [直连-极速·IPv4] Hysteria 2【H3-UDP-Brutal·暴力抗丢包】`
4. `🏘️ [住宅-家宽·IPv4] Hysteria 2【H3-UDP-Brutal·恶劣线路家宽加速】`
5. `⚡ [直连-极速·IPv4] TUIC v5【H3-QUIC-0RTT·秒开首选】`
6. `🏡 [住宅-家宽·IPv4] TUIC v5【H3-QUIC-0RTT·晚高峰家宽流媒体】`
7. `🛡️ [直连-极速·IPv4] AnyTLS【TCP-Padding·动态包长防探测】`
8. `🌐 [住宅-家宽·IPv4] AnyTLS【TCP-Padding·特征防探测家宽】`
9. `☁️ [直连-极速·IPv4] VMess-xHTTP【H2/H3-分块·分段防审查】`
10. `🛋️ [住宅-家宽·IPv4] VMess-xHTTP【H2/H3-分块·动态家宽流】`

##### 【B 组：IPv6 原生直连节点】（当 VPS 具有 IPv6 时自动下发）
11. `🚀 [直连-极速·IPv6] VLESS-Reality【TCP-Vision·原生IPv6】`
12. `🌪️ [直连-极速·IPv6] Hysteria 2【H3-UDP-Brutal·IPv6暴力加速】`
13. `⚡ [直连-极速·IPv6] TUIC v5【H3-QUIC-0RTT·IPv6秒开】`
14. `☁️ [直连-极速·IPv6] VMess-xHTTP【H2/H3-分块·原生IPv6】`

##### 【C 组：Cloudflare CDN / Argo 穿透节点】（应用 Anycast 三网优选 IP 赋能）
15. `⛅ [CDN-优选IP·IPv4] VMess-WS-Argo【Anycast优选·Cloudflare全球破墙】`（连接地址使用测速优选 IP，SNI为Argo域名）
16. `⛅ [CDN-小黄云·IPv4] VMess-xHTTP【Cloudflare-CDN·分块免流破墙】`（走 Cloudflare 小黄云 CDN 443）
17. `⛅ [CDN-小黄云·IPv4] VLESS-WS-TLS【Cloudflare-CDN·小黄云破墙】`（经典 WebSocket 小黄云破墙）
18. `⛅ [CDN-小黄云·IPv6] VMess-xHTTP【Cloudflare-CDN-IPv6·分块穿透】`（Cloudflare Anycast IPv6 优选穿透）

---

### 5. WARP 智能分流与住宅/原生冲突彻底解决机制 (`ml warp`)

#### 核心冲突剖析：
- **用户顾虑**：如果开启了 WARP，访问 OpenAI、Netflix 会不会把我的【住宅家宽节点】也劫持到 Cloudflare 机房 IP？如果我的 VPS 原生 IP 本身就已经解锁了 Netflix/YouTube，被 WARP 覆盖了岂不是冲突甚至导致降权？
- **业界的解法与本项目实现**：
  1. **严格限定仅对【直连节点 (`direct-user`)】生效，绝对不劫持【住宅节点 (`residential-user`)】**：
     - 在 Sing-box 路由引擎中，`residential-user` 的流量全部通过 `auth_user: ["residential-user"]` 强制导向 `127.0.0.1:8500` 动态家宽出口；
     - 即使您在 `ml warp` 中开启了全局或流媒体分流，**住宅节点也 100% 走纯正家庭宽带 IP**，绝对不会被 WARP 降级为 Cloudflare 机房 IP！
  2. **细粒度自选解锁模式**：
     - `ml warp` 选项 `[1]` **仅解锁 OpenAI/ChatGPT**：仅对访问 ChatGPT 的流量走 WARP，保留您 VPS 原生的 Netflix、YouTube 优质原生 IP，完美解决冲突！
     - `ml warp` 选项 `[2]` **解锁 AI 与海外主流流媒体**：OpenAI + Netflix + Disney+ + TikTok 走 WARP，其余网站跑千兆直连。
     - `ml warp` 选项 `[4]` **一键关闭 WARP**：恢复 100% VPS 原生直连。

---

### 6. 测速工具 `ml cf` 保存的优选 IP 生效范围清单

#### 关键问答：测速后保存的 Anycast 优选 IP 会不会覆盖我的 VPS 物理公网 IP？
**绝对不会！** 优选 IP 的替换规则严格限定如下：

| 节点类型 | 是否使用 Anycast 优选 IP？ | 实际客户端连接地址 | 伪装 Host / SNI |
| :--- | :--- | :--- | :--- |
| **`🚀 [直连-极速]` 节点** | ❌ **绝不使用** | **您的 VPS 物理真实 IPv4/IPv6** | 原生配置（如 gateway.icloud.com） |
| **`🏠 [住宅-家宽]` 节点** | ❌ **绝不使用** | **您的 VPS 物理真实 IPv4/IPv6** | 原生配置（入站直连，出站走住宅） |
| **`⛅ [CDN-优选IP]` 节点** | ✅ **完全生效** | **Cloudflare Anycast 优选 IP (如 104.16.160.10)** | 您的 Argo 穿透域名 |
| **`⛅ [CDN-小黄云]` 节点** | ✅ **完全生效** | **Cloudflare Anycast 优选 IP (如 104.16.160.10)** | 开启小黄云的子域名（如 cdn.domain.com） |

---

### 7. Cloudflare DNS 双栈与子域名傻瓜式配置指南 (`ml dns`)

为彻底解决【开小黄云导致 Reality/Hy2/TUIC 报废与直连拖慢】的问题，当 VPS 拥有 IPv4 和 IPv6 双栈时，请在 Cloudflare 添加以下 4 条记录：

| 组别 | 记录类型 | 名称 (Subdomain) | 内容 (Content) | 代理状态 (Proxy Status) | 用途与作用 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **组一：直连与住宅极速域名** | **A** | `direct` | 您的 IPv4 地址 | **仅 DNS (灰云 / 必须关闭小黄云)** | 专供 Reality / Hy2 / TUIC / 住宅直连，享受 VPS 原生千兆极速 |
| **组一：直连与住宅极速域名** | **AAAA** | `direct` | 您的 IPv6 地址 | **仅 DNS (灰云 / 必须关闭小黄云)** | 专供 IPv6 极速直连 |
| **组二：破墙与CDN逃生域名** | **A** | `cdn` | 您的 IPv4 地址 | **已代理 (橙色小黄云 / 开启)** | 专供 VMess-WS、xHTTP、Argo 隧道，VPS 被封时 100% 救急 |
| **组二：破墙与CDN逃生域名** | **AAAA** | `cdn` | 您的 IPv6 地址 | **已代理 (橙色小黄云 / 开启)** | 专供 CDN IPv6 穿透 |

---

<a name="english"></a>

## English

### 1. System Overview

**Aimili VPN + Sing-box | Full-Protocol Dual-Stack Dual-Outbound Matrix**

This system combines the cutting-edge ingress of **Sing-box** with the global residential egress of **AimiliVPN**:
- **Ingress Proxy Matrix (Sing-box)**: Delivers 5 major protocols on ports 443 (TCP Reality & UDP Hy2), 8443 (UDP TUIC), 8444 (TCP AnyTLS), and 8445 (TCP VMess). Fully supports **IPv4 & IPv6 dual-stack**, using user-level authentication (`auth_user`) to achieve instantaneous zero-downtime dual-outbound routing.
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
ml sub      # Print full node matrix and HTTPS subscription URLs
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

### 4. Complete Node Matrix

#### [Group A: IPv4 Direct & Residential Nodes] (Physical VPS IPv4)
1. `🚀 [直连-极速·IPv4] VLESS-Reality【TCP-Vision·原生千兆】` (Direct Gigabit)
2. `🏠 [住宅-家宽·IPv4] VLESS-Reality【TCP-Vision·Aimili动态家宽】` (Residential ISP)
3. `🌪️ [直连-极速·IPv4] Hysteria 2【H3-UDP-Brutal·暴力抗丢包】` (Brutal Congestion)
4. `🏘️ [住宅-家宽·IPv4] Hysteria 2【H3-UDP-Brutal·恶劣线路家宽加速】` (Residential Brute)
5. `⚡ [直连-极速·IPv4] TUIC v5【H3-QUIC-0RTT·秒开首选】` (QUIC 0-RTT)
6. `🏡 [住宅-家宽·IPv4] TUIC v5【H3-QUIC-0RTT·晚高峰家宽流媒体】` (Residential QUIC)
7. `🛡️ [直连-极速·IPv4] AnyTLS【TCP-Padding·动态包长防探测】` (Packet Padding)
8. `🌐 [住宅-家宽·IPv4] AnyTLS【TCP-Padding·特征防探测家宽】` (Residential Padding)
9. `☁️ [直连-极速·IPv4] VMess-xHTTP【H2/H3-分块·分段防审查】` (Chunked HTTP)
10. `🛋️ [住宅-家宽·IPv4] VMess-xHTTP【H2/H3-分块·动态家宽流】` (Residential Chunked)

#### [Group B: IPv6 Direct Nodes] (Generated when VPS has native IPv6)
11. `🚀 [直连-极速·IPv6] VLESS-Reality【TCP-Vision·原生IPv6】`
12. `🌪️ [直连-极速·IPv6] Hysteria 2【H3-UDP-Brutal·IPv6暴力加速】`
13. `⚡ [直连-极速·IPv6] TUIC v5【H3-QUIC-0RTT·IPv6秒开】`
14. `☁️ [直连-极速·IPv6] VMess-xHTTP【H2/H3-分块·原生IPv6】`

#### [Group C: Cloudflare CDN & Argo Proxied Nodes] (Empowered by Anycast Clean IP)
15. `⛅ [CDN-优选IP·IPv4] VMess-WS-Argo【Anycast优选·Cloudflare全球破墙】`
16. `⛅ [CDN-小黄云·IPv4] VMess-xHTTP【Cloudflare-CDN·分块免流破墙】`
17. `⛅ [CDN-小黄云·IPv4] VLESS-WS-TLS【Cloudflare-CDN·小黄云破墙】`
18. `⛅ [CDN-小黄云·IPv6] VMess-xHTTP【Cloudflare-CDN-IPv6·分块穿透】`

---

### 5. WARP Routing & Residential Isolation Architecture

- **No Hijacking of Residential Nodes**:
  - Residential users (`residential-user`) are strictly routed to `127.0.0.1:8500`. They **NEVER** exit through WARP, preserving 100% genuine ISP residential IPs for anti-fraud bypassing.
- **Granular Unlock for Direct Nodes**:
  - `ml warp` Option 1: Unlock OpenAI/ChatGPT only (preserves native VPS IP for Netflix and YouTube);
  - `ml warp` Option 2: Unlock OpenAI + Netflix + Disney+ + TikTok;
  - `ml warp` Option 4: Disable WARP outbound.

---

### 6. Clean Anycast IP Scope

- **Applies ONLY to**: Nodes labeled with `⛅ [CDN-优选IP]` or `[CDN-小黄云]`;
- **NEVER modifies**: All `🚀 [直连-极速]` and `🏠 [住宅-家宽]` nodes, which 100% retain direct connections to your VPS physical IP.

---

### 7. Cloudflare Dual-Stack DNS 4-Record Setup Guide (`ml dns`)

- **`direct.yourdomain.com`**:
  - `A` -> IPv4 (**DNS Only / Grey Cloud**)
  - `AAAA` -> IPv6 (**DNS Only / Grey Cloud**)
  - *Purpose*: Uncapped gigabit speed for Reality, Hy2, TUIC, and Residential egress.
- **`cdn.yourdomain.com`**:
  - `A` -> IPv4 (**Proxied / Orange Cloud**)
  - `AAAA` -> IPv6 (**Proxied / Orange Cloud**)
  - *Purpose*: Censorship bypass emergency fallback for WebSocket, xHTTP, and Argo tunnels.

---

**Version: V1.4.2 (Sing-box Dual-Outbound Enterprise Full-Stack Suite)**
