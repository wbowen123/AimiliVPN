# AimiliVPN (V1.4.7) 代码审查报告

- 审查时间：2026-10-22
- 审查范围：仓库全部可读源码（`install.sh`、`aimili_cli.py`、`scripts/*.sh`、`scripts/generate_subs.py`、`vpngate_manager.py`、`proxy_server.py`、nginx 配置、README）
- 未覆盖：`core/**/*.so`（Cython 编译产物，共 130 个，无可读源码）、`country_registry.json` 的运行时消费逻辑
- 审查方式：静态分析（pyflakes / 人工逐行）+ 关键路径实机复现（Windows 侧 Python 直接执行 CLI）
- 本报告**只做分析，未改动任何源码**

标注约定：✅ 已实机复现 ｜ 🔍 静态推断（给出复核命令）

---

## 一、结论摘要

**项目整体工程质量高于同类一键脚本**：有事务式配置替换（备份→check→原子替换→健康校验→回滚）、GOMEMLIMIT 防 OOM、镜像容灾下载、防火墙多后端适配、卸载清单校验等设计，架构分层也清晰（安装器 / 运行守护 / 协议核心 / 订阅生成 / 运维子命令）。

但当前版本存在 **3 个会直接阻断使用的致命问题**，以及 **8 个"功能宣称已实现、实际不生效"的功能性缺陷**。建议先修 P0，再决定 P1 中哪些功能是"要么修好、要么从 README 下架"。

| 级别 | 数量 | 典型症状 |
| :--- | :--- | :--- |
| P0 阻断 | 3 | `ml` 主菜单直接崩、交互式安装中途退出、nginx 配置无法通过 `nginx -t` |
| P1 功能失效 | 8 | WARP 空转且写坏配置、C 组 CDN 节点全部不通、IP 漂移后订阅不更新、伪装站永不生效、面板更新检测被伪造 |
| P2 质量/安全 | 9 | 默认密码硬编码、Token 明文与可预测面板后缀、sysctl 互相覆盖、仓库 204MB 二进制 |
| P3 杂项 | 6 | 死代码、校验被 `|| true` 吞掉、README 版本自相矛盾 |

---

## 二、P0 阻断级缺陷

### P0-1 `aimili_cli.py` 调用两个从未定义的函数，主菜单与核心命令全部崩溃 ✅

**现象**（实机执行）：

```
$ python3 aimili_cli.py          # 即用户日常敲的 ml
NameError: name 'get_web_auth_data' is not defined   (aimili_cli.py:433)

$ python3 aimili_cli.py sub
NameError: name 'get_web_auth_data' is not defined   (aimili_cli.py:169)

$ python3 aimili_cli.py web
NameError: name 'print_web_dashboard' is not defined (aimili_cli.py:633)

$ python3 aimili_cli.py status
NameError: name 'get_web_auth_data' is not defined   (aimili_cli.py:742)
```

**位置**：`aimili_cli.py` 第 169 / 433 / 485 / 633 / 742 行调用，但全文件（以及 `git log -S` 追溯的全部历史提交）中都不存在 `def get_web_auth_data` / `def print_web_dashboard`。pyflakes 也独立报出同样 5 处 undefined name。

**影响**：README 中作为主入口的 `ml`、以及 `ml sub` / `ml web` / `ml status` 三条最常用命令 **100% 不可用**。安装结束时 `install.sh:1357` 与 `setup_singbox.sh:655` 都会调用 `aimili_cli.py sub`，因此部署完成后的"订阅卡片 + 二维码"也不会打印，用户拿不到节点信息。

**触发条件**：无条件。

**修复方向**：补两个函数实现——`get_web_auth_data()` 从 `vpngate_data/ui_auth.json` 读 `secret_path/username/password/port` 并拼 `web_url`（与 `install.sh:1304-1310` 的读取逻辑一致即可）；`print_web_dashboard()` 打印该地址与账号密码。或退一步，把 5 处调用替换为已有的读取逻辑并删除这两个引用。

---

### P0-2 `install.sh` 在函数外使用 `local`，`set -e` 下交互式安装中途静默退出 ✅（机制实测）/ 🔍（安装器定位）

**位置**：`install.sh:646`

```bash
    local mem_mb=$(( $(aimili_mem_kb) / 1024 ))
```

该行位于第 589 行开始的**顶层 `if` 块**内，不在任何函数体内。

**机制实测**（最小复现）：

