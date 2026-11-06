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

# ---- 载荷（HFish / Cowrie 本体）必须先放进 app/bin/ ----
# 仓库里不放这两个大包（.gitignore 忽略 *.tgz），构建前需从已安装的 NAS 上取：
#   NAS:  /vol2/@appcenter/hive/bin/{hfish,cowrie}.tar.gz   ← 安装时解包留下的原始包
#   或:   /vol2/1000/docker/hive/3.3.7 与 /vol2/1000/docker/cowrie
# 约 96MB，缺失时构建出来的 fpk 装上去是没有蜜罐服务的空壳。
for need in app/bin/hfish.tar.gz app/bin/cowrie.tar.gz; do
  if [ ! -f "$SRC/$need" ]; then
    echo "缺少载荷 $need —— 请先从 NAS 上拷贝 hfish.tar.gz / cowrie.tar.gz 到 $SRC/app/bin/" >&2
    exit 1
  fi
done
# Windows 上编辑会把脚本写成 CRLF，打进包必炸（set -u\r），统一洗成 LF
sed -i 's/\r$//' cmd/* app/bin/*.sh app/bin/*.py wizard/* 2>/dev/null || true
tar -czf app.tgz -C app .
chmod 755 cmd/* app/bin/*.sh app/bin/*.py 2>/dev/null || true

cd "$SRC"
tar -czf "$OUT/hive.fpk" \
  app.tgz cmd config manifest wizard ICON.PNG ICON_256.PNG

echo "built: $OUT/hive.fpk ($(stat -c %s "$OUT/hive.fpk") bytes)"
