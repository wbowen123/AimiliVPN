# Aimili VPN + Sing-box 双出站节点管理系统 🌐

Bilingual: [中文](#中文) | [English](#english)

本项目基于 AimiliVPN 深度定制，原生整合 **Sing-box** 现代化代理核心，在 Linux VPS 上实现：
1. **多协议公共住宅池管理**：统一采集与管理 OpenVPN、SoftEther、SSTP、L2TP 等多协议节点，提供持续可用性检测、真实连接延迟检测与 Web 管理；
2. **全协议双出站分流架构 (Dual-Outbound Matrix)**：单节点支持 **VLESS-Reality、Hysteria 2、TUIC v5、AnyTLS、VMess-xHTTP** 5 大主流协议，一键下发包含 **“原生 VPS 高速直连 (5个)”** 与 **“Aimili 动态住宅家宽穿透 (5个)”** 的 10 大节点完整订阅；
3. **全平台多格式订阅支持**：原生输出通用 Base64 (`sub.txt`)、Clash Meta / Mihomo (`clash.yaml` 内置自动延迟优选策略组)、以及 Sing-box 客户端开箱即用规则 (`singbox.json`)；
4. **Cloudflare 全生态无缝集成**：
   - ☁️ **Argo 隧道穿透**：支持 Quick Tunnel (免CF账号临时穿透) 与 Named Token 隧道，破除 NAT、无公网 IP 限制；
   - 🛡️ **WARP 双栈网络与流媒体解锁**：基于 Sing-box 原生 WireGuard 用户态出站，零侵入 VPS 主路由表，原生解锁 Netflix、Disney+、OpenAI/ChatGPT；
   - ⚡ **CDN 三网优选 IP 测速**：内置电信/联通/移动亚太低延迟 Anycast 测速算法，一键替换节点连接 IP，告别晚高峰减速；
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
ml          # 启动全新交互式双核心管理控制台（支持 19 项专业运维）
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
ml egress   # 配置住宅出口模式（内置Aimili家宽池 / 外接第三方商业SOCKS5）
ml status   # 查看 AimiliVPN 运行状态与当前活跃住宅节点
ml logs     # 查看 AimiliVPN 实时拨号与隧道日志
ml restart  # 重启 AimiliVPN 住宅网关
ml singbox  # Sing-box 核心管理（start/stop/restart/logs/status）
```

### 4. 高阶功能体系详解

#### (1) Cloudflare Argo 隧道穿透 (`ml argo`)
- **临时穿透 (Quick Tunnel)**：无需 Cloudflare 账号，自动拉起 cloudflared 并捕获 `https://*.trycloudflare.com` 穿透域名，直接穿透本地代理端口，无公网 IP 或 NAT 阻断下仍可顺畅破墙。
- **固定隧道 (Named Tunnel)**：直接输入 Cloudflare Zero Trust 申请的 Token，以 systemd 服务稳定常驻，域名永久固定。

#### (2) Cloudflare WARP 双栈网络与流媒体解锁 (`ml warp`)
- **用户态原生分流**：采用 Sing-box 原生 WireGuard 出站能力，**绝不篡改宿主机默认路由表**，绝不导致 VPS SSH 断联。
- **智能规则分流**：精准针对 Netflix、Disney+、OpenAI/ChatGPT、YouTube、TikTok 走 WARP 出口，其余流量保持原生千兆直连，兼顾极速与流媒体解锁。

#### (3) Cloudflare CDN 三网优选 IP 测速 (`ml cf`)
- 内置涵盖中国电信、中国联通、中国移动亚太低延迟 Anycast 优选段。
- 自动进行 443 端口 TCP 延迟与丢包率测速，自动排序并一键保存最优 IP，配合 SNI 域名伪装，彻底破解国内晚高峰 QoS 限速。

#### (4) HTML5 本地高保真伪装网站模版库 (`ml camo`)
- 提供 4 套无需外网依赖、纯本地加载的可交互真实站点：
  1. **现代科技云原生 SaaS 官网** (Aether Cloud 平台)
  2. **在线全功能开发者工具箱与计算器** (真实可算数、Base64 编解码)
  3. **极简极客技术博客** (Ray's Engineering Notes 架构手记)
  4. **经典 HTML5 2048 益智小游戏** (键盘/触屏真实可玩)
- 配合 Nginx 443 回退，彻底消除审查机构的主动探测风险。

#### (5) Telegram Bot 节点与告警即时推送 (`ml tg`)
- 配置 Bot Token 与 Chat ID 即可实现：
  - 一键将 10 大节点与全生态订阅推送到个人 Telegram；
  - 服务器公网 IP 变动时自动更新订阅并触发推送；
  - 核心进程（Sing-box / AimiliVPN）异常崩溃时实时告警。

#### (6) 定时系统自愈与内存深度清理 (`ml cron`)
- **每日凌晨 04:00 深度维护**：
  - `sync && echo 3 > /proc/sys/vm/drop_caches` 释放缓存，防止小内存 VPS (512MB/1GB) OOM；
  - 调用 HTTPS 权威时钟同步，消除时钟漂移；
  - 检测 SSL 证书有效期并自动续期；
  - 清理过期 journalctl 历史日志，杜绝磁盘打满。
- **每 15 分钟看门狗**：巡检核心服务并秒级自愈拉起。

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
ml          # Launch interactive dual-core management console (19 options)
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
ml egress   # Toggle residential egress (internal pool vs external SOCKS5)
ml status   # View AimiliVPN status and active residential IP
ml logs     # Tail real-time VPN dialer and tunnel logs
ml restart  # Restart AimiliVPN residential daemon
ml singbox  # Sing-box service management (start/stop/restart/logs/status)
```

### 4. Advanced Feature Matrix

1. **Cloudflare Argo Tunnel (`ml argo`)**:
   - Quick Tunnel (free temporary `*.trycloudflare.com` tunnel without CF account) & Named Tunnel (permanent token). Bypasses NAT & restrictive firewalls.
2. **Cloudflare WARP Dual-Stack Ingress (`ml warp`)**:
   - Implemented via Sing-box native WireGuard outbound without kernel modification or SSH routing disruption. Seamlessly unlocks OpenAI, Netflix, Disney+, and TikTok.
3. **Cloudflare Clean IP Selector (`ml cf`)**:
   - Measures TCP 443 round-trip time across global Anycast clusters (Telecom/Unicom/Mobile). Solves evening congestion on CF proxied nodes.
4. **HTML5 Camouflage Sites (`ml camo`)**:
   - Deploys 4 realistic, fully interactive HTML5 templates (SaaS Platform, Online Developer Tools & Calculator, Tech Blog, 2048 Game) to neutralize active probe attacks.
5. **Telegram Bot Dispatcher (`ml tg`)**:
   - Directly broadcasts node subscription links to your Telegram and sends instant push notifications upon VPS IP migration or core crashes.
6. **Self-Healing Cron Scheduler (`ml cron`)**:
   - Nightly 04:00 AM cache release (`drop_caches`), authoritative HTTPS clock sync, cert auto-renewal, and 15-minute process watchdog.

---

**Version: V1.4.0 (Sing-box Dual-Outbound Enterprise Full-Stack Suite)**