```bash
$ printf '%s\n' 'set -e' 'echo before' 'local x=$(( 1 + 1 ))' 'echo after' > t1.sh
$ bash t1.sh
before
t1.sh: line 3: local: can only be used in a function
exit=1
```

即 `local` 在函数外返回 1，`set -e`（install.sh:2）立即终止脚本。

**影响**：交互式安装走到"定时维护看门狗"提问前直接退出，**后续 sing-box 部署、WARP、伪装站、订阅生成、HTTPS 配置全部不会执行**。默认模式 [1] 必现（因为 `INSTALL_SINGBOX=y`）。用户看到的是脚本莫名其妙结束，且已写入部分系统状态（依赖包、sysctl、服务单元）。

**注意**：这是**当前工作区未提交的改动**（`git diff install.sh` 可见，今日新增），已提交的 HEAD 版本没有这一行。也就是说这是一次"正在开发中的回归"，风险是它很容易被直接 commit 上去。

**修复方向**：去掉 `local`，改成 `mem_mb=$(( $(aimili_mem_kb) / 1024 ))`；并在 CI 里加 `shellcheck`（`SC2034`/`SC2168` 一类规则能直接拦住）。

---

### P0-3 nginx 配置在正则 location 中使用带 URI 的 `proxy_pass`，`nginx -t` 会报 emerg 🔍（高置信，附复核命令）

**位置**：`scripts/nginx/aimilivpn-production.conf:17-25`

```nginx
location ~ ^/(vmess|vmess-ws)$ {
    proxy_pass http://127.0.0.1:8445/vmess;   # ← 正则 location + 带 URI
    ...
}
```

nginx 对"正则 location / 命名 location / if 块内的 proxy_pass"禁止携带 URI 部分，会直接报：

```
nginx: [emerg] "proxy_pass" cannot have URI part in location given by regular expression,
or inside named location, or inside "if" statement, or inside "limit_except" block
```

**影响链**：`setup_https.sh:174` 安装该配置 → `setup_https.sh:189` 无保护地执行 `nginx -t`（脚本 `set -euo pipefail`）→ 脚本以非 0 退出 → `install.sh:1175` 无 `|| true` 地 `bash setup_https.sh` → 安装器 `set -e` 中断。同时 8443 面板与 18443 订阅入口全部不可用。

**复核命令**：`nginx -t`（部署机上直接跑）。

**附带问题**：即使去掉 URI 让语法通过，这条反代也大概率不通——sing-box 的 `transport.type = "http"` 是 HTTP/2 语义，而 `proxy_http_version 1.1` 只能向上游说 HTTP/1.1；nginx 开源版也无法对上游使用 h2。建议改成 `location = /vmess { proxy_pass http://127.0.0.1:8445; }` 并确认协议匹配，或干脆放弃用 nginx 中转 VMess。

---

## 三、P1 功能失效级缺陷

### P1-1 WARP 写坏配置后谎称"已安全回滚"，且规则用了已废弃的 `geosite` 🔍

**位置**：`scripts/setup_warp.sh:169-297`

两个问题叠加：

1. **假回滚**：Python 段（276 行）**直接覆写** `/etc/sing-box/config.json`，之后才 `sing-box check`（283 行）。检查失败时只打印"配置已安全回滚"并 `return 1`，**没有任何恢复动作**——磁盘上留下的是那份未通过校验的配置。当前运行的进程仍用内存里的旧配置，看起来"没事"，但下一次 `systemctl restart sing-box`（看门狗、升级、证书同步、`ml singbox restart` 都会触发）就会起不来，**表现为整台机器节点全挂**。
2. **规则本身大概率无效**：`geosite: ["openai","netflix",...]`（252-258 行）是 sing-box 1.8 起已废弃、改用 `rule_set` 的旧写法，且依赖 `geosite.db` 数据库文件——脚本从未下载该数据库。在默认安装的 1.14.x 内核上，要么 `check` 失败（触发上面的假回滚），要么启动后规则不生效，**"自适应 WARP 解锁"这个旗舰功能实际空转**。

**修复方向**：写入前 `cp` 一份 `.bak`，失败时 `mv` 回来（照抄 `setup_singbox.sh:236-238 / 513-517` 已有的正确写法）；`geosite` 改为 `rule_set` + 启动时下载 `sing-box` 官方 geo 规则集，或直接用 `domain_suffix` 列表硬编码主流域名。

---

