#!/usr/bin/env bash
# ==============================================================================
# AimiliVPN - HTML5 本地高保真伪装网站模版库管理器 (setup_camouflage.sh)
# 提供 4 套免外网依赖、纯本地极速加载的高保真可交互静态站点
# 部署于 /var/www/camouflage/，配合 Nginx / 443 回退完美抵御主动探测与特征扫描
# ==============================================================================

set -e

INSTALL_DIR="/opt/aimilivpn"
CAMO_DIR="/var/www/camouflage"
META_FILE="${CAMO_DIR}/template_info.json"

C_RED="\033[0;31m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[0;33m"
C_BLUE="\033[0;36m"
C_BOLD="\033[1m"
C_RESET="\033[0m"

log_info() { echo -e "${C_GREEN}[INFO]${C_RESET} $1"; }
log_warn() { echo -e "${C_YELLOW}[WARN]${C_RESET} $1"; }
log_err() { echo -e "${C_RED}[ERROR]${C_RESET} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_err "请使用 root 权限运行此脚本: sudo bash $0"
        exit 1
    fi
}

mkdir -p "${CAMO_DIR}"

deploy_tech_saas() {
    log_info "正在部署【现代化科技云原生与 SaaS 平台官网】模板..."
    cat > "${CAMO_DIR}/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Aether Cloud | Enterprise High-Throughput Edge Infrastructure</title>
    <style>
        :root {
            --bg-primary: #0a0e17;
            --bg-secondary: #131b2e;
            --accent: #3b82f6;
            --accent-glow: #60a5fa;
            --text-main: #f8fafc;
            --text-muted: #94a3b8;
            --card-border: rgba(255, 255, 255, 0.08);
        }
        * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
        body { background-color: var(--bg-primary); color: var(--text-main); line-height: 1.6; }
        header { display: flex; justify-content: space-between; align-items: center; padding: 24px 8%; border-bottom: 1px solid var(--card-border); }
        .logo { font-size: 1.3rem; font-weight: 700; color: #fff; display: flex; align-items: center; gap: 8px; }
        .logo-dot { width: 10px; height: 10px; background: var(--accent); border-radius: 50%; box-shadow: 0 0 12px var(--accent-glow); }
        nav a { color: var(--text-muted); text-decoration: none; margin-left: 24px; font-size: 0.95rem; transition: color 0.2s; }
        nav a:hover { color: #fff; }
        .hero { padding: 90px 8% 60px; text-align: center; max-width: 900px; margin: 0 auto; }
        .badge { display: inline-block; padding: 6px 16px; background: rgba(59, 130, 246, 0.12); color: var(--accent-glow); border-radius: 20px; font-size: 0.85rem; margin-bottom: 24px; border: 1px solid rgba(59, 130, 246, 0.3); }
        h1 { font-size: 3rem; font-weight: 800; letter-spacing: -1px; margin-bottom: 20px; background: linear-gradient(135deg, #fff 40%, #94a3b8 100%); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
        p.subtitle { font-size: 1.15rem; color: var(--text-muted); margin-bottom: 36px; }
        .btn-group { display: flex; justify-content: center; gap: 16px; }
        .btn { padding: 12px 28px; border-radius: 8px; font-weight: 600; text-decoration: none; transition: 0.2s; font-size: 0.95rem; }
        .btn-primary { background: var(--accent); color: #fff; box-shadow: 0 4px 16px rgba(59, 130, 246, 0.3); }
        .btn-primary:hover { background: #2563eb; }
        .btn-outline { background: transparent; color: #fff; border: 1px solid var(--card-border); }
        .btn-outline:hover { background: rgba(255, 255, 255, 0.05); }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 24px; padding: 60px 8%; max-width: 1200px; margin: 0 auto; }
        .card { background: var(--bg-secondary); border: 1px solid var(--card-border); padding: 32px; border-radius: 12px; transition: transform 0.2s, border-color 0.2s; }
        .card:hover { transform: translateY(-4px); border-color: rgba(59, 130, 246, 0.4); }
        .card h3 { font-size: 1.2rem; margin-bottom: 12px; color: #fff; }
        .card p { color: var(--text-muted); font-size: 0.95rem; }
        footer { border-top: 1px solid var(--card-border); padding: 36px 8%; text-align: center; color: var(--text-muted); font-size: 0.85rem; }
    </style>
</head>
<body>
    <header>
        <div class="logo"><div class="logo-dot"></div>Aether Infrastructure</div>
        <nav>
            <a href="#services">Services</a>
            <a href="#solutions">Solutions</a>
            <a href="#pricing">Pricing</a>
            <a href="#docs">Documentation</a>
        </nav>
    </header>
    <main>
        <div class="hero">
            <div class="badge">v4.12 Enterprise Edge Engine Released</div>
            <h1>Global Anycast Distributed Network & Real-Time Computing</h1>
            <p class="subtitle">Accelerate enterprise microservices with deterministic sub-millisecond edge routing, distributed caching, and zero-trust perimeter security.</p>
            <div class="btn-group">
                <a href="#start" class="btn btn-primary">Deploy Cluster</a>
                <a href="#demo" class="btn btn-outline">Read Whitepaper</a>
            </div>
        </div>
        <div class="grid" id="services">
            <div class="card">
                <h3>Global Anycast Routing</h3>
                <p>Spans over 300 tier-1 Internet Exchange Points with BGP automated traffic balancing and instant latency optimization.</p>
            </div>
            <div class="card">
                <h3>L7 Intelligent Edge WAF</h3>
                <p>Hardware-accelerated deep packet inspection filtering volumetric DDoS attacks, TLS replay risks, and malicious probers.</p>
            </div>
            <div class="card">
                <h3>Native Micro-VM Runtime</h3>
                <p>Isolate workloads in lightweight 5ms cold-start sandboxes with global state synchronization and TLS 1.3 0-RTT handshakes.</p>
            </div>
        </div>
    </main>
    <footer>
        <p>&copy; 2026 Aether Edge Technologies Inc. All rights reserved. ISO/IEC 27001 Certified Infrastructure.</p>
    </footer>
</body>
</html>
EOF
    echo '{"template": "tech_saas", "name": "科技云原生 SaaS 官网"}' > "${META_FILE}"
}

deploy_tools_calculator() {
    log_info "正在部署【全功能在线工具箱与极简计算器】模板..."
    cat > "${CAMO_DIR}/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DevBox 在线开发者工具箱 & 科学计算中心</title>
    <style>
        :root { --bg: #f3f4f6; --panel: #ffffff; --primary: #2563eb; --text: #1f2937; }
        * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
        body { background: var(--bg); color: var(--text); padding: 30px 20px; }
        .container { max-width: 900px; margin: 0 auto; }
        header { text-align: center; margin-bottom: 30px; }
        h1 { font-size: 1.8rem; margin-bottom: 8px; color: #111827; }
        p.desc { color: #6b7280; font-size: 0.95rem; }
        .tools-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 24px; }
        @media(max-width: 768px) { .tools-grid { grid-template-columns: 1fr; } }
        .box { background: var(--panel); padding: 24px; border-radius: 12px; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.05); }
        h2 { font-size: 1.2rem; margin-bottom: 16px; border-bottom: 2px solid #e5e7eb; padding-bottom: 8px; }
        /* Calculator */
        .calc-screen { width: 100%; height: 50px; background: #1f2937; color: #10b981; font-family: monospace; font-size: 1.5rem; text-align: right; padding: 10px; border-radius: 6px; border: none; margin-bottom: 12px; }
        .calc-btns { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; }
        .btn-c { padding: 14px; font-size: 1.1rem; background: #e5e7eb; border: none; border-radius: 6px; cursor: pointer; transition: 0.1s; }
        .btn-c:hover { background: #d1d5db; }
        .btn-op { background: #dbeafe; color: #1d4ed8; font-weight: bold; }
        .btn-eq { background: #2563eb; color: #fff; grid-column: span 2; }
        /* Base64 & Hash */
        textarea { width: 100%; height: 100px; padding: 10px; border: 1px solid #d1d5db; border-radius: 6px; resize: none; margin-bottom: 12px; font-family: monospace; }
        .action-btns { display: flex; gap: 10px; margin-bottom: 12px; }
        .btn-act { padding: 8px 16px; background: var(--primary); color: #fff; border: none; border-radius: 6px; cursor: pointer; font-size: 0.9rem; }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>🛠️ DevBox 在线极简工具箱</h1>
            <p class="desc">纯本地客户端运行 · 零网络上传隐私安全 · 极速计算与编解码</p>
        </header>
        <div class="tools-grid">
            <div class="box">
                <h2>标准/科学计算器</h2>
                <input type="text" id="calc-display" class="calc-screen" value="0" readonly>
                <div class="calc-btns">
                    <button class="btn-c" onclick="calcClear()">C</button>
                    <button class="btn-c" onclick="calcDel()">←</button>
                    <button class="btn-c btn-op" onclick="calcInput('/')">/</button>
                    <button class="btn-c btn-op" onclick="calcInput('*')">×</button>
                    <button class="btn-c" onclick="calcInput('7')">7</button>
                    <button class="btn-c" onclick="calcInput('8')">8</button>
                    <button class="btn-c" onclick="calcInput('9')">9</button>
                    <button class="btn-c btn-op" onclick="calcInput('-')">-</button>
                    <button class="btn-c" onclick="calcInput('4')">4</button>
                    <button class="btn-c" onclick="calcInput('5')">5</button>
                    <button class="btn-c" onclick="calcInput('6')">6</button>
                    <button class="btn-c btn-op" onclick="calcInput('+')">+</button>
                    <button class="btn-c" onclick="calcInput('1')">1</button>
                    <button class="btn-c" onclick="calcInput('2')">2</button>
                    <button class="btn-c" onclick="calcInput('3')">3</button>
                    <button class="btn-c" onclick="calcInput('.')">.</button>
                    <button class="btn-c" onclick="calcInput('0')">0</button>
                    <button class="btn-c btn-eq" onclick="calcEqual()">=</button>
                </div>
            </div>
            <div class="box">
                <h2>Base64 快速编解码</h2>
                <textarea id="b64-input" placeholder="输入要编码或解码的文本..."></textarea>
                <div class="action-btns">
                    <button class="btn-act" onclick="b64Encode()">Base64 编码</button>
                    <button class="btn-act" onclick="b64Decode()">Base64 解码</button>
                    <button class="btn-act" style="background:#6b7280" onclick="document.getElementById('b64-input').value=''">清空</button>
                </div>
                <textarea id="b64-output" placeholder="处理结果输出区..." readonly></textarea>
            </div>
        </div>
    </div>
    <script>
        let expr = "";
        const disp = document.getElementById('calc-display');
        function calcInput(ch) { expr += ch; disp.value = expr; }
        function calcClear() { expr = ""; disp.value = "0"; }
        function calcDel() { expr = expr.slice(0, -1); disp.value = expr || "0"; }
        function calcEqual() {
            try {
                disp.value = Function('"use strict";return (' + expr + ')')();
                expr = disp.value;
            } catch(e) { disp.value = "Error"; expr = ""; }
        }
        function b64Encode() {
            try {
                const s = document.getElementById('b64-input').value;
                document.getElementById('b64-output').value = btoa(unescape(encodeURIComponent(s)));
            } catch(e) { alert("编码失败: " + e.message); }
        }
        function b64Decode() {
            try {
                const s = document.getElementById('b64-input').value;
                document.getElementById('b64-output').value = decodeURIComponent(escape(atob(s)));
            } catch(e) { alert("解码失败: 格式不正确"); }
        }
    </script>
</body>
</html>
EOF
    echo '{"template": "tools_calculator", "name": "在线工具箱与计算器"}' > "${META_FILE}"
}

deploy_engineering_blog() {
    log_info "正在部署【极简极客技术博客与工程随笔】模板..."
    cat > "${CAMO_DIR}/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Ray's Engineering Log | Systems, Kernels & Distributed Storage</title>
    <style>
        body { max-width: 720px; margin: 40px auto; padding: 0 20px; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; color: #222; line-height: 1.7; background: #fff; }
        header { margin-bottom: 50px; border-bottom: 2px solid #eee; padding-bottom: 20px; }
        h1 { font-size: 1.75rem; letter-spacing: -0.5px; }
        .meta { color: #888; font-size: 0.9rem; }
        article { margin-bottom: 40px; }
        h2 { font-size: 1.3rem; margin-bottom: 6px; }
        h2 a { color: #111; text-decoration: none; }
        h2 a:hover { color: #0066cc; }
        .date { font-size: 0.85rem; color: #999; margin-bottom: 8px; }
        p { color: #444; font-size: 0.98rem; margin-bottom: 12px; }
        pre { background: #f6f8fa; padding: 12px; border-radius: 6px; font-size: 0.88rem; overflow-x: auto; }
        footer { margin-top: 60px; padding-top: 20px; border-top: 1px solid #eee; font-size: 0.85rem; color: #aaa; text-align: center; }
    </style>
</head>
<body>
    <header>
        <h1>Ray's Engineering Notes</h1>
        <div class="meta">Senior Infrastructure Architect @ OpenSource Labs · Focus on eBPF, TCP BBR, and NVMe-oF</div>
    </header>
    <main>
        <article>
            <h2><a href="#">Deep Dive into Linux TCP BBRv3 Pacing and Bufferbloat Reduction</a></h2>
            <div class="date">October 14, 2026 · 8 min read · Systems Networking</div>
            <p>Recent benchmarks across trans-Pacific 100GbE links show BBRv3 achieves 28% higher throughput under 2% stochastic loss compared to classic Cubic. Here is our kernel sysctl configuration and packet queue trace.</p>
            <pre><code>net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq_pie
net.ipv4.tcp_notsent_lowat = 16384</code></pre>
        </article>
        <article>
            <h2><a href="#">Zero-Copy RPC Serialization in Rust using FlatBuffers</a></h2>
            <div class="date">September 29, 2026 · 12 min read · Distributed Systems</div>
            <p>Investigating memory layout alignment and cache line misses when deserializing high-volume telemetry packets in multi-threaded asynchronous event loops.</p>
        </article>
    </main>
    <footer>
        <p>&copy; 2026 Ray Zhang. Powered by static markdown engine. All opinions are my own.</p>
    </footer>
</body>
</html>
EOF
    echo '{"template": "engineering_blog", "name": "极简极客技术博客"}' > "${META_FILE}"
}

deploy_html5_game() {
    log_info "正在部署【经典 HTML5 2048 益智小游戏】模板..."
    cat > "${CAMO_DIR}/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>2048 Puzzle Web Edition</title>
    <style>
        body { background: #faf8ef; color: #776e65; font-family: "Clear Sans", "Helvetica Neue", Arial, sans-serif; display: flex; flex-direction: column; align-items: center; justify-content: center; min-height: 100vh; margin: 0; }
        .header { display: flex; justify-content: space-between; align-items: center; width: 340px; margin-bottom: 20px; }
        h1 { font-size: 48px; font-weight: bold; margin: 0; color: #776e65; }
        .score-box { background: #bbada0; padding: 6px 16px; border-radius: 6px; color: #fff; text-align: center; }
        .score-title { font-size: 11px; text-transform: uppercase; font-weight: bold; }
        .score-val { font-size: 20px; font-weight: bold; }
        #board { width: 340px; height: 340px; background: #bbada0; border-radius: 6px; padding: 10px; display: grid; grid-template-columns: repeat(4, 1fr); grid-gap: 10px; box-sizing: border-box; }
        .cell { background: rgba(238, 228, 218, 0.35); border-radius: 4px; display: flex; justify-content: center; align-items: center; font-size: 26px; font-weight: bold; color: #776e65; }
        .c-2 { background: #eee4da; }
        .c-4 { background: #ede0c8; }
        .c-8 { background: #f2b179; color: #f9f6f2; }
        .c-16 { background: #f59563; color: #f9f6f2; }
        .c-32 { background: #f67c5f; color: #f9f6f2; }
        .c-64 { background: #f65e3b; color: #f9f6f2; }
        .c-128 { background: #edcf72; color: #f9f6f2; font-size: 22px; }
        .c-256 { background: #edcc61; color: #f9f6f2; font-size: 22px; }
        .c-512 { background: #edc850; color: #f9f6f2; font-size: 22px; }
        .c-1024 { background: #edc53f; color: #f9f6f2; font-size: 18px; }
        .c-2048 { background: #edc22e; color: #f9f6f2; font-size: 18px; }
        .tip { margin-top: 15px; font-size: 13px; color: #8f7a66; }
    </style>
</head>
<body>
    <div class="header">
        <h1>2048</h1>
        <div class="score-box">
            <div class="score-title">SCORE</div>
            <div id="score" class="score-val">0</div>
        </div>
    </div>
    <div id="board"></div>
    <div class="tip">HOW TO PLAY: Use your <b>Arrow Keys</b> to merge tiles!</div>
    <script>
        let board = Array(4).fill(0).map(() => Array(4).fill(0));
        let score = 0;
        function init() {
            spawn(); spawn(); render();
            window.addEventListener('keydown', e => {
                let moved = false;
                if (e.key === 'ArrowUp') moved = moveUp();
                else if (e.key === 'ArrowDown') moved = moveDown();
                else if (e.key === 'ArrowLeft') moved = moveLeft();
                else if (e.key === 'ArrowRight') moved = moveRight();
                if (moved) { spawn(); render(); }
            });
        }
        function spawn() {
            let empty = [];
            for (let r=0; r<4; r++) for (let c=0; c<4; c++) if (board[r][c] === 0) empty.push([r, c]);
            if (empty.length > 0) {
                let [r, c] = empty[Math.floor(Math.random() * empty.length)];
                board[r][c] = Math.random() < 0.9 ? 2 : 4;
            }
        }
        function render() {
            const b = document.getElementById('board');
            b.innerHTML = '';
            document.getElementById('score').innerText = score;
            for (let r=0; r<4; r++) {
                for (let c=0; c<4; c++) {
                    let d = document.createElement('div');
                    let val = board[r][c];
                    d.className = 'cell ' + (val > 0 ? 'c-' + val : '');
                    d.innerText = val > 0 ? val : '';
                    b.appendChild(d);
                }
            }
        }
        function slide(row) {
            let arr = row.filter(x => x !== 0);
            for (let i = 0; i < arr.length - 1; i++) {
                if (arr[i] === arr[i+1]) { arr[i] *= 2; score += arr[i]; arr[i+1] = 0; }
            }
            arr = arr.filter(x => x !== 0);
            while (arr.length < 4) arr.push(0);
            return arr;
        }
        function moveLeft() {
            let changed = false;
            for (let r = 0; r < 4; r++) {
                let old = [...board[r]];
                board[r] = slide(board[r]);
                if (old.some((v, idx) => v !== board[r][idx])) changed = true;
            }
            return changed;
        }
        function moveRight() {
            let changed = false;
            for (let r = 0; r < 4; r++) {
                let old = [...board[r]];
                board[r] = slide(board[r].reverse()).reverse();
                if (old.some((v, idx) => v !== board[r][idx])) changed = true;
            }
            return changed;
        }
        function moveUp() {
            let changed = false;
            for (let c = 0; c < 4; c++) {
                let col = [board[0][c], board[1][c], board[2][c], board[3][c]];
                let nCol = slide(col);
                for (let r = 0; r < 4; r++) {
                    if (board[r][c] !== nCol[r]) { board[r][c] = nCol[r]; changed = true; }
                }
            }
            return changed;
        }
        function moveDown() {
            let changed = false;
            for (let c = 0; c < 4; c++) {
                let col = [board[3][c], board[2][c], board[1][c], board[0][c]];
                let nCol = slide(col);
                for (let r = 0; r < 4; r++) {
                    if (board[3-r][c] !== nCol[r]) { board[3-r][c] = nCol[r]; changed = true; }
                }
            }
            return changed;
        }
        init();
    </script>
</body>
</html>
EOF
    echo '{"template": "html5_game", "name": "HTML5 2048 益智小游戏"}' > "${META_FILE}"
}

reload_web_server() {
    if systemctl is-active --quiet nginx.service 2>/dev/null; then
        systemctl reload nginx.service || true
        log_info "Nginx Web 服务已平滑重载生效！"
    fi
}

show_status() {
    echo ""
    echo -e "${C_GREEN}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}             🎭 当前 HTML5 本地高保真伪装站点状态${C_RESET}"
    echo -e "${C_GREEN}======================================================================${C_RESET}"
    echo -e "  部署目录: ${C_BLUE}${CAMO_DIR}${C_RESET}"
    if [[ -f "${META_FILE}" ]]; then
        local name
        name=$(grep -oE '"name": "[^"]+"' "${META_FILE}" | cut -d'"' -f4 || echo "未知")
        local tpl
        tpl=$(grep -oE '"template": "[^"]+"' "${META_FILE}" | cut -d'"' -f4 || echo "custom")
        echo -e "  当前模版: ${C_BOLD}${C_YELLOW}${name}${C_RESET} (${tpl})"
    else
        echo -e "  当前模版: 未记录 (默认模板)"
    fi
    echo -e "  验证访问: 浏览器直接打开 https://您的域名 或 http://您的IP"
    echo -e "${C_GREEN}======================================================================${C_RESET}"
}

menu() {
    check_root
    while true; do
        echo ""
        echo -e "${C_GREEN}======================================================================${C_RESET}"
        echo -e "${C_BOLD}${C_GREEN}        🎭 AimiliVPN - HTML5 本地高保真伪装网站模版库${C_RESET}"
        echo -e "${C_GREEN}======================================================================${C_RESET}"
        echo -e "  ${C_GREEN}[1]${C_RESET} 部署【现代化科技云原生与 SaaS 平台官网】(推荐，科技感十足)"
        echo -e "  ${C_GREEN}[2]${C_RESET} 部署【全功能在线工具箱与极简计算器】(真实可点击、可算数)"
        echo -e "  ${C_GREEN}[3]${C_RESET} 部署【极简极客技术博客与工程随笔】(优雅学术、极简专业)"
        echo -e "  ${C_GREEN}[4]${C_RESET} 部署【经典 HTML5 2048 益智小游戏】(真实可玩、互动性强)"
        echo -e "  ${C_GREEN}[5]${C_RESET} 查看当前伪装站点状态"
        echo -e "  ${C_RED}[0]${C_RESET} 返回上级菜单"
        echo -e "${C_GREEN}======================================================================${C_RESET}"

        read -rp "请选择伪装模板 [0-5]: " opt
        case "${opt}" in
            1)
                deploy_tech_saas
                reload_web_server
                show_status
                read -rp "按回车键继续..." _
                ;;
            2)
                deploy_tools_calculator
                reload_web_server
                show_status
                read -rp "按回车键继续..." _
                ;;
            3)
                deploy_engineering_blog
                reload_web_server
                show_status
                read -rp "按回车键继续..." _
                ;;
            4)
                deploy_html5_game
                reload_web_server
                show_status
                read -rp "按回车键继续..." _
                ;;
            5)
                show_status
                read -rp "按回车键继续..." _
                ;;
            0)
                break
                ;;
            *)
                echo -e "${C_RED}无效选项${C_RESET}"
                ;;
        esac
    done
}

case "${1:-}" in
    1|tech)
        check_root
        deploy_tech_saas
        reload_web_server
        show_status
        ;;
    2|tools)
        check_root
        deploy_tools_calculator
        reload_web_server
        show_status
        ;;
    3|blog)
        check_root
        deploy_engineering_blog
        reload_web_server
        show_status
        ;;
    4|game)
        check_root
        deploy_html5_game
        reload_web_server
        show_status
        ;;
    status|info)
        show_status
        ;;
    menu|"")
        menu
        ;;
    *)
        echo "用法: $0 {1|2|3|4|status|menu}"
        exit 1
        ;;
esac
