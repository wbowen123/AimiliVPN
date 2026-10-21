# Aimili VPN + Sing-box 双出站节点管理系统 🌐

Bilingual: [中文](#中文) | [English](#english)

本项目基于 AimiliVPN 深度定制，原生整合 **Sing-box** 现代化代理核心，在 Linux VPS 上实现：
1. **多协议公共节点池管理**：统一采集与管理 OpenVPN、SoftEther、SSTP、L2TP 等多协议节点，提供持续可用性检测、真实连接延迟检测与 Web 管理；
2. **Sing-box 双出站分流架构 (Dual-Outbound)**：单端口 (443 / Reality) 下发包含 **“原生 VPS 高速直连”** 与 **“Aimili 住宅 IP 穿透”** 的双节点统一订阅；
3. **日常极速与风控破局兼得**：日常视频/下载跑满物理机千兆带宽，访问高风控站点一键无缝切换至全球住宅出口。

<a name="中文"></a>

## 中文

### 1. 系统名称与定位

**Aimili VPN + Sing-box｜双出站节点管理系统**

系统由两大核心组成：
- **前端代理接入（Sing-box）**：监听 443 端口，采用抗封锁能力出色的 VLESS + Reality 协议，通过用户鉴权（`auth_user`）实现毫秒级双出站分流。
- **后端住宅网桥（AimiliVPN）**：持续维护全球公共/住宅节点池，拨号建立虚拟隧道，并在 `127.0.0.1:8500` 提供 SOCKS5 出站网桥，使特定流量能以第三方住宅 IP 出站。

### 2. 端口架构

| 用途 | 端口 | 监听方式 | 说明 |
| --- | ---: | --- | --- |
| Sing-box 代理入站 (VLESS Reality) | `443/tcp` | 公网 | 核心代理入口，单端口下发双节点 |
| HTTPS 管理后台 | `8443/tcp` | 公网，Nginx 反代 `127.0.0.1:8501` | 可视化管理面板，支持国家/节点切换 |
| HTTPS 订阅入口 | `18443/tcp` | 公网，Nginx 静态托管 | 提供通用 Base64 订阅文件 |
| 备用订阅路径 | `8443/tcp` | 公网，`/sub/sub.txt` | 后台同端口备用订阅路径 |
| HTTP/SOCKS5 代理网桥 | `8500/tcp` | 仅本机 `127.0.0.1`（或白名单） | AimiliVPN 隧道出口网桥 |
| 管理后台内部服务 | `8501/tcp` | 仅本机 `127.0.0.1` | Python Web 服务，严禁暴露到公网 |

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