### P1-2 配置了域名后，VMess 直连节点的 TLS 与服务端不匹配 🔍

**服务端**（`setup_singbox.sh:358-377`）：`vmess-in` 监听 8445，只有 `transport.http`，**没有任何 `tls` 字段**（明文）。

**客户端**（`generate_subs.py:202 / 215 / 552`）：`"tls": "tls" if domain else ""`、`"tls": bool(domain)`、`"tls": {"enabled": bool(domain)}`。

即：**一旦用户填了域名，VMess 直连节点（A 组第 9/10 条 + IPv6 第 14 条）全部变成"客户端 TLS 握手 → 服务端明文"，必然连不上**；不填域名时反而正常。这类"只在特定配置下坏"的 bug 极难被用户定位。

**修复方向**：二者取一——要么服务端给 vmess inbound 加 TLS，要么客户端恒为明文（`tls: false`）。

---

### P1-3 C 组 CDN / Argo 节点没有可落地的源站（4 条节点全部不通） 🔍

**生成逻辑**（`generate_subs.py:280-332`）：C 组节点统一指向 `clean_ip:443`，`SNI = cdn.域名`，路径 `/vmess` 或 `/vless-ws`。

**实际服务端**：443 端口只有 sing-box 的 VLESS-Reality（TCP）与 Hysteria 2（UDP）。nginx 只监听 8443 / 18443，**没有任何 443 的 HTTP 源站**。所以 CDN 回源到 443 时会被 Reality 当作"未通过握手的探测流量"转发到伪装目标（如 gateway.icloud.com），拿不到 VMess 服务。

**另外两个叠加问题**：
- Cloudflare 代理（橙云）**只支持 443 / 2053 / 2083 / 2087 / 2096 / 8443** 这几个 HTTPS 端口，8445 不在其中，无法通过"源站端口"绕开；
- Argo 节点用 `net: ws` + `path: /vmess-ws`（`generate_subs.py:284`），而 quick tunnel 指向 `http://127.0.0.1:8445`，8445 只提供 HTTP transport 的 `/vmess`，**路径与传输方式都对不上**。

**影响**：README 宣传的"VPS 被封时 100% 破墙救急"的 C 组 4 条节点，实际一条也用不了。

**修复方向**：给 nginx 增加 `listen 443 ssl` 的 CDN 回源 vhost（或用 Reality 的 `dest` 分流），并在 CF 侧用 Origin Rules 把 443 映射到该 vhost；Argo 节点改为 `net: http` + `path: /vmess`，或给 8445 增加 ws 传输。

---

### P1-4 公网 IP 漂移后订阅不会重新生成 🔍

**位置**：`scripts/setup_cron.sh:142-144`

```bash
if [[ -x "${INSTALL_DIR}/scripts/generate_subs.py" ]]; then
    python3 "${INSTALL_DIR}/scripts/generate_subs.py" >/dev/null 2>&1 || true
fi
```

`generate_subs.py` 的 `__main__` 要求两个位置参数（`singbox_nodes.json`、`output_dir`），无参调用只会打印用法并 `sys.exit(1)`，错误被 `|| true` 吞掉。**结果是：IP 变了、`public_ip.txt` 更新了、TG 也推送了"已自动更新订阅"，但订阅文件里还是旧 IP。**

另外 `[[ -x ... ]]` 判断的是可执行位，而 `generate_subs.py` 在仓库里通常没有 +x，这个分支可能压根不会进入。

**修复方向**：改为 `python3 generate_subs.py "$DATA_DIR/singbox_nodes.json" /var/www/aimilivpn-sub && cp -f ... /var/lib/aimilivpn/subscriptions/`，并去掉 `|| true` 或至少记录日志。

---

### P1-5 伪装站部署到磁盘，但没有任何 Web 服务引用它 🔍

`setup_camouflage.sh` 把 4 套模板写入 `/var/www/camouflage/index.html`，然后 `systemctl reload nginx`。但两份 nginx 配置（`scripts/nginx/aimilivpn-production.conf`、`deploy/aimilivpn-production.conf`）中**没有任何 `root /var/www/camouflage` 或对应 location**；Reality 的 `handshake.server` 也是外部域名。

全仓库 grep 结果：除卸载时的 `rm -rf` 外，`/var/www/camouflage` 无任何消费者。**README 第 17 条"HTML5 高保真本地伪装库……完美抵御主动嗅探"目前是无效功能**，用户切换模板后只是重载了一次 nginx。

