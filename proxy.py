import http.server
import socketserver
import urllib.request

class ProxyHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        url = self.path
        if not url.startswith("http://") and not url.startswith("https://"):
            url = "http://" + self.headers.get("Host", "") + url
        try:
            req = urllib.request.Request(url, headers={k: v for k, v in self.headers.items() if k.lower() != "host"})
            with urllib.request.urlopen(req, timeout=30) as resp:
                self.send_response(resp.status)
                for k, v in resp.getheaders():
                    if k.lower() not in ["transfer-encoding", "content-length"]:
                        self.send_header(k, v)
                data = resp.read()
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
        except Exception as e:
            self.send_error(500, str(e))

    def do_CONNECT(self):
        # We only need HTTP for alpine mirrors
        self.send_error(501, "HTTPS not needed for alpine HTTP mirrors")

if __name__ == "__main__":
    port = 8080
    with socketserver.ThreadingTCPServer(("0.0.0.0", port), ProxyHandler) as httpd:
        print(f"Proxy listening on 0.0.0.0:{port}")
        httpd.serve_forever()
