#!/bin/bash
# 把 fpk/ 目录打成可安装的完整包 hive.fpk（自包含 HFish/Cowrie 载荷，卸载后可独立重装）
# 用法：./scripts/build-fpk.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/fpk"
OUT="$ROOT/dist"
mkdir -p "$OUT"

cd "$SRC"
rm -f app.tgz
# Windows 上编辑会把脚本写成 CRLF，打进包必炸（set -u\r），统一洗成 LF
sed -i 's/\r$//' cmd/* app/bin/*.sh app/bin/*.py wizard/* 2>/dev/null || true
tar -czf app.tgz -C app .
chmod 755 cmd/* app/bin/*.sh app/bin/*.py 2>/dev/null || true

cd "$SRC"
tar -czf "$OUT/hive.fpk" \
  app.tgz cmd config manifest wizard ICON.PNG ICON_256.PNG

echo "built: $OUT/hive.fpk ($(stat -c %s "$OUT/hive.fpk") bytes)"
