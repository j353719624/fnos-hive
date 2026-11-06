# HFish 蜜罐节点部署说明

> **给接手的人：先看下面这一节，能避免 90% 的误操作。**

---

## ⚠️ 交接必读（五点，全部写在这里，不用另外问）

### 1. `:22` 不是 SSH 管理口，是蜜罐诱饵

```
:22      → HFish SSH 蜜罐（假 OpenSSH 7.4，接受任意密码并记录）
:52200   → 真 SSH（密钥登录，唯一运维通道）
```

**运维一律用 52200：**

```bash
ssh -p 52200 -i <私钥> root@47.100.29.31
```

拿 22 去连会反复"登录失败"，那是蜜罐在工作，不是机器坏了。**不要改 22 端口上的任何东西**——那是在拆诱饵。

### 2. `:4433` 管理面板只能走 SSH 隧道，公网永久关闭

```powershell
ssh -N -L 4433:127.0.0.1:4433 -p 52200 -i "<私钥>" root@47.100.29.31
```

浏览器：`https://127.0.0.1:4433/web/`

**三个必须**：
- 必须 **HTTPS**（4433 是 TLS，用 `http://` 会返回 400 Bad Request）
- 必须带 **`/web/`** 路径（少了返回 404）
- 证书自签，浏览器警告 → 高级 → 继续访问

**不要把 4433 加进防火墙白名单。** 这是有意设计的边界，面板一旦上公网就等于把整套蜜罐的配置权交出去。

### 3. syslog 到 NAS 守卫的链路**已接通（2026-11-06 16:24 实测通过）**

```
ECS HFish ──UDP:5514──► LUMO 隧道(58619) ──► NAS 守卫 5514  ✅
```

**实测证据**：从 NAS 打 ECS 的 Redis 蜜罐（`CONFIG GET`），守卫侧立刻出现事件
`112.22.108.149:6379 · 类型 attack · 蜜罐 数据库服务`。

链路走向：

```
攻击者 → ECS HFish 蜜罐(:22/:23/:6379/:445…)
            │ 告警策略 guard-syslog（含 scan）+ 扫描白名单滤掉自家网段
            ▼
      127.0.0.1:5514 (lumos 监听)
            │ LUMO 反向映射 udp 5514
            ▼
      NAS 127.0.0.1:5514 (hfish-guard syslog 接收器)
            │ 自动封禁：auto_block_level = all
            ▼
      NAS ipset hfish_guard_black → INPUT 顶部 DROP（全端口断网）
```

**注意**：ECS 上 HFish 用 SQLite（`/usr/share/hfish/database/hfish.db`），与 NAS 上的 MySQL 不是一套库，两边各自独立记录，只有告警汇总到同一个守卫。

### 4. `80` 端口的 Tomcat 蜜罐报错是正常的

日志里这条：

```
service[TOMCAT] listen err: listen tcp 0.0.0.0:80: bind: address already in use
```

**不要处理**。80 是 nginx 的 HTTPS 跳转入口，业务在用，不能让给蜜罐。HFish 会自动跳过这个服务，其他蜜罐不受影响。

### 5. 默认密码 `admin / HFish2021` 必须改

面板虽然只在隧道后面，但这是官方默认值。首次登录立刻改。

---

## 一、架构

```
公网攻击者
   │
   ├── :22    SSH 蜜罐    ┐
   ├── :23    Telnet 蜜罐 ├─ HFish 内置节点（本机 172.24.51.21）
   └── :6379  Redis 蜜罐  ┘
                              │
                              ├─ 攻击记录 → /usr/share/hfish/database/hfish.db (SQLite)
                              └─ 告警 syslog → 待接入 NAS 守卫（5514）

          ┌─ :4433 管理面板（HTTPS）  仅 SSH 隧道可达，公网关闭
          └─ :4434 节点通信           仅 SSH 隧道可达，公网关闭

真 SSH 保持在 :52200（密钥登录），与蜜罐 :22 完全隔离。
```

