# Aimili VPN + Sing-box 双出站节点管理系统 🌐

Bilingual: [中文](#中文) | [English](#english)

本项目基于 AimiliVPN 深度定制，原生整合 **Sing-box** 现代化代理核心，在 Linux VPS 上实现：
1. **多协议公共住宅池管理**：统一采集与管理 OpenVPN、SoftEther、SSTP、L2TP 等多协议节点，提供持续可用性检测、真实连接延迟检测与 Web 管理；
2. **全协议双出站分流架构 (Dual-Outbound Matrix)**：单节点支持 **VLESS-Reality、Hysteria 2、TUIC v5、AnyTLS、VMess-xHTTP** 5 大主流协议，一键下发包含 **“原生 VPS 高速直连 (5个)”** 与 **“Aimili 动态住宅家宽穿透 (5个)”** 的 10 大节点完整订阅；
3. **全平台多格式订阅支持**：原生输出通用 Base64 (`sub.txt`)、Clash Meta / Mihomo (`clash.yaml` 内置自动延迟优选策略组)、以及 Sing-box 客户端开箱即用规则 (`singbox.json`)；
4. **系统底层调优与智能伪装**：自动开启 Google BBR 与 TCP 网络栈缓冲区优化，本地自动对权威大厂域名执行 TLS 1.3 握手测速并智能优选最低延迟伪装 SNI。

<a name="中文"></a>

## 中文

### 1. 系统名称与定位

**Aimili VPN + Sing-box｜全协议双出站节点管理系统**

系统由两大核心组成：
- **前端多协议代理矩阵（Sing-box）**：监听 443 (TCP Reality & UDP Hy2)、8443 (UDP TUIC)、8444 (TCP AnyTLS)、8445 (TCP VMess)，通过用户鉴权（`auth_user`）实现毫秒级双出站分流。
- **后端住宅网桥（AimiliVPN）**：持续维护全球公共/住宅节点池，拨号建立虚拟隧道，并在 `127.0.0.1:8500` 提供 SOCKS5 出站网桥，使特定流量能以第三方住宅 IP 出站。

### 2. 端口与协议架构

| 协议 / 服务 | 端口 | 传输载体 | 说明 |
| :--- | :--- | :--- | :--- |
| **VLESS-Reality** | `443/tcp` | TCP + TLS Vision | 核心伪装入口，借用大厂证书免个人证书 |
| **Hysteria 2** | `443/udp` | UDP (Brutal) | 恶劣线路暴力加速，晚高峰不丢包 |
| **TUIC v5** | `8443/udp` | UDP / QUIC (BBR) | 原生 BBR 拥塞控制，0-RTT 极速秒开 |
| **AnyTLS** | `8444/tcp` | TCP (包长混淆) | 动态数据包长度填充，防主动探测特征 |
| **VMess-xHTTP** | `8445/tcp` | TCP (HTTP/3 分块) | 标准分段 HTTP 流，防封锁与审查 |
| **HTTPS 管理后台** | `8443/tcp` | TCP, Nginx 反代 8501 | 可视化管理面板，支持国家/节点切换 |
| **全格式订阅入口** | `18443/tcp` | TCP, Nginx 静态托管 | 提供 `sub.txt`、`clash.yaml`、`singbox.json` |
| **HTTP/SOCKS5 网桥** | `8500/tcp` | 本机 `127.0.0.1` | AimiliVPN 动态住宅隧道出口网桥 |

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
- **Sing-box 统一订阅链接**（支持一键导入主流客户端）；
- 两个节点的明文 `vless://` 分享链接。

#### 常用管理命令

系统提供全局快捷命令 `ml` 随时管理：
```bash
ml          # 启动全新交互式双核心管理控制台（支持查看节点、控制服务等）
ml sub      # 随时在终端快速打印双节点链接与 HTTPS 订阅卡片
ml web      # 查看网页控制面板地址、安全后缀、管理员账号与密码
ml status   # 查看 AimiliVPN 运行状态与当前活跃住宅节点
ml logs     # 查看 AimiliVPN 实时拨号与隧道日志
ml restart  # 重启 AimiliVPN 住宅网关
ml singbox  # Sing-box 核心管理（start/stop/restart/logs/status）

# 快速重新部署 Sing-box 核心或更新订阅
bash /opt/aimilivpn/scripts/setup_singbox.sh
# 快速查看订阅与节点
bash /opt/aimilivpn/scripts/show_nodes.sh
```

#### 完全卸载

```bash
ml uninstall
# 或
bash <(curl -Ls https://raw.githubusercontent.com/wbowen123/AimiliVPN/main/install.sh) uninstall
```

### 4. 快速使用与双节点订阅

1. **导入订阅**：
   - 复制安装完成后输出的 **HTTPS 订阅链接**：`https://你的域名或IP:18443/sub.txt`（或 `https://你的域名或IP:8443/sub/sub.txt`）；
   - 将链接导入到客户端（V2rayN、Clash Verge / Mihomo、Sing-box、Shadowrocket、Loon、Quantumult X 等）。
2. **节点选择与分流说明**：
   - **🚀 [VPS-直连] 原生千兆高速**：
     * 流量由您的 VPS 物理网卡直接送出；
     * 延迟最低（几十毫秒），跑满 VPS 物理带宽，适合 YouTube 4K/8K、Steam、大文件下载与日常访问。
   - **🏠 [VPS-住宅] Aimili穿透**：
     * 流量进入 VPS 后，由 Sing-box 自动分流转发至 `127.0.0.1:8500`，穿透 AimiliVPN 拨号建立的 VPN 隧道，以目标国家的住宅/家宽 IP 出站；
     * 适合访问 ChatGPT、Claude、特定海外流媒体、账号注册及高风控检测场景。
3. **切换住宅出口国家**：
   - 登录后台管理页面 `https://你的域名或IP:8443/安全后缀/`；
   - 在节点列表中按国家（美国、日本、英国等）、延迟筛选，点击“切换”；
   - AimiliVPN 会自动在新隧道验证成功后平滑切换，客户端无需重新连接，所有住宅节点的出站 IP 自动变为新国家。

### 5. HTTPS 访问规则

网页管理后台固定使用 **HTTPS + 8443**：
- **没有绑定域名**：使用 `https://服务器IP:8443/安全后缀/`，安装器提供自签名 HTTPS 证书，浏览器可能提示证书不受信任。
- **绑定域名后**：使用 `https://你的域名:8443/安全后缀/`。首次绑定该域名时自动申请并安装 Let's Encrypt 证书，后台自动续期。
- 绑定域名时，请先将域名 A/AAAA 解析到这台服务器，并确保公网 TCP 80 可用于 ACME 验证。

### 6. 节点检测与可用性

状态筛选说明：
| 状态 | 含义 |
| --- | --- |
| 全部节点 | 显示全部采集到的外部节点 |
| 待检测 | 尚未完成可用性验证，正在等待后台队列检测 |
| 检测中 | 当前正在建立真实隧道并执行联通性检测 |
| 可用节点 | 已经完成真实可用性验证，延迟为隧道建立后的实际延迟 |
| 失效节点 | 当前连接失败或网络不可达 |

### 7. 本地 HTTP/SOCKS5 代理网桥

代理固定监听 `127.0.0.1:8500`（或指定外部 IP）。默认账号为 `socks5`，密码为 `ilovestudy`。

测试本地代理连接：
```bash
curl --socks5-hostname socks5:ilovestudy@127.0.0.1:8500 https://api.ipify.org
```

### 8. 常见问题

* **网页出现 502 Bad Gateway**：
  通常表示 Nginx 正在运行，但内部 Python 服务 `127.0.0.1:8501` 正在启动或重启中。等待数秒后刷新，或运行 `systemctl status aimilivpn` 查看状态。
* **Sing-box 无法启动（443 端口冲突）**：
  检查是否有其他 Web 服务（如 Apache、其他 Xray 实例）占用了 443 端口：`ss -ltnp | grep :443`。
* **导入订阅后住宅节点连不上**：
  检查 AimiliVPN 后台是否已经成功连接至少一个活跃节点（首次部署可能需要 10~30 秒建立首个加密通道）。

---

<a name="english"></a>

## English

### 1. System Overview

**Aimili VPN + Sing-box | Dual-Outbound Node Management System**

This system combines the strengths of two engines:
- **Ingress Proxy (Sing-box)**: Listens on port 443 with VLESS + Reality protocol, providing high-speed and censorship-resistant client connections with instant user-based routing.
- **Egress Bridge (AimiliVPN)**: Manages a pool of global public/residential relay nodes (OpenVPN, SoftEther, SSTP, L2TP), providing automated failover and a local SOCKS5 proxy on `127.0.0.1:8500`.

### 2. Port Architecture

| Purpose | Port | Binding | Description |
| --- | ---: | --- | --- |
| Sing-box Inbound (VLESS Reality) | `443/tcp` | Public | Core proxy port delivering dual-node subscriptions |
| HTTPS Web Management | `8443/tcp` | Public (Nginx to `127.0.0.1:8501`) | Dashboard for country/node switching and monitoring |
| HTTPS Subscription | `18443/tcp` | Public | Serves Base64-encoded subscription files |
| Fallback Subscription Path | `8443/tcp` | Public (`/sub/sub.txt`) | Same-port HTTPS subscription alternative |
| HTTP/SOCKS5 Egress Bridge | `8500/tcp` | `127.0.0.1` (or allowlist) | AimiliVPN tunnel egress proxy |
| Internal Management | `8501/tcp` | Local only `127.0.0.1` | Backend daemon API, never expose publicly |

### 3. One-Click Installation

Repository: [wbowen123/AimiliVPN](https://github.com/wbowen123/AimiliVPN)

Run as root on your Linux VPS:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/wbowen123/AimiliVPN/main/install.sh)
```

The installer will guide you through:
1. Selecting **1. Install**;
2. Entering your domain (or press Enter for IP self-signed certificate);
3. Installing Sing-box core with automatic Reality keypair generation.

Full uninstall:

```bash
ml uninstall
# or
bash <(curl -Ls https://raw.githubusercontent.com/wbowen123/AimiliVPN/main/install.sh) uninstall
```

### 4. Dual-Node Subscription Usage

1. **Import Subscription**:
   - Copy the subscription URL printed by the installer: `https://YOUR_DOMAIN_OR_IP:18443/sub.txt` (or `https://YOUR_DOMAIN_OR_IP:8443/sub/sub.txt`).
   - Import into any VLESS-Reality compatible client (V2rayN, Clash Verge / Mihomo, Sing-box, Shadowrocket, etc.).
2. **Node Differences**:
   - **🚀 [VPS-Direct]**: Exits through your VPS's physical network interface. Maximizes bandwidth (gigabit speeds) and minimizes latency. Ideal for YouTube 4K/8K, downloads, and general browsing.
   - **🏠 [VPS-Residential]**: Routed via `127.0.0.1:8500` through AimiliVPN's active tunnel. Exits through global residential/ISP IPs. Ideal for ChatGPT, Claude, streaming, and anti-fraud bypassing.
3. **Switching Residential Country**:
   - Open the web dashboard at `https://YOUR_IP:8443/SECRET_PATH/`.
   - Select any country (US, JP, UK, etc.) and click **Switch**. AimiliVPN establishes the new tunnel and smoothly updates the egress without interrupting your client connection.

---

**Version: V1.2.0 (Sing-box Dual-Outbound Edition)**
