#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Windows 侧 TCP 端口转发器 - aTunnel 组件 (portmapper) - 热加载版
监听 127.0.0.1 端口 -> 转发到 aTrust 内网目标
转发连接在 Windows 协议栈内发起, 被 aTrust 透明劫持进隧道

热更新: portmapper.json 变更后每 3 秒自动生效, 无需重启进程
  - 新增映射 -> 自动监听新端口
  - 删除映射 -> 自动关闭对应监听
用法: pythonw.exe portmapper.py
作者: weiyufei
"""
import socket
import threading
import json
import os
import time

VERSION = "2.0.0"
LOG_MAX_BYTES = 5 * 1024 * 1024      # 单文件上限
LOG_KEEP = 3                         # 保留份数

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG = os.path.join(BASE_DIR, "portmapper.json")
LOG_FILE = os.path.join(BASE_DIR, "portmapper.log")
RELOAD_INTERVAL = 3

_log_lock = threading.Lock()


def _rotate_if_needed():
    try:
        if not os.path.exists(LOG_FILE) or os.path.getsize(LOG_FILE) < LOG_MAX_BYTES:
            return
        for i in range(LOG_KEEP - 1, 0, -1):
            src, dst = "%s.%d" % (LOG_FILE, i), "%s.%d" % (LOG_FILE, i + 1)
            if os.path.exists(src):
                if os.path.exists(dst):
                    os.remove(dst)
                os.rename(src, dst)
        if os.path.exists(LOG_FILE + ".1"):
            os.remove(LOG_FILE + ".1")
        os.rename(LOG_FILE, LOG_FILE + ".1")
    except Exception:
        pass


def log(msg):
    _rotate_if_needed()
    line = "[%s] %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg)
    print(line, flush=True)
    try:
        with _log_lock:
            with open(LOG_FILE, "a", encoding="utf-8") as f:
                f.write(line + "\n")
    except Exception:
        pass


def relay(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except Exception:
        pass
    finally:
        try:
            src.close()
        except Exception:
            pass
        try:
            dst.close()
        except Exception:
            pass


def handle(client, target_host, target_port):
    peer = ""
    try:
        peer = "%s:%d" % client.getpeername()
        backend = socket.create_connection((target_host, target_port), timeout=10)
        backend.settimeout(None)  # 关键: 连接成功后恢复阻塞模式, 避免空闲 recv 超时切断连接
        log("连接 %s -> %s:%d" % (peer, target_host, target_port))
        threading.Thread(target=relay, args=(client, backend), daemon=True).start()
        threading.Thread(target=relay, args=(backend, client), daemon=True).start()
    except Exception as e:
        log("失败 %s -> %s:%d : %s" % (peer, target_host, target_port, e))
        try:
            client.close()
        except Exception:
            pass


def create_listener(item):
    listen = item.get("listen")
    thost = item.get("target_host")
    tport = item.get("target_port")
    name = item.get("name", "")
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind(("127.0.0.1", listen))
    except OSError as e:
        log("绑定 127.0.0.1:%d 失败: %s" % (listen, e))
        return None
    s.listen(64)
    log("监听 127.0.0.1:%d -> %s:%d [%s]" % (listen, thost, tport, name))
    return s


def accept_loop(sock, item):
    while True:
        try:
            c, _ = sock.accept()
        except OSError:
            break  # 监听 socket 已关闭(配置删除)
        threading.Thread(
            target=handle,
            args=(c, item["target_host"], item["target_port"]),
            daemon=True,
        ).start()


def load_maps():
    try:
        with open(CONFIG, encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        log("配置读取失败: %s" % e)
        return []


def main():
    servers = {}   # listen -> sock
    last_mtime = None
    log("启动转发器(热加载版), 配置: %s" % CONFIG)
    while True:
        try:
            mtime = os.path.getmtime(CONFIG)
        except OSError:
            mtime = None
        if mtime != last_mtime:
            last_mtime = mtime
            maps = {m["listen"]: m for m in load_maps()}
            # 关闭已删除的映射
            for port in list(servers):
                if port not in maps:
                    sock = servers.pop(port)
                    try:
                        sock.close()
                    except Exception:
                        pass
                    log("停止监听 127.0.0.1:%d" % port)
            # 启动新增的映射
            for port, item in maps.items():
                if port not in servers:
                    sock = create_listener(item)
                    if sock:
                        servers[port] = sock
                        threading.Thread(
                            target=accept_loop, args=(sock, item), daemon=True
                        ).start()
        time.sleep(RELOAD_INTERVAL)


def _existing_startup_entry(startup):
    """检测启动文件夹里是否已有拉起本转发器的入口（避免双实例抢端口）"""
    try:
        for fn in os.listdir(startup):
            fp = os.path.join(startup, fn)
            if not os.path.isfile(fp):
                continue
            try:
                txt = open(fp, "r", encoding="gbk", errors="ignore").read()
            except Exception:
                continue
            if "portmapper.py" in txt or "wsl-atrust-portmapper" in txt:
                return fn
    except Exception:
        pass
    return None


def do_install():
    """把转发器加入当前用户"启动"文件夹（免管理员，登录自启）"""
    startup = os.path.join(os.environ.get("APPDATA", ""),
                           r"Microsoft\Windows\Start Menu\Programs\Startup")
    if not os.path.isdir(startup):
        print("[x] 未找到启动文件夹: %s" % startup); return 1
    exist = _existing_startup_entry(startup)
    if exist:
        print("[i] 启动文件夹已有入口: %s" % exist)
        print("    为避免双实例争抢端口，本次不创建新入口；如需替换请先删除它。")
        return 0
    vbs = os.path.join(BASE_DIR, "start-portmapper.vbs")
    with open(vbs, "w", encoding="gbk", errors="ignore") as f:
        f.write('Set sh = CreateObject("WScript.Shell")\r\n')
        f.write('sh.CurrentDirectory = "%s"\r\n' % BASE_DIR)
        f.write('sh.Run "pythonw.exe ""%s""", 0, False\r\n' % os.path.join(BASE_DIR, "portmapper.py"))
    link = os.path.join(startup, "atunnel-portmapper.vbs")
    try:
        with open(vbs, "rb") as src, open(link, "wb") as dst:
            dst.write(src.read())
    except Exception as e:
        print("[x] 写入启动项失败: %s" % e); return 1
    print("[ok] 已加入登录自启: %s" % link)
    print("     说明: 首次可先手动运行 `pythonw.exe portmapper.py` 验证端口监听")
    print("     取消自启: 删除该 vbs 即可")
    return 0


