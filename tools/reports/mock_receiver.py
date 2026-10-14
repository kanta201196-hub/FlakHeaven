import http.server, json, sys
OUT = sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0)); body = self.rfile.read(n)
        d = json.loads(body.decode('utf-8'))
        ok = d.get('token') == 'fh-tester-2026'
        with open(OUT, 'a', encoding='utf-8') as f: f.write(json.dumps(d, ensure_ascii=False) + '\n')
        self.send_response(302); self.send_header('Location', 'https://script.googleusercontent.com/x'); self.send_header('Content-Length','0'); self.end_headers()
    def log_message(self, *a): pass
http.server.HTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
