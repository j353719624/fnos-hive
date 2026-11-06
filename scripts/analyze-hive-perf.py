# -*- coding: utf-8 -*-
"""分析 NAS 上 HFish 扫描感知最近一小时写入的数据，定位「卡死」真凶。"""
import subprocess
from collections import Counter


def _mysql_password():
    """MySQL 口令从容器环境变量取，不写死在脚本里。"""
    try:
        out = subprocess.run(
            ["docker", "inspect", "mysql", "--format",
             "{{range .Config.Env}}{{println .}}{{end}}"],
            capture_output=True, text=True, timeout=15).stdout
    except Exception:
        return ""
    for line in out.splitlines():
        if line.startswith("MYSQL_ROOT_PASSWORD="):
            return line.split("=", 1)[1].strip()
    return ""


PASS = _mysql_password()

Q = [
    ("最近 1 小时新增", "select count(*) from scanners where create_time > now() - interval 1 hour"),
    ("总行数", "select count(*) from scanners"),
    ("IPv6 占比", "select concat(sum(instr(source_ip,':')>0),' / ',count(*)) from scanners where create_time > now() - interval 1 hour"),
    ("链路本地(fe80::)条数", "select count(*) from scanners where create_time > now() - interval 1 hour and source_ip like 'fe80%'"),
    ("ULA(fc/fd)条数", "select count(*) from scanners where create_time > now() - interval 1 hour and (source_ip like 'fc%' or source_ip like 'fd%')"),
    ("私网 192.168/10/172.16 条数", "select count(*) from scanners where create_time > now() - interval 1 hour and (source_ip like '192.168.%' or source_ip like '10.%' or source_ip like '172.16.%' or source_ip like '172.17.%' or source_ip like '172.18.%' or source_ip like '172.19.%' or source_ip like '172.2%' or source_ip like '172.30.%' or source_ip like '172.31.%')"),
    ("--- 源 IP TOP10（近 1 小时）---", "select source_ip, count(*) c, count(distinct dest_port) p from scanners where create_time > now() - interval 1 hour group by 1 order by c desc limit 10"),
    ("--- 目标端口 TOP10（近 1 小时）---", "select dest_port, count(*) c, count(distinct source_ip) s from scanners where create_time > now() - interval 1 hour group by 1 order by c desc limit 10"),
    ("--- scan_type 分布 ---", "select scan_type, count(*) from scanners where create_time > now() - interval 1 hour group by 1 order by 2 desc limit 5"),
    ("--- 最近 8 条原始记录 ---", "select create_time, source_ip, dest_port, scan_type, left(detail,50) from scanners order by id desc limit 8"),
    ("--- 命中 NAS 自身蜜罐端口的记录 ---", "select count(*) from scanners where create_time > now() - interval 1 hour and dest_port in (22,23,1099,2022,5900,6379,8080,8081,8989,9000,9080,9092,9198,9200,9294,7878)"),
    ("--- infos(蜜罐命中) 近1小时 ---", "select count(*) from infos where create_time > now() - interval 1 hour"),
    ("--- flows(会话) 近1小时 ---", "select count(*) from flows where create_time > now() - interval 1 hour"),
]

for title, sql in Q:
    r = subprocess.run(
        ["docker", "exec", "mysql", "mysql", "-uroot", "-p" + PASS,
         "-D", "HFish", "-N", "-e", sql],
        capture_output=True, text=True)
    out = (r.stdout or "").strip()
    if r.returncode != 0:
        out = "ERR: " + (r.stderr or "").strip().splitlines()[-1]
    print("== %s ==" % title)
    if out:
        for line in out.splitlines():
            print("   ", line)
    else:
        print("    (空)")
