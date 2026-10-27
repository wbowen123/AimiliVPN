import importlib.machinery
import importlib.util
import os
import sys


def _load(name):
    here = os.path.dirname(os.path.abspath(__file__))
    for suffix in importlib.machinery.EXTENSION_SUFFIXES:
        path = os.path.join(here, name + suffix)
        if os.path.exists(path):
            spec = importlib.util.spec_from_file_location(name, path)
            module = importlib.util.module_from_spec(spec)
            sys.modules[name] = module
            spec.loader.exec_module(module)
            return module
    sys.stderr.write("AimiliVPN 程序模块缺失，请运行 bash scripts/select_core.sh 或重新安装。\n")
    raise SystemExit(1)


def start_residential_engine(port=8500):
    """尝试启动现代化的 Netns 隔离与住宅家宽调度引擎"""
    try:
        here = os.path.dirname(os.path.abspath(__file__))
        scripts_dir = os.path.join(here, "scripts")
        if scripts_dir not in sys.path:
            sys.path.insert(0, scripts_dir)
        import vpngate_engine
        if vpngate_engine.LinuxNetnsManager.is_supported():
            sys.stdout.write("[*] 正在启动 AimiliVPN 现代化 Netns 隔离与住宅家宽调度引擎...\n")
            daemon = vpngate_engine.AimiliResidentialDaemon(bridge_port=port)
            daemon.start()
            import time
            while True:
                time.sleep(3600)
            return True
    except Exception as e:
        sys.stderr.write(f"[!] 启动现代化 Netns 引擎失败，平滑降级至内置内核: {e}\n")
    return False


if __name__ == "__main__":
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    _port = int(os.environ.get("LOCAL_PROXY_PORT", "8500"))
    _host = os.environ.get("LOCAL_PROXY_HOST", "127.0.0.1")

    # 优先尝试启动现代化 Netns 隔离引擎
    if os.environ.get("USE_LEGACY_CORE") != "1" and sys.platform == "linux" and os.geteuid() == 0:
        if start_residential_engine(_port):
            sys.exit(0)

    _mod = _load("proxy_server")
    if hasattr(_mod, "_cli_main"):
        _mod._cli_main()
    else:
        import threading
        try:
            threading.stack_size(512 * 1024)
        except (ValueError, RuntimeError):
            pass
        _trim = getattr(_mod, "_memory_trim_loop", None)
        if _trim is not None:
            threading.Thread(target=_trim, daemon=True, name="malloc-trim").start()
        _mod.start_proxy_server(_host, _port)
else:
    try:
        _m = _load("proxy_server")
        globals().update({k: v for k, v in vars(_m).items() if not k.startswith("__")})
    except SystemExit:
        pass

