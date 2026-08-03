# aTunnel

让 WSL 里的应用**零改动透明访问**需要 aTrust 零信任认证的内网服务。

应用照常连接内网原 IP（如 `172.20.2.15:32279`），aTunnel 自动将其桥接进 aTrust 隧道 —— 全程免管理员、热更新、网络环境自适应。

## 架构

```
WSL 应用连 172.20.2.x 原 IP（零改动）
  → ① iptables DNAT（WSL 内, 透明改写）
  → ② socat 中转（systemd 自启, 纯回环源发起）
  → ③ Windows portmapper.py（协议栈内连接 → aTrust 透明劫持 → 隧道）
  → 内网服务 ✅
```

**原理**：aTrust 只接管"Windows 协议栈内发起的连接"；WSL 流量走 Hyper-V vSwitch 旁路（镜像模式）进不了协议栈，因此裸连被网关丢弃。aTunnel 让连接"借道 Windows 协议栈"，从而被 aTrust 正常接管。

## 特性

- **应用零改动**：应用配置里写内网原 IP 即可
- **热更新**：增删映射零重启零中断（iptables 增量 + socat 单进程 + portmapper 3 秒热加载）
- **免管理员**：日常增删查全部免管理员（Windows 侧仅首次部署需一次管理员）
- **网络自适应**：aTrust 网络下自动桥接，其他网络自动跳过不干扰直连
- **统一命令**：`atunnel list/add/del/status/restart/log`

## 部署

### 前置条件

- WSL 2（镜像网络模式 `networkingMode=mirrored`）
- aTrust 客户端在线（隧道可用）
- 目标内网服务需通过 aTrust 认证才能访问

### WSL 侧（root）

```bash
cd atunnel
./install.sh
```

### Windows 侧（首次需管理员一次）

1. 复制 `windows/` 目录到 `C:\Users\<user>\AppData\Local\wsl-atrust-portmapper\`
2. 按需修改 `portmapper.json`（映射清单）
3. 启动：`pythonw.exe portmapper.py`（或放入启动文件夹实现开机自启）

## 使用

```bash
atunnel list                    # 查看所有映射（状态/连通性）
atunnel add <IP> <端口> [名称]  # 一键热新增映射
atunnel del <IP> <端口>         # 一键热删除映射
atunnel status                  # 整体状态（aTrust在线/IP/服务/规则）
atunnel restart [端口]          # 重启 Windows 转发器
atunnel log [行数]              # 查看转发器日志
```

### 新增映射的完整链路（一条命令）

```bash
atunnel add 172.20.2.16 8080 新服务
```

自动完成：端口冲突检查 → WSL 增量热添加（iptables+socat）→ Windows portmapper.json 更新（3 秒热加载）→ 链路验证。

## 配置文件

| 文件 | 位置 | 说明 |
|---|---|---|
| `config/wsl-atrust-forward.conf.example` | `/etc/wsl-atrust-forward.conf` | WSL 侧映射清单（目标IP 端口 socat端口） |
| `windows/portmapper.json.example` | Windows 转发器目录 | Windows 侧映射清单 |

两处配置保持同步（`atunnel add/del` 自动维护）。

## 限制

- 仅支持 TCP
- 依赖 aTrust 客户端在线
- 依赖 Windows 转发器进程运行（开机自启已配置）

## 文件结构

```
bin/                    # 命令行工具
  atunnel               主命令
  atunnel-add           一键热新增
  atunnel-del           一键热删除
  atunnel-restart       Windows 转发器重启
  atunnel-forward.sh    WSL 侧 DNAT+socat 管理
windows/                # Windows 侧组件
  portmapper.py         热加载转发器
  portmapper.json.example
config/                 # 配置模板
systemd/                # WSL 自启服务
skill/                  # agent 技能（自动判断是否加入桥接）
```
