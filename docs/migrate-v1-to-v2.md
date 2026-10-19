# v1 → v2 迁移说明

## 为什么要迁

v1 的桥接表以**本地端口号**为键（`local ≡ 目标端口`）。当多套环境都用同一个端口号（如 `58204/58202/58201`）时，**一个 listen 只能指一个目标** → 先建者赢，后建者被**静默顶替**；表现为"配置读空 / 连到别的环境"，且没有任何报错。v1 还有两个坑：`atunnel-verify` 以 `/etc/wsl-atrust-forward.conf` 为期望态（与 portmapper 双期望态并存）、`get_local_ip()` 绑物理网卡 IP（IP 漂移即失效、重启会重建失效规则）。

v2 改为**清单驱动**：`(host, target_port)` 独占一个 `local` 端口 + **内容级身份指纹**校验 + 开机 oneshot 重放。

## 迁移（一条命令）

```bash
sudo /path/to/atunnel/scripts/migrate-v1-to-v2.sh --dry-run     # 先看会做什么
sudo /path/to/atunnel/scripts/migrate-v1-to-v2.sh --yes         # 执行（含结束 socat 进程）
```

步骤：备份现场 → 无清单则从 `portmapper.json` 反推草稿 → 装/启用 `atunnel-env.service` 并 `apply` → **doctor 全绿后**才退役 v1（停旧 unit、归档 conf 留 stub、结束 socat、清理指向物理 IP 的旧 DNAT）→ 打印下一步。

>`doctor` 未全绿时会**主动中止**（不会带着错配置退役 v1）；修好清单后可重复运行本脚本（幂等）。

## 迁移后要补的三件事

1. **补 `fingerprint`**：`tcp-only` 只能证明"通"，不能证明"是我" → 用 `atunnel fingerprint <env>` 取值后写回清单；
2. **登记 `runtime_ports`** 并按端口段约定分配（`atunnel ports --check` 体检，会拦跨项目冲突）；
3. **项目启动脚本接入** `atunnel-env preflight <env> --role <role> || exit 1`。

## 回退

```bash
cp /etc/atunnel/backup/wsl-atrust-forward.conf.<ts>.bak /etc/wsl-atrust-forward.conf
systemctl enable --now wsl-atrust-forward.service
iptables-restore < /etc/atunnel/backup/iptables-nat.<ts>.bak
systemctl disable --now atunnel-env.service
```
v1 源码全部保留在仓库 `legacy/`（可随时恢复安装）。
