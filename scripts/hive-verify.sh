#!/bin/bash
# 验证卡死是否解决：进程 CPU、日志是否还刷、面板接口响应时间
set -u
PASS=$(docker inspect mysql --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | sed -n 's/^MYSQL_ROOT_PASSWORD=//p' | head -1)
[ -z "$PASS" ] && { echo "取不到 MySQL 口令（容器 mysql 的 MYSQL_ROOT_PASSWORD）" >&2; exit 1; }

echo "=== hive 进程（按完整路径找）==="
ps -eo pid,pcpu,pmem,rss,etimes,args | grep "appcenter/hive/bin" | grep -v grep | cut -c1-110

echo
echo "=== hfish.log 尾部 3 行 ==="
tail -c 2000 /vol2/@appdata/hive/hfish.log 2>/dev/null | tr -d '\000' | tail -3
echo "--- server.log 尾部 3 行 ---"
tail -c 2000 /vol2/@appdata/hive/hfish-data/logs/server.log 2>/dev/null | tr -d '\000' | tail -3

echo
echo "=== 日志体积 ==="
du -h /vol2/@appdata/hive/hfish.log /vol2/@appdata/hive/hfish-data/logs/server.log 2>/dev/null

echo
echo "=== 面板 API 响应时间（连测 3 次，这是卡死的核心指标）==="
for ep in "/api/v1/setting" "/api/v1/dashboard/attack" "/api/v1/scan/list?page=1&limit=10"; do
  printf "%-46s " "$ep"
  curl -sk -m 30 -o /dev/null -w "HTTP=%{http_code} 用时=%{time_total}s\n" \
    -H "Authorization: Bearer CItDNoQWMuwepmRLNnDMMwxDaSXDdMtTIZuYxPNmPKZlVRjitvyKGBTAmyNywScj" \
    "https://127.0.0.1:4433${ep}"
done

echo
echo "=== 慢查询 top5（MySQL 正在忙什么）==="
docker exec mysql mysql -uroot -p${PASS} -N -e "
select round(sum_time/1000000,1) as 秒, count_star, left(left(query,90),90)
from performance_schema.events_statements_summary_by_digest
where digest_text is not null and sum_timer_wait>100000000
order by sum_timer_wait desc limit 5;" 2>/dev/null
