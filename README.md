# fnos-hive · 蜜罐蜂巢

给飞牛 fnOS 用的一体化蜜罐应用（FPK）。把 **HFish**、**Cowrie** 和一个**反向代理**打进同一个应用，装完点图标就能在飞牛面板里操作。

## 组成

| 组件 | 版本 | 端口 | 作用 |
|---|---|---|---|
| HFish | 3.3.7 | 4433 / 4434 | 多协议诱捕、攻击态势、情报联动 |
| Cowrie | 3.1.5 | 22 → 2022 | 真实 SSH 协议栈，记录攻击者登录后的每条命令 |
| proxy.py | - | 9704 | HTTP→HTTPS 反向代理，供飞牛 iframe 内嵌 |

```
hive (FPK, 自包含 ~91 MB)
 ├─ HFish      server 4433，API 4434，蜜罐端口由面板分配
 ├─ Cowrie     twistd 监听 2022，iptables 把 22 转发过来
 └─ proxy.py   9704 暴露给浏览器/iframe，剥掉 Set-Cookie 的 Secure 标志
```

## 为什么需要反向代理

HFish 的 Web 面板是自签 HTTPS。三件事会坏：

1. 飞牛 iframe 加载自签 HTTPS 会被浏览器拦；
2. 它的会话 cookie 带 `Secure`，在 HTTP 页面下浏览器不保存，导致**登录时验证码永远报错**；
3. HFish 响应带 `X-Frame-Options`，飞牛 iframe 会被浏览器直接拒绝。

`proxy.py` 把 4433 转成普通 HTTP 的 9704：剥掉 `Set-Cookie` 的 `Secure`、剥掉 `X-Frame-Options` 与含 `frame-ancestors` 的 CSP，并把根路径 `/` 重定向到 `/web/`。所以正确入口是：

```
http://<NAS_IP>:9704/
```

## 安装

`hive.fpk` 是**完整自包含包**（内含 HFish / Cowrie 二进制、UI 与安装向导，约 91 MB），不依赖机器上的旧安装。从 [Releases](https://github.com/j353719624/fnos-hive/releases) 下载 `hive.fpk`。

### 方式一：飞牛应用中心（推荐）

应用中心 → 手动安装 → 选择 `hive.fpk`。已安装时覆盖安装即为升级，配置不丢。

### 方式二：命令行

```bash
fnos-cli app install-fpk hive.fpk --yes
```

装完**自动启动**（安装回调会注册 systemd 托管单元并立即拉起），无需手动 start。

### 构建

```bash
bash scripts/build-fpk.sh   # 产出 dist/hive.fpk（完整包）
```

### 数据库

默认 SQLite，零配置开箱即用。需要集中存储时选 MySQL：提前建好库（如 `HFish`），连接串格式
`user:password@tcp(host:port)/dbname?charset=utf8mb4&parseTime=true&loc=Local`，装完后在应用「配置」里填写。

数据库配置写在 `hfish-data/config.toml`，**只在首次初始化时由安装包落盘**，之后应用启动不会覆盖它——网页里改完数据库、按提示重启应用即持久生效（升级、重启 NAS 都不会丢）。

## 启动 / 停止 / 自启

应用由 systemd 单元 `hive-honeypot.service`（`Type=simple` + `Restart=always`）托管：

- **装完即启动**，NAS 重启后自动拉起；
- 进程崩溃或被误杀，**3 秒内自动整体恢复**（HFish / Cowrie / 代理一并）；
- 应用中心「停止」= 真停止，不会被自动拉回（systemd 语义：显式 stop 不触发 Restart）；「启动」「重启」同样经 `cmd/main` 走 systemd；
- 应用中心显示的状态与真实状态一致（`cmd/main status` → `systemctl is-active`）。

## 卸载行为

| 卸载方式 | 结果 |
|---|---|
| 勾选「保留数据」 | 配置、账号密码、HFish 数据保留在 `/vol2/@appdata/hive/hfish-data`，重装后直接沿用，无需重新初始化 |
| 不勾选 | 应用目录、数据目录、软链、systemd 单元、22 端口转发全部清除，无残留 |

数据真身从首次启动起就存放在 `@appdata`，`/usr/share/hfish` 只是指向它的软链（HFish 无感知）。MySQL 外置库不受卸载影响。

## 路径约定

```
/vol2/@appcenter/hive/bin/        程序与启动脚本（自包含；旧安装位置仅作回退探测）
/vol2/@appdata/hive/hfish-data/   HFish 运行数据真身（config.toml / 账号 / db）
/vol2/@appdata/hive/*.log         各组件日志
/usr/share/hfish                  软链 → 上面的 hfish-data
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
