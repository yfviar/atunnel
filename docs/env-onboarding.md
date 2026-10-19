# 新项目接入 SOP（env 登记 + 端口段 + 校验）

> 目标（aTunnel v2）：任何项目（含将来新项目）照此可**独立接入**本机的 aTunnel 桥接与端口约定；
> 前提：已装 aTunnel v2（`install.sh`） 与 `/etc/atunnel/environments.json`。

## 0. 先看现状（只读）

```bash
atunnel list            # 现有 env 与端点
atunnel ports           # 各项目进程端口表 + 实际占用
atunnel ports --check   # 端口冲突体检（清单互斥 / 跨 env / 与 ss -ltn 实际监听）
atunnel doctor          # 全量身份校验（声明地址 vs 桥接目标 vs 内容指纹）
```

## 1. 取一段空闲端口段

- 约定：每项目一段，**不要与其它 env 重叠**，也不要与**桥接 local 端口**冲突（后者由 `ports --check` 自动拦）；
- 现有段：`dev-hydrology` 9200-9299 / gateway 18080 / ui 80｜`dev-flood` 9300-9399 / 8080 / ui 8082｜`dev-model`（预留 9400-9499 / 18081 / 8083）；
- 选段前先 `ports --check` 与 `ss -ltn` 比对。

## 2. 在清单里登记该 env

编辑 `/etc/atunnel/environments.json`，新增：

```jsonc
"<env-id>": {
  "host": "172.20.2.x",                 // 该 env 的内网主机
  "owner": "<项目名>",
  "services": {                          // 桥接层：内网端点 → 本机中继端口（local 全局唯一）
    "nacos":      { "target": 58204, "local": <空闲本机端口>, "fingerprint": "nacos-dataid:<本项目独有 dataId>" },
    "redis":      { "target": 58202, "local": <空闲本机端口>, "fingerprint": "redis-runid:<期望 run_id>" },
    "pg":         { "target": 58201, "local": <空闲本机端口>, "fingerprint": "pg:<inet_server_addr>" }
  },
  "runtime_ports": {                     // 进程层：本项目服务监听端口
    "auth": <port>, "system": <端口>, "business": <端口>, "gateway": <端口>, "frontend": <端口>
  }
}
```

要点：
- `local`（桥接中继端口）与 `runtime_ports`（进程端口）**语义不同，都要登记**；
- `fingerprint` 是**内容级身份**（Nacos 用独有 dataId、Redis 用 `run_id`、PG 用 `inet_server_addr()`）——用来判定"是否串到别的环境"；
- 拿不到内容指纹的端点写 `"tcp-only"`（会显示"未校验"）。

## 3. 应用与校验

```bash
atunnel plan            # 只读预览（退出码 10 = 有变更）
atunnel apply           # 幂等应用（写 portmapper.json + iptables DNAT/SNAT，并做结构自检）
atunnel doctor <env>    # 逐条校验：声明地址 / 桥接实际目标 / 指纹 / 结论
atunnel ports --check   # 端口体检
```

## 4. 项目侧接入

- 启动脚本首行加：`atunnel preflight <env> --role <role> || exit 1`
  （`--role` 让端口检查只针对本角色，避免顺序启动时互相误报）；
- 若该项目的服务端口从其 `bootstrap.yml` 读取，可在脚本里用 **`-Dserver.port=<段内端口>`** 覆盖（实测有效），**无需改仓库文件、无需重编 jar**；
- 前端：`npm run dev -- --port <段内端口>`；
- 项目 `AGENTS.md` 写明：**本项目 env = `<env-id>`** + 端口段 + preflight 命令。

## 5. 新增映射的红线

- **禁止**使用 `atunnel-add` / `atunnel-del`（已停用，打印弃用指引后 exit 1）——它们按端口号建映射，会绕过清单造成静默错配；
- 一律"改清单 → `plan` → `apply` → `doctor`"；
- 上线前跑 `atunnel selftest` 确认校验层自身完好。

## 6. 回退

- 清单与 `portmapper.json` 的每次写操作前自动备份到 `/etc/atunnel/backup/`；
- 清理清单外条目：`atunnel plan --prune` 先看，再 `apply --prune`。
