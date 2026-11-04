#!/bin/bash
# fnOS 蜜罐蜂巢：HFish 3.3.7 + Cowrie 3.1.5 + 反向代理（全部自包含在 app 目录内）
# 用法：start.sh      后台拉起一次（手动场景，行为同旧版）
#       start.sh fg   前台运行 + 看门狗：核心进程没了就退出整个脚本，
#                     交给 systemd Restart=always 3 秒后整体拉起
set -u
BIN="/vol2/@appcenter/hive/bin"
PKGVAR="/vol2/@appdata/hive"
# 自动发现 HFish / Cowrie 真实安装位置：fpk 自包含目录优先，回落到 docker 原始安装
HF=""
for d in "${BIN}/hfish" /vol2/1000/docker/hive/3.3.7 /vol2/1000/docker/hive /vol2/@appdata/hive/hfish; do
  [ -x "${d}/server" ] && HF="${d}" && break
done
CW="${BIN}/cowrie"; VENV="${BIN}/venv"
for d in "${BIN}/cowrie" /vol2/1000/docker/cowrie; do
  [ -x "${d}/venv/bin/twistd" ] && CW="${d}" && VENV="${d}/venv" && break
done
mkdir -p "${PKGVAR}"

if [ -z "${HF}" ]; then
  echo "$(date) ERROR: HFish server binary not found in any known location" >>"${PKGVAR}/start.log"
  exit 1
fi
mkdir -p "${PKGVAR}"

start_all() {
  # ---------- 0) HFish 数据迁入 @appdata：勾"保留数据"卸载才能保住配置和密码 ----------
  # 数据真身放 ${PKGVAR}/hfish-data，/usr/share/hfish 只留软链穿透，HFish 无感知。
  # 幂等：已是软链就跳过；首次升级把现有真实目录整体搬过去（先杀进程避免拷贝竞争）。
  if [ ! -L /usr/share/hfish ]; then
    pkill -f "${HF}/server" 2>/dev/null
    sleep 1
    mkdir -p "${PKGVAR}/hfish-data"
    if [ -d /usr/share/hfish ]; then
      cp -a /usr/share/hfish/. "${PKGVAR}/hfish-data/" 2>/dev/null || true
      rm -rf /usr/share/hfish
    fi
    ln -sfn "${PKGVAR}/hfish-data" /usr/share/hfish
    echo "$(date) migrated hfish data to ${PKGVAR}/hfish-data" >>"${PKGVAR}/start.log"
  fi
  # ---------- 1) HFish ----------
  mkdir -p /usr/share/hfish/logs 2>/dev/null
  # 配置只在首次落盘：之后用户在 Web 里改的数据库配置不被每次启动覆盖
  [ -f /usr/share/hfish/config.toml ] || cp -f "${HF}/config.toml" /usr/share/hfish/ 2>/dev/null || true
  for d in web db i18n static template; do
    [ -e "/usr/share/hfish/$d" ] || cp -rf "${HF}/$d" /usr/share/hfish/ 2>/dev/null || true
  done
  pkill -f "${HF}/server" 2>/dev/null
  sleep 1
  # 用绝对路径起进程，保证 pgrep/pkill 能匹配到 cmdline（相对路径 ./server 会导致 status 永远 stopped）
  cd "${HF}" 2>/dev/null && setsid "${HF}/server" >>"${PKGVAR}/hfish.log" 2>&1 &

  # ---------- 2) Cowrie（venv 便携化，安装后自动修 shebang）----------
  if [ -x "${VENV}/bin/twistd" ]; then
    if ! head -1 "${VENV}/bin/cowrie" 2>/dev/null | grep -q "@appcenter"; then
      grep -rl "docker/cowrie/venv" "${VENV}/bin" 2>/dev/null | xargs -r sed -i "s|/vol2/1000/docker/cowrie/venv|${VENV}|g"
    fi
    pkill -f "twistd.*cowrie" 2>/dev/null
    sleep 1
    # Cowrie 拒绝以 root 运行：降权到 admin（目录归属由 install_callback chown 保证）
    chown -R admin:Users "${CW}/var" 2>/dev/null || true
    setsid su -s /bin/bash admin -c "cd ${CW} && exec ${VENV}/bin/twistd -n cowrie" </dev/null >>"${PKGVAR}/cowrie.log" 2>&1 &
    sleep 5
    iptables -t nat -C PREROUTING -p tcp --dport 22 -j REDIRECT --to-port 2022 2>/dev/null \
      || iptables -t nat -A PREROUTING -p tcp --dport 22 -j REDIRECT --to-port 2022 2>/dev/null || true
  fi

  # ---------- 3) 反向代理（飞牛 iframe / HTTP 登录）----------
  pkill -f "${BIN}/proxy.py" 2>/dev/null
  sleep 1
  # 上游用 NAS 自己的 LAN IP：HFish 对 127.0.0.1:4433 的 /assets/ 请求会回 index.html
  NASIP="$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')"
  HFISH_TARGET="https://${NASIP:-127.0.0.1}:4433" setsid python3 "${BIN}/proxy.py" >>"${PKGVAR}/proxy.log" 2>&1 &
  echo "all started $(date)" >>"${PKGVAR}/start.log"
}

start_all

if [ "${1:-}" = "fg" ]; then
  sleep 3
  while :; do
    pgrep -f "${HF}/server" >/dev/null 2>&1 || exit 1
    pgrep -f "${BIN}/proxy.py" >/dev/null 2>&1 || exit 1
    sleep 5
  done
fi