**设计原则**：
- 蜜罐端口（22/23/6379）对公网开放，用于钓鱼
- 管理面板（4433）与节点通信（4434）绝不上公网，只走 SSH 隧道
- 真 SSH 迁移到 52200，避免与蜜罐 :22 混淆
- 80 / 443 / 8443 留给 nginx（业务入口），HFish 的 Tomcat 蜜罐绑 80 失败属正常

---

## 二、目录与文件

| 路径 | 说明 |
|---|---|
| `/opt/hfish/hfish` | 主程序（daemon） |
| `/opt/hfish/3.3.6/` | 版本目录（含 db / packages / static / template / web） |
| `/usr/share/hfish/config.toml` | 运行配置（端口、数据库类型） |
| `/usr/share/hfish/database/hfish.db` | SQLite 数据库（攻击记录、节点配置） |
| `/usr/share/hfish/logs/server.log` | 服务日志 |
| `/etc/systemd/system/hfish.service` | systemd 单元 |

**重要**：安装脚本原本用 `nohup + crontab` 保活，已改为 **systemd 托管**（`Restart=always`），更可靠。

---

## 三、蜜罐配置（当前生效）

节点名：`内置节点`，client_id `bdQYwvlVkRUHNI8zmQh6Zzyb`

| 服务 | 端口 | 状态 |
|---|---|---|
| **SSH** | TCP/22 | ✅ online |
| **Telnet** | TCP/23 | ✅ online |
| **Redis** | TCP/6379 | ✅ online |
| Elasticsearch | TCP/9200 | ✅ online |
| Coremail | TCP/9000 | ✅ online |
| ESXi | TCP/8081 | ✅ online |
| 海康摄像头 | TCP/8080 | ✅ online |
| TCP 端口监听 | 135,139,445,1433,3389 | ✅ online |
| Tomcat | TCP/80 | ⚠️ 绑定失败（80 被 nginx 占用，正常） |

**公网实测**：

```
:22    open=true   banner="SSH-2.0-OpenSSH_7.4"
:23    open=true   banner=""
:6379  open=true   banner="ING"          ← 发 PING 后回
```

蜜罐配置存在 `clients.services` 字段（JSON 数组），没有节点模板（moulds）时可直接改库：

```python
# 追加蜜罐示例
import json, sqlite3
con = sqlite3.connect("/usr/share/hfish/database/hfish.db")
cur = con.cursor()
cid, raw = cur.execute("select id, services from clients limit 1").fetchone()
svcs = json.loads(raw or "[]")
svcs.append({
    "type": "SSH", "name": "SSH蜜罐", "class": "网络服务", "port": "TCP/22",
    "level": "low", "fish": 0, "https": "false", "command": "", "describe": "",
    "status": 1, "error": "", "is_web": False, "apikey": "", "proxy": "",
    "hostname": "", "username": "", "password": "", "files": "",
    "dns_books": "", "exe_ip": "", "exe_port": "", "firewall_status": 0
})
cur.execute("update clients set services=? where id=?", (json.dumps(svcs, ensure_ascii=False), cid))
con.commit()
```

改完必须 `systemctl restart hfish` 才生效。

---

## 四、防火墙（三处同步）

**① nftables ingress 白名单**（阿里云下发的那张表，手工维护）

```
/etc/nftables-ingress.nft
    tcp dport { 22, 23, 80, 443, 6379, 8443, 52200, 58619 } accept
```

**② firewalld**

```
ports: 22/tcp 23/tcp 6379/tcp 8443/tcp 52200/tcp 80/tcp 443/tcp
```

**③ 自动巡检**

```
/etc/systemd/system/fix-ingress-ports.timer   每分钟
/usr/local/sbin/fix-ingress-ports.sh          校验 22 23 80 443 6379 8443 52200 58619
```

