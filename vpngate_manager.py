import importlib.machinery
import importlib.util
import os
import sys
import subprocess
import shutil
import re


def _sync_core_if_needed():
    """自动将 core/<arch>/ 目录下最新的 .so 复制到根目录，确保 git pull 后免脚本自动更新"""
    try:
        here = os.path.dirname(os.path.abspath(__file__))
        import platform
        import sysconfig
        arch = platform.machine().lower()
        if arch in ("amd64", "x86_64"):
            arch = "x86_64"
        elif arch in ("arm64", "aarch64"):
            arch = "aarch64"
        suf = sysconfig.get_config_var("EXT_SUFFIX") or ""
        core_src = os.path.join(here, "core", arch, f"vpngate_manager{suf}")
        dest = os.path.join(here, f"vpngate_manager{suf}")
        if os.path.isfile(core_src):
            if (not os.path.exists(dest) or 
                os.path.getmtime(core_src) > os.path.getmtime(dest) or 
                os.path.getsize(core_src) != os.path.getsize(dest)):
                shutil.copy2(core_src, dest)
    except Exception:
        pass


def _load(name):
    _sync_core_if_needed()
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


def _apply_patches(mod):
    """动态净化品牌与链接并增强更新检测 (wbowen123 & tg: @wbowen)"""
    TG_URL = "https://t.me/wbowen"
    TG_HANDLE = "@wbowen"
    USER_BRAND = "wbowen123"
    REPO_NAME = "wbowen123/AimiliVPN"

    v_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "VERSION")
    if os.path.exists(v_file):
        try:
            with open(v_file, "r", encoding="utf-8") as vf:
                VERSION_TAG = vf.read().strip()
        except Exception:
            VERSION_TAG = "V1.4.8"
    else:
        VERSION_TAG = "V1.4.8"

    def _get_commit():
        commit = ""
        try:
            commit = subprocess.check_output(
                ["git", "rev-parse", "--short=8", "HEAD"],
                cwd=os.path.dirname(os.path.abspath(__file__)),
                stderr=subprocess.DEVNULL
            ).decode().strip()
        except Exception:
            pass
        return commit

    def _patch_str(s):
        if not isinstance(s, str):
            return s
        # 1. 替换 Telegram 链接与账号
        s = re.sub(r'https://t\.me/(?:ILovestudycn|ILovestudyus|ilovestudycn|ilovestudyus)\b', TG_URL, s, flags=re.I)
        s = re.sub(r'https://t\.me/wbowen\s+', TG_URL + ' ', s)
        s = re.sub(r'@(?:ILovestudycn|ILovestudyus|ilovestudycn|ilovestudyus)\b', TG_HANDLE, s, flags=re.I)
        s = re.sub(r't\.me/(?:ILovestudycn|ILovestudyus|ilovestudycn|ilovestudyus)\b', 't.me/wbowen', s, flags=re.I)
        
        # 2. 顶栏按钮文字强化显示为 TG: @wbowen
        s = re.sub(
            r'(<a\s+href=")[^"]*("[^>]*class="[^"]*btn-telegram[^"]*"[^>]*>[\s\S]*?<svg[\s\S]*?</svg>\s*)Telegram(\s*</a>)',
            rf'\1{TG_URL}\2TG: {TG_HANDLE}\3',
            s
        )

        # 3. 替换品牌与官网
        s = s.replace("我爱研究.ILovestudy", USER_BRAND)
        s = s.replace("我爱研究", USER_BRAND)
        s = s.replace("ILovestudy", USER_BRAND)
        s = re.sub(r'https?://(?:www\.)?ilovestudycn\.com/?', f"https://github.com/{REPO_NAME}", s, flags=re.I)
        s = re.sub(r'https?://(?:www\.)?ilovestudyip\.com/?', f"https://github.com/{REPO_NAME}", s, flags=re.I)
        s = re.sub(r'https?://ilovestudyus\.blogspot\.com/?', f"https://github.com/{REPO_NAME}", s, flags=re.I)
        s = s.replace("mailto:ilovestudyus@gmail.com", TG_URL)

        # 4. 版本号与模板替换
        commit = _get_commit()
        full_version = f"{VERSION_TAG} - {commit} (wbowen123)" if commit else f"{VERSION_TAG} (wbowen123)"
        s = s.replace("__APP_VERSION__", full_version)
        s = s.replace("V1.1.7", VERSION_TAG)
        return s

    def _patch_bytes(b):
        if not isinstance(b, (bytes, bytearray)):
            return b
        raw = bytes(b)
        try:
            text = raw.decode("utf-8")
            return _patch_str(text).encode("utf-8")
        except UnicodeDecodeError:
            commit = _get_commit()
            full_version = f"{VERSION_TAG} - {commit} (wbowen123)" if commit else f"{VERSION_TAG} (wbowen123)"
            raw = raw.replace(b"https://t.me/ILovestudycn", TG_URL.encode("utf-8"))
            raw = raw.replace(b"https://t.me/ILovestudyus", TG_URL.encode("utf-8"))
            raw = raw.replace(b"https://t.me/ilovestudycn", TG_URL.encode("utf-8"))
            raw = raw.replace(b"https://t.me/ilovestudyus", TG_URL.encode("utf-8"))
            raw = raw.replace(b"@ILovestudycn", TG_HANDLE.encode("utf-8"))
            raw = raw.replace(b"@ILovestudyus", TG_HANDLE.encode("utf-8"))
            raw = raw.replace("我爱研究.ILovestudy".encode("utf-8"), USER_BRAND.encode("utf-8"))
            raw = raw.replace("我爱研究".encode("utf-8"), USER_BRAND.encode("utf-8"))
            raw = raw.replace(b"ILovestudy", USER_BRAND.encode("utf-8"))
            raw = raw.replace(b"__APP_VERSION__", full_version.encode("utf-8"))
            raw = raw.replace(b"V1.1.7", VERSION_TAG.encode("utf-8"))
            return raw

    # 替换模块内的模板字符串
    for attr in ["INDEX_HTML", "LOGIN_HTML", "_INDEX_PAGE", "__UI_PAGE", "INDEX_SHELL_HTML"]:
        if hasattr(mod, attr):
            v = getattr(mod, attr)
            if isinstance(v, str):
                setattr(mod, attr, _patch_str(v))
            elif isinstance(v, (bytes, bytearray)):
                setattr(mod, attr, _patch_bytes(v))

    handler_cls = getattr(mod, "Handler", None)
    if handler_cls is not None:
        if hasattr(handler_cls, "do_GET"):
            orig_do_GET = handler_cls.do_GET
            def custom_do_GET(self):
                clean_path = self.path.split("?")[0].rstrip("/")
                commit = _get_commit()
                label = f"{VERSION_TAG} - {commit} (wbowen123)" if commit else f"{VERSION_TAG} (wbowen123)"
                if clean_path == "/api/github_version":
                    return self.send_json({"ok": True, "current_version": label, "repository": REPO_NAME})
                elif clean_path == "/api/github_update/check":
                    return self.send_json({
                        "ok": True,
                        "current_version": label,
                        "latest_version": label,
                        "repository": REPO_NAME,
                        "has_update": False,
                        "relation": "up_to_date",
                        "message": f"当前已经是最新正式版（{VERSION_TAG} · wbowen123）。"
                    })
                return orig_do_GET(self)
            handler_cls.do_GET = custom_do_GET

        if hasattr(handler_cls, "send_bytes"):
            orig_sb = handler_cls.send_bytes
            def custom_sb(self, content_bytes, *args, **kwargs):
                return orig_sb(self, _patch_bytes(content_bytes), *args, **kwargs)
            handler_cls.send_bytes = custom_sb

        if hasattr(handler_cls, "send_json"):
            orig_sj = handler_cls.send_json
            def custom_sj(self, data, *args, **kwargs):
                if isinstance(data, dict):
                    if "current_version" in data or "latest_version" in data:
                        commit = _get_commit()
                        if not commit and "current_version" in data:
                            parts = str(data["current_version"]).split(" - ")
                            if len(parts) > 1:
                                commit = parts[1].split()[0]
                        label = f"{VERSION_TAG} - {commit} (wbowen123)" if commit else f"{VERSION_TAG} (wbowen123)"
                        data["current_version"] = label
                        data["repository"] = REPO_NAME
                return orig_sj(self, data, *args, **kwargs)
            handler_cls.send_json = custom_sj

    if hasattr(mod, "_update_repository"):
        mod._update_repository = lambda *args, **kwargs: REPO_NAME
    if hasattr(mod, "current_github_version"):
        mod.current_github_version = lambda *args, **kwargs: (f"{VERSION_TAG} (wbowen123)", _get_commit())
    if hasattr(mod, "_version_label"):
        mod._version_label = lambda *args, **kwargs: f"{VERSION_TAG} - {_get_commit()} (wbowen123)"


if __name__ == "__main__":
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    _mod = _load("vpngate_manager")
    _apply_patches(_mod)
    _mod.main()
else:
    _m = _load("vpngate_manager")
    _apply_patches(_m)
    globals().update({k: v for k, v in vars(_m).items() if not k.startswith("__")})
