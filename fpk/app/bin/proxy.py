#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""HFish 反向代理：HTTP 9703 -> HTTPS 127.0.0.1:4433（忽略自签证书），供飞牛 iframe 内嵌"""
import http.server, socketserver, urllib.request, ssl, sys, os

TARGET = os.environ.get("HFISH_TARGET", "https://127.0.0.1:4433")
PORT = int(os.environ.get("HFISH_PROXY_PORT", "9704"))

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

SKIP = {"transfer-encoding", "connection", "content-length", "content-encoding", "keep-alive"}

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
        req = urllib.request.Request(TARGET + self.path, data=body, method=self.command)
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
