#!/bin/bash
set -u
HF="/vol2/1000/docker/hive"
BIN="/vol2/@appcenter/hive/bin"
CW="/vol2/1000/docker/cowrie"
LOG="${HF}/hfish.log"

# ---------- 1) HFish ----------
mkdir -p /usr/share/hfish/log 2>/dev/null
cp -f "${HF}/config.toml" /usr/share/hfish/ 2>/dev/null
for d in web db i18n static template ttf; do [ -e "/usr/share/hfish/$d" ] || cp -rf "${HF}/$d" /usr/share/hfish/ 2>/dev/null; done
pkill -f "${HF}/server" 2>/dev/null
pkill -f "${BIN}/proxy.py" 2>/dev/null
sleep 2
cd "${HF}" || exit 1
setsid ./server >>"${LOG}" 2>&1 &

# ---------- 2) Cowrie（真实 SSH 协议栈）----------
if [ -x "${CW}/venv/bin/cowrie" ]; then
  pkill -f "twistd.*cowrie" 2>/dev/null
  sleep 1
  cd "${CW}" || exit 1
  setsid env PATH="${CW}/venv/bin:$PATH" "${CW}/venv/bin/cowrie" start >>"${HF}/cowrie.log" 2>&1 &
  sleep 5
  # 22 -> 2022（iptables 转发，让 Cowrie 占住最真实的入口）
  iptables -t nat -C PREROUTING -p tcp --dport 22 -j REDIRECT --to-port 2022 2>/dev/null \
    || iptables -t nat -A PREROUTING -p tcp --dport 22 -j REDIRECT --to-port 2022 2>/dev/null
fi

# ---------- 3) 反向代理（飞牛 iframe 用）----------
cd "${BIN}" || exit 1
setsid python3 "${BIN}/proxy.py" >>"${HF}/proxy.log" 2>&1 &
echo "all started at $(date)" >>"${LOG}"
