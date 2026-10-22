# Aimili VPN + Sing-box 双出站节点管理系统 🌐

Bilingual: [中文](#中文) | [English](#english)

本项目基于 AimiliVPN 深度定制，原生整合 **Sing-box** 现代化代理核心，在 Linux VPS 上实现：
1. **模块化排列组合一键部署 (Modular Permutation Installer)**：安装第 1 步提供清晰交互式选项，支持【全套旗舰版】、【仅原生直连五协议】、【仅Aimili动态住宅家宽网桥】、【直连+自适应WARP】、【直连+动态家宽】、【仅订阅分发中心】及【高级自定义按需勾选】，满足不同配置 VPS 的极致轻量与全能需求；
2. **Cloudflare WARP 自适应流媒体与 AI 智能免装引擎**：基于 Sing-box 原生 WireGuard 用户态出站，安装时自动探测 IPv4/IPv6 原生 IP 解锁能力。**若原生 IP 已 100% 解锁 ChatGPT/Netflix/Disney+/TikTok，则智能放弃安装 WARP**，保持纯千兆直连；若部分受阻，则精准针对未解锁网站挂载 WARP，**严格隔离住宅出口（家宽 100% 走纯正家宽，绝不被机房 WARP 劫持）**；
3. **全协议双栈双出站分流架构 (Dual-Stack Dual-Outbound Matrix)**：单节点支持 **VLESS-Reality、Hysteria 2、TUIC v5、AnyTLS、VMess-xHTTP** 5 大主流协议，全面支持 **IPv4 与 IPv6 原生双栈**，一键下发包含 **“原生 VPS 高速直连”**、**“Aimili 动态住宅家宽穿透”** 与 **“Cloudflare CDN/Argo 优选穿透”** 的 18 节点双栈矩阵完整订阅；
4. **全生态全格式聚合订阅与终端扫码**：原生输出通用 Base64 (`sub.txt`)、Sing-box 原生 1.10+ JSON (`singbox.json` 内置 Smart-DNS 与分流规则)、Clash Meta / Mihomo (`clash.yaml` 内置自动测速优选与故障转移策略组) 及明文单节点列表 (`nodes.txt`)；部署完成时直接在终端渲染 **ASCII 双色二维码**，手机客户端（小火箭 / Sing-box）扫码一键导入；
5. **节点健康状态与端口连通性实时自检**：安装结束时全自动对 VLESS-Reality (443)、Hysteria 2 (443)、TUIC (8443)、AnyTLS (8444)、VMess (8445)、Aimili SOCKS5 (8500)、Nginx 订阅 (18443) 展开端口监听与链路状态诊断，即时输出 `[ OK ]` 健康清单；
6. **脚本智能更新与配置平滑迁移系统 (`ml update`)**：一键检测 GitHub 仓库最新 Commit 与版本，展示前后版本对比、更新内容日志、文件变动统计与配置零丢失安全说明，支持交互式确认是否升级，升级过程自动备份现有配置并平滑热重载；
7. **Cloudflare 全生态无缝集成**：
   - ☁️ **Argo 隧道穿透**：支持 Quick Tunnel (免CF账号临时穿透) 与 Named Token 固定隧道，破除 NAT、无公网 IP 限制；
   - ⚡ **CDN 三网优选 IP 测速**：内置电信/联通/移动亚太低延迟 Anycast 测速算法，**仅对 CDN 穿透节点生效，物理直连节点 100% 保持原生千兆 IP 直连**；
   - 📖 **子域名隔离傻瓜向导 (`ml dns`)**：通过直连子域名（灰云）与破墙子域名（橙色小黄云）物理隔离，彻底解决开小黄云拖慢直连与家宽的问题；
8. **主动探测防御与自动化运维**：
   - 🎭 **HTML5 高保真本地伪装库**：内置科技云 SaaS、开发者工具箱/计算器、极客博客、2048 小游戏等 4 套可交互模板，完美抵御主动嗅探；
   - 🤖 **Telegram Bot 即时推送**：支持节点订阅一键下发至 TG、公网 IP 漂移告警、核心进程崩溃拉起告警；
   - ⏰ **定时系统自愈与内存清理**：每日凌晨 4 点强制内核缓存释放 (`drop_caches`)、权威 HTTPS 时钟校准、15分钟进程看门狗；
9. **工业级可靠性加固**：
   - 🛡️ **GOMEMLIMIT 软内存限制**：针对 128MB/512MB/1GB 等小内存/NAT VPS，动态测算 Go 堆内存配额，根除 OOM 崩溃；
   - 🔄 **事务快照与原子回滚**：配置更新遵循“备份 $\to$ 临时写入 $\to$ sing-box check 预检 $\to$ 原子替换 $\to$ 健康监控 $\to$ 异常秒级回滚”闭环；
   - ⏱️ **高精度时间同步与补偿**：内置 `check_time_sync.sh` 对齐权威 HTTPS 响应头，消除 $>15$ 秒时钟漂移导致的握手超时；
   - 🌪️ **端口跳跃与 Salamander 混淆**：Hysteria 2 支持 UDP 40000-50000 端口范围映射与 Salamander 混淆，破解晚高峰运营商 QoS 限速。

<a name="中文"></a>

## 中文

### 1. 系统名称与定位

**Aimili VPN + Sing-box｜全协议双栈双出站节点管理系统 (V1.4.8)**

系统由三大模块组成：
- **前端多协议代理矩阵（Sing-box）**：监听 443 (TCP Reality & UDP Hy2)、8443 (UDP TUIC)、8444 (TCP AnyTLS)、8445 (TCP VMess)，通过用户鉴权（`auth_user`）实现毫秒级双出站分流。
- **后端住宅网桥（AimiliVPN）**：持续维护全球公共/住宅节点池，拨号建立虚拟隧道，并在 `127.0.0.1:8500` 提供 SOCKS5 出站网桥；亦可外接第三方住宅/落地代理。
- **全生态订阅分发与 Web 控制中心（Nginx）**：在 18443 端口集中托管 `sub.txt`、`singbox.json`、`clash.yaml`、`nodes.txt`，并在 8443 端口提供带防探测随机后缀的可视化管理面板。

---

### 2. 模块化排列组合安装模式

在安装脚本第一步，系统提供详细的排列组合交互选项，用户可按需选择：

| 选项编号 | 模式名称 | 包含组件 | 内存开销 | 适用场景 |
| :--- | :--- | :--- | :--- | :--- |
| **[1] (默认推荐)** | **🌟 全套旗舰尊享版** | 原生直连五协议 + Aimili动态家宽 + 自适应WARP + 伪装站 + 全格式聚合订阅 | ~150MB | 需要兼顾千兆低延迟极速、流媒体与AI完美解锁、跨境抗封锁的全能用户 |
| **[2]** | **🚀 仅安装 极速原生直连代理矩阵** | VLESS-Reality / Hysteria 2 / TUIC v5 / AnyTLS / VMess-xHTTP | **< 50MB** | 搬瓦工/甲骨文低配 VPS，不跑家宽后台，CPU零空载，追求极致轻量与极速看 4K |
| **[3]** | **🏠 仅安装 Aimili 动态住宅家宽网桥** | SOCKS5 127.0.0.1:8500 虚拟隧道池 + 8443 可视化管理控制台 | ~80MB | 已有自建节点（如 Xray/九合一），仅需在 VPS 上增设动态住宅出口落地 |
| **[4]** | **⚡ 组合: 原生直连 + 自适应 WARP 解锁** | Sing-box 原生五协议 + Cloudflare WARP 自适应解锁引擎 (不含家宽) | ~60MB | 原生 IP 被流媒体阻断但无需家宽轮转，兼顾低开销与 100% 流媒体/AI 原生解锁 |
| **[5]** | **🌐 组合: 原生直连 + Aimili 动态住宅家宽** | Sing-box 原生五协议 + Aimili 动态住宅网桥 (不含 WARP) | ~140MB | 直连走机房 IP，住宅走真实家宽，无需 Cloudflare 介入，保证原生与住宅 IP 纯洁度 |
| **[6]** | **📦 仅安装 独立聚合订阅系统与 Web 后台** | Nginx 18443 订阅中心 (sub/clash/singbox) + 8443 HTTPS 面板 | ~30MB | 仅用于托管现有节点或作为多格式订阅转换分发服务器 |
| **[7]** | **🛠️ 自定义高级组合自由勾选** | 交互式自选: ①直连五协议 ②动态家宽 ③自适应WARP ④伪装站 ⑤BBR优化 | 按需 | 高级极客自定义安装组合 |
| **[8]** | **🗑️ 完全卸载 AimiliVPN 及所有关联组件** | 彻底清理服务、端口放行、网卡、路由表与文件 | 0MB | 干净无残留卸载 |

---

### 3. WARP 自适应智能分流与免装机制 (`ml warp auto`)

针对传统 WARP 脚本盲目安装导致测速下降、延迟增大及误劫持住宅出口的顽疾，本项目实现了**业界首创的自适应智能免装机制**：

```
[安装时触发自适应探测 (ml warp auto)]
           │
           ├──> 依次测试当前 VPS 原生 IPv4 / IPv6 对各大主流平台的连通性:
           │     1. OpenAI / ChatGPT (chatgpt.com / API cookie test)
           │     2. Netflix (netflix.com/title/80018499 非自制剧全量片库)
           │     3. Disney+ (disneyplus.com 国际版)
           │     4. TikTok (tiktok.com 国际短视频)
           │     5. YouTube (全球边缘 CDN)
           │
           ├──> 【场景 A: 原生已 100% 全部解锁】
           │     🎉 决策: 自动放弃 / 跳过安装 WARP 出站！
           │     🚀 优势: 100% 保持 VPS 纯物理千兆直连，零中转损耗、零 Anycast 延迟抖动！
           │
           └──> 【场景 B: 原生存在部分受阻】(例如: OpenAI 封锁，但 Netflix 原生解锁)
                 ⚠️ 决策: 仅针对未解锁网站精准生成 WireGuard 用户态出站规则！
                 💡 优势: 
                   - OpenAI 自动切入 Cloudflare WARP 虚拟出口原生解锁；
                   - Netflix / YouTube 依然 100% 走 VPS 原生千兆极速，看剧速度绝不受损；
                   - 🛡️ 安全红线: 严格限定 auth_user: ["direct-user"]，住宅家宽节点绝对不走 WARP！
```

---

### 4. 端口与协议架构

| 协议 / 服务 | 端口 | 传输载体 | 说明 |
| :--- | :--- | :--- | :--- |
| **VLESS-Reality** | `443/tcp` | TCP + TLS Vision | 核心伪装入口，借用顶级大厂证书免个人证书 |
| **Hysteria 2** | `443/udp` (跳跃: 40000-50000) | UDP (Brutal + Salamander) | 恶劣线路暴力抗丢包，支持端口跳跃与混淆防 QoS |
| **TUIC v5** | `8443/udp` | UDP / QUIC (BBR) | 原生 BBR 拥塞控制，0-RTT 极速秒开 |
| **AnyTLS** | `8444/tcp` | TCP (包长混淆) | 动态数据包长度填充，防主动探测特征 |
| **VMess-xHTTP** | `8445/tcp` | TCP (HTTP/3 分块) | 标准分段 HTTP 流，防封锁与审查 |
| **HTTPS 管理后台** | `8443/tcp` | TCP, Nginx 反代 8501 | 可视化管理面板，支持国家/节点切换与安全后缀 |
| **全格式订阅入口** | `18443/tcp` | TCP, Nginx 静态托管 | 提供 `sub.txt`、`clash.yaml`、`singbox.json`、`nodes.txt` |
| **住宅出站网桥** | `8500/tcp` | 本机 `127.0.0.1` | 内置 Aimili 动态家宽池或外部第三方 SOCKS5 落地 |

---

### 5. 一键部署与管理

仓库地址：[wbowen123/AimiliVPN](https://github.com/wbowen123/AimiliVPN)

以 root 用户在 Linux VPS（Ubuntu / Debian / CentOS / Alpine / RHEL 等）上执行：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/wbowen123/AimiliVPN/main/install.sh)
```

#### 全局快捷命令 `ml`

```bash
ml          # 启动全新交互式双核心管理控制台（支持 21 项专业运维）
ml sub      # 终端打印全协议 18 节点矩阵、全格式聚合订阅卡片与扫码二维码
ml qr       # 📱 终端直接渲染 ASCII 双色二维码 (手机小火箭 / Sing-box 扫码一键导入)
ml web      # 查看网页控制面板地址、安全后缀、管理员账号与密码
ml test     # 全自动节点连通性与健康诊断（排查 -1 超时、端口监听与阻断根因）
ml core     # Sing-box 内核管理（一键升级最新稳定版、选择历史版本）
ml cert     # 域名 SSL 证书管理（申请/续期/ZeroSSL/Cloudflare DNS API 免80端口）
ml argo     # Cloudflare Argo 隧道穿透（免CF账号临时穿透/固定Token穿透）
ml warp     # Cloudflare WARP 双栈自适应解锁（auto自适应探测 / ai / stream / off）
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

---

### 6. 全生态多格式聚合订阅与扫码指南

系统在 `https://你的域名或IP:18443/` 提供全客户端适配的订阅：

1. **🌟 Base64 通用自适应订阅 (`/sub.txt`)**：
   - 适配客户端：**Shadowrocket (小火箭)**、**v2rayN**、**Loon**、**Surge**、**Quantumult X**；
   - 支持客户端自适应解析节点类型与混淆参数。
2. **📦 Sing-box 原生 1.10+ JSON 订阅 (`/singbox.json`)**：
   - 适配客户端：**Sing-box 官方客户端 (Android / iOS / Windows / macOS)**；
   - 原生内置 Smart-DNS 分流规则、本地直连与 `🎯 手动选择`、`🚀 极速原生 (自动优选)`、`🏠 住宅家宽 (自动优选)`、`⚡ 故障转移` 策略组，开箱即用无需转换。
3. **🐱 Clash Meta (Mihomo) YAML 订阅 (`/clash.yaml`)**：
   - 适配客户端：**Clash Verge Rev**、**Mihomo Party**、**Clash Nyanpasu**、**CFW**；
   - 内置健康测速分组（Urltest 自动选择延迟最低节点）与故障转移分组（Fallback 自动剔除异常节点）。
4. **📄 Plaintext 原始节点列表 (`/nodes.txt`)**：
   - 纯文本单链接格式，便于手动复制单节点到剪贴板或单独分享给朋友。
5. **📱 终端 ASCII 二维码扫码 (`ml qr` 或 `ml sub`)**：
   - 部署完成或在终端运行 `ml qr`，屏幕立即打印高对比度半高字符二维码；
   - 手机打开 Shadowrocket 或 Sing-box 扫描屏幕即可自动识别并批量导入 18 个节点，彻底告别手动复制长链接的繁琐！

---

### 7. 完整 18 节点双栈矩阵清单

所有节点名称均严格遵循**【出站属性 + 协议名称 + 传输特征 + 网络栈】**四维规范：

#### 【A 组：IPv4 原生直连与住宅节点】（直连 VPS 物理 IPv4）
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

#### 【B 组：IPv6 原生直连节点】（当 VPS 具有 IPv6 时自动下发）
11. `🚀 [直连-极速·IPv6] VLESS-Reality【TCP-Vision·原生IPv6】`
12. `🌪️ [直连-极速·IPv6] Hysteria 2【H3-UDP-Brutal·IPv6暴力加速】`
13. `⚡ [直连-极速·IPv6] TUIC v5【H3-QUIC-0RTT·IPv6秒开】`
14. `☁️ [直连-极速·IPv6] VMess-xHTTP【H2/H3-分块·原生IPv6】`

#### 【C 组：Cloudflare CDN / Argo 穿透节点】（应用 Anycast 三网优选 IP 赋能）
15. `⛅ [CDN-优选IP·IPv4] VMess-WS-Argo【Anycast优选·Cloudflare全球破墙】`（连接地址使用测速优选 IP，SNI为Argo域名）
16. `⛅ [CDN-小黄云·IPv4] VMess-xHTTP【Cloudflare-CDN·分块免流破墙】`（走 Cloudflare 小黄云 CDN 443）
17. `⛅ [CDN-小黄云·IPv4] VLESS-WS-TLS【Cloudflare-CDN·小黄云破墙】`（经典 WebSocket 小黄云破墙）
18. `⛅ [CDN-小黄云·IPv6] VMess-xHTTP【Cloudflare-CDN-IPv6·分块穿透】`（Cloudflare Anycast IPv6 优选穿透）

---

### 8. Cloudflare DNS 双栈与子域名傻瓜式配置指南 (`ml dns`)

为彻底解决【开小黄云导致 Reality/Hy2/TUIC 报废与直连拖慢】的问题，当 VPS 拥有 IPv4 和 IPv6 双栈时，请在 Cloudflare 添加以下 4 条记录：

| 组别 | 记录类型 | 名称 (Subdomain) | 内容 (Content) | 代理状态 (Proxy Status) | 用途与作用 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **组一：直连与住宅极速域名** | **A** | `direct` | 您的 IPv4 地址 | **仅 DNS (灰云 / 必须关闭小黄云)** | 专供 Reality / Hy2 / TUIC / 住宅直连，享受 VPS 原生千兆极速 |
| **组一：直连与住宅极速域名** | **AAAA** | `direct` | 您的 IPv6 地址 | **仅 DNS (灰云 / 必须关闭小黄云)** | 专供 IPv6 极速直连 |
| **组二：破墙与CDN逃生域名** | **A** | `cdn` | 您的 IPv4 地址 | **已代理 (橙色小黄云 / 开启)** | 专供 VMess-WS、xHTTP、Argo 隧道，VPS 被封时 100% 救急 |
| **组二：破墙与CDN逃生域名** | **AAAA** | `cdn` | 您的 IPv6 地址 | **已代理 (橙色小黄云 / 开启)** | 专供 CDN IPv6 穿透 |

---

### 9. 全套工程化最佳实践优化建议 (Architecture Recommendations)

| 优化维度 | 现状与已实现能力 | 进阶运营与全套实操建议 |
| :--- | :--- | :--- |
| **1. 双栈 DNS 物理隔离** | 已内置 `ml dns` 指向指引，区分灰云（直连）与橙云（破墙） | **建议严格落实 4 条 DNS 记录**：`direct` 解析真实 IP4/V6 (关小黄云)，`cdn` 解析真实 IP4/V6 (开小黄云)，绝不将所有流量混杂在单一域名下。系统在生成订阅时会自动探测 `direct.<domain>` 并实现免配置隔离！ |
| **2. 晚高峰抗 QoS 阻断** | 已支持 UDP 40000-50000 端口跳跃 + Salamander 混淆 | 遇到个别地区运营商严重扼杀 UDP 443 时，生成的客户端订阅内建 **`🛡️ 晚高峰抗QoS (TCP优先)`** 自动策略组，优先使用 `VLESS-Reality` (TCP)、`AnyTLS` 与 `VMess`；亦可开启 Hysteria 2 多端口跳跃。 |
| **3. 内存与稳定性保护** | 已部署 GOMEMLIMIT 软上限计算 + 每日凌晨 4 点 drop_caches 释放缓存 | 低配小内存（如 512MB/1GB VPS）在安装向导与 `ml cron` 菜单中会自动高亮告警，**建议默认启用看门狗调度任务**，彻底根绝长期运行缓存堆积导致的 OOM 假死。 |
| **4. 证书全自动维护** | 已集成 10年免维护 IP 证书 + 域名 ACME HTTP/DNS-01 续签 | 若使用域名且未开 80 端口（或 80 端口被运营商封锁），可通过安装向导或 `ml cert` 配置 Cloudflare API Token 走 **DNS-01 验证**，实现无需任何外网 80 端口即可静默自动申请与续签。 |

---

<a name="english"></a>

## English

### 1. System Overview

**Aimili VPN + Sing-box | Full-Protocol Dual-Stack Dual-Outbound Matrix (V1.4.8)**

This system combines the cutting-edge ingress proxy matrix of **Sing-box** with the dynamic residential egress of **AimiliVPN** and an automated multi-format subscription hub:
- **Ingress Proxy Matrix (Sing-box)**: Delivers 5 major protocols on ports 443 (TCP Reality & UDP Hy2), 8443 (UDP TUIC), 8444 (TCP AnyTLS), and 8445 (TCP VMess). Fully supports **IPv4 & IPv6 dual-stack**, using user-level authentication (`auth_user`) to achieve instantaneous zero-downtime dual-outbound routing.
- **Residential Egress Bridge (AimiliVPN)**: Dynamically maintains global public/residential relay tunnels, providing a local SOCKS5 bridge on `127.0.0.1:8500` or integrating third-party commercial residential proxies.
- **Unified Subscription & Web Control Hub (Nginx)**: Serves `sub.txt`, `singbox.json`, `clash.yaml`, and `nodes.txt` on port 18443, while hosting an obfuscated HTTPS administration panel on port 8443.

---

### 2. Modular Permutation Installer Choices

At Step 1 of `install.sh`, the installer offers clear, interactive permutation choices:

| Mode | Name | Components Included | RAM Footprint | Use Case |
| :--- | :--- | :--- | :--- | :--- |
| **[1] (Default)** | **🌟 Flagship All-in-One** | Direct 5 Protocols + Aimili Residential + Adaptive WARP + Camouflage + Subscriptions | ~150MB | Ultimate power users needing gigabit direct speed, streaming/AI unlock, and residential anti-fraud |
| **[2]** | **🚀 Direct Matrix Only** | VLESS-Reality / Hysteria 2 / TUIC v5 / AnyTLS / VMess-xHTTP | **< 50MB** | Low-spec VPS (128M/512M Bandwagon/Oracle); zero idle CPU load; raw 4K streaming speed |
| **[3]** | **🏠 Residential Bridge Only** | SOCKS5 127.0.0.1:8500 Virtual Tunnel Pool + 8443 HTTPS Dashboard | ~80MB | Standalone residential gateway for existing proxies (e.g. self-built Xray or other tools) |
| **[4]** | **⚡ Direct + Adaptive WARP** | Sing-box Direct Matrix + Cloudflare WARP Adaptive Unlock (No Residential) | ~60MB | Bypasses streaming blocks without running residential daemon; ultra-low RAM usage |
| **[5]** | **🌐 Direct + Residential** | Sing-box Direct Matrix + Aimili Residential Bridge (No WARP) | ~140MB | Pure physical and residential routing; avoids Cloudflare WARP intermediary |
| **[6]** | **📦 Subscription Server Only** | Nginx 18443 Subscription Dispatcher (sub/clash/singbox) + 8443 Dashboard | ~30MB | Centralized node hosting and subscription conversion distribution hub |
| **[7]** | **🛠️ Custom Modular Selection** | Interactive checklist: Direct, Residential, Adaptive WARP, Camo, BBR | Custom | Tailored component installation for advanced administrators |
| **[8]** | **🗑️ Complete Uninstallation** | Clean removal of services, firewall rules, interfaces, routes, and files | 0MB | 100% clean teardown |

---

### 3. Adaptive WARP Intelligence & Auto-Skip Logic (`ml warp auto`)

Unlike conventional scripts that unconditionally inject WARP (degrading gigabit speeds and hijacking residential IPs), this project implements **industry-first adaptive auto-detection**:

```
[Adaptive Pre-flight Testing (ml warp auto)]
           │
           ├──> Probes native IPv4/IPv6 egress capabilities for top platforms:
           │     1. OpenAI / ChatGPT (chatgpt.com & API compliance endpoints)
           │     2. Netflix (netflix.com/title/80018499 non-original full catalog)
           │     3. Disney+ (disneyplus.com international)
           │     4. TikTok (tiktok.com short video)
           │     5. YouTube (global edge CDN)
           │
           ├──> [Scenario A: Native IP is 100% Fully Unlocked]
           │     🎉 Decision: AUTOMATICALLY ABORT / SKIP WARP OUTBOUND!
           │     🚀 Benefit: Retains 100% physical gigabit line speed; zero Anycast latency or jitter.
           │
           └──> [Scenario B: Partial Restriction Detected] (e.g. OpenAI blocked, Netflix unlocked)
                 ⚠️ Decision: Precision routing injected ONLY for blocked platforms!
                 💡 Benefit: 
                   - OpenAI traffic routes through Cloudflare WARP user-space WireGuard;
                   - Netflix & YouTube maintain 100% direct VPS gigabit speed;
                   - 🛡️ Redline: Strictly scoped to auth_user: ["direct-user"]; Residential nodes NEVER touch WARP!
```

---

### 4. Port & Protocol Matrix

| Protocol / Service | Port | Transport | Description |
| :--- | :--- | :--- | :--- |
| **VLESS-Reality** | `443/tcp` | TCP + TLS Vision | Steals authoritative TLS certs, zero domain required |
| **Hysteria 2** | `443/udp` (Hopping: 40000-50000) | UDP (Brutal + Salamander) | Extreme line acceleration with port hopping & obfs |
| **TUIC v5** | `8443/udp` | UDP / QUIC (BBR) | Native BBR congestion control, 0-RTT instant handshake |
| **AnyTLS** | `8444/tcp` | TCP (Padding Obfs) | Dynamic packet size randomization against active probing |
| **VMess-xHTTP** | `8445/tcp` | TCP (HTTP/3 Chunks) | Segmented HTTP/3 stream bypassing deep packet inspection |
| **HTTPS Web Admin** | `8443/tcp` | TCP, Nginx reverse proxy | Visual control panel for country & node switching |
| **Full Subscriptions** | `18443/tcp` | TCP, Nginx static host | Serves `sub.txt`, `clash.yaml`, `singbox.json`, `nodes.txt` |
| **Residential Bridge** | `8500/tcp` | `127.0.0.1` | Local Aimili dynamic residential bridge or external SOCKS5 |

---

### 5. One-Click Installation & Management

Run as root on your Linux VPS:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/wbowen123/AimiliVPN/main/install.sh)
```

#### CLI Management Commands (`ml`)

```bash
ml          # Launch interactive dual-core management console (21 operations)
ml sub      # Print 18-node dual-stack matrix, subscription URLs, and QR code
ml qr       # 📱 Render terminal ASCII QR code directly (scan with Shadowrocket / Sing-box)
ml web      # Display web dashboard URL, secret path, and credentials
ml test     # Run automated health check & troubleshooting for -1 errors
ml core     # Sing-box core manager (upgrade to latest, switch versions)
ml cert     # SSL/TLS cert manager (HTTP-01, Cloudflare DNS API, force renew)
ml argo     # Cloudflare Argo tunnel manager (Quick tunnel & Named Token)
ml warp     # Cloudflare WARP dual-stack manager (auto adaptive probe / ai / stream / off)
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
ml update   # 🔄 Check GitHub updates with diff, changelog, and zero-loss auto-migration
```

---

### 6. Aggregated Subscription Hub & Terminal QR Scanning

Subscription links available on `https://your-domain-or-ip:18443/`:

