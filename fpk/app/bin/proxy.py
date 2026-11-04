#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""HFish 反向代理：HTTP 9704 -> HTTPS <NAS_IP>:4433（忽略自签证书），供飞牛 iframe 内嵌"""
import http.server, socketserver, urllib.request, ssl, sys, os

TARGET = os.environ.get("HFISH_TARGET", "https://127.0.0.1:4433")
PORT = int(os.environ.get("HFISH_PROXY_PORT", "9704"))

def _target(host_header):
    """用浏览器实际访问的主机名/IP（同主机换 4433 端口）作上游。
    HFish 对 127.0.0.1:4433 的 /assets/ 请求会走 SPA 回退返回 index.html，
    固定回环地址会导致页面 CSS/JS 全部 404 成登录页。"""
    h = (host_header or "").split(":")[0].strip()
    if h in ("", "localhost", "127.0.0.1", "::1"):
        return TARGET
    return "https://%s:4433" % h

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

SKIP = {"transfer-encoding", "connection", "content-length", "content-encoding", "keep-alive",
        "x-frame-options"}

class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _proxy(self):
        if self.path in ("/", ""):
            self.send_response(302)
            self.send_header("Location", "/web/")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else None
        req = urllib.request.Request(_target(self.headers.get("Host")) + self.path, data=body, method=self.command)
        for k, v in self.headers.items():
            if k.lower() not in ("host", "connection", "accept-encoding"):
                req.add_header(k, v)
        req.add_header("Accept-Encoding", "identity")
        try:
            with urllib.request.urlopen(req, context=ctx, timeout=60) as r:
                data = r.read()
                self.send_response(r.status)
                for k, v in r.headers.items():
                    if k.lower() in SKIP:
                        continue
                    # CSP 带 frame-ancestors 时同样会拦 iframe，剥掉
                    if k.lower() == "content-security-policy" and "frame-ancestors" in v.lower():
                        continue
                    if k.lower() == "set-cookie":
                        # 去掉 Secure，否则浏览器在 HTTP 下不会保存验证码 session
                        v = v.replace("; Secure", "").replace(";Secure", "").replace("; secure", "")
                    self.send_header(k, v)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                if self.command != "HEAD":
                    self.wfile.write(data)
        except urllib.error.HTTPError as e:
            data = e.read()
            self.send_response(e.code)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except Exception as e:
            msg = ("proxy error: %s" % e).encode()
            self.send_response(502)
            self.send_header("Content-Length", str(len(msg)))
            self.end_headers()
            self.wfile.write(msg)

    do_GET = _proxy
    do_POST = _proxy
    do_PUT = _proxy
    do_DELETE = _proxy
    do_HEAD = _proxy
    do_OPTIONS = _proxy

class S(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

if __name__ == "__main__":
    print("hfish-proxy %s -> :%d" % (TARGET, PORT), flush=True)
    S(("0.0.0.0", PORT), H).serve_forever()
