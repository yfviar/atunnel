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

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG = os.path.join(BASE_DIR, "portmapper.json")
LOG_FILE = os.path.join(BASE_DIR, "portmapper.log")
RELOAD_INTERVAL = 3

_log_lock = threading.Lock()


def log(msg):
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


if __name__ == "__main__":
    main()