1. **🌟 Universal Base64 Adaptive Subscription (`/sub.txt`)**:
   - Compatible with: **Shadowrocket**, **v2rayN**, **Loon**, **Surge**, **Quantumult X**;
   - Client-adaptive format resolution.
2. **📦 Sing-box Native 1.10+ JSON Subscription (`/singbox.json`)**:
   - Compatible with: **Sing-box Official Client (Android / iOS / Windows / macOS)**;
   - Features built-in Smart-DNS routing rules, Direct routing, and policy groups: `🎯 手动选择`, `🚀 极速原生 (自动优选)`, `🏠 住宅家宽 (自动优选)`, and `⚡ 故障转移`.
3. **🐱 Clash Meta (Mihomo) YAML Subscription (`/clash.yaml`)**:
   - Compatible with: **Clash Verge Rev**, **Mihomo Party**, **Clash Nyanpasu**, **CFW**;
   - Includes automatic latency urltest groups and fallback failover groups.
4. **📄 Plaintext Node List (`/nodes.txt`)**:
   - Raw single links for easy manual copy/paste or sharing single nodes.
5. **📱 Terminal ASCII QR Code (`ml qr` or `ml sub`)**:
   - Prints visual ANSI QR code blocks directly in terminal;
   - Mobile users can point their camera / Shadowrocket app at the screen to import all 18 nodes in 1 second.

