#!/bin/bash
# 蜜罐蜂巢卡死诊断：日志内容、表体积、容器状态、重启记录
set -u
PASS=$(docker inspect mysql --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | sed -n 's/^MYSQL_ROOT_PASSWORD=//p' | head -1)
[ -z "$PASS" ] && { echo "取不到 MySQL 口令（容器 mysql 的 MYSQL_ROOT_PASSWORD）" >&2; exit 1; }
echo "=== hfish.log 内容（尾部去重统计）==="
tail -c 3000000 /vol2/@appdata/hive/hfish.log 2>/dev/null | tr -d '\000' \
  | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9:.+]+[[:space:]]*//' \
  | sed -E 's/[0-9]{2,}/N/g' | sort | uniq -c | sort -rn | head -8

echo
echo "=== server.log 尾部 ==="
tail -c 4000 /vol2/@appdata/hive/hfish-data/logs/server.log 2>/dev/null | tr -d '\000' | tail -6

echo
echo "=== MySQL 表体积（最大的 6 张）==="
docker exec mysql mysql -uroot -p"$PASS" -D HFish -N -e "
select table_name, table_rows, round((data_length+index_length)/1048576) as mb
from information_schema.tables where table_schema='HFish' order by (data_length+index_length) desc limit 6;" 2>/dev/null

echo
echo "=== 容器状态与重启次数 ==="
docker ps --format "{{.Names}}\t{{.Status}}" | grep -iE "mysql|hive|hfish" | head -5
docker inspect mysql --format "mysql 重启次数={{.RestartCount}} 启动于={{.State.StartedAt}}" 2>/dev/null

echo
echo "=== hive 应用相关进程 ==="
ps -eo pid,pcpu,pmem,rss,etimes,args --sort=-pcpu | grep -iE "hfish|cowrie|hive" | grep -v grep | head -6 | cut -c1-140

echo
echo "=== 系统 OOM / 卡死记录（近 3 天）==="
journalctl --since "-3 days" --no-pager 2>/dev/null | grep -iE "oom|killed process|hung task|blocked for more than" | tail -6

echo
echo "=== 磁盘 IO 压力 ==="
cat /proc/pressure/io 2>/dev/null | head -2
vmstat 1 3 2>/dev/null | tail -2
