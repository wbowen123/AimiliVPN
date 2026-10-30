# Aimili VPN + Sing-box 双出站节点管理系统 🌐

Bilingual: [中文](#中文) | [English](#english)

本项目基于 AimiliVPN 深度定制，原生整合 **Sing-box** 现代化代理核心，在 Linux VPS 上实现：
1. **模块化排列组合一键部署 (Modular Permutation Installer)**：安装第 1 步提供清晰交互式选项，支持【全套旗舰版】、【仅原生直连五协议】、【仅Aimili动态住宅家宽网桥】、【直连+自适应WARP】、【直连+动态家宽】、【仅订阅分发中心】及【高级自定义按需勾选】，满足不同配置 VPS 的极致轻量与全能需求；
2. **Cloudflare WARP 自适应流媒体与 AI 智能免装引擎**：基于 Sing-box 原生 WireGuard 用户态出站，安装时自动探测 IPv4/IPv6 原生 IP 解锁能力。**若原生 IP 已 100% 解锁 ChatGPT/Netflix/Disney+/TikTok，则智能放弃安装 WARP**，保持纯千兆直连；若部分受阻，则精准针对未解锁网站挂载 WARP，**严格隔离住宅出口（家宽 100% 走纯正家宽，绝不被机房 WARP 劫持）**；
3. **全协议双栈多国矩阵分流架构 (Dual-Stack & Multi-Country Egress Matrix)**：单节点支持 **VLESS-Reality、Hysteria 2、TUIC v5、AnyTLS、VMess-xHTTP** 5 大主流协议，全面支持 **IPv4 与 IPv6 原生双栈**，一键下发包含 **“原生 VPS 高速直连”**、**“Aimili 动态住宅家宽穿透 (全球/美/日多国矩阵)”** 与 **“Cloudflare CDN/Argo 优选穿透”** 的 **18~24+ 节点双栈多国矩阵完整订阅**；
4. **全生态全格式聚合订阅与终端扫码**：原生输出通用 Base64 (`sub.txt`)、Sing-box 原生 1.10+ JSON (`singbox.json` 内置 Smart-DNS 与分流规则)、Clash Meta / Mihomo (`clash.yaml` 内置自动测速优选与故障转移策略组) 及明文单节点列表 (`nodes.txt`)；部署完成时直接在终端渲染 **ASCII 双色二维码**，手机客户端（小火箭 / Sing-box）扫码一键导入 18~24+ 节点；
5. **节点健康状态与端口连通性实时自检**：安装结束时全自动对 VLESS-Reality (443)、Hysteria 2 (443)、TUIC (8443)、AnyTLS (8444)、VMess (8445)、Aimili SOCKS5 (8500/8502/8503)、Nginx 订阅 (18443) 展开端口监听与链路状态诊断，即时输出 `[ OK ]` 健康清单；
6. **脚本智能更新与配置平滑迁移系统 (`ml update`)**：一键检测 GitHub 仓库最新 Commit 与版本，展示前后版本对比、更新内容日志、文件变动统计与配置零丢失安全说明，支持交互式确认是否升级，升级过程自动备份现有配置并平滑热重载；
7. **Cloudflare 全生态无缝集成**：
   - ☁️ **Argo 隧道穿透**：支持 Quick Tunnel (免CF账号临时穿透) 与 Named Token 固定隧道，破除 NAT、无公网 IP 限制；
   - ⚡ **CDN 三网优选 IP 测速**：内置电信/联通/移动亚太低延迟 Anycast 测速算法，**仅对 CDN 穿透节点生效，物理直连节点 100% 保持原生千兆 IP 直连**；
   - 📖 **子域名隔离傻瓜向导 (`ml dns`)**：通过直连子域名（灰云）与破墙子域名（橙色小黄云）物理隔离，彻底解决开小黄云拖慢直连与家宽的问题；
8. **主动探测防御与自动化运维**：
   - 🎭 **HTML5 高保真本地伪装库**：内置科技云 SaaS、开发者工具箱/计算器、极客博客、2048 小游戏等 4 套可交互模板，完美抵御主动嗅探；
   - 🤖 **Telegram Bot 即时推送**：支持节点订阅一键下发至 TG、公网 IP 漂移告警、核心进程崩溃拉起告警；
   - ⏰ **定时系统自愈与精准时钟同步**：每日凌晨 4 点权威 HTTPS 时钟校准、节点状态自愈检查与 15分钟进程看门狗；
9. **工业级可靠性加固**：
   - 🛡️ **GOMEMLIMIT 软内存限制**：针对 128MB/512MB/1GB 等小内存/NAT VPS，动态测算 Go 堆内存配额，根除 OOM 崩溃；
   - 🔄 **事务快照与原子回滚**：配置更新遵循“备份 $\to$ 临时写入 $\to$ sing-box check 预检 $\to$ 原子替换 $\to$ 健康监控 $\to$ 异常秒级回滚”闭环；
   - ⏱️ **高精度时间同步与补偿**：内置 `check_time_sync.sh` 对齐权威 HTTPS 响应头，消除 $>15$ 秒时钟漂移导致的握手超时；
   - 🌪️ **端口跳跃与 Salamander 混淆**：Hysteria 2 支持 UDP 40000-50000 端口范围映射与 Salamander 混淆，破解晚高峰运营商 QoS 限速。
10. **【V1.5.0 重大突破】Linux Netns 物理网络隔离与工业级动态家宽调度引擎**：
   - 🛡️ **物理级隔离防母机劫持**：OpenVPN 限制在独立网络命名空间（`aimili_ns_*`）运行，彻底消除注入默认路由劫持母机网关导致 VPS 掉线的行业顽疾；
   - 🏠 **真实家宽精准判定 (`is_residential`)**：基于 CIDR 规则物理剔除筑波大学官方学术机房网段（`219.100.37.0/24`）与 `public-vpn-*` 域名，100% 保障海外居民宽带纯洁度；
   - ⚡ **多源容灾与并发竞发建连 (`RaceConditionScheduler`)**：官方 API 与 Cloudflare Worker 镜像双源无缝容灾；多候选节点并发探活握手，先赢者直接胜出，建连耗时从 30s 缩减至 3~5 秒，15s 周期健康探测自愈。
11. **【V1.5.1 安全与稳态加固】全生态订阅防暴破防扫描与全链路容错闭环**：
   - 🔒 **18443 订阅中心安全加固**：全面引入 `sub_<token>/` 随机安全路径，屏蔽根路径暴力扫描与 UUID 泄露（公网全网扫描器直接探测根路径严格返回 404）；
   - 🛡️ **WARP 出站零黑洞**：彻底重构 Cloudflare WARP 注册容错机制，API 失败时杜绝注入未生效虚假凭据，保障直连主出站零损伤；
   - ⚡ **DNS 智能探针异步化**：`generate_subs.py` 引入带 1.5 秒硬超时的线程池并发探测，杜绝在极端弱网环境下的进程阻塞；
   - 🩺 **监控假阴性与安装容错闭环**：`check_health.sh` 纳管动态家宽健康退出码，`install.sh` 强化异常陷阱，确保部署总结与面板凭证始终可靠输出。
12. **【V1.6.0 架构升华】Sing-box 原生多国家住宅出口矩阵与生产级安全稳态引擎**：
   - 🛡️ **OpenVPN 白名单清洗与 RCE 防御 (`sanitize_ovpn_config`)**：借鉴 `OpenMili/aimili-vpngate` 规范，对第三方 OpenVPN 配置实施严格指令与内联块白名单清洗，剔除 `up/down/script-security/plugin` 等高危脚本挂钩，从底层杜绝不可信节点提权与远程代码执行；
   - ⚡ **毫秒级下游连接主动切断 (`ConnRegistry`)**：借鉴 `Guli-Joy/aimili-vpngate` 连接追踪模型，节点切换/漂移时主动中断存量下游黑洞 Socket，促使客户端即刻重连新隧道，彻底消灭客户端无网卡死；
   - 🚀 **并发非阻塞 TCP 毫秒级端口预筛 (`tcp_prescreen_nodes`)**：0.8s 并发快速淘汰死端口节点，候选池筛选与建连测速效率提升 5~10 倍；
   - ⏳ **假活节点 1800 秒惩罚与防抖冷却池 (`NodeCooldownPool`)**：自动标记并隔离“TCP握手成功但无法出网”的假活节点，彻底消除自愈死循环换线；
   - 🌐 **Netns 多槽位独立网桥与国家矩阵 (`AimiliMultiSlotManager`)**：槽位 0（8500，全球最优）、槽位 1（8502，美国住宅）、槽位 2（8503，日本住宅），支持原子持久化状态文件 `slots_state.json`；
   - 📦 **Sing-box 服务端多出站与全平台聚合订阅无缝协同**：`setup_singbox.sh` 自动注入多国家 SOCKS5 出站与分流用户；`generate_subs.py` 全生态生成包含 `[住宅-家宽·美国]`、`[住宅-家宽·日本]` 的 Base64 / Clash Meta / Sing-box 客户端开箱即用多国矩阵订阅。

<a name="中文"></a>

## 中文

### 1. 系统名称与定位

**Aimili VPN + Sing-box｜全协议双栈双出站节点管理系统 (V1.6.0)**
* **当前版本**：`V1.6.0`
* **更新发布时间**：`2026-10-30 16:45:00 CST`
* **架构基石**：Sing-box 1.14+ 代理矩阵 × Linux Netns 物理网络隔离 × 多国家动态住宅出口矩阵

系统由四大核心模块协同运作：
- **前端多协议代理矩阵（Sing-box）**：监听 443 (TCP Reality & UDP Hy2)、8443 (UDP TUIC)、8444 (TCP AnyTLS)、8445 (TCP VMess)，通过用户鉴权（`auth_user`）实现毫秒级双出站与多国家矩阵分流。
- **后端动态住宅网桥矩阵（AimiliVPN Netns 引擎）**：基于 Linux Network Namespace 物理隔离运行，维护全球及多国独享住宅节点池，在本地提供绝对安全的 SOCKS5 出站网桥矩阵（槽位 0 `127.0.0.1:8500` 全球最优、槽位 1 `8502` 美国住宅、槽位 2 `8503` 日本住宅）。
- **全生态订阅分发与 Web 控制中心（Nginx）**：在 18443 端口集中托管 `sub.txt`、`singbox.json`、`clash.yaml`、`nodes.txt`，并在 8443 端口提供带防探测随机后缀的可视化管理面板。
- **自愈巡检与自动化门禁体系（Code Gate V2.0 & check_health.sh）**：提供从代码 AST 级静态拓扑门禁到实机 10 大核心端口实时自检排错的全套生产级稳态保障。

---

### 1.1 【V1.5.0 架构重构】Linux Netns 物理网络隔离与工业级动态家宽调度引擎

借鉴并吸收了业界前沿开源家宽调度工程（`byJoey/fanout` 与 `vioIetMiku/miku-gate`）的实战精髓，本次架构重构彻底攻克了传统家宽代理的三大死穴：

```
┌────────────────────────────────────────────────────────────────────────┐
│                     Linux VPS 物理主机 (Host / eth0)                   │
│                                                                        │
│  [Sing-box 多协议网关] ─── auth_user 鉴权 ───┬─> [原生千兆直连] ──> 外网出口
│  (TCP 443 / UDP 443 / 8443 / 8444 / 8445)     │                        │
│                                               └─> (vpngate-user 住宅) │
│                                                          │             │
│  [Nginx HTTPS 管理面板] 8443 ──反代──> [Python 8501]     │             │
│  [Nginx 订阅中心] 18443 (sub / clash / singbox)          ▼             │
│                                                   127.0.0.1:8500        │
│                                              (NetnsBridgeServer)       │
│                                                          │ (veth-pair) │
│  ════════════════════════════════════════════════════════╪═════════════╪══════
│  [物理隔离网络空间: Linux netns (aimili_ns_*)]           ▼             │
│                                                    10.99.X.2 (vp_1)    │
│  * 母机默认网关 100% 保持完好，绝不被篡改                │             │
│  * OpenVPN 进程被彻底关入 netns 运行                     ▼             │
│  * 虚拟网卡: tun0 (0.0.0.0/1 via OpenVPN Gateway)  ──> [OpenVPN] ──────┘
│  * 纯正海外居民家庭宽带真实出口 (如 219.54.213.227)                    │
└────────────────────────────────────────────────────────────────────────┘
```

#### 核心阶段落地：
1. **阶段一：真实家宽规则判定与多源容灾池 (`scripts/vpngate_engine.py`)**
   - **启发式过滤算法 (`is_residential`)**：严格剔除主机名以 `public-vpn-` 命名的学术节点，并使用 CIDR 地址掩码算法物理屏蔽筑波大学官方自营机房网段（`219.100.37.0/24`），确保筛选出的节点 100% 归属于真实民用 ISP；
   - **双源与 Cloudflare Worker 镜像容灾**：默认拉取官方接口，遭遇网络抖动或超时（>10s）自动无缝切换至 Cloudflare Worker 镜像源（`https://p.xy.kg/vpngate`），彻底告别单点数据源故障。
2. **阶段二：多候选并发竞发建连与 IP 漂移自愈 (`RaceConditionScheduler`)**
   - **并发竞发建连**：抛弃单线程串行阻塞重试机制，对优质候选节点并发发起握手，先通过出口 IP 真实性校验的节点直接当选，其余节点优雅释放，换线耗时由 30s 压缩至 **3~5 秒**；
   - **IP 漂移巡检与自愈守护**：后台看门狗以 15 秒周期持续探测链路健康，一旦检测到节点掉线或 IP 漂移，自动触发无感换线自愈。
3. **阶段三：Linux netns 物理网络隔离架构 (`LinuxNetnsManager`)**
   - **母机路由 0 污染、0 劫持**：在独立网络命名空间内运行 OpenVPN 并分配私有 `veth-pair` 子网（`10.99.<slot>.0/24`），OpenVPN 注入的路由被死死限制在 netns 内部；
   - **母机原生网卡（`eth0`）与默认网关（`default via ...`）100% 完好无损，SSH 连接与原生千兆直连业务永远不掉线**；
   - **本地网桥直通**：宿主机监听 `127.0.0.1:8500`，通过 SOCKS5 网桥透明穿透 netns 出口，上游 Sing-box 无感接入。

---

### 1.2 【V1.6.0 架构升华】Sing-box 原生多国家住宅出口矩阵与生产级安全稳态引擎

在 V1.5.0 单一 8500 住宅出口物理隔离的基础上，V1.6.0 深度融合业界前沿开源最佳实践，完成了从“单点动态家宽”向**“生产级多国家住宅出口矩阵与主动稳态系统”**的跃升：

```
┌──────────────────────────────────────────────────────────────────────────────────────────────┐
│                                Linux VPS 物理主机 (Host / eth0)                              │
│                                                                                              │
│  [Sing-box 多协议网关] ─── auth_user 鉴权 ───┬─> [direct-user] ──────────> VPS 原生千兆物理直连
│  (TCP 443 / UDP 443 / 8443 / 8444 / 8445)     ├─> [residential-user] ────> 127.0.0.1:8500 ──┐
│                                               ├─> [residential-us-user] ─> 127.0.0.1:8502 ──┼─┐
│                                               └─> [residential-jp-user] ─> 127.0.0.1:8503 ──┼─┼─┐
│                                                                                              │ │ │
│  ════════════════════════════════════════════════════════════════════════════════════════════╪═╪═╪══
│  [物理隔离 Linux Netns 多槽位矩阵]                                                           │ │ │
│  ├── 槽位 0 [aimili_ns_0] (10.99.0.2) ──> [OpenVPN] ──> 🌐 全球最优动态住宅家宽出口 <────────┘ │ │
│  ├── 槽位 1 [aimili_ns_1] (10.99.1.2) ──> [OpenVPN] ──> 🇺🇸 美国独享住宅家宽出口 (US) <─────────┘ │
│  └── 槽位 2 [aimili_ns_2] (10.99.2.2) ──> [OpenVPN] ──> 🇯🇵 日本独享住宅家宽出口 (JP) <───────────┘
└──────────────────────────────────────────────────────────────────────────────────────────────┘
```

#### 核心三大演进阶段：
1. **阶段一：生产级安全白名单清洗与下游黑洞连接主动切断（Phase 1）**
   - **OpenVPN 指令与内联块白名单清洗 (`sanitize_ovpn_config`)**：借鉴 `OpenMili/aimili-vpngate` 防御体系，建立 `SAFE_OVPN_DIRECTIVES` 与 `SAFE_OVPN_INLINE_BLOCKS` 白名单，物理剥离第三方配置中的 `up/down/script-security/plugin/tls-verify` 等高危脚本挂钩，从根源杜绝未授权脚本执行与提权风险；
   - **下游黑洞 Socket 主动切断机制 (`ConnRegistry`)**：借鉴 `Guli-Joy/aimili-vpngate` 连接追踪理念，维护活跃下游 Socket 注册表。主节点断开或换线自愈时，网桥主动调用 `close_all()` 强制掐断死连接，促使客户端 TCP 栈毫秒级感知中断并立即重建新连接，彻底消灭切换时长达数十秒的无网卡死。
2. **阶段二：非阻塞并发 TCP 端口毫秒级预筛与假活节点冷却防抖（Phase 2）**
   - **非阻塞并发 TCP 端口预筛 (`tcp_prescreen_nodes`)**：借鉴 `Guli-Joy/aimili-vpngate` 分层预检思路，多线程以 0.8s 硬超时并发探测候选节点目标端口，毫秒级快速淘汰 40%~60% 的死端口节点，候选池筛选与建连测速效率提升 5~10 倍；
   - **假活与僵尸节点 1800 秒惩罚冷却池 (`NodeCooldownPool`)**：借鉴 `Guli-Joy/aimili-vpngate` 防抖机制，对“OpenVPN 握手成功但无法出网获取出口公网 IP 或 IP 瞬间漂移”的假活节点，实施 1800 秒（30分钟）硬性冷却惩罚，换线时自动规避，到期无感解冻，彻底杜绝自愈死循环换线。
3. **阶段三：Netns 多槽位独立网桥与 Sing-box 原生多国家住宅出口矩阵（Phase 3）**
   - **多槽位物理隔离调度器 (`AimiliMultiSlotManager` & `ResidentialSlot`)**：实现槽位 0 (`127.0.0.1:8500` 全球最优)、槽位 1 (`8502` 美国独享住宅)、槽位 2 (`8503` 日本独享住宅)，各槽位拥有独立的 Netns 命名空间、子网分配与 OpenVPN 实例，并通过 `slots_state.json` 实现原子持久化；
   - **Sing-box 服务端多出站与入站用户自适应动态注入**：`setup_singbox.sh` 自动读取槽位状态，向 Sing-box 动态注入 `resi-us-out`、`resi-jp-out` 以及各协议国家专属用户（`residential-us-user`、`residential-jp-user`）与分流路由规则；
   - **客户端多国矩阵订阅与自动策略组**：`generate_subs.py` 协同下发美日独立住宅节点，并在 Clash Meta 与 Sing-box 订阅中内置专用的国家策略组，客户端订阅无缝从 18 节点扩展至 **18~24+ 节点全矩阵**！

---

### 2. 模块化排列组合安装模式

在安装脚本第一步，系统提供详细的排列组合交互选项，用户可按需选择：

| 选项编号 | 模式名称 | 包含组件 | 内存开销 | 适用场景 |
| :--- | :--- | :--- | :--- | :--- |
| **[1] (默认推荐)** | **🌟 全套旗舰尊享版** | 原生直连五协议 + Aimili动态家宽多国矩阵 + 自适应WARP + 伪装站 + 全格式聚合订阅 | ~150MB | 需要兼顾千兆低延迟极速、流媒体与AI完美解锁、跨境抗封锁的全能用户 |
| **[2]** | **🚀 仅安装 极速原生直连代理矩阵** | VLESS-Reality / Hysteria 2 / TUIC v5 / AnyTLS / VMess-xHTTP | **< 50MB** | 搬瓦工/甲骨文低配 VPS，不跑家宽后台，CPU零空载，追求极致轻量与极速看 4K |
| **[3]** | **🏠 仅安装 Aimili 动态住宅家宽网桥矩阵** | SOCKS5 127.0.0.1:8500/8502/8503 虚拟多国隧道池 + 8443 可视化管理控制台 | ~80MB | 已有自建节点（如 Xray/九合一），仅需在 VPS 上增设动态住宅出口矩阵落地 |
| **[4]** | **⚡ 组合: 原生直连 + 自适应 WARP 解锁** | Sing-box 原生五协议 + Cloudflare WARP 自适应解锁引擎 (不含家宽) | ~60MB | 原生 IP 被流媒体阻断但无需家宽轮转，兼顾低开销与 100% 流媒体/AI 原生解锁 |
| **[5]** | **🌐 组合: 原生直连 + Aimili 动态住宅家宽矩阵** | Sing-box 原生五协议 + Aimili 动态住宅网桥 (不含 WARP) | ~140MB | 直连走机房 IP，住宅走真实家宽，无需 Cloudflare 介入，保证原生与住宅 IP 纯洁度 |
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
| **动态住宅网桥矩阵** | `8500` (槽位0·全球) / `8502` (槽位1·美国) / `8503` (槽位2·日本) | 本机 `127.0.0.1` | Linux Netns 物理网络隔离的多槽位动态住宅家宽出站矩阵，支持多国独享分流 |

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
ml sub      # 终端打印全协议 18~24+ 节点矩阵、全格式聚合订阅卡片与扫码二维码
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
ml status   # 查看 AimiliVPN 多槽位运行状态与当前活跃住宅节点
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
   - 原生内置 Smart-DNS 分流规则、本地直连与 `🎯 手动选择`、`🚀 极速原生 (自动优选)`、`🏠 住宅家宽 (自动优选)`、`🇺🇸 美国住宅家宽 (选流)`、`🇯🇵 日本住宅家宽 (选流)`、`⚡ 故障转移` 策略组，开箱即用无需转换。
3. **🐱 Clash Meta (Mihomo) YAML 订阅 (`/clash.yaml`)**：
   - 适配客户端：**Clash Verge Rev**、**Mihomo Party**、**Clash Nyanpasu**、**CFW**；
   - 内置健康测速分组（Urltest 自动选择延迟最低节点）、故障转移分组（Fallback 自动剔除异常节点）与专属国家策略组（`🇺🇸 美国住宅家宽`、`🇯🇵 日本住宅家宽`）。
4. **📄 Plaintext 原始节点列表 (`/nodes.txt`)**：
   - 纯文本单链接格式，便于手动复制单节点到剪贴板或单独分享给朋友。
5. **📱 终端 ASCII 二维码扫码 (`ml qr` 或 `ml sub`)**：
   - 部署完成或在终端运行 `ml qr`，屏幕立即打印高对比度半高字符二维码；
   - 手机打开 Shadowrocket 或 Sing-box 扫描屏幕即可自动识别并批量导入 18~24+ 个节点，彻底告别手动复制长链接的繁琐！

---

### 7. 完整 18~24+ 节点双栈多国矩阵清单

所有节点名称均严格遵循**【出站属性 + 协议名称 + 传输特征 + 网络栈】**四维规范。基础部署默认下发 18 节点；开启多国家住宅矩阵后，自动下发包含美日独立住宅的 24+ 全矩阵：

#### 【A 组：IPv4 原生直连与全球住宅节点】（直连 VPS 物理 IPv4）
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
17. `⛅ [CDN-小黄云·IPv4] VMess-WS-TLS【Cloudflare-CDN·小黄云破墙】`（经典 WebSocket 小黄云破墙）
18. `⛅ [CDN-小黄云·IPv6] VMess-xHTTP【Cloudflare-CDN-IPv6·分块穿透】`（Cloudflare Anycast IPv6 优选穿透）

#### 【D 组：多国家独享住宅家宽矩阵节点 (V1.6.0 架构升级)】（Netns 物理多槽位隔离，按需下发）
19. `🏠 [住宅-家宽·美国住宅] VLESS-Reality【TCP-Vision·US住宅】`（槽位 1 独享美国家宽，物理 Netns 隔离）
20. `🏘️ [住宅-家宽·美国住宅] Hysteria 2【H3-UDP-Brutal·US住宅加速】`（暴力抗丢包，海外低风控 AI / 流媒体专用）
21. `🏡 [住宅-家宽·美国住宅] TUIC v5【H3-QUIC-0RTT·US住宅流媒体】`（0-RTT 极速秒开美国家宽）
22. `🏠 [住宅-家宽·日本住宅] VLESS-Reality【TCP-Vision·JP住宅】`（槽位 2 独享日本家宽，物理 Netns 隔离）
23. `🏘️ [住宅-家宽·日本住宅] Hysteria 2【H3-UDP-Brutal·JP住宅加速】`（专供日本本土流媒体、游戏与超低延迟）
24. `🏡 [住宅-家宽·日本住宅] TUIC v5【H3-QUIC-0RTT·JP住宅流媒体】`（0-RTT 极速秒开日本家宽）

> 💡 **客户端协议兼容性与分流策略说明**：
> 1. **AnyTLS (节点 7 & 8)**：属于 Sing-box 专有防探测混淆协议，原生支持在 `sub.txt`、`singbox.json` 及 `nodes.txt` 订阅中下发；由于 Clash / Mihomo 官方尚未合并 AnyTLS 协议，`clash.yaml` 自动智能剔除 AnyTLS 节点，保障不同客户端的最佳兼容性；
> 2. **多国家矩阵策略组 (D 组)**：在生成的 Clash Meta (`clash.yaml`) 与 Sing-box (`singbox.json`) 订阅中，自动内置独立的 **`🇺🇸 美国住宅家宽`** 与 **`🇯🇵 日本住宅家宽`** 策略组，客户端分流规则支持一键定向分流，无需手动选线！


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

### 10. 致谢与开源项目鸣谢 (Acknowledgments & Open Source Credits)

本项目由衷感谢全球开源社区与网络工程先锋项目的杰出贡献，AimiliVPN 的诞生与演进深度吸收、调用或借鉴了以下优秀开源项目与技术实践（排名不分先后）：

| 开源项目 / 仓库 | 机构 / 作者 / 链接 | 核心贡献与本项目调用/借鉴说明 |
| :--- | :--- | :--- |
| **aimili-vpngate (OpenMili)** | [OpenMili/aimili-vpngate](https://github.com/OpenMili/aimili-vpngate) | 原初开源母体（Stars 2298+），为本项目提供了生产级 OpenVPN 配置安全指令白名单清洗规范与防 RCE 任意代码执行/提权架构设计。 |
| **aimili-vpngate (Guli-Joy)** | [Guli-Joy/aimili-vpngate](https://github.com/Guli-Joy/aimili-vpngate) | 多出口调优版（Stars 27+），为本项目提供了非阻塞并发 TCP 端口毫秒级预筛、假活节点 1800 秒惩罚冷却池防抖与换线时下游 Socket 主动切断理念。 |
| **AimiliVPN (hankinsus)** | [hankinsus/AimiliVPN](https://github.com/hankinsus/AimiliVPN) | 提供了早期控制面与 Web 动态库基础，本项目在此基础上进行了纯 Python 开源解耦与 Netns 现代化架构重构。 |
| **AimiliVPN (liuyesblog)** | [liuyesblog/AimiliVPN](https://github.com/liuyesblog/AimiliVPN) | 提供了静态镜像分支与跨版本对照参考。 |
| **Sing-box** | [SagerNet/sing-box](https://github.com/SagerNet/sing-box) | 本项目核心代理平台底座。提供了现代化的 VLESS-Reality、Hysteria 2、TUIC v5、AnyTLS、VMess 协议栈、高性能规则引擎与原生 WireGuard 用户态出站能力。 |
| **Cloudflare cloudflared & WARP** | [cloudflare/cloudflared](https://github.com/cloudflare/cloudflared) | Cloudflare 官方零信任 Named Tunnel 隧道客户端与全球 Anycast 边缘网络，为本项目提供了 IPv4 被封救急、免公网 IP 穿透与 WARP 智能流媒体/AI 解锁方案。 |
| **acme.sh** | [acmesh-official/acme.sh](https://github.com/acmesh-official/acme.sh) | 业界最轻量纯 Unix Shell 实现的自动化 SSL/TLS 证书客户端，为本项目提供了 HTTP-01 验证、零停机 Webroot 挂载与 Cloudflare DNS-01 API 免 80 端口泛域名签发能力。 |
| **University of Tsukuba VPNGate Project** | 筑波大学·登大游 ([vpngate.net](https://www.vpngate.net/)) | 筑波大学学术实验项目，维护全球海量自愿中继学术与居民节点网络，为本项目的动态住宅家宽出站调度池提供了基石数据源。 |
| **SoftEther VPN Project** | [SoftEtherVPN/SoftEtherVPN](https://github.com/SoftEtherVPN/SoftEtherVPN) | 登大游博士开发的工业级多协议跨平台 VPN 引擎，为本项目提供了底层高性能虚拟网卡与隧道通信协议支持。 |
| **SSTP-Client** | [sstp-project/sstp-client](https://gitlab.com/sstp-project/sstp-client) | Eivind Næss 维护的高性能开源 Linux SSTP 客户端，实现了基于 TLS 端口的高鲁棒性企业级穿透拨号。 |
| **Clash.Meta (Mihomo)** | [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) | 新一代开源分流核心，本项目全生态订阅系统自动适配生成符合其规格的高性能 YAML 订阅与策略组。 |
| **v2ray-agent (八合一/九合一)** | [mack-a/v2ray-agent](https://github.com/mack-a/v2ray-agent) | 开拓性的多协议共存与 Nginx SNI 回源分流理念，为本项目早期的双出站设计提供了宝贵的架构参考。 |
| **fanout & miku-gate** | `byJoey/fanout` & `vioIetMiku/miku-gate` | 启发了本项目 V1.5.0 的真实家宽判定启发式算法（`is_residential`）与多源容灾调度池并发架构设计。 |
| **Linux TCP BBR 优化实践** | 秋水逸冰 ([teddysun.com](https://teddysun.com)) / 逗比根据地 (Toyo) | 经典 Linux 内核拥塞控制与网络调优方法论，为本项目的一键 BBR 与 TCP 缓冲区调优脚本提供了设计灵感。 |
| **Hysteria** | [apernet/hysteria](https://github.com/apernet/hysteria) | 突破性的 UDP-Brutal 传输协议与丢包补偿算法，为本项目提供了恶劣弱网环境下的极限单线程加速能力。 |
| **EAimili** | AimiliVPN 初始核心团队 | 提供了 AimiliVPN 初始的住宅节点智能调度和可视化控制面板雏形。 |

---

### 11. 版本历史与更新日志 (Version History & Changelog)

> **版本发布与时间戳规范**：本项目严格遵循语义化版本控制（SemVer）。每次重大更新均在此章节以**版本号**（Version）与**发布时间戳**（YYYY-MM-DD HH:mm:ss CST）为严格倒序记录更新要点、核心功能说明与架构演进细节。

#### 🌟 V1.6.0 (2026-10-30 16:45:00 CST) - Sing-box 原生多国家住宅出口矩阵与生产级安全稳态引擎
- 🛡️ **阶段一：安全清洗加固与下游连接主动切断（Phase 1）**：
  - **OpenVPN 白名单清洗与 RCE 防御 (`sanitize_ovpn_config`)**：借鉴 `OpenMili/aimili-vpngate` 生产级安全防护模型，建立指令白名单 `SAFE_OVPN_DIRECTIVES` 与内联块白名单 `SAFE_OVPN_INLINE_BLOCKS`，强行剥离所有 `up/down/script-security/plugin/tls-verify` 等高危脚本挂钩指令，从操作系统底层封杀不可信节点的提权与远程代码执行（RCE）漏洞；
  - **下游黑洞 Socket 主动切断机制 (`ConnRegistry`)**：借鉴 `Guli-Joy/aimili-vpngate` 连接追踪模型，建立客户端 Socket 全生命周期管理池。主节点发生切换或 IP 漂移自愈时，网桥主动调用 `close_all()` 强制中断存量下游死连接，促成客户端 TCP 栈毫秒级感知并重新发起拨号，彻底消灭客户端长达数十秒的无网卡死。
- 🚀 **阶段二：性能预筛分层与假活节点冷却防抖（Phase 2）**：
  - **非阻塞并发 TCP 端口毫秒级预筛 (`tcp_prescreen_nodes`)**：借鉴 `Guli-Joy/aimili-vpngate` 分层筛选思想，基于多线程发起 0.8s 非阻塞端口探针，毫秒级快速淘汰 40%~60% 的死端口节点，候选池筛选与建连测速效率提升 5~10 倍，UDP 节点默认免筛放行；
  - **假活与僵尸节点 1800 秒冷却惩罚池 (`NodeCooldownPool`)**：借鉴 `Guli-Joy/aimili-vpngate` 惩罚机制，对“OpenVPN 握手成功但无法出网获取出口公网 IP 或 IP 瞬间漂移”的假活节点，实施 1800 秒（30分钟）硬性冷却惩罚，抓取与换线时自动过滤，到期无感释放，彻底杜绝自愈死循环换线。
- 🌐 **阶段三：架构升华 - Sing-box 原生多国家住宅出口矩阵（Phase 3）**：
  - **Netns 多槽位独立网桥管理器 (`AimiliMultiSlotManager` & `ResidentialSlot`)**：突破单一 8500 家宽出口限制，实现物理隔离的多国家家宽出口矩阵：
    - **槽位 0**：本地 `127.0.0.1:8500`（默认全球最优家宽，命名空间 `aimili_ns_0`，保持 100% 向后兼容）；
    - **槽位 1**：本地 `127.0.0.1:8502`（美国独享住宅家宽 `US`，命名空间 `aimili_ns_1`）；
    - **槽位 2**：本地 `127.0.0.1:8503`（日本独享住宅家宽 `JP`，命名空间 `aimili_ns_2`）。
    - 支持原子状态保存与无损加载（`slots_state.json`），向控制面、Sing-box 与订阅生成器实时暴露各槽位状态。
  - **Sing-box 服务端多出站与多入站用户动态注入**：`setup_singbox.sh` 步骤 8.2 动态加载国家矩阵槽位，自适应注入 `resi-us-out`、`resi-jp-out` 以及各协议国家专属用户（`residential-us-user`、`residential-jp-user`）与分流路由；
  - **客户端聚合订阅生成引擎协同升级**：`generate_subs.py` 全生态生成包含 `[住宅-家宽·美国]`、`[住宅-家宽·日本]` 的 Base64、Clash Meta 与 Sing-box 客户端订阅，客户端策略组（Selector）全自动纳管国家矩阵选流。
- 🩺 **全阶段独立复检与红蓝对抗自动化单元测试**：
  - 新增 `tests/test_phase1_security_conn.py`（5/5 PASS）；
  - 新增 `tests/test_phase2_prescreen_cooldown.py`（3/3 PASS）；
  - 新增 `tests/test_phase3_multislot_subs.py`（4/4 PASS）；
  - 质量门禁 `scripts/code_gate.py` 全绿通过，0 个 P0/P1 阻塞性缺陷。

#### 🔒 V1.5.1 (2026-10-28 17:15:00 CST) - 全生态订阅防暴破防扫描与全链路容错闭环
- 🔒 **18443 订阅中心安全加固**：全面引入 `sub_<token>/` 随机安全路径，屏蔽根路径暴力扫描与 UUID 泄露（公网全网扫描器直接探测根路径严格返回 404）；
- 🛡️ **WARP 出站零黑洞**：彻底重构 Cloudflare WARP 注册容错机制，API 失败时杜绝注入未生效虚假凭据，保障直连主出站零损伤；
- ⚡ **DNS 智能探针异步化**：`generate_subs.py` 引入带 1.5 秒硬超时的线程池并发探测，杜绝在极端弱网环境下的进程阻塞；
- 🩺 **监控假阴性与安装容错闭环**：`check_health.sh` 纳管动态家宽健康退出码，`install.sh` 强化异常陷阱，确保部署总结与面板凭证始终可靠输出。

#### 🌟 V1.5.0 (2026-10-27 14:30:00 CST) - 工业级 Linux Netns 物理网络隔离与家宽调度重构版
- 🛡️ **Linux Netns 物理网络隔离**：引入独立网络命名空间（`aimili_ns_*`）与专用 `veth-pair` 子网（`10.99.<slot>.0/24`），将 OpenVPN 拨号进程绝对限制在隔离空间内部；**母机物理网卡（`eth0`）与默认网关 100% 保持完好，彻底终结了母机掉线与 SSH 失联的行业顽疾**；
- 🏠 **真实家宽精准过滤算法**：借鉴 `fanout` 设计，通过 `is_residential` 算法严格排除 `public-vpn-*` 域名，并通过 CIDR 掩码物理剔除筑波大学官方学术机房网段（`219.100.37.0/24`），确保出站 100% 走海外居民宽带；
- ⚡ **多源容灾池与并发竞发建连**：官方 API 阻断或超时（>10s）自动无缝切换至 Cloudflare Worker 镜像源（`https://p.xy.kg/vpngate`）；`RaceConditionScheduler` 并发探测多候选节点，先到先赢，换线耗时缩短至 3~5 秒，15 秒周期持续巡检与 IP 漂移自动无感自愈；
- 🔧 **动态链接器加固与防损坏规范**：建立 Linux 文本清洗规范，严禁对 ELF 二进制动态链接库执行 `sed -i`，保障所有 compiled C-Python `.so` 模块在 Ubuntu 24.04 (Python 3.12) 环境下零崩溃安全加载；
- 🩺 **全链路诊断工具升级 (`check_health.sh`)**：全协议矩阵 10 大核心网络端口（443, 8443, 8444, 8445, 8446, 18443, 8500, 8501）监听检测，集成客户端 -1 超时排错指南与住宅出站真实性检测；
- 🚀 **海外真机部署全绿验收**：在真实 Ubuntu 24.04 LTS (x86_64, Linux 6.8 内核) 服务器上完成三阶段全流程闭环验证，自动化质量门禁 `scripts/code_gate.py` 全绿通过。

#### 📦 V1.4.8 (2026-10-23 18:20:00 CST) - 架构可靠性与 Code Gate V2.0 加固版
- 修复 local-dns `detour: direct` 启动崩溃缺陷；
- 彻底解决 Sing-box 国内规则集启动死锁，转为高可用本地内联分流规则并开启 `cache_file`；
- 升级 `scripts/code_gate.py` 质量门禁，增加 Sing-box run 2 秒真机常驻冒烟测试。

---

<a name="english"></a>

## English

### 1. System Overview

**Aimili VPN + Sing-box | Full-Protocol Dual-Stack & Multi-Country Matrix (V1.6.0)**
* **Current Version**: `V1.6.0` | **Release Timestamp**: `2026-10-30 16:45:00 CST`

This system combines the cutting-edge ingress proxy matrix of **Sing-box** with the dynamic residential egress matrix of **AimiliVPN** (powered by Linux Network Namespace physical isolation across multiple country slots) and an automated multi-format subscription hub:
- **Ingress Proxy Matrix (Sing-box)**: Delivers 5 major protocols on ports 443 (TCP Reality & UDP Hy2), 8443 (UDP TUIC), 8444 (TCP AnyTLS), and 8445 (TCP VMess). Fully supports **IPv4 & IPv6 dual-stack**, using user-level authentication (`auth_user`) to achieve instantaneous zero-downtime dual-outbound and multi-country routing.
- **Residential Egress Netns Engine (AimiliVPN V1.6.0)**: Dynamically maintains global and country-dedicated residential relay tunnels isolated in dedicated Linux network namespaces, preventing host default gateway hijacking while providing a local SOCKS5 bridge matrix (`127.0.0.1:8500` for global optimal, `8502` for US, `8503` for Japan).
- **Unified Subscription & Web Control Hub (Nginx)**: Serves `sub.txt`, `singbox.json`, `clash.yaml`, and `nodes.txt` on port 18443, while hosting an obfuscated HTTPS administration panel on port 8443.

---

### 2. Modular Permutation Installer Choices

At Step 1 of `install.sh`, the installer offers clear, interactive permutation choices:

| Mode | Name | Components Included | RAM Footprint | Use Case |
| :--- | :--- | :--- | :--- | :--- |
| **[1] (Default)** | **🌟 Flagship All-in-One** | Direct 5 Protocols + Aimili Multi-Country Residential Matrix + Adaptive WARP + Camouflage + Subscriptions | ~150MB | Ultimate power users needing gigabit direct speed, streaming/AI unlock, and residential anti-fraud |
| **[2]** | **🚀 Direct Matrix Only** | VLESS-Reality / Hysteria 2 / TUIC v5 / AnyTLS / VMess-xHTTP | **< 50MB** | Low-spec VPS (128M/512M Bandwagon/Oracle); zero idle CPU load; raw 4K streaming speed |
| **[3]** | **🏠 Residential Bridge Matrix Only** | SOCKS5 127.0.0.1:8500/8502/8503 Virtual Multi-Country Tunnel Pool + 8443 HTTPS Dashboard | ~80MB | Standalone residential gateway for existing proxies (e.g. self-built Xray or other tools) |
| **[4]** | **⚡ Direct + Adaptive WARP** | Sing-box Direct Matrix + Cloudflare WARP Adaptive Unlock (No Residential) | ~60MB | Bypasses streaming blocks without running residential daemon; ultra-low RAM usage |
| **[5]** | **🌐 Direct + Residential Matrix** | Sing-box Direct Matrix + Aimili Residential Multi-Country Bridge Matrix (No WARP) | ~140MB | Pure physical and residential routing; avoids Cloudflare WARP intermediary |
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
| **Residential Bridge Matrix** | `8500` (Slot 0·Global) / `8502` (Slot 1·US) / `8503` (Slot 2·JP) | Local `127.0.0.1` | Linux Netns physically isolated multi-slot residential egress matrix with dedicated country routing |

---

### 5. One-Click Installation & Management

Run as root on your Linux VPS:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/wbowen123/AimiliVPN/main/install.sh)
```

#### CLI Management Commands (`ml`)

```bash
ml          # Launch interactive dual-core management console (21 operations)
ml sub      # Print 18-24+ node dual-stack matrix, subscription URLs, and QR code
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
ml status   # View AimiliVPN multi-slot status and active residential IPs per country
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
   - Features built-in Smart-DNS routing rules, Direct routing, and policy groups: `🎯 手动选择`, `🚀 极速原生 (自动优选)`, `🏠 住宅家宽 (自动优选)`, `🇺🇸 美国住宅家宽 (选流)`, `🇯🇵 日本住宅家宽 (选流)`, and `⚡ 故障转移`.
3. **🐱 Clash Meta (Mihomo) YAML Subscription (`/clash.yaml`)**:
   - Compatible with: **Clash Verge Rev**, **Mihomo Party**, **Clash Nyanpasu**, **CFW**;
   - Includes automatic latency urltest groups, fallback failover groups, and dedicated country selectors (`🇺🇸 美国住宅家宽`, `🇯🇵 日本住宅家宽`).
4. **📄 Plaintext Node List (`/nodes.txt`)**:
   - Raw single links for easy manual copy/paste or sharing single nodes.
5. **📱 Terminal ASCII QR Code (`ml qr` or `ml sub`)**:
   - Prints visual ANSI QR code blocks directly in terminal;
   - Mobile users can point their camera / Shadowrocket app at the screen to import all 18~24+ nodes in 1 second.

---

### 7. Complete 18-24+ Node Dual-Stack & Multi-Country Matrix

All node identifiers follow the strict 4D taxonomy: **`[Egress Property + Protocol + Transport Feature + Network Stack]`**. Standard deployments output 18 core nodes, which seamlessly expand to 24+ nodes when the Multi-Country Dedicated Residential Matrix is active:

- **[Group A: IPv4 Direct & Global Residential]**:
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
- **[Group D: Multi-Country Dedicated Residential Matrix (V1.6.0 Upgrade)]**:
  19. `🏠 [住宅-家宽·美国住宅] VLESS-Reality【TCP-Vision·US住宅】` (Slot 1 US Dedicated Residential, Netns Isolated)
  20. `🏘️ [住宅-家宽·美国住宅] Hysteria 2【H3-UDP-Brutal·US住宅加速】` (UDP Brutal acceleration, optimized for US AI & streaming)
  21. `🏡 [住宅-家宽·美国住宅] TUIC v5【H3-QUIC-0RTT·US住宅流媒体】` (0-RTT fast handshake for US streaming)
  22. `🏠 [住宅-家宽·日本住宅] VLESS-Reality【TCP-Vision·JP住宅】` (Slot 2 JP Dedicated Residential, Netns Isolated)
  23. `🏘️ [住宅-家宽·日本住宅] Hysteria 2【H3-UDP-Brutal·JP住宅加速】` (Low latency for JP gaming and streaming)
  24. `🏡 [住宅-家宽·日本住宅] TUIC v5【H3-QUIC-0RTT·JP住宅流媒体】` (0-RTT fast handshake for JP media)

> 💡 **Client Compatibility & Routing**:
> 1. **AnyTLS (Nodes 7 & 8)**: Proprietary obfuscation protocol native to Sing-box clients. Automatically omitted from `clash.yaml` until upstream Mihomo implements support;
> 2. **Multi-Country Policy Groups (Group D)**: Clash Meta (`clash.yaml`) and Sing-box (`singbox.json`) subscriptions automatically include dedicated policy selectors for `🇺🇸 美国住宅家宽` and `🇯🇵 日本住宅家宽` for one-click country routing.

---

### 8. Acknowledgments & Upstream Projects

AimiliVPN extends our sincere gratitude to the global open-source community and network engineering pioneers. The design and implementation of this project builds upon and integrates the following outstanding open-source projects (listed in no particular order):

| Project / Repository | Organization / Author / Link | Contribution & How AimiliVPN Uses It |
| :--- | :--- | :--- |
| **Sing-box** | [SagerNet/sing-box](https://github.com/SagerNet/sing-box) | Core proxy platform underpinning this system. Powers VLESS-Reality, Hysteria 2, TUIC v5, AnyTLS, VMess-xHTTP, user-space WireGuard endpoints, and the rule routing engine. |
| **Cloudflare cloudflared & WARP** | [cloudflare/cloudflared](https://github.com/cloudflare/cloudflared) | Cloudflare Zero Trust Named Tunnels and global Anycast CDN edge. Powers IPv4 emergency rescue, NAT punching, and WARP adaptive streaming/AI unblocking. |
| **acme.sh** | [acmesh-official/acme.sh](https://github.com/acmesh-official/acme.sh) | Ultra-lightweight pure Unix shell ACME client. Powers automated HTTP-01 webroot issuance and Cloudflare DNS-01 API wildcard certificates without port 80. |
| **University of Tsukuba VPNGate Project** | University of Tsukuba / Daiyuu Nobori ([vpngate.net](https://www.vpngate.net/)) | Academic research project maintaining a global volunteer relay network, providing the foundation for our residential relay pool. |
| **SoftEther VPN Project** | [SoftEtherVPN/SoftEtherVPN](https://github.com/SoftEtherVPN/SoftEtherVPN) | Multi-protocol enterprise VPN software created by Dr. Daiyuu Nobori, providing high-performance virtual adapter and tunneling capabilities. |
| **SSTP-Client** | [sstp-project/sstp-client](https://gitlab.com/sstp-project/sstp-client) | High-performance open-source SSTP client maintained by Eivind Næss, enabling robust enterprise-grade TLS-based tunneling. |
| **Clash.Meta (Mihomo)** | [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) | Advanced rule-based proxy core. AimiliVPN generates automated YAML configs with latency urltest and failover groups matching its specification. |
| **v2ray-agent (8-in-1 / 9-in-1)** | [mack-a/v2ray-agent](https://github.com/mack-a/v2ray-agent) | Pioneering script for multi-protocol coexistence and Nginx SNI reverse proxy architectures in China, providing invaluable early architectural insights. |
| **aimili-vpngate (OpenMili)** | [OpenMili/aimili-vpngate](https://github.com/OpenMili/aimili-vpngate) | Original open-source upstream (Stars 2298+). Provided production-grade OpenVPN directive whitelist sanitization standards and anti-RCE privilege escalation defense architecture. |
| **aimili-vpngate (Guli-Joy)** | [Guli-Joy/aimili-vpngate](https://github.com/Guli-Joy/aimili-vpngate) | Multi-egress tuned fork (Stars 27+). Provided non-blocking concurrent TCP port prescreening, 1800s dead-node cooldown penalty pool, and active downstream socket termination concepts. |
| **AimiliVPN (hankinsus)** | [hankinsus/AimiliVPN](https://github.com/hankinsus/AimiliVPN) | Provided early control plane and web dynamic library foundations; refactored in this project into pure Python and modern Linux Netns isolation. |
| **AimiliVPN (liuyesblog)** | [liuyesblog/AimiliVPN](https://github.com/liuyesblog/AimiliVPN) | Static mirror and cross-version comparative reference. |
| **fanout & miku-gate** | `byJoey/fanout` & `vioIetMiku/miku-gate` | Inspired our residential IP qualification algorithm (`is_residential`) and multi-source concurrent racing scheduler. |
| **Linux TCP BBR Practice** | Teddysun ([teddysun.com](https://teddysun.com)) / Toyo | Classical Linux TCP BBR congestion control tuning methodologies inspiring our kernel optimization scripts. |
| **Hysteria** | [apernet/hysteria](https://github.com/apernet/hysteria) | Groundbreaking UDP-Brutal transport protocol compensating for packet loss under adverse network conditions. |
| **EAimili** | Original AimiliVPN Core Team | Pioneered the original concept of residential proxy pool management and the web administration dashboard. |

---

### 9. Changelog (版本历史与更新记录)

> **Version Release Specification**: This project strictly adheres to Semantic Versioning (SemVer). Every major release is recorded in reverse chronological order with its **Version** (SemVer) and explicit **Release Timestamp** (YYYY-MM-DD HH:mm:ss CST).

#### 🌟 V1.6.0 (2026-10-30 16:45:00 CST) - Sing-box 原生多国家住宅出口矩阵与生产级安全稳态引擎
- 🛡️ **阶段一：安全清洗加固与下游连接主动切断（Phase 1）**：
  - **OpenVPN 白名单清洗与 RCE 防御 (`sanitize_ovpn_config`)**：借鉴 `OpenMili/aimili-vpngate` 生产级安全防护模型，建立指令白名单 `SAFE_OVPN_DIRECTIVES` 与内联块白名单 `SAFE_OVPN_INLINE_BLOCKS`，强行剥离所有 `up/down/script-security/plugin/tls-verify` 等高危脚本挂钩指令，从操作系统底层封杀不可信节点的提权与远程代码执行（RCE）漏洞；
  - **下游黑洞 Socket 主动切断机制 (`ConnRegistry`)**：借鉴 `Guli-Joy/aimili-vpngate` 连接追踪模型，建立客户端 Socket 全生命周期管理池。主节点发生切换或 IP 漂移自愈时，网桥主动调用 `close_all()` 强制切断存量下游死连接，促成客户端 TCP 栈毫秒级感知并重新发起拨号，彻底消灭客户端长达数十秒的无网卡死。
- 🚀 **阶段二：性能预筛分层与假活节点冷却防抖（Phase 2）**：
  - **非阻塞并发 TCP 端口毫秒级预筛 (`tcp_prescreen_nodes`)**：借鉴 `Guli-Joy/aimili-vpngate` 分层筛选思想，基于多线程发起 0.8s 非阻塞端口探针，毫秒级快速淘汰 40%~60% 的死端口节点，候选池筛选与建连测速效率提升 5~10 倍，UDP 节点默认免筛放行；
  - **假活与僵尸节点 1800 秒冷却惩罚池 (`NodeCooldownPool`)**：借鉴 `Guli-Joy/aimili-vpngate` 惩罚机制，对“OpenVPN 握手成功但无法出网获取出口公网 IP 或 IP 瞬间漂移”的假活节点，实施 1800 秒（30分钟）硬性冷却惩罚，抓取与换线时自动过滤，到期无感释放，彻底杜绝自愈死循环换线。
- 🌐 **阶段三：架构升华 - Sing-box 原生多国家住宅出口矩阵（Phase 3）**：
  - **Netns 多槽位独立网桥管理器 (`AimiliMultiSlotManager` & `ResidentialSlot`)**：突破单一 8500 家宽出口限制，实现物理隔离的多国家家宽出口矩阵：
    - **槽位 0**：本地 `127.0.0.1:8500`（默认全球最优家宽，命名空间 `aimili_ns_0`，保持 100% 向后兼容）；
    - **槽位 1**：本地 `127.0.0.1:8502`（美国独享住宅家宽 `US`，命名空间 `aimili_ns_1`）；
    - **槽位 2**：本地 `127.0.0.1:8503`（日本独享住宅家宽 `JP`，命名空间 `aimili_ns_2`）。
    - 支持原子状态保存与无损加载（`slots_state.json`），向控制面、Sing-box 与订阅生成器实时暴露各槽位状态。
  - **Sing-box 服务端多出站与多入站用户动态注入**：`setup_singbox.sh` 步骤 8.2 动态加载国家矩阵槽位，自适应注入 `resi-us-out`、`resi-jp-out` 以及各协议国家专属用户（`residential-us-user`、`residential-jp-user`）与分流路由；
  - **客户端聚合订阅生成引擎协同升级**：`generate_subs.py` 全生态生成包含 `[住宅-家宽·美国]`、`[住宅-家宽·日本]` 的 Base64、Clash Meta 与 Sing-box 客户端订阅，客户端策略组（Selector）全自动纳管国家矩阵选流。
- 🩺 **全阶段独立复检与红蓝对抗自动化单元测试**：
  - 新增 `tests/test_phase1_security_conn.py`（5/5 PASS）；
  - 新增 `tests/test_phase2_prescreen_cooldown.py`（3/3 PASS）；
  - 新增 `tests/test_phase3_multislot_subs.py`（4/4 PASS）；
  - 质量门禁 `scripts/code_gate.py` 全绿通过，0 个 P0/P1 阻塞性缺陷。

#### 🔒 V1.5.1 (2026-10-28 17:15:00 CST) - 全生态订阅防暴破防扫描与全链路容错闭环
- 🔒 **18443 订阅中心安全加固**：全面引入 `sub_<token>/` 随机安全路径，屏蔽根路径暴力扫描与 UUID 泄露（公网全网扫描器直接探测根路径严格返回 404）；
- 🛡️ **WARP 出站零黑洞**：彻底重构 Cloudflare WARP 注册容错机制，API 失败时杜绝注入未生效虚假凭据，保障直连主出站零损伤；
- ⚡ **DNS 智能探针异步化**：`generate_subs.py` 引入带 1.5 秒硬超时的线程池并发探测，杜绝在极端弱网环境下的进程阻塞；
- 🩺 **监控假阴性与安装容错闭环**：`check_health.sh` 纳管动态家宽健康退出码，`install.sh` 强化异常陷阱，确保部署总结与面板凭证始终可靠输出。

#### 🌟 V1.5.0 (2026-10-27 14:30:00 CST) - 工业级 Linux Netns 物理网络隔离与家宽调度重构版
- 🛡️ **Linux Netns 物理网络隔离**：引入独立网络命名空间（`aimili_ns_*`）与专用 `veth-pair` 子网（`10.99.<slot>.0/24`），将 OpenVPN 拨号进程绝对限制在隔离空间内部；**母机物理网卡（`eth0`）与默认网关 100% 保持完好，彻底终结了母机掉线与 SSH 失联的行业顽疾**；
- 🏠 **真实家宽精准过滤算法**：借鉴 `fanout` 设计，通过 `is_residential` 算法严格排除 `public-vpn-*` 域名，并通过 CIDR 掩码物理剔除筑波大学官方学术机房网段（`219.100.37.0/24`），确保出站 100% 走海外居民宽带；
- ⚡ **多源容灾池与并发竞发建连**：官方 API 阻断或超时（>10s）自动无缝切换至 Cloudflare Worker 镜像源（`https://p.xy.kg/vpngate`）；`RaceConditionScheduler` 并发探测多候选节点，先到先赢，换线耗时缩短至 3~5 秒，15 秒周期持续巡检与 IP 漂移自动无感自愈；
- 🔧 **动态链接器加固与防损坏规范**：建立 Linux 文本清洗规范，严禁对 ELF 二进制动态链接库执行 `sed -i`，保障所有 compiled C-Python `.so` 模块在 Ubuntu 24.04 (Python 3.12) 环境下零崩溃安全加载；
- 🩺 **全链路诊断工具升级 (`check_health.sh`)**：全协议矩阵 10 大核心网络端口（443, 8443, 8444, 8445, 8446, 18443, 8500, 8501）监听检测，集成客户端 -1 超时排错指南与住宅出站真实性检测；
- 🚀 **海外真机部署全绿验收**：在真实 Ubuntu 24.04 LTS (x86_64, Linux 6.8 内核) 服务器上完成三阶段全流程闭环验证，自动化质量门禁 `scripts/code_gate.py` 全绿通过。

#### 📦 V1.4.8 (2026-10-23 18:20:00 CST) - 架构可靠性与 Code Gate V2.0 加固版
- 修复 local-dns `detour: direct` 启动崩溃缺陷；
- 彻底解决 Sing-box 国内规则集启动死锁，转为高可用本地内联分流规则并开启 `cache_file`；
- 升级 `scripts/code_gate.py` 质量门禁，增加 Sing-box run 2 秒真机常驻冒烟测试。

---

**Version: V1.6.0 (Sing-box Dual-Outbound Enterprise Full-Stack Suite - Netns Multi-Matrix Edition)**
