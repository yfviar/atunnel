#!/bin/bash
# aTunnel v1 → v2 迁移（WSL 侧，幂等、可回退）
# 用法: sudo ./migrate-v1-to-v2.sh [--dry-run] [--yes]
#   1) 备份 v1 现场（conf / iptables / portmapper.json / 旧 unit）
#   2) 无清单时从 portmapper.json 反推生成 /etc/atunnel/environments.json（标记待补指纹）
#   3) 安装并启用 v2 unit（oneshot），apply 一次
#   4) doctor 无 FAIL 后：停用旧 unit、归档旧 conf（留 stub）、结束 socat、清理指向物理 IP 的旧 DNAT
# 作者: weiyufei
set -u
DRY=0; YES=0
for a in "$@"; do case "$a" in --dry-run) DRY=1;; --yes) YES=1;; esac; done
TS=$(date +%Y%m%d-%H%M%S); BK=/etc/atunnel/backup; RET=/etc/atunnel/retired
WIN_JSON="${ATUNNEL_WIN_JSON:-$(ls -d /mnt/c/Users/*/AppData/Local/wsl-atrust-portmapper/portmapper.json 2>/dev/null | head -1)}"
run() { if [ "$DRY" = "1" ]; then echo "  [dry-run] $*"; else eval "$@"; fi }
say() { echo "  $*"; }

echo "=== aTunnel v1 → v2 迁移 $( [ "$DRY" = 1 ] && echo '(dry-run)' ) ==="
run "install -d $BK $RET"

echo "[1/6] 备份 v1 现场"
[ -f /etc/wsl-atrust-forward.conf ] && { run "cp -f /etc/wsl-atrust-forward.conf $BK/wsl-atrust-forward.conf.$TS.bak"; [ "$DRY" = 0 ] && say "conf 已备份"; }
run "iptables-save > $BK/iptables-nat.$TS.bak" ; [ "$DRY" = 0 ] && say "iptables 已备份"
[ -n "$WIN_JSON" ] && [ -f "$WIN_JSON" ] && { run "cp -f '$WIN_JSON' $BK/portmapper.json.$TS.bak"; [ "$DRY" = 0 ] && say "portmapper.json 已备份"; }
if systemctl cat wsl-atrust-forward.service >/dev/null 2>&1; then
  run "cp -f /etc/systemd/system/wsl-atrust-forward.service $RET/wsl-atrust-forward.service.$TS.bak"; [ "$DRY" = 0 ] && say "旧 unit 已备份"
fi

echo "[2/6] 清单"
if [ -f /etc/atunnel/environments.json ]; then
  say "已存在清单，保留（如需重建请先移走）"
else
  if [ -n "$WIN_JSON" ] && [ -f "$WIN_JSON" ]; then
    if [ "$DRY" = "1" ]; then say "[dry-run] 将依据 portmapper.json 生成清单草稿"; else
      python3 - "$WIN_JSON" <<'PY'
import json, sys, collections
d = json.load(open(sys.argv[1], encoding='utf-8'))
envs = collections.OrderedDict()
for e in d:
    key = f"legacy-{e['target_host'].replace('.', '_')}"
    envs.setdefault(key, {"host": e['target_host'], "owner": "unknown",
                          "note": "由 v1 portmapper.json 反推生成；请补 fingerprint 并整理 env 名",
                          "services": {}})
    svc = (e.get('name') or f"svc-{e['listen']}").replace('/', '-').replace(' ', '-')
    envs[key]["services"][svc] = {"target": e['target_port'], "local": e['listen'], "fingerprint": "tcp-only"}
out = {"version": 2,
       "note": "由 migrate-v1-to-v2.sh 生成的草稿：请补全 fingerprint（nacos-dataid/redis-runid/pg）并整理 env 划分",
       "envs": envs}
json.dump(out, open('/etc/atunnel/environments.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print("  已生成草稿: %d env / %d 端点（fingerprint 均为 tcp-only，待补）" %
      (len(envs), sum(len(v['services']) for v in envs.values())))
PY
    fi
  else
    say "未找到 portmapper.json，跳过清单生成（请自行安装 config/environments.json.example）"
  fi
fi

echo "[3/6] 安装 v2 unit 并应用清单"
run "install -m 644 '$(dirname "$0")/../systemd/atunnel-env.service' /etc/systemd/system/atunnel-env.service"
run "systemctl daemon-reload && systemctl enable atunnel-env.service >/dev/null 2>&1 || true"
run "systemctl start atunnel-env.service || true"
say "unit: $(systemctl is-enabled atunnel-env.service 2>/dev/null)/$(systemctl is-active atunnel-env.service 2>/dev/null)"

echo "[4/6] 校验（doctor）"
if [ "$DRY" = "1" ]; then say "[dry-run] atunnel-env doctor"; else
  if /usr/local/bin/atunnel-env doctor; then say "✅ 全绿"; else
    say "⚠ doctor 未全绿 —— 先修清单/fingerprint，再继续退役 v1（可重复运行本脚本）"
    say "  用法: atunnel doctor ; atunnel ports --check"
    exit 1
  fi
fi

echo "[5/6] 退役 v1"
run "systemctl disable --now wsl-atrust-forward.service 2>/dev/null || true"
run "systemctl reset-failed wsl-atrust-forward.service 2>/dev/null || true"
if [ "$DRY" = "1" ]; then say "[dry-run] 归档 conf → stub、结束 socat、清理旧 DNAT"; else
  if [ -f /etc/wsl-atrust-forward.conf ]; then
    grep -q '本文件已退役' /etc/wsl-atrust-forward.conf || {
      cp -f /etc/wsl-atrust-forward.conf $RET/wsl-atrust-forward.conf.retired
      cat > /etc/wsl-atrust-forward.conf <<'EOF'
# ⚠️ 本文件已退役（aTunnel v2）
# 期望态改为 /etc/atunnel/environments.json + atunnel-env；请勿在此添加映射。
# 历史内容见 /etc/atunnel/retired/wsl-atrust-forward.conf.retired
EOF
    }
  fi
  PIDS=$(ps -eo pid,args | awk '/[s]ocat TCP-LISTEN/{print $1}')
  if [ -n "$PIDS" ]; then
    if [ "$YES" = "1" ]; then kill $PIDS 2>/dev/null; say "已结束 socat: $(echo $PIDS | tr '\n' ' ')"
    else say "检出 socat 进程 $(echo $PIDS | tr '\n' ' ') —— 加 --yes 才会结束（或手动处理）"; fi
  fi
  iptables -t nat -S OUTPUT | grep -E -- '--to-destination (192\.168\.|172\.16\.)' | while read -r l; do
    iptables -t nat -D ${l#-A } && say "清理旧 DNAT: ${l#-A }"
  done
fi

echo "[6/6] 下一步"
say "1) 补 fingerprint（atunnel fingerprint <env> 可辅助取值）并整理 env 划分"
say "2) 登记 runtime_ports 并按端口段约定分配（atunnel ports --check 体检）"
say "3) 各项目启动脚本接入: atunnel-env preflight <env> --role <role> || exit 1"
say "4) 文档/接入指引: docs/env-onboarding.md"
echo "=== 迁移结束（备份目录 $BK；回退: 还原 conf + systemctl enable --now wsl-atrust-forward.service + iptables-restore） ==="
