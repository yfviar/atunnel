#!/bin/bash
# aTunnel v2 一键部署/升级（WSL 侧）
# 用法: sudo ./install.sh [--dry-run] [--with-skill]
#   --with-skill   同时把 skill/SKILL.md 同步到 ~/.pi/agent/skills/atunnel/（改全局文件，默认不做）
# 作者: weiyufei
set -e
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
DRY=0; WITH_SKILL=0
for a in "$@"; do
  case "$a" in --dry-run) DRY=1;; --with-skill) WITH_SKILL=1;; esac
done
VER="$(cat "$REPO_DIR/VERSION" 2>/dev/null || echo unknown)"
run() { if [ "$DRY" = "1" ]; then echo "  [dry-run] $*"; else eval "$@"; fi; }

echo "=== aTunnel v$VER 安装/升级 ==="

echo "[1/6] 命令工具 → /usr/local/bin"
run "install -m 755 '$REPO_DIR/bin/atunnel-env' /usr/local/bin/atunnel-env"
run "install -m 755 '$REPO_DIR/bin/atunnel' /usr/local/bin/atunnel"
run "install -m 755 '$REPO_DIR/bin/atunnel-verify' /usr/local/bin/atunnel-verify"
for f in atunnel-add atunnel-del atunnel-restart atunnel-forward.sh; do
  [ -f "$REPO_DIR/bin/$f" ] && run "install -m 755 '$REPO_DIR/bin/$f' /usr/local/bin/$f"
done
run "install -d /usr/local/share/atunnel && install -m 644 '$REPO_DIR/VERSION' /usr/local/share/atunnel/VERSION"
run "ln -sf /usr/local/bin/atunnel /usr/local/bin/wsl-atrust 2>/dev/null || true"

echo "[2/6] 清单与凭据模板 → /etc/atunnel"
run "install -d /etc/atunnel /etc/atunnel/backup /etc/atunnel/retired"
if [ ! -f /etc/atunnel/environments.json ]; then
  run "install -m 644 '$REPO_DIR/config/environments.json.example' /etc/atunnel/environments.json"
  echo "  ✅ 已创建 /etc/atunnel/environments.json（请按本机环境编辑：host / 端点 / local / fingerprint / runtime_ports）"
else
  echo "  ⏭  已存在 /etc/atunnel/environments.json，保留"
fi
if [ ! -f /etc/atunnel/credentials.conf ]; then
  run "install -m 600 '$REPO_DIR/config/credentials.conf.example' /etc/atunnel/credentials.conf"
  echo "  ✅ 已创建 /etc/atunnel/credentials.conf（0600，请填只读账号；勿入库）"
else
  run "chmod 600 /etc/atunnel/credentials.conf || true"
  echo "  ⏭  已存在 /etc/atunnel/credentials.conf，保留"
fi

echo "[3/6] systemd 单元 → atunnel-env.service（oneshot，开机 apply）"
run "install -m 644 '$REPO_DIR/systemd/atunnel-env.service' /etc/systemd/system/atunnel-env.service"
run "systemctl daemon-reload"
run "systemctl enable atunnel-env.service >/dev/null 2>&1 || true"

echo "[4/6] 应用清单（幂等 apply，含结构自检）"
run "/usr/local/bin/atunnel-env apply || echo '  ⚠ apply 未完全成功，请按输出处理（常见：清单未填完 / 转发器未起）'"

echo "[5/6] v1 检测与退役提示"
V1_UNIT=0; systemctl cat wsl-atrust-forward.service >/dev/null 2>&1 && V1_UNIT=1
V1_ACTIVE=$(systemctl is-active wsl-atrust-forward.service 2>/dev/null || true)
if [ "$V1_UNIT" = "1" ] && [ "$V1_ACTIVE" = "inactive" ]; then
  echo "  [OK] v1 已退役（unit 存在但 inactive；旧 conf 已留 stub）"
elif [ "$V1_UNIT" = "1" ]; then
  echo "  [!] 检测到运行中的 v1（wsl-atrust-forward.service: $V1_ACTIVE）"
  echo "      推荐执行迁移: sudo $REPO_DIR/scripts/migrate-v1-to-v2.sh"
  echo "      （备份 → 生成/校验清单 → 装 v2 unit → 退役 v1 unit 与 socat → 清理旧 DNAT）"
else
  echo "  [OK] 未检测到 v1 unit"
fi

echo "[6/6] Windows 侧（一次）"
echo "  📁 复制 windows/ 到: %LOCALAPPDATA%\\wsl-atrust-portmapper\\"
echo "  ⚙  python portmapper.py --install   # 加入登录自启（免管理员）"
echo "  🔍  python portmapper.py --status    # 查看配置/日志/监听"
echo "  📋 portmapper.json 由 WSL 侧 atunnel apply 自动维护，无需手改"
if [ "$WITH_SKILL" = "1" ]; then
  SK="$HOME/.pi/agent/skills/atunnel"
  run "install -d '$SK' && cp -f '$REPO_DIR/skill/SKILL.md' '$SK/SKILL.md'"
  echo "  ✅ 技能已同步到 $SK（全局生效）"
else
  echo "  ℹ️  技能未同步（默认）；如需: sudo ./install.sh --with-skill"
fi
echo ""
echo "=== 完成。验证: atunnel --version && atunnel doctor && atunnel ports --check ==="