**修复方向**：给 443 增加默认 vhost 指向该目录（配合 P1-3 一起做），或明确说明它只是"手动反代时可用的素材库"。

---

### P1-6 Telegram Bot 只有"发送"没有"服务"，且发送失败永远返回成功 🔍

- `tg_bot.sh:12` 定义了 `SERVICE_FILE="/etc/systemd/system/aimilivpn-tgbot.service"`，**全脚本从未创建该文件**。`install.sh` 的卸载流程却会 `systemctl stop aimilivpn-tgbot`，README 宣称的"TG 指令交互"没有任何常驻进程实现。
- `send_tg_message()` 用 Python 捕获所有异常后只 `print("FAILED: ...")`，函数退出码恒为 0；`send_test_message` 依据退出码判断"测试消息发送成功"。**Token 错了、ChatID 错了、被墙了，都会显示"发送成功"。**
- `vpngate_data/tg_bot.json` 未设权限（默认 644），Bot Token 明文且同机任意用户可读。

**修复方向**：Python 段 `sys.exit(1)` 传递失败；`chmod 600` 配置文件；要么实现 systemd 常驻服务（`getUpdates` 轮询），要么从 README 删掉"指令交互"。

---

### P1-7 网页面板的"检查更新"被强制改写成"已是最新"，且版本号硬编码 V1.2.0 🔍

**位置**：`vpngate_manager.py:48-187`（`_apply_patches`）

```python
VERSION_TAG = "V1.2.0"
...
elif clean_path == "/api/github_update/check":
    return self.send_json({... "has_update": False, "relation": "up_to_date" ...})
```

并且 `send_json` 钩子会把任何含 `has_update` / `latest_version` 的响应统一改成 `False` / 当前版本。

**影响**：面板里的版本永远是 `V1.2.0 - <commit>`（而 `VERSION` 文件是 `V1.4.7`），"检查更新"永远返回"已是最新正式版"。这属于**用 patch 掩盖功能**：用户无法从面板获知有新版本，也让"版本号"这条排障线索失效。

**修复方向**：改为真实读取 `VERSION` 文件 + 调用 GitHub API；若确实要锁定仓库，只改 `repository` 字段，不要伪造 `has_update`。

---

### P1-8 生成的 `singbox.json` 客户端配置与默认内核 1.14.x 不兼容 🔍

`generate_subs.py:638-667` 输出的客户端配置使用：

- 旧版 DNS server 格式 `{"tag": "...", "address": "https://8.8.8.8/dns-query"}`；
- 旧版 DNS 规则项 `{"outbound": ["any"], ...}`；
- 路由规则 `geoip` / `geosite`（1.8 起废弃）。

按 sing-box 官方迁移文档，**旧 DNS 格式的兼容层在 1.14.0 被移除**（1.12 release notes 原文："Compatibility for old formats will be removed in sing-box 1.14.0"）。而本项目 `setup_singbox.sh:72` 与 `manage_core.sh:47` 的默认目标版本正是 `1.14.3`。

**影响**：用户把 `/singbox.json` 导入新版 Sing-box 客户端会直接报配置错误；README 宣称的"Sing-box 原生 1.10+ 开箱即用"只在 1.10~1.13 成立。

**修复方向**：改用 `{"type":"https","server":"8.8.8.8","detour":"..."}` 新格式 + `rule_set`，或明确标注"仅适配 1.10–1.13"。

---

## 四、P2 质量与安全问题

