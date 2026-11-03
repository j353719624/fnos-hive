#!/bin/bash
# 把 fpk/ 目录打成可安装的 hive.fpk
# 用法：./scripts/build-fpk.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/fpk"
OUT="$ROOT/dist"
mkdir -p "$OUT"

cd "$SRC"
rm -f app.tgz
tar -czf app.tgz --exclude='app/bin/hfish' -C app .
chmod 755 cmd/* app/bin/*.sh app/bin/*.py 2>/dev/null || true

cd "$SRC"
tar -czf "$OUT/hive.fpk" \
  app.tgz cmd config ICON.PNG ICON_256.PNG manifest

echo "built: $OUT/hive.fpk ($(stat -c %s "$OUT/hive.fpk") bytes)"
