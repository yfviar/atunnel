---
name: atunnel
description: 当需要访问 aTrust 零信任内网服务（如 172.20.2.x 网段的 Redis/Nacos/API/数据库），或检测到应用连接内网地址超时失败、需要将目标加入 aTunnel 桥接时使用。触发词：内网、aTrust、aTunnel、连不上、172.20.2、物管Redis、Nacos、OneAPI、内网服务。
---

# aTunnel 技能：自动判断并桥接 aTrust 内网服务

## 作用

让 agent 在遇到"需要访问 aTrust 认证内网服务"的场景时，**自动判断目标是否应该加入 aTunnel 桥接**，并自动完成添加，无需用户手动配置。

## 判断流程（三步，全部满足才添加）

1. **目标是否属于 aTrust 内网段**
   - 默认内网段: `172.20.2.0/24`（可用 `atunnel status` 或配置文件确认）
   - 命中内网段 → 继续；否则 → **不需要桥接**，正常直连

2. **直连是否失败**
   - 执行 `timeout 3 nc -zv <IP> <PORT>`，超时/无响应，或应用报连接超时
   - 直连失败 → 继续；成功 → **不需要桥接**

3. **是否已有映射**
   - `atunnel list` 检查是否存在 `<IP>:<PORT>`
   - 已有 → 不重复添加，改用 `atunnel status` 检查链路健康
   - 没有 → 执行添加

## 操作命令

```bash
atunnel add <IP> <PORT> <名称>   # 一键热新增（自动端口检查、WSL+Windows 同步、链路验证）
atunnel list                     # 查看映射与连通性
atunnel status                   # 整体状态（aTrust在线/IP/服务/规则）
atunnel log [行数]               # 转发器日志（排查连接问题）
atunnel del <IP> <PORT>          # 删除映射（服务下架时）
atunnel restart [端口]           # 应急重启 Windows 转发器
```

## 边界与注意事项

- **仅 TCP**：UDP 服务（DNS/NTP/部分数据库）不支持，不要尝试添加
- **端口冲突**：`atunnel-add` 自动检查；报冲突时换端口或先确认
- **依赖**：aTrust 客户端在线 + Windows portmapper 运行；`atunnel status` 显示 eth7 断开或服务 inactive 时，先修复链路再添加
- **新增后验证**：添加完成后用 `nc -zv` 或应用实际连接验证连通性
- **常见误区**：目标是局域网同段（如 172.16.203.x）且能连通时，**不要**加桥接（物理直连即可）；只有 aTrust 内网段才需要桥接

## 排查速查

| 现象 | 处理 |
|---|---|
| `atunnel list` 显示"异常" | 检查 eth7 在线 + Windows 转发器进程 + 端口监听 |
| 连接立即 refused | 目标端口本身无服务，或端口冲突 |
| 连接超时 | aTrust 隧道未建立 / Windows 转发器未运行 |
| 连接 10 秒反复断开 | 曾由 portmapper timeout bug 导致（已修复），若重现检查转发器是否为最新版 |