| # | 问题 | 位置 | 说明与建议 |
| :-- | :--- | :--- | :--- |
| P2-1 | DNS 分流规则自相矛盾 | `generate_subs.py:646` | `{"outbound":["any"],"server":"local-dns"}` 命中所有查询，`final: remote-dns` 永远用不到 → 被墙域名全部走 223.5.5.5 解析，存在污染风险。应删除该条或改为 `outbound` 精确匹配。 |
| P2-2 | 域名只 `export` 不落盘 | `install.sh:702`、`setup_singbox.sh:148-157` | `AIMILIVPN_DOMAIN` 只在安装器进程内有效；后续 `setup_singbox.sh` 靠"证书 SAN 反推"取域名，`direct.` / `cdn.` 前缀一旦混用就会生成错误节点。建议安装时写入 `/etc/default/aimilivpn` 作为唯一真源。 |
| P2-3 | 新增的 DNS-01 选项实际无效（未提交改动） | `install.sh:601-611` | 只 `export CF_Token`，而证书实际由 **systemd 服务** `aimilivpn` 申请，systemd 不会继承安装器的环境变量，也没写入 `EnvironmentFile`。选 [2] 仍然会走 HTTP-01 并失败。 |
| P2-4 | 升级脚本的"校验"是假的 | `upgrade_script.sh:160-162` | `py_compile ... || true` 之后无条件打印"语法完整性校验通过"；`git reset --hard origin/main`（151 行）会丢弃用户本地改动，且备份只覆盖 `vpngate_data`。建议失败即中止 + 备份整个 `/opt/aimilivpn`（除 .git）。 |
| P2-5 | 硬编码凭据与可预测的面板后缀 | `install.sh:868, 1298, 1305`；`setup_singbox.sh:120` | SOCKS5 默认密码 `ilovestudy`；`ui_auth.json` 缺失时回退到固定后缀 `EJsW2EeBo9lY`。若文件被误删，面板"防探测后缀"形同虚设。建议随机生成并 600 权限。 |
| P2-6 | Token 泄露面偏大 | `tg_bot.sh:107`、`setup_argo.sh:177` | TG Token 明文 644；cloudflared `--token` 写在 unit 里并出现在 `ps` 输出中（同机任意用户可见）。建议 `chmod 600` + 使用 `--token-file` / credentials 文件。 |
| P2-7 | sysctl 互相覆盖 + `drop_caches` 反模式 | `install.sh:1095` vs `tune_bbr.sh:44` | `99-aimilivpn-bbr.conf` 设 `somaxconn=32768`，但按文件名排序 `99-aimilivpn.conf` 后加载、把它改回 1024，BBR 调优被抵消。另外每日 `echo 3 > drop_caches` 并不会"释放内存"，只是丢弃页缓存、增加后续磁盘 IO，对 OOM 无实质帮助（真正的保护是 GOMEMLIMIT + swap，项目已有）。 |
| P2-8 | 仓库 204MB 二进制 + 安装全量 clone | `core/**`（130 个 .so，204MB；`.git` 130MB） | `install.sh:824` 每次安装都 `git clone` 整个仓库，等于每次装都拉 200MB+，在受限 VPS 上极慢且易失败。建议 CI 产出 release 附件（按 arch + py 版本），安装时只下当前平台；或把 `core/` 移到独立 release 分支。 |
| P2-9 | 双份 nginx 配置漂移 + README 版本矛盾 | `deploy/aimilivpn-production.conf` vs `scripts/nginx/…`；`README.md:32` vs `:358` | `deploy/` 那份已与使用中的配置不一致（无 18443 细分 location、有 timeout 参数），属死文件；README 顶部写 V1.4.7、结尾写 V1.4.5。建议删一份、版本号单一来源。 |

---

## 五、P3 杂项

1. `check_health.sh:136-140`：`RESI_TIME` / `START_TS` / `END_TS` 计算后从未使用（死代码）。
2. `install.sh:858` 只 `py_compile vpngate_manager.py proxy_server.py`，**没有检查 `aimili_cli.py` / `generate_subs.py`**；而 P0-1 这类未定义名用 `pyflakes` 一秒可发现，`py_compile` 查不出来。建议 `pip install pyflakes && python3 -m pyflakes *.py scripts/*.py` 进 CI。
3. `check_time_sync.sh` 完全忽略传入的 `fix` 参数（`setup_cron.sh:85` 传了），行为与参数不符；且用 `date -s "@epoch"` 直接跳时钟，若远端 `Date` 头被 CDN 缓存成旧值，会造成时钟回跳。
4. `test_sni.sh:41` 依赖 `timeout` 命令，最小化系统（部分 Alpine）没有该命令会导致所有候选域名被判"不合格"，最终回落到 `gateway.icloud.com`。
5. 用户输入未校验/未转义即插入配置：`SINGBOX_CAMOUFLAGE` 直接进 `setup_singbox.sh:270` 的 JSON heredoc，含 `"` 即可破坏 JSON（本地 root 输入，风险低但应有白名单校验）。
6. `install.sh:910` 与 `:990` 两次写入 `/usr/bin/ml`，前一份被后一份覆盖（前者有 `except Exception` 兜底，后者没有，异常时直接抛栈）。

---

## 六、优化建议（按收益排序）

