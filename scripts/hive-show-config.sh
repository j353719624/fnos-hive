#!/bin/bash
# 查 NAS 与 ECS 两端的 HFish 扫描感知/威胁情报配置
set -u
PASS=$(docker inspect mysql --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | sed -n 's/^MYSQL_ROOT_PASSWORD=//p' | head -1)
[ -z "$PASS" ] && { echo "取不到 MySQL 口令（容器 mysql 的 MYSQL_ROOT_PASSWORD）" >&2; exit 1; }

echo "=== NAS 端 settings ==="
docker exec mysql mysql -uroot -p${MYSQL_PASS} -D HFish -N -e \
"select name, status, left(config,150) from settings where name in ('isScan','threat','whiteIp','apikey','syslog','counter');" 2>/dev/null

echo
echo "=== NAS 端配置项扫描相关（config.toml）==="
grep -inE "scan|threat|log|level" /vol2/@appdata/hive/hfish-data/config.toml 2>/dev/null | head -20

echo
echo "=== NAS 端 63219 监听与公网 IPv6 入站 ==="
ss -lntp 2>/dev/null | grep -E ":(63219|4434|4433) " | head -4
ip -6 addr show scope global | grep -oP "inet6 \K[0-9a-f:]+" | head -2
