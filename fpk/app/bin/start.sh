#!/bin/bash
# fnOS 蜜罐蜂巢：HFish 3.3.7 + Cowrie 3.1.5 + 反向代理（全部自包含在 app 目录内）
set -u
BIN="/vol2/@appcenter/hive/bin"
HF="${BIN}/hfish"
CW="${BIN}/cowrie"
VENV="${BIN}/venv"
PKGVAR="/vol2/@appdata/hive"
mkdir -p "${PKGVAR}"

# ---------- 1) HFish ----------
mkdir -p /usr/share/hfish/logs 2>/dev/null
cp -f "${HF}/config.toml" /usr/share/hfish/ 2>/dev/null || true
for d in web db i18n static template; do
  [ -e "/usr/share/hfish/$d" ] || cp -rf "${HF}/$d" /usr/share/hfish/ 2>/dev/null || true
done
pkill -f "${HF}/server" 2>/dev/null
sleep 1
cd "${HF}" 2>/dev/null && setsid ./server >>"${PKGVAR}/hfish.log" 2>&1 &

# ---------- 2) Cowrie（venv 便携化，安装后自动修 shebang）----------
if [ -x "${VENV}/bin/twistd" ]; then
  if ! head -1 "${VENV}/bin/cowrie" 2>/dev/null | grep -q "@appcenter"; then
    grep -rl "docker/cowrie/venv" "${VENV}/bin" 2>/dev/null | xargs -r sed -i "s|/vol2/1000/docker/cowrie/venv|${VENV}|g"
  fi
  pkill -f "twistd.*cowrie" 2>/dev/null
  sleep 1
  cd "${CW}" 2>/dev/null && setsid "${VENV}/bin/twistd" -n cowrie >>"${PKGVAR}/cowrie.log" 2>&1 &
  sleep 5
  iptables -t nat -C PREROUTING -p tcp --dport 22 -j REDIRECT --to-port 2022 2>/dev/null \
    || iptables -t nat -A PREROUTING -p tcp --dport 22 -j REDIRECT --to-port 2022 2>/dev/null || true
fi

# ---------- 3) 反向代理（飞牛 iframe / HTTP 登录）----------
pkill -f "${BIN}/proxy.py" 2>/dev/null
sleep 1
setsid python3 "${BIN}/proxy.py" >>"${PKGVAR}/proxy.log" 2>&1 &
echo "all started $(date)" >>"${PKGVAR}/start.log"