def do_status():
    print("aTunnel portmapper v%s" % VERSION)
    print("  配置: %s" % CONFIG)
    print("  日志: %s (%d 字节, 上限 %d 字节 x%d)" %
          (LOG_FILE, os.path.getsize(LOG_FILE) if os.path.exists(LOG_FILE) else 0,
           LOG_MAX_BYTES, LOG_KEEP))
    try:
        maps = json.load(open(CONFIG, encoding="utf-8"))
        listening = 0
        for m in maps:
            try:
                s = socket.create_connection(("127.0.0.1", m["listen"]), timeout=1)
                s.close(); listening += 1
            except Exception:
                pass
        print("  映射: %d 条，本转发器监听中 %d 条" % (len(maps), listening))
    except Exception as e:
        print("  映射: 读取失败 %s" % e)
    return 0


if __name__ == "__main__":
    import sys as _sys
    args = _sys.argv[1:]
    if args and args[0] in ("--version", "-v", "version"):
        print(VERSION); _sys.exit(0)
    if args and args[0] == "--install":
        _sys.exit(do_install())
    if args and args[0] == "--status":
        _sys.exit(do_status())
    if args and args[0] in ("-h", "--help", "help"):
        print("用法: pythonw.exe portmapper.py            # 运行转发器（热加载 portmapper.json，3s）")
        print("      python portmapper.py --install     # 加入当前用户登录自启（免管理员）")
        print("      python portmapper.py --status      # 查看配置/日志/监听状态")
        print("      python portmapper.py --version")
        _sys.exit(0)
    main()
