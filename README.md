# aTunnel v2

WSL → aTrust 零信任内网的**透明 TCP 桥接**：WSL 里按内网地址直连，流量经 Windows 侧转发器进隧道。

> v1（按端口号建映射的 socat 世代）已退役，源码保留在 `legacy/`；迁移见 `docs/migrate-v1-to-v2.md`。

## 架构

```
应用(WSL) ──连接内网地址(如 172.20.2.15:58202)
   │
   ├─ iptables OUTPUT DNAT: 172.20.2.15:58202 → 127.0.0.1:58212      ← 本机中继端口(local)
   │  + POSTROUTING SNAT  --to-source 127.0.0.1                     ← mirrored 网络必需
   ▼
Windows 转发器 portmapper.py（监听 127.0.0.1:<local>）  ← 3s 热加载 portmapper.json
   ▼
aTrust 隧道（Windows 协议栈）──► 内网目标
```

**为什么不需要改应用配置**：Redis/PG/SSO 的地址写在远端 Nacos 配置里，应用直接连 → 由 DNAT 在本机"接住"，应用无感。

## 核心概念

| 概念 | 含义 |
|---|---|
| **env** | 一套完整环境（一台主机 + 其 Nacos/Redis/PG/…）。本机可同时存在多套（如 `dev-hydrology`=`.15`、`dev-flood`=`.14`、`shared`=共享设施） |
| **services** | 桥接层登记：`target`（内网端口）→ `local`（本机中继端口）+ **fingerprint**（内容级身份） |
| **runtime_ports** | 进程层登记：项目自身服务监听端口（用于多项目并行与冲突检测） |
| **fingerprint** | 身份指纹：Nacos=`nacos-dataid:<本项目独有 dataId>`、Redis=`redis-runid:<run_id>`、PG=`pg:<inet_server_addr>`；拿不到内容时用 `tcp-only`（显示"未校验"） |

**不变式**（`plan/apply` 前强制校验，违反即拒绝且零变更）：`local` 全局唯一；一个 `(host,target)` 只对应一个 `local`；进程端口在 env 内/跨 env 唯一且不得与 `local` 相同（I5）。

## 安装

```bash
# WSL 侧（root）
sudo ./install.sh [--dry-run] [--with-skill]
#   装: atunnel-env / atunnel / 兼容命令 / atunnel-env.service(oneshot) / 清单与凭据模板
#   --with-skill: 同时把 skill/SKILL.md 同步到 ~/.pi/agent/skills/atunnel/（全局生效）

# Windows 侧（一次）
#   复制 windows/ 到 %LOCALAPPDATA%\wsl-atrust-portmapper\
#   python portmapper.py --install    # 加入登录自启（免管理员）
#   python portmapper.py --status     # 配置/日志/监听状态
```

从 v1 升级：`sudo scripts/migrate-v1-to-v2.sh --yes`（幂等，自动备份，`doctor` 不过则中止）。

## 使用

```bash
atunnel --version                 # 版本
atunnel status                    # aTrust 网卡 / 本机 IP / 单元状态 / 清单摘要
atunnel list                      # 清单端点
atunnel plan                      # 只读预览（退出码 10 = 有待应用变更）
atunnel apply                     # 幂等应用（写 portmapper.json + iptables，并做结构自检）
atunnel verify <env>              # 身份校验（逐条指纹，指出串到哪个 env）
atunnel doctor [env]              # 对照表：声明地址 / 桥接实际目标 / 指纹 / 结论
atunnel ports [--check]           # 进程端口表 / 冲突体检（同 env、跨 env、与 local 冲突）
atunnel preflight <env> --role R  # 启动脚本用：数据面同源 + 该角色端口空闲
atunnel selftest                  # 校验层自检（纯内存）
atunnel log [n]                   # Windows 转发器日志
```

> `atunnel add|del|restart` 属 v1，**已停用**（打印指引并 exit 1）。新增/修改映射一律：**改清单 → `plan` → `apply` → `doctor`**。

## 端口段约定（多项目并行）

| 项目 | 业务服务 | 网关 | 前端 |
|---|---|---|---|
| 例：项目 A | 9200-9299 | 18080 | 80 |
| 例：项目 B | 9300-9399 | 8080 | 8082 |

新项目接入：**取一段空闲端口段** → 登记 env → `atunnel plan/apply/doctor` → 脚本加 `preflight --role` → 写项目文档。完整 SOP 见 `docs/env-onboarding.md`。
服务的 `server.port` 若来自 `bootstrap.yml`，优先用启动脚本 `-Dserver.port=<段内端口>` 覆盖（实测有效，**无需改仓库、无需重编 jar**）。

## 限制

- 仅 TCP；依赖 aTrust 客户端在线、Windows 转发器常驻；
- Windows 转发器按 `listen`（本地端口）索引 → **同一本地端口只能有一个目标**：多环境同端口号时必须各自分配不同 `local`（v2 清单强制，`atunnel ports --check` 兜底）；
- `iptables` 规则不持久 → 由 `atunnel-env.service`（oneshot）开机重放。

## 目录结构

```
bin/atunnel             CLI（薄封装、含 v1 弃用 stub）
bin/atunnel-env         核心（清单驱动：plan/apply/verify/doctor/ports/preflight/selftest）
config/*.example        清单与凭据模板
systemd/                atunnel-env.service（oneshot）
windows/                portmapper.py（转发器；--install/--status/日志轮转）
docs/                   接入 SOP、v1→v2 迁移说明
scripts/                migrate-v1-to-v2.sh
legacy/                 v1 退役件（源码保留 + 退役说明）
VERSION                 版本
```

## 版本

- **2.0.0**（2026-10）：清单驱动 + 内容级身份指纹 + 多环境/多项目并存 + 进程端口体检 + v1 退役 + Windows 侧纳管
- 1.x：socat + 按端口号建映射（已退役，见 `legacy/`）
