import hashlib
import hmac
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

root = Path(sys.argv[1])
key = b'x' * 48

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        case = (root / 'case.txt').read_text().strip()
        timestamp = self.headers.get('X-DevFleet-Host-Timestamp', '')
        nonce = self.headers.get('X-DevFleet-Host-Nonce', '')
        host = self.headers.get('X-DevFleet-Host-Expected', '')
        material = f'GET\n{self.path}\n{timestamp}\n{nonce}\n\n{host}'.encode()
        valid = hmac.compare_digest(hmac.new(key, material, hashlib.sha256).hexdigest(), self.headers.get('X-DevFleet-Host-Signature', ''))
        if case == 'timeout':
            time.sleep(4)
        status = 200 if valid and case != 'unauthorized' else 401
        healthy = 'false' if case == 'string-health' else status == 200 and case != 'not-ok'
        body = json.dumps({'ok': healthy}, separators=(',', ':')).encode()
        response_host = 'OTHER-FIXTURE' if case == 'wrong-host' else host
        response_material = f'GET\n{self.path}\n{timestamp}\n{nonce}\n{status}\n'.encode() + body + b'\n' + response_host.encode()
        signature = hmac.new(key, response_material, hashlib.sha256).hexdigest()
        if case == 'bad-signature':
            signature = '0' * 64
        try:
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            if case != 'unauthorized':
                self.send_header('X-DevFleet-Host-Response-Signature', signature)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass

server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
(root / 'port.txt').write_text(str(server.server_port))
server.serve_forever()
