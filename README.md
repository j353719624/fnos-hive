# fnos-hive · 蜜罐蜂巢

给飞牛 fnOS 用的一体化蜜罐应用（FPK）。把 **HFish**、**Cowrie** 和一个**反向代理**打进同一个应用，装完点图标就能在飞牛面板里操作。

## 组成

| 组件 | 版本 | 端口 | 作用 |
|---|---|---|---|
| HFish | 3.3.7 | 4433 / 4434 | 多协议诱捕、攻击态势、情报联动 |
| Cowrie | 3.1.5 | 22 → 2022 | 真实 SSH 协议栈，记录攻击者登录后的每条命令 |
| proxy.py | - | 9704 | HTTP→HTTPS 反向代理，供飞牛 iframe 内嵌 |

```
hive (FPK)
 ├─ HFish      server 4433，API 4434，蜜罐端口由面板分配
 ├─ Cowrie     twistd 监听 2022，iptables 把 22 转发过来
 └─ proxy.py   9704 暴露给浏览器/iframe，剥掉 Set-Cookie 的 Secure 标志
```

## 为什么需要反向代理

HFish 的 Web 面板是自签 HTTPS。两件事会坏：

1. 飞牛 iframe 加载自签 HTTPS 会被浏览器拦；
2. 它的会话 cookie 带 `Secure`，在 HTTP 页面下浏览器不保存，导致**登录时验证码永远报错**。

`proxy.py` 把 4433 转成普通 HTTP 的 9704，并把 `Set-Cookie` 里的 `Secure` 剥掉，同时把根路径 `/` 重定向到 `/web/`。所以正确入口是：

```
http://<NAS_IP>:9704/
```

## 安装

### 方式一：完整离线包（推荐，含二进制）

从 [Releases](https://github.com/j353719624/fnos-hive/releases) 下载 `fnos-hive-offline-*.tar.gz`，解压后执行：

```bash
tar -xzf fnos-hive-offline-*.tar.gz
cd fnos-hive-offline
sudo ./install.sh
```

### 方式二：只装 FPK（机器上已有运行目录时）

```bash
fnos-cli app install-fpk fpk/hive.fpk --yes
fnos-cli app start hive --yes
```

## 路径约定

FPK 本身只有 10 KB，是**启动器**，真正的程序在：

```
/vol2/1000/docker/hive/      HFish 二进制 + web + db + config
/vol2/1000/docker/cowrie/    Cowrie venv + etc + var
/usr/share/hfish/            运行时配置与 sqlite 数据库
/vol2/@appcenter/hive/bin/   FPK 解压的启动脚本（start.sh / proxy.py）
```

## 首次登录

```
地址  http://<NAS_IP>:9704/
账号  admin
密码  HFish2021
```

登录后**立刻改密码**，并在「节点管理」里勾选要启用的蜜罐服务。

## 端口避让

装之前确认这些端口没被占用（飞牛自带或常见应用会占）：

```
22      本机 SSH（若已改端口则空出，Cowrie 要用）
80 443  飞牛面板 / Web 服务
445     Samba
3000    MoviePilot
5666    飞牛面板
8085    其它穿透/代理
9701    MinerHunt
9704    本应用代理
```

## 安全提醒

- HFish 默认口令必须改；
- Cowrie 监听 22 会暴露在局域网，确认你确实想要这个诱捕面；
- 蜜罐本身不发起出站连接，但 Cowrie 会保存攻击者上传的文件到 `var/lib/cowrie/downloads/`，别拿真实环境跑未知样本。

## License

MIT