---

### 7. Complete 18-Node Dual-Stack Matrix

- **[Group A: IPv4 Direct & Residential]**:
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
- **[Group B: IPv6 Direct Nodes]**:
  11. `🚀 [直连-极速·IPv6] VLESS-Reality【TCP-Vision·原生IPv6】`
  12. `🌪️ [直连-极速·IPv6] Hysteria 2【H3-UDP-Brutal·IPv6暴力加速】`
  13. `⚡ [直连-极速·IPv6] TUIC v5【H3-QUIC-0RTT·IPv6秒开】`
  14. `☁️ [直连-极速·IPv6] VMess-xHTTP【H2/H3-分块·原生IPv6】`
- **[Group C: Cloudflare CDN & Argo Proxied Nodes]**:
  15. `⛅ [CDN-优选IP·IPv4] VMess-WS-Argo【Anycast优选·Cloudflare全球破墙】`
  16. `⛅ [CDN-小黄云·IPv4] VMess-xHTTP【Cloudflare-CDN·分块免流破墙】`
  17. `⛅ [CDN-小黄云·IPv4] VLESS-WS-TLS【Cloudflare-CDN·小黄云破墙】`
  18. `⛅ [CDN-小黄云·IPv6] VMess-xHTTP【Cloudflare-CDN-IPv6·分块穿透】`

---

**Version: V1.4.8 (Sing-box Dual-Outbound Enterprise Full-Stack Suite)**
