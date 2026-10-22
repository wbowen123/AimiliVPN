# Aimili VPN + Sing-box 双出站节点管理系统 🌐

Bilingual: [中文](#中文) | [English](#english)

本项目基于 AimiliVPN 深度定制，原生整合 **Sing-box** 现代化代理核心，在 Linux VPS 上实现：
1. **多协议公共住宅池管理**：统一采集与管理 OpenVPN、SoftEther、SSTP、L2TP 等多协议节点，提供持续可用性检测、真实连接延迟检测与 Web 管理；
2. **全协议双出站分流架构 (Dual-Outbound Matrix)**：单节点支持 **VLESS-Reality、Hysteria 2、TUIC v5、AnyTLS、VMess-xHTTP** 5 大主流协议，一键下发包含 **“原生 VPS 高速直连 (5个)”** 与 **“Aimili 动态住宅家宽穿透 (5个)”** 的 10 大节点完整订阅；
3. **全平台多格式订阅支持**：原生输出通用 Base64 (`sub.txt`)、Clash Meta / Mihomo (`clash.yaml` 内置自动延迟优选策略组)、以及 Sing-box 客户端开箱即用规则 (`singbox.json`)；
4. **工业级可靠性加固 (借鉴 singbox-lite 架构)**：
   - 🛡️ **GOMEMLIMIT 软内存限制**：针对 128MB/512MB/1GB 等小内存/NAT VPS，动态测算 Go 堆内存配额，根除 OOM 崩溃；
   - 🔄 **事务快照与原子回滚**：配置更新遵循“备份 $\to$ 临时写入 $\to$ sing-box check 预检 $\to$ 原子替换 $\to$ 健康监控 $\to$ 异常秒级回滚”闭环；
   - ⏱️ **高精度时间同步与补偿**：内置 `check_time_sync.sh` 对齐权威 HTTPS 响应头，消除 $>15$ 秒时钟漂移导致的 Reality 握手超时；
   - 🐳 **容器虚拟化自适应**：智能探测 Docker/LXC 容器环境，非特权模式自动降级权能要求，确保平顺拉起；
   - 🌪️ **端口跳跃与 Salamander 混淆**：Hysteria 2 支持 UDP 40000-50000 端口范围映射与 Salamander 混淆，破解晚高峰运营商 QoS 限速；
   - 🏠 **住宅出口双模切换**：支持随时在“AimiliVPN 内置动态家宽池”与“用户自有第三方商业 SOCKS5 代理”间无缝切换。

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

安装脚本交互提示：
1. **安装选项**：输入 `1` 安装；
2. **域名配置**：已有解析到本机的域名请输入，无域名可直接回车（自动使用 VPS 公网 IP 自签证书）；
3. **Sing-box 核心**：回车默认安装 Sing-box（推荐），回车使用默认伪装域名 `gateway.icloud.com`。

安装完成后，终端将自动输出：
- HTTPS 网页管理后台地址、账号、密码及安全路径；
- **全格式订阅入口**（`sub.txt`、`clash.yaml`、`singbox.json`、`nodes.txt`）；
- 10 大节点矩阵完整链接。

#### 常用管理命令

系统提供全局快捷命令 `ml` 随时管理：
```bash
ml          # 启动全新交互式双核心管理控制台（支持查看节点、控制服务等）
ml sub      # 终端快速打印 10 大节点矩阵与 HTTPS 全生态订阅卡片
ml web      # 查看网页控制面板地址、安全后缀、管理员账号与密码
ml test     # 全自动节点连通性与健康诊断（排查 -1 超时、端口监听与阻断根因）
ml core     # Sing-box 内核管理（一键升级最新稳定版、选择历史版本）
ml cert     # 域名 SSL 证书管理（申请/续期/ZeroSSL/Cloudflare DNS API 免80端口）
ml egress   # 配置住宅出口模式（内置Aimili家宽池 / 外接第三方商业SOCKS5）
ml status   # 查看 AimiliVPN 运行状态与当前活跃住宅节点
ml logs     # 查看 AimiliVPN 实时拨号与隧道日志
ml restart  # 重启 AimiliVPN 住宅网关
ml singbox  # Sing-box 核心管理（start/stop/restart/logs/status）

# 快速重新部署 Sing-box 核心或更新订阅
bash /opt/aimilivpn/scripts/setup_singbox.sh
```

#### 完全卸载

```bash
ml uninstall
# 或
bash <(curl -Ls https://raw.githubusercontent.com/wbowen123/AimiliVPN/main/install.sh) uninstall
```

### 4. 快速使用与 10 大节点订阅矩阵

1. **导入订阅**：
   - 复制安装完成后输出的 **HTTPS 订阅链接**：`https://你的域名或IP:18443/sub.txt`（或 `https://你的域名或IP:8443/sub/sub.txt`）；
   - **Clash 专属订阅**：`https://你的域名或IP:18443/clash.yaml`（内置自动延迟优选与策略组）；
   - **Sing-box 专属订阅**：`https://你的域名或IP:18443/singbox.json`；
   - 将链接导入到客户端（V2rayN、Clash Verge / Mihomo、Sing-box、Shadowrocket、Loon、Quantumult X 等）。
2. **节点选择与分流说明**：
   - **🚀 [直连-极速] (5个协议)**：
     * 流量由您的 VPS 物理网卡直接送出；
     * 延迟最低（几十毫秒），跑满 VPS 物理千兆带宽，适合 YouTube 4K/8K、Steam、大文件下载与日常访问。
   - **🏠 [住宅-家宽] (5个协议)**：
     * 流量进入 VPS 后，由 Sing-box 自动分流转发至 `127.0.0.1:8500`（或配置的外部 SOCKS5 落地代理），以目标国家的住宅/家宽 IP 出站；
     * 适合访问 ChatGPT、Claude、特定海外流媒体、账号注册及高风控检测场景。
3. **切换住宅出口国家**：
   - 登录后台管理页面 `https://你的域名或IP:8443/安全后缀/`；
   - 在节点列表中按国家（美国、日本、英国等）、延迟筛选，点击“切换”；
   - AimiliVPN 会自动在新隧道验证成功后平滑切换，客户端无需重新连接，所有住宅节点的出站 IP 自动变为新国家。

### 5. HTTPS 与域名证书管理

- **没有绑定域名**：使用 `https://服务器IP:8443/安全后缀/`，安装器自动提供 ECC P-256 IP 自签名证书。
- **绑定或更换域名**：随时在终端运行 `ml cert`，支持：
  1. **HTTP-01 模式**：通过 80 端口一键申请 Let's Encrypt / ZeroSSL 官方权威证书；
  2. **Cloudflare DNS API 模式**：输入 Cloudflare API Token 纯 DNS 解析申请，**无需开放 80 端口，并支持 `*.domain.com` 泛域名通配符证书**；
  3. **强制续期与自动重载**：证书更新后自动分发至 Nginx 与 Sing-box 并热重载，永不过期。

### 6. 常见问题与客户端显示 -1 排查

* **客户端测试节点显示 -1 (超时)**：
  - 请立即运行 `ml test` 执行全自动化诊断；
  - **最常见原因**：云服务商（AWS Lightsail、Oracle Cloud、阿里云、腾讯云等）控制台的安全组未开放入站端口。请在云后台放行 TCP `443, 8444, 8445, 18443` 和 UDP `443, 8443, 40000-50000`；
  - 若仅 `[住宅-家宽]` 报 -1，表示 AimiliVPN 正在拨号或切换节点，运行 `ml logs` 查看拨号进度或后台切换可用节点。
* **网页出现 502 Bad Gateway**：
  - 通常表示内部 Python 服务 `127.0.0.1:8501` 正在启动中，数秒后刷新即可。

---

<a name="english"></a>

## English

### 1. System Overview

**Aimili VPN + Sing-box | Full-Protocol Dual-Outbound Node Management Matrix**

This system combines the cutting-edge ingress of **Sing-box** with the global residential egress of **AimiliVPN**:
- **Ingress Proxy Matrix (Sing-box)**: Delivers 5 major protocols on ports 443 (TCP Reality & UDP Hy2), 8443 (UDP TUIC), 8444 (TCP AnyTLS), and 8445 (TCP VMess). Uses user-level authentication (`auth_user`) to achieve instantaneous zero-downtime dual-outbound routing.
- **Residential Egress Bridge (AimiliVPN)**: Dynamically maintains global public/residential relay tunnels (OpenVPN, SoftEther, SSTP, L2TP), providing a local SOCKS5 bridge on `127.0.0.1:8500` or integrating third-party commercial residential proxies.

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
ml          # Launch interactive dual-core management console
ml sub      # Print 10-node matrix and HTTPS subscription URLs
ml web      # Display web dashboard URL, secret path, and credentials
ml test     # Run automated health check & troubleshooting for -1 errors
ml core     # Sing-box core manager (upgrade to latest, switch versions)
ml cert     # SSL/TLS cert manager (HTTP-01, Cloudflare DNS API, force renew)
ml egress   # Toggle residential egress (internal pool vs external SOCKS5)
ml status   # View AimiliVPN status and active residential IP
ml logs     # Tail real-time VPN dialer and tunnel logs
ml restart  # Restart AimiliVPN residential daemon
ml singbox  # Sing-box service management (start/stop/restart/logs/status)
```

#### Complete Uninstall

```bash
ml uninstall
# or
bash <(curl -Ls https://raw.githubusercontent.com/wbowen123/AimiliVPN/main/install.sh) uninstall
```

### 4. 10-Node Matrix & Subscription Links

- **General Base64 Subscription**: `https://YOUR_DOMAIN_OR_IP:18443/sub.txt`
- **Clash Meta / Mihomo Subscription**: `https://YOUR_DOMAIN_OR_IP:18443/clash.yaml` (Built-in auto-latency selector groups)
- **Sing-box Client Subscription**: `https://YOUR_DOMAIN_OR_IP:18443/singbox.json`

Each subscription delivers:
1. **🚀 [Direct-Gigabit] (5 nodes)**: Exits through VPS physical interface. Uncapped gigabit bandwidth for YouTube 4K/8K, gaming, and downloads.
2. **🏠 [Residential-ISP] (5 nodes)**: Routed via residential tunnel. Exits through genuine residential IPs for ChatGPT, Claude, streaming, and anti-fraud bypassing.

---

**Version: V1.3.0 (Sing-box Dual-Outbound Enterprise Hardened)**

