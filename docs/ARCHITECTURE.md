# 架构与踩坑记录

## 为什么是三个进程

HFish 的 server 自带内网节点，但它的 SSH 蜜罐只做到"识别协议、抓握手"，记不到攻击者登录后敲了什么。Cowrie 是完整 SSH 实现，能做会话记录和样本落盘。两个一起上，覆盖面和深度都够。

反向代理是为了解决飞牛 iframe 和 cookie 的两个坑（见下）。

## 三个真实的坑

### 1. FPK 的 `cmd/main` 不执行

fnOS 把应用文件解压到 `/vol2/@appcenter/<app>/bin/`，而 `/var/apps/<app>/` 下只有 `cmd/`、`config/` 和几个符号链接。所以 `cmd/main` 里用 `${TRIM_APPDEST}/bin/start.sh` 会指向不存在的路径。

**正确写法**：写死 `/vol2/@appcenter/hive/bin/start.sh`。

### 2. HFish 硬编码 `/usr/share/hfish`

第一次启动会 panic：

```
mkdir log dir err: mkdir /usr/share/hfish: permission denied
panic: open /usr/share/hfish/config.toml: no such file or directory
```

它不认工作目录，配置、日志、数据库全在 `/usr/share/hfish`。必须以 root 建这个目录，并把 `config.toml`、`web/`、`db/`、`i18n/` 放进去。

### 3. 验证码永远报错

HFish 的验证码会话存在 cookie 里，而响应头是：

```
set-cookie: ...; HttpOnly; Secure; SameSite=Lax
```

`Secure` 意味着浏览器只在 HTTPS 下保存。走自签 HTTPS（4433）时浏览器可能丢 cookie，走反代的 HTTP（9704）时更是一定丢。

结果就是 `/v1/login` 一直返回 `Captcha does not exist`。

**解法**：代理层把 `Set-Cookie` 里的 `Secure` 剥掉。

```python
if k.lower() == "set-cookie":
    v = v.replace("; Secure", "").replace(";Secure", "")
```

顺带把根路径 `/` 302 到 `/web/`，否则直接访问 9704 是 404。

## 版本显示问题

HFish 3.3.7 的前端包里版本字符串没更新，面板角标一直显示 V3.3.6。判断真实版本要看二进制：

```bash
md5sum /vol2/1000/docker/hive/server
# 与官方 hfish-3.3.7-linux-amd64.tgz 里的 server 一致即为 3.3.7
```

要改角标就替换 `web/assets/Decoy.*.js` 里的 `3.3.6`，但升级会被覆盖。

## 端口

| 端口 | 归属 |
|---|---|
| 4433 / 4434 | HFish server（面板 / API） |
| 2022 | Cowrie twistd |
| 22 | iptables REDIRECT → 2022 |
| 9704 | proxy.py |
| 9210–9226 等 | HFish 内网节点蜜罐（面板里勾选后监听） |