1. **建立"配置写入"统一事务函数**：目前只有 `setup_singbox.sh` 有完整的备份→校验→原子替换→回滚闭环，`setup_warp.sh` / `manage_cert.sh` / `cf_speedtest.sh` 都是直接覆写。抽成 `lib/tx.sh`（`tx_begin` / `tx_commit` / `tx_rollback`），所有脚本复用——这是当前最高性价比的稳定性改造。
2. **拆出"只重生成订阅"的轻量命令**：现在改一个优选 IP 就要跑整个 `setup_singbox.sh`（重跑 SNI 测速、重跑 WARP 探测、重启 sing-box）。建议 `ml sub-regen`，只跑 `generate_subs.py` + `cp`，秒级完成、零中断。
3. **配置真源收敛**：`/etc/default/aimilivpn`（凭据/出口）+ `vpngate_data/state.json`（域名/IP/端口）+ `ui_auth.json`（面板），三者职责重叠且互相反推。建议收敛为单一 `state.json`，其他脚本只读不推。
4. **CI 三件套**：`shellcheck`（全量 .sh）、`pyflakes`（全量 .py）、`bash -n`。当前 P0-1、P0-2 都能被前两项直接拦下，成本不到 10 行配置。
5. **安装器幂等化**：`install.sh` 目前混装了"环境检测 / 依赖安装 / 代码部署 / 服务注册 / 证书 / 各功能模块"六个阶段，任一环节失败都留下半装状态。建议支持 `--only=<stage>` 与 `--check`（已有 `AIMILI_DETECT_ONLY` 雏形），便于失败后原地重试而非从头再来。
6. **可观测性**：`ml test` 目前只查本机端口与 8500 出口，没有"客户端视角"的握手自测（Reality 握手、Hy2 证书链）。建议加一条 `sing-box` 临时客户端实例做端到端探活，把 P1-2 / P1-3 这类"配置错配"在部署时暴露出来。
7. **安全基线**：随机 SOCKS5 密码、`ui_auth.json`/`tg_bot.json` 600 权限、去掉固定面板后缀兜底、Argo 用 credentials 文件替代 `--token`、`/var/log` 加 logrotate（当前 `aimilivpn-maintenance.log` 只增不减）。
8. **降低对宿主机的侵入**：全局 `rp_filter=2`、遍历所有网卡改写 `rp_filter`、每日 `drop_caches` 都属于"影响面大于收益"的操作，建议改为仅对 `tun*`/`vpn_*` 网卡设置，并去掉定时 `drop_caches`。

---

## 七、10 分钟自检清单（部署机上逐条执行）

```bash
# 1) P0-1：主菜单是否崩溃
ml                    # 期望看到控制台；若 NameError 即命中
python3 -m pyflakes /opt/aimilivpn/*.py /opt/aimilivpn/scripts/*.py

# 2) P0-2：安装器是否有函数外 local
grep -n "^\s*local " /opt/aimilivpn/install.sh | head

# 3) P0-3：nginx 语法
nginx -t

# 4) P1-1：WARP 写坏配置后能否重启
sing-box check -c /etc/sing-box/config.json && systemctl restart sing-box && systemctl is-active sing-box

# 5) P1-2：VMess 直连节点是否真的能通（用订阅里的节点实测一次）

# 6) P1-4：IP 漂移后订阅是否更新
python3 /opt/aimilivpn/scripts/generate_subs.py    # 无参应打印用法并退出 1 —— 证明 cron 里那行是空操作

# 7) P1-6：TG 发送失败是否被当成成功（故意填错 Token 试一次）

# 8) P1-5：伪装站是否可访问
curl -sk https://127.0.0.1:18443/ | head   # 与 /var/www/camouflage/index.html 对比
```

---

## 八、总体评价

- **架构与工程意识：优**。事务回滚、GOMEMLIMIT、镜像容灾、防火墙多后端、卸载校验，这些在同生态脚本里都属上乘。
- **实现与宣称的一致性：差**。WARP 自适应、CDN 破墙、伪装站、TG 交互、面板更新检测这 5 个"卖点功能"目前都不成立（P1-1/3/5/6/7），README 的宣传口径明显超前于实现。
- **可维护性风险：中高**。130 个二进制模块 + 8 个 setup 脚本各自为政 + 缺少 lint/CI，导致 P0 级问题能直接进入主分支。

**建议的修复顺序**：P0-1 → P0-2 → P0-3（先让工具能跑起来）→ P1-1（防止把机器搞挂）→ P1-2/P1-3（让节点真的能用）→ 其余按功能取舍。
