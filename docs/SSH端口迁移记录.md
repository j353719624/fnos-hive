# SSH 端口迁移记录

| 项目 | 内容 |
|---|---|
| 执行时间 | 2026-11-03 04:27 (CST) |
| 目标主机 | `47.100.29.31`（`iZjeq4bxy2cfwhZ`） |
| 变更内容 | SSH 端口 **22 → 52200** |
| 变更原因 | 减少公网批量扫描噪音（22 端口每天数百次探测） |
| 结果 | ✅ 22 已彻底关闭，52200 登录验证通过 |

---

## 一、当前对外端口

```
0.0.0.0:80       nginx     ACME 验证 + 已知域名 301 跳转
0.0.0.0:443      nginx     HTTPS（Host 白名单，仅 7 个域名）
0.0.0.0:52200    sshd      SSH（仅密钥登录）      ← 新端口
*:58619          lumos     LUMO 隧道（NAS 主动连入）
udp 47011        lumos     LUMO kcp 备用通道
```

**已关闭**：22、5666、8096、8123、3000、9091、13097、8001、8089、46351、18080

实测：

```
external 47.100.29.31:22    -> CLOSED
external 47.100.29.31:52200 -> OPEN
```

---

## 二、客户端连接方式

### 2.1 命令行

```bash
ssh -p 52200 -i "C:\Users\35371\.ssh\aliyun_as" root@47.100.29.31
```

### 2.2 写入 SSH config（推荐）

编辑 `C:\Users\35371\.ssh\config`（没有就新建），加入：

```
Host aliyun
    HostName 47.100.29.31
    Port 52200
    User root
    IdentityFile C:\Users\35371\.ssh\aliyun_as
```

以后直接：

```bash
ssh aliyun
```

### 2.3 图形化工具

| 工具 | 需要改的位置 |
|---|---|
| WinSCP / FileZilla | 站点配置里的「端口」改为 `52200` |
| MobaXterm / Xshell / SecureCRT | 会话属性 → 端口 → `52200` |
| VS Code Remote-SSH | 在 `~/.ssh/config` 里加 `Port 52200` |
| 手机 SSH App（Termius 等） | 主机设置里端口改 `52200` |
| Git / rsync / scp | 命令加 `-P 52200`（scp）或 `-p 52200`（ssh） |

---

## 三、服务端配置位置

### 3.1 SSH 配置

```
/etc/ssh/sshd_config
    └─ 第 144 行：Port 52200
```

**注意**：sshd 的规则是「只要配置里出现任何 `Port` 指令，就不再使用默认的 22」。所以现在只有 52200 生效。

### 3.2 防火墙（两层）

**① nftables ingress 白名单**（阿里云下发的那张表，我手动维护）

```
/etc/nftables-ingress.nft
    └─ tcp dport { 80, 443, 52200, 58619 } accept
```

**② firewalld**

```
services: dhcpv6-client
ports:    52200/tcp
```

（原来的 `ssh` service 已移除，它只放行 22）

### 3.3 自动巡检

```
/etc/systemd/system/fix-ingress-ports.timer      每分钟触发一次
/usr/local/sbin/fix-ingress-ports.sh             校验 80/443/52200/58619 四个端口
```

如果阿里云把 ingress 表重置回旧规则，这个定时器会在 1 分钟内自动重放正确配置。

---

## 四、回滚方法（改回 22 端口）

如果哪天客户端用不了 52200，需要临时开回 22：

```bash
# 1. 加回 22 端口（sshd_config）
echo "Port 22" >> /etc/ssh/sshd_config

# 2. 防火墙放行
nft add rule inet ingress input tcp dport 22 ct state new,untracked accept
firewall-cmd --permanent --add-service=ssh && firewall-cmd --reload

# 3. 重载 sshd（不断开现有连接）
systemctl reload sshd

# 4. 验证
ss -lntp | grep sshd
```

**完全回滚到最初状态**：

