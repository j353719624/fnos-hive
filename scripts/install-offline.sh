#!/bin/bash
# 离线包安装：把 HFish / Cowrie / FPK 一次性铺好并启动
# 用法：sudo ./install.sh   （在解压后的 fnos-hive-offline 目录内）
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

HF_DIR=/vol2/1000/docker/hive
CW_DIR=/vol2/1000/docker/cowrie
SHARE=/usr/share/hfish

echo "[1/6] 检查目录"
mkdir -p "$HF_DIR" "$CW_DIR" "$SHARE/logs"

echo "[2/6] 部署 HFish"
if [ -d "$HERE/hfish" ]; then
  cp -rf "$HERE/hfish/." "$HF_DIR/"
  chmod +x "$HF_DIR/server"
else
  echo "  跳过：离线包内没有 hfish/ 目录"
fi

echo "[3/6] 部署 Cowrie"
if [ -d "$HERE/cowrie" ]; then
  cp -rf "$HERE/cowrie/." "$CW_DIR/"
  if [ -d "$CW_DIR/venv" ]; then
    "$CW_DIR/venv/bin/python" -c "import cowrie" 2>/dev/null && echo "  venv 可用" || echo "  venv 异常"
  fi
else
  echo "  跳过：离线包内没有 cowrie/ 目录"
fi

echo "[4/6] 同步 HFish 配置目录"
cp -f "$HF_DIR/config.toml" "$SHARE/config.toml" 2>/dev/null || true
for d in web db i18n static template ttf; do
  [ -d "$HF_DIR/$d" ] && cp -rf "$HF_DIR/$d" "$SHARE/" 2>/dev/null || true
done

echo "[5/6] 安装 FPK"
FPK="$(ls "$HERE"/hive.fpk 2>/dev/null | head -1)"
if [ -n "$FPK" ] && command -v fnos-cli >/dev/null 2>&1; then
  fnos-cli app install-fpk "$FPK" --yes || true
  fnos-cli app start hive --yes || true
else
  echo "  跳过：未找到 hive.fpk 或 fnos-cli，请在飞牛应用中心手动安装"
fi

echo "[6/6] 完成"
cat <<EOF

访问： http://<NAS_IP>:9704/
账号： admin / HFish2021（登录后立刻修改）

组件：
  HFish    4433 / 4434
  Cowrie   22 -> 2022
  proxy    9704
EOF
