#!/bin/bash
# [v2 已弃用] v1 入口（按目标端口号建映射，会绕过环境清单 → 静默错配风险）
cat <<'MSG'
[已弃用] 该命令属于 aTunnel v1（按端口号建映射），v2 起停用，本次未做任何改动。
请改用清单式流程：
  1) 编辑 /etc/atunnel/environments.json（唯一事实源；模板见 config/environments.json.example）
  2) atunnel plan        # 预览变更（退出码 10 = 有待应用变更）
  3) atunnel apply       # 幂等应用（写 portmapper.json + iptables DNAT/SNAT，并做结构自检）
  4) atunnel doctor      # 校验（声明地址 / 桥接目标 / 内容指纹 / 结论）
  5) atunnel ports --check   # 进程端口体检（多项目并行）
v1 源码保留在 legacy/；接入指引见 docs/env-onboarding.md
MSG
exit 1
