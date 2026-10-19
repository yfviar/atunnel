# Windows 侧组件：portmapper（TCP 转发器）

## 作用

监听 `127.0.0.1:<listen>`，把连接转发到 aTrust 内网目标。**连接在 Windows 协议栈内发起**，才会被 aTrust 透明劫持进隧道——这是 WSL 无法直连内网、必须经它的原因。

## 安装（一次）

1. 把本目录复制到：`%LOCALAPPDATA%\wsl-atrust-portmapper\`（即 `C:\Users\<你>\AppData\Local\wsl-atrust-portmapper\`）
2. 运行一次自检：
   ```bat
   python portmapper.py --status
   ```
3. 加入登录自启（二选一）：
   - **推荐（免管理员）**：`python portmapper.py --install`（在启动文件夹生成 vbs）
   - 或手工放一个 `.cmd` 到启动文件夹：
     ```bat
     @echo off
     start "" "<Python>\pythonw.exe" "%LOCALAPPDATA%\wsl-atrust-portmapper\portmapper.py"
     ```
     > ⚠️ **只保留一个自启入口**：两个实例会争抢同一个 `listen` 端口 → 第二个实例报绑定失败。
     > `--install` 会先检测既有入口，发现后不再新建（避免双实例）。

## portmapper.json（由 WSL 侧自动维护，勿手改）

```json
[{ "listen": 58214, "target_host": "172.20.2.15", "target_port": 58204, "name": "dev-hydrology/nacos" }]
```
- `listen`：**本机监听端口**（= 清单里的 `local`），全局唯一；多环境同端口号时必须各不相同；
- `name`：`<env>/<service>`，由 `atunnel apply` 写入（便于识别归属）；
- 文件保存后 **3 秒内热加载**（新增/删除监听自动生效，无需重启）。

## 其它

```bat
python portmapper.py --version
python portmapper.py --status      # 配置 / 日志大小 / 监听状态
python portmapper.py --help
```
- 日志：`portmapper.log`，**按大小轮转**（默认 5MB × 保留 3 份）；
- 与旧 `netsh interface portproxy` 冲突时先删除旧规则。