```bash
cp /etc/ssh/sshd_config.bak-20261103-* /etc/ssh/sshd_config
cp /etc/nftables-ingress.nft.bak-20261103-* /etc/nftables-ingress.nft
nft -f /etc/nftables-ingress.nft
systemctl reload sshd
```

---

## 五、救生索：万一 SSH 完全进不去

**走阿里云控制台 VNC，不依赖任何 SSH 端口：**

1. 登录 [轻量应用服务器控制台](https://swasnext.console.aliyun.com/)
2. 找到实例 `Alibaba Cloud Linux-mdhk`
3. 右上角点 **「远程连接」**
4. 选 **VNC / 救援登录**
5. 用 root 密码或者密钥登录进去改配置

**VNC 走的是阿里云内部通道，不受 firewalld、nftables、sshd 端口影响。**

---

## 六、备份文件清单

| 文件 | 内容 |
|---|---|
| `/etc/ssh/sshd_config.bak-20261103-*` | 改端口前的 sshd 配置 |
| `/etc/nftables-ingress.nft.bak-20261103-*` | 改端口前的 ingress 白名单 |
| `/etc/nginx/conf.d/*.bak-*` | nginx 各阶段配置备份 |
| `/etc/nginx/backup/00-acme.conf.bak-*` | 80 端口配置备份 |

---

## 七、本次迁移的操作步骤（供参考）

安全的两步走，全程没有「改完自己登不进去」的窗口期：

1. **先双端口**
   - `sshd_config` 显式写 `Port 22` + `Port 52200`
   - `systemctl restart sshd` → 两个端口同时监听

2. **外部验证新端口**
   - 用密钥连 52200，执行 `whoami; hostname`
   - 返回 `root` + `iZjeq4bxy2cfwhZ` → 确认可用

3. **再关旧端口**
   - 删除配置里的 `Port 22`
   - `systemctl reload sshd`（SIGHUP 重载，不重启进程、不断开现有会话）
   - 22 立即停止监听

4. **同步三处防火墙**
   - nftables ingress 白名单去掉 22
   - firewalld 移除 `ssh` service
   - 更新 `fix-ingress-ports.sh` 的校验列表

---

## 八、注意事项

### 8.1 会失效的东西

任何硬编码 `-p 22` 或默认 22 的脚本、CI、监控会全部失败。检查：

```bash
# 在服务器上查有没有其他系统在连自己
grep -r "47.100.29.31" /etc/cron* /etc/systemd/system/ 2>/dev/null
```

当前 `cron.d` 里只有 certbot 续期任务（本地执行，不走 SSH），不受影响。

### 8.2 扫描不会归零，只会减少

改端口能过滤掉**最廉价的批量扫描**（只扫 22 的那种），估计能减少 70-80% 的日志噪音。

但定向攻击者会用 `nmap -p-` 扫全端口（几分钟就能扫完 65535 个），所以**端口不是安全屏障，只认密钥 + 强密码才是**。

### 8.3 现有安全措施（保持不变）

- SSH 只允许密钥（`PasswordAuthentication no`）
- `MaxStartups 3:50:10`、`LoginGraceTime 20`
- nginx 恶意 UA / 恶意路径拦截（sqlmap、nikto、`.env`、`.git` 等）
- HTTPS 域名白名单，未知 Host 直接 444 断开
- IP 直连 80 端口 444 断开

---

## 九、速查卡

```
连接        ssh -p 52200 root@47.100.29.31
配置文件    /etc/ssh/sshd_config  (Port 52200)
防火墙      /etc/nftables-ingress.nft  { 80, 443, 52200, 58619 }
服务管理    systemctl status|restart|reload sshd
看监听      ss -lntp | grep sshd
看失败日志  journalctl -u sshd --since "1 hour ago" | grep -i invalid
救生索      阿里云控制台 → 远程连接 → VNC
```

---

*文档生成时间：2026-11-03 04:33 CST*