阿里云若重置 ingress 表，定时器 1 分钟内自动纠正。

---

## 五、管理面板访问（只能走 SSH 隧道）

**公网 4433 已确认关闭**：

```
47.100.29.31:4433 -> CLOSED
```

**访问方式**：

```powershell
# 建隧道（保持窗口）
ssh -p 52200 -i "C:\Users\35371\.ssh\aliyun_as" -N -L 4433:127.0.0.1:4433 root@47.100.29.31
```

浏览器打开：

```
https://127.0.0.1:4433/web/
```

- 必须 **HTTPS**（4433 是 TLS，用 http 会返回 400）
- 必须带 **/web/** 路径
- 证书自签，浏览器提示不安全 → 高级 → 继续访问

**默认账号**：`admin` / `HFish2021`（首次登录后应立即修改）

**同时转发节点通信端口**：

```powershell
ssh -N -L 4433:127.0.0.1:4433 -L 4434:127.0.0.1:4434 root@47.100.29.31
```

**SSH config 写法**（`C:\Users\35371\.ssh\config`）：

```
Host hfish
    HostName 47.100.29.31
    Port 52200
    User root
    IdentityFile C:\Users\35371\.ssh\aliyun_as
    LocalForward 4433 127.0.0.1:4433
    LocalForward 4434 127.0.0.1:4434
```

之后 `ssh -N hfish` 即可。

**验证隧道**（实测结果）：

```
公网 47.100.29.31:4433          -> CLOSED
隧道内 https://127.0.0.1:4433/web/ -> HTTP/1.1 200 OK
                                     <title>HFish</title>
```

---

## 六、syslog 汇总到 NAS 守卫（已接通）

**目标**：ECS 上 HFish 的攻击告警 → NAS 上的 netfilter 守卫（5514）—— ✅ 已完成

### 6.1 做法（关键：别改 engine toml）

⚠️ **`/vol2/@appdata/lumo/engine-*.toml` 是生成物**，`appcenter-cli stop/start lumo` 时会从
`/vol2/@appdata/lumo/lumo-configs.json` 重新生成，手改会被覆盖（踩过一次）。

正确做法是改 **`lumo-configs.json`** 的 `mappings` 数组：

```json
{
  "id": "guardsys",
  "name": "hfish-guard-syslog",
  "type": "udp",
  "localIP": "127.0.0.1",
  "localPort": 5514,
  "remotePort": 5514,
  "compress": false
}
```

然后 `appcenter-cli stop lumo && sleep 3 && appcenter-cli start lumo`。
日志里出现 `proxy "d1e880aa-guardsys" (udp) registered` 即成功。

### 6.2 ECS 侧 HFish 配置（已写入，可复现）

```python
# settings.syslog
[{"addr": "127.0.0.1", "protocol": "UDP", "port": "5514", "format_type": 1}]

# settings.whiteIp —— 扫描白名单：把自家公网段加进来
#   LUMO 隧道心跳（打 58619，每 15 秒一条）会被 HFish 扫描感知记成「扫描」，
#   不加白名单的话，守卫按扇出判定可能把自家公网 IP 封了。
["112.22.0.0/16"]

# policies（type 里已含 scan：公网扫描器必须推给守卫才会被封；
#          广播噪声由 whiteIp + 守卫侧「源地址是否公网」双重过滤）
{"threat_alert": {"scenario": "all",
                  "type": ["signon", "attack", "compromise", "hr_signon", "scan"]},
 "system_alert": ["honeypot_offline", "node_offline", "high_load"]}
method = "syslog"
config = {"syslog": ["UDP:127.0.0.1:5514"]}
status = 1
```

改完 `systemctl restart hfish` 生效。

### 6.2.1 守卫侧必须配成「收到就封」

守卫配置页 → HFish 联动 → **按告警等级自动封禁 = 全部等级（含 other，收到即封）**。

原因：HFish 对蜜罐命中给的等级是 `other`，不是 `high`/`mid`。配 `high` 的话真机上一条都不会封
（实测 14 条蜜罐告警等级全是 `other`，`LEVEL_RANK` 里原本没有这个键，门禁形同虚设）。

配套两个保护（防止上游配置失误把黑名单刷爆）：

| 配置项 | 默认 | 作用 |
|---|---|---|
| 扫描判定扇出 `scan_fanout` | 5 | 同源命中多少个**不同端口**才算扫描者并封一次 |
| 自动封禁熔断 `auto_block_max_per_min` | 60 | 一分钟封满就只记事件不再封 |
| 黑名单容量 `max_blocks` | 20000 | 到顶不再新增（TTL 到期自然回落） |

实测（v1.5.0，100 秒）：syslog +204 条，黑名单 +5 条——`204.76.203.212/213/221/214`
四个专业扫描器（各扫 180~207 个端口）被判定为端口扫描并封禁；自家隧道心跳被
`whiteIp` 挡在源头，`noise=0`，没有误封。

### 6.3 验证方法

```bash
# 1) ECS 侧应有监听
ss -lnup | grep 5514            # *:5514 users:(("lumos",...))

# 2) 从 NAS 打 ECS 蜜罐，制造真实告警
python3 -c "import socket;s=socket.create_connection(('47.100.29.31',6379),5);s.sendall(b'*2\r\n\$6\r\nCONFIG\r\n\$3\r\nGET\r\n');s.close()"

# 3) 守卫侧查事件（应出现源为宽带公网 IP、端口 6379、类型 attack 的记录）
curl -H "Authorization: Bearer <token>" http://192.168.110.97:9705/api/events?limit=5
```

### 6.4 已知细节

- 守卫白名单含 `127.0.0.1`，所以**从 ECS 本机**打的自我测试会被记为 `skipped`（正常，不算漏报）
- 家宽公网 IP 是动态的（当天从 `112.22.108.139` 变成 `.149`），用自己的 IP 打蜜罐会被当成外部攻击记录，属预期

### 6.5 归属地（GeoIP）

守卫事件表里的「归属地」需要地理库。**没有库时所有公网 IP 都显示「未知地域」**——
这不是 bug，是没有数据源（守卫自带的兜底表只有十几条粗粒度规则）。

数据源优先级：`geo.json`（精确匹配） → MaxMind/DB-IP `.mmdb` → 内置推算表。

**城市库（推荐，一劳永逸）**——DB-IP 免费版，无需注册，每月更新：

```bash
# 在 NAS 上执行（约 58MB，解压后 121MB）
curl -sL -o /tmp/dbip.mmdb.gz \
  https://download.db-ip.com/free/dbip-city-lite-$(date +%Y-%m).mmdb.gz \
  && gunzip -f /tmp/dbip.mmdb.gz \
  && mv /tmp/dbip-city-lite-*.mmdb /vol2/@appdata/hfish-guard/DB-IP-City.mmdb \
  && systemctl restart hfish-guard
```

解析器 `geoip2` 由守卫的安装/升级钩子自动装（`apt install python3-geoip2`），不用手工处理。
DB-IP 的库不含中文国名，守卫内置了 ISO→中文映射表（123 条）兜底，所以显示「美国」「俄罗斯」而非英文。

**已知攻击源速查表**——HFish 自己就把归属地解析好了
（`scanners.source_ip_country` 字段，形如「美国」「中国-江苏-无锡」），可以直接导出成
守卫的 `geo.json`（精确匹配优先，未命中的 IP 仍会走 mmdb）：

```bash
# 在 ECS 上执行（HFish 用 SQLite 的那台）
python3 export-geo-from-hfish.py > /tmp/geo.json     # 脚本在守卫仓库 scripts/ 下
scp /tmp/geo.json admin@192.168.110.97:/vol2/@appdata/hfish-guard/geo.json
ssh -p 52200 admin@192.168.110.97 'sudo systemctl restart hfish-guard'
```

当前这台 NAS 上已就位：城市库 + 678 条 HFish 情报速查表（`geo.source = custom`）。

---

## 七、常用运维命令

```bash
# 服务状态
systemctl status hfish --no-pager
systemctl restart hfish
systemctl enable hfish

# 看蜜罐端口
ss -lntp | grep hfish

# 看节点服务状态
sqlite3 /usr/share/hfish/database/hfish.db "select mould_status from clients;"

# 看攻击总数
sqlite3 /usr/share/hfish/database/hfish.db "select count(*) from flows;"

# 看最近攻击（字段名以 .schema flows 为准）
sqlite3 -header -column /usr/share/hfish/database/hfish.db \
  "select * from flows order by id desc limit 10;"

# 看服务日志
journalctl -u hfish -n 50 --no-pager
tail -f /usr/share/hfish/logs/server.log

# 端口连通性自测（从外部）
nc -zv 47.100.29.31 22
nc -zv 47.100.29.31 23
nc -zv 47.100.29.31 6379
```

---

## 八、补充说明

### 8.1 端口语义总表

| 端口 | 用途 | 公网 |
|---|---|---|
| **22** | HFish SSH 蜜罐（**不是**真 SSH） | ✅ 开 |
| 23 | HFish Telnet 蜜罐 | ✅ 开 |
| 6379 | HFish Redis 蜜罐 | ✅ 开 |
| **52200** | **真 SSH**，密钥登录，唯一运维通道 | ✅ 开 |
| 4433 | HFish 管理面板 | ❌ 仅隧道 |
| 4434 | HFish 节点通信 | ❌ 仅隧道 |
| 80 / 443 / 8443 | nginx 业务入口 | ✅ 开 |
| 135,139,445,1433,3389,8080,8081,9000,9200 | 其他蜜罐 | ❌ 本地监听 |

### 8.2 蜜罐端口会刷屏

22/23/6379 是全网扫描率最高的三个端口，日志量会很大（每天几千次连接）。这是预期行为，HFish 会自动归类到 `flows` 表。

### 8.2.1 「老是卡死」的真正原因与处置（2026-11-06 19:00 定位并修复）

**症状**：HFish 面板转圈 / 打不开，飞牛桌面整体发涩。

**根因不是蜜罐在被打，是蜜罐在**记录**自己被打**，而且是每秒上百条地记录：

```
ECS 上的 HFish 客户端，每扫到一次 → 向 NAS 上报一次 (POST /api/v1/report/scan)
   → NAS 的 HFish server 逐条写 scanners / scans / ip_profile 三张表
   → 每条再打 2 行 INFO 日志
```

实测数据（修复前）：

| 指标 | 值 |
|---|---|
| `scanners` 表 | **51.4 万行 / 548 MB** |
| `scans` 表 | 51.1 万行 / 235 MB |
| `ip_profile` 表 | 10.3 万行 / 24 MB |
| `infos`（真攻击记录） | 只有 **221 行** |
| 写入速率 | **55 万条/小时**（约 150 条/秒） |
| HFish server CPU | **30.4%** 常驻，累计写盘 64 GB |
| MySQL CPU | 12.9% |
| IO 压力 | `full avg60 = 7.59%` |
| `hfish.log` | 338 MB（轮转后又有） |

面板查 `scanners` 做聚合统计，50 万行的表 → **接口要几十秒**，前端就一直转圈。

**处置（已执行）**：

1. **两端关闭「扫描感知」**
   - ECS：`settings.isScan.is_open = false`（停止上报源头）
   - NAS：同上（停止本地 63219 上的公网扫描入库）
   > 注意 NAS 侧 `isScan.configs` 为空只是「不推 syslog」，**照样入库**。要停必须改 `is_open`。
2. **关闭威胁情报**（`settings.threat.source` 置空）
   微步（threatbook）接口**已超授权**，每条记录都在白跑一次失败的 HTTPS 请求，日志里全是
   `fetch threat data err: 您当前调用的接口已经超出接口授权限制`。
3. **清理噪声数据**：`truncate scanners / scans / ip_profile`（`infos`/`flows` 保留，那是真攻击）
4. **清空日志**并 `analyze table` 刷新统计信息（否则面板显示的表大小还是旧值）
5. **装卫生巡检**（防复发）：`/usr/local/bin/hive-hygiene.sh` + `/etc/cron.d/hive-hygiene`，
   每小时第 17 分钟检查一次，超过阈值才清理（20 万行 / 200 MB），正常时零开销。
   撤销：`rm /etc/cron.d/hive-hygiene /usr/local/bin/hive-hygiene.sh`

**修复后实测**：

| 指标 | 修复前 | 修复后 |
|---|---|---|
| HFish server CPU | 30.4% | **0.0%** |
| MySQL CPU | 12.9% | **0.0%** |
| IO 压力 `full avg60` | 7.59% | **0.61%** |
| 面板接口响应 | 几十秒（转圈） | **4–7 ms** |
| 面板首屏加载 | 卡死 | **114 ms** |
| 噪声表 | 55 万行/小时 | **0，不增长** |

**取舍**：关闭扫描感知后，HFish 不再记录「谁在扫我的哪些端口」。真正的攻击记录
（`infos` 蜜罐命中、`flows` 会话）**不受影响**，守卫的自动封禁也不受影响
（它靠的是蜜罐命中告警，不是扫描记录）。需要「谁在扫我」时，用 ECS 上的
`scripts/export-geo-from-hfish.py` 定期导出即可。

### 8.3 数据存储

默认 SQLite（`hfish.db`，544 KB 初始）。HFish 官方建议：**数据量大时换 MySQL**，SQLite 在高并发写入下可能死锁。

当前配置：

```toml
[database]
    type = "sqlite"
    [[database.sqlite]]
        link = "hfish.db?cache=shared&mode=rwc"
    [[database.mysql]]
        link = "root:123456@tcp(127.0.0.1:3306)/hfish?charset=utf8mb4&parseTime=true&loc=Local"
```

流量起来了再考虑切 MySQL（本机目前没装 MySQL）。

---

## 九、部署过程回顾（供复现）

```bash
# 1. 下载离线包（123 MB）
curl -sSL "http://hfish.cn-bj.ufileos.com/hfish-3.3.6-linux-amd64.tgz" -o /tmp/hfish.tgz

# 2. 解压
mkdir -p /opt/hfish && tar zxf /tmp/hfish.tgz -C /opt/hfish

# 3. 安装（原脚本会 cp 二进制 + 写 crontab）
cd /opt/hfish && sh ./install.sh

# 4. 改为 systemd 托管（原 crontab 保活不可靠）
cat > /etc/systemd/system/hfish.service <<'EOF'
[Unit]
Description=HFish Honeypot Server
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/hfish
ExecStart=/opt/hfish/hfish
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable --now hfish

# 5. 注入 SSH / Telnet 蜜罐到节点配置
python3 /tmp/add_pots.py

# 6. 重启生效
systemctl restart hfish

# 7. 防火墙放行
nft -f /etc/nftables-ingress.nft
firewall-cmd --permanent --add-port=22/tcp --add-port=23/tcp --add-port=6379/tcp
firewall-cmd --reload
```

**离线包直链**（官方文档给的）：

```
http://hfish.cn-bj.ufileos.com/hfish-3.3.6-linux-amd64.tgz
http://hfish.cn-bj.ufileos.com/hfish-3.3.6-linux-arm64.tgz
```

> 注意后缀是 `.tgz` 不是 `.tar.gz`。官网 `/download/latest/` 那条 301 已经失效（返回 UFile 404）。

---

*文档生成时间：2026-11-06 16:20 CST*
