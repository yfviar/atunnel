# legacy/ — v1 退役件（保留源码，勿再使用）

v1 的设计缺陷：桥接表以**本地端口号**为键（`local ≡ 目标端口`），导致"同一端口号的多套环境只能存在一个目标"，先建者赢、后建者被静默顶替（表现为"配置读空/连到别的环境"，无任何报错）。

| 文件 | 说明 |
|---|---|
| `atunnel-add` / `atunnel-del` / `atunnel-restart` | 按端口号建/删映射 → 会绕过清单，**已停用**（安装为弃用 stub） |
| `atunnel-forward.sh` | socat + DNAT 到**物理网卡 IP** 的旧实现（IP 漂移即失效，且会重建失效规则） |
| `atunnel-verify` | 以 `/etc/wsl-atrust-forward.conf` 为"期望态"的旧校验（与 portmapper 双期望态并存，是历史混乱来源） |
| `wsl-atrust-forward.conf.example` | 旧期望态配置模板 |
| `wsl-atrust-forward.service` | 旧 systemd unit（开机重建旧规则/socat） |

迁移到 v2：见 `docs/migrate-v1-to-v2.md`（或直接 `sudo scripts/migrate-v1-to-v2.sh`）。
