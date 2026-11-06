#!/bin/bash
# NAS 端止血：关扫描感知 + 关威胁情报 + 清噪声表 + 清日志 + 重启
set -u
PASS=$(docker inspect mysql --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | sed -n 's/^MYSQL_ROOT_PASSWORD=//p' | head -1)
[ -z "$PASS" ] && { echo "取不到 MySQL 口令（容器 mysql 的 MYSQL_ROOT_PASSWORD）" >&2; exit 1; }
DB="docker exec mysql mysql -uroot -p${MYSQL_PASS} -D HFish"

echo "=== 备份 settings ==="
$DB -N -e "select name,config,status from settings where name in ('isScan','threat');" 2>/dev/null > /tmp/settings-before.txt
cat /tmp/settings-before.txt

echo
echo "=== 关闭扫描感知（is_open -> false，保留白名单等其余配置）==="
$DB -e "update settings set config=json_set(config,'\$.is_open',false) where name='isScan';" 2>/dev/null
$DB -N -e "select name,config from settings where name='isScan';" 2>/dev/null

echo
echo "=== 关闭威胁情报（source 置空，不再请求已超授权的接口）==="
$DB -e "update settings set config=json_set(config,'\$.source','') where name='threat';" 2>/dev/null
$DB -N -e "select name,left(config,60) from settings where name='threat';" 2>/dev/null

echo
echo "=== 清噪声表（scanners / scans / ip_profile —— 真攻击在 infos/flows，保留）==="
$DB -N -e "select 'infos', count(*) from infos; select 'flows', count(*) from flows;" 2>/dev/null
$DB -e "truncate table scanners; truncate table scans; truncate table ip_profile;" 2>/dev/null
$DB -e "optimize table scanners; optimize table scans; optimize table ip_profile;" 2>/dev/null
$DB -N -e "select 'scanners', count(*) from scanners; select 'ip_profile', count(*) from ip_profile;" 2>/dev/null

echo
echo "=== 清日志 ==="
: > /vol2/@appdata/hive/hfish.log
: > /vol2/@appdata/hive/hfish-data/logs/server.log
du -h /vol2/@appdata/hive/hfish.log /vol2/@appdata/hive/hfish-data/logs/server.log 2>/dev/null

echo
echo "=== 重启 hive 应用 ==="
/usr/local/bin/appcenter-cli restart hive 2>&1 | tail -2
sleep 12
systemctl is-active hive-honeypot.service 2>/dev/null || pgrep -f "hfish/server" >/dev/null && echo "hfish server 在跑"
pgrep -f "hfish/server" | head -2
