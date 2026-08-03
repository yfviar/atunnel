#!/bin/bash
# aTunnel 一键部署脚本 (WSL 侧)
# 用法: sudo ./install.sh
# 安装: 命令工具 -> 配置模板 -> systemd 服务 -> 兼容别名
# 作者: weiyufei

set -e
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$REPO_DIR/bin"

echo "=== aTunnel 安装 ==="

# 1. 安装命令工具
echo "[1/4] 安装命令到 /usr/local/bin ..."
install -m 755 "$BIN_DIR/atunnel" /usr/local/bin/atunnel
install -m 755 "$BIN_DIR/atunnel-add" /usr/local/bin/atunnel-add
install -m 755 "$BIN_DIR/atunnel-del" /usr/local/bin/atunnel-del
install -m 755 "$BIN_DIR/atunnel-restart" /usr/local/bin/atunnel-restart
install -m 755 "$BIN_DIR/atunnel-forward.sh" /usr/local/bin/atunnel-forward.sh
# 兼容旧命令
ln -sf /usr/local/bin/atunnel /usr/local/bin/wsl-atrust
ln -sf /usr/local/bin/atunnel-add /usr/local/bin/wsl-atrust-add
ln -sf /usr/local/bin/atunnel-del /usr/local/bin/wsl-atrust-del
ln -sf /usr/local/bin/atunnel-restart /usr/local/bin/wsl-atrust-restart
ln -sf /usr/local/bin/atunnel-forward.sh /usr/local/bin/wsl-atrust-forward.sh

# 2. 安装配置模板 (已存在则保留)
echo "[2/4] 安装配置模板 ..."
if [ ! -f /etc/wsl-atrust-forward.conf ]; then
  install -m 644 "$REPO_DIR/config/wsl-atrust-forward.conf.example" /etc/wsl-atrust-forward.conf
  echo "  ✅ 已创建 /etc/wsl-atrust-forward.conf (请按需编辑)"
else
  echo "  ⏭  已存在 /etc/wsl-atrust-forward.conf, 跳过"
fi

# 3. 安装 systemd 服务
echo "[3/4] 安装 systemd 服务 ..."
install -m 644 "$REPO_DIR/systemd/wsl-atrust-forward.service" /etc/systemd/system/wsl-atrust-forward.service
systemctl daemon-reload
systemctl enable wsl-atrust-forward.service >/dev/null 2>&1 || true
systemctl start wsl-atrust-forward.service || true
echo "  服务状态: $(systemctl is-active wsl-atrust-forward.service)"

# 4. Windows 侧提示
echo "[4/4] Windows 侧部署指引 (首次需管理员一次)"
echo "  📁 复制 windows/ 目录到: C:\\Users\\<user>\\AppData\\Local\\wsl-atrust-portmapper\\"
echo "  📝 修改 portmapper.json (映射清单)"
echo "  🚀 启动: pythonw.exe portmapper.py  (建议放入启动文件夹)"
echo "  🔧 若与旧 netsh portproxy 冲突, 先删除: netsh interface portproxy delete v4tov4 ..."

echo ""
echo "=== 安装完成! 运行 atunnel status 验证 ==="
atunnel status 2>/dev/null || echo "atunnel status (需 WSL 环境)"
