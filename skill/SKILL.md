---
name: atunnel
description: 需要访问 aTrust 零信任内网（172.20.2.x 等）服务时使用，用清单驱动的 aTunnel v2 桥接；含多环境串台排查、身份指纹校验、进程端口冲突体检。触发词：内网、aTrust、aTunnel、连不上、超时、172.20.2、Nacos、Redis、PG、内网服务、串台、端口冲突。
---

# aTunnel v2 技能：清单驱动的内网桥接

## 0. 一句话原则

**环境身份靠"内容指纹"证明，不靠 IP/端口/命名空间猜。** 地址无法标识环境（同 IP 多服务、同端口多主机、同名命名空间）——v1 就栽在这里。

## 1. 先体检（不要先猜）

```bash
atunnel --version
atunnel status                 # aTrust 网卡 / 本机 IP / 单元 / 清单摘要
atunnel doctor                 # 全量对照表：声明地址 / 桥接实际目标 / 指纹 / 结论
atunnel ports --check          # 端口体检（清单互斥、跨 env、与本机监听）
```

## 2. 故障三分类（按症状定位）

| 症状 | 归类 | 首查 |
|---|---|---|
| 连接超时 / 拒绝 / 认证莫名失败 | **类 A 不通** | `atunnel plan`（是否有待应用变更）、`ss -ltn` 本机监听、`atunnel status` 单元状态 |
| 能连上但**内容不对**（配置读空、数据不对、用户不存在） | **类 B 错连** | `atunnel doctor` → 看"桥接实际目标 vs 声明"与**指纹**是否指向别的 env |
| 配置来自 A 环境、数据却在 B 环境（现象最飘） | **类 C 混搭** | `atunnel doctor <env>` 逐行看：Nacos/Redis/PG **必须同一 env** |
| 服务"起来了但少个能力"（如消费者不工作） | **残留规则优先命中** | `iptables -t nat -S OUTPUT` 看**顺序**：靠前的失效规则（目标≠`127.0.0.1` 且≠清单 `local`）会先命中 → `atunnel apply` 修 |

## 3. 修与验

```bash
atunnel plan            # 只读预览（退出码 10 = 有待应用变更）
atunnel apply           # 幂等应用（两侧桥接 + 结构自检；失败非 0）
atunnel verify <env>    # 身份校验；输出会指出"串到哪个 env"
atunnel selftest        # 校验层自身自检
```

## 4. 新增/修改映射（唯一正确路径）

1. 打开 `/etc/atunnel/environments.json`（模板 `config/environments.json.example`）；
2. 加/改 `services`（`target` → `local` + `fingerprint`）或 `runtime_ports`；
3. `atunnel plan` → `atunnel apply` → `atunnel doctor`。

**禁止**：`atunnel add|del|restart`（v1 入口，已停用）、手工 `iptables -A`、手工改 `portmapper.json`——都会绕过清单，重新引入静默错配。

## 5. 多项目并行（进程端口层）

- 每项目一段：如 `9200-9299/18080/ui 80` vs `9300-9399/8080/ui 8082`；
- 服务端口若来自 `bootstrap.yml`，用启动脚本 `-Dserver.port=<段内端口>` 覆盖（实测有效，**不改仓库、不重编 jar**）；前端用 `npm run dev -- --port <段内端口>`；
- 启动脚本首行：`atunnel-env preflight <env> --role <role> || exit 1`（`--role` 让端口检查只针对本角色，避免顺序启动互相误报）。

## 6. 新项目接入

照 `docs/env-onboarding.md`：取空闲端口段 → 登记 env（`services` + `runtime_ports` + `fingerprint`）→ `plan/apply/doctor/ports --check` → 脚本接入 preflight → 项目 `AGENTS.md` 写明 env id。

## 7. 关键事实（排查时的先验）

- **一个本地端口只能有一个目标**：Windows 转发器按 `listen` 索引；多环境同端口号（如 `58204/58202/58201`）必须各配不同 `local`；
- **DNAT + SNAT 成对**：mirrored 模式下 `127.0.0.1` 经 `loopback0` 镜像到 Windows 回环，**只接受回环源地址**；`OUTPUT` 链不支持 SNAT，必须放 `POSTROUTING`；
- **规则不持久**：`iptables` 易失 → `atunnel-env.service`（oneshot）开机 `apply` 自愈；手工加的规则会在重启后消失；
- **判定"两条链路是否同源"必须按目标分别取内容指纹**，禁止用"我从哪条链路进来的/哪个代理变量生效"当自变量；
- **比较内容长度注意字符数 vs 字节数**（中文 UTF-8 每字 3 字节），否则会误判为"后端返回不一致"。
