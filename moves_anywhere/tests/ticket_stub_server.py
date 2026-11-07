#!/usr/bin/env python3
# ticket_stub_server.py #######################################################
#
# What:      Stub ticket server for docs/RUN_TICKET.md (standard library only).
# Does:      Serves GET /ticket, GET /in/<name> and PUT /out/<name> until stopped (see the docstring).
# Called by: tests/test_ticket_mode.sh, in a container. Not run by launch.sh.
# Reads:     the files in --in
# Writes:    files PUT to --out; the PUT order to --log (default puts.log beside --out)
# Exits:     2 on bad arguments (argparse); otherwise runs until killed
###############################################################################
"""Stub ticket server for docs/RUN_TICKET.md (standard library only).

GET /ticket      -> ticket JSON listing every file in --in as an input (/in/<name>)
                    and the four fixed outputs as PUT targets (/out/<name>)
GET /in/<name>   -> the file from --in
PUT /out/<name>  -> stored in --out; the order is appended to --log

--ghost NAME lists NAME as an input but does not serve it (404): the failure case.
"""
import argparse, hashlib, http.server, json, os, re

OUTPUTS = [("data.csv.gz", "application/gzip"), ("moveslog.txt.gz", "application/gzip"),
           ("replication.tar.xz", "application/x-xz"), ("run_manifest.json", "application/json")]

ap = argparse.ArgumentParser()
ap.add_argument("--in", dest="indir", required=True)
ap.add_argument("--out", dest="outdir", required=True)
ap.add_argument("--log", default=None)
ap.add_argument("--host", default="127.0.0.1")
ap.add_argument("--port", type=int, default=8765)
ap.add_argument("--run-id", default="d36109-u1-o1")
ap.add_argument("--ghost", action="append", default=[])
A = ap.parse_args()
LOG = A.log or os.path.join(os.path.dirname(os.path.abspath(A.outdir)), "puts.log")


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


def ticket(base):
    inputs = []
    for n in sorted(os.listdir(A.indir)):
        p = os.path.join(A.indir, n)
        if os.path.isfile(p) and re.match(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$", n):
            inputs.append({"name": n, "url": f"{base}/in/{n}?sig=stub", "sha256": sha(p),
                           "bytes": os.path.getsize(p)})
    for n in A.ghost:
        inputs.append({"name": n, "url": f"{base}/in/{n}?sig=stub"})
    outputs = [{"name": n, "put_url": f"{base}/out/{n}?sig=stub", "content_type": c, "required": True}
               for n, c in OUTPUTS]
    return {"ticket_version": 1, "run_id": A.run_id, "inputs": inputs, "outputs": outputs,
            "expires_at": "2099-01-01T00:00:00Z", "callbacks": []}


class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *a):  # never log the query string
        pass

    def reply(self, code, body=b"", ctype="application/octet-stream"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        base = f"http://{self.headers.get('Host')}"
        if path == "/ticket":
            return self.reply(200, json.dumps(ticket(base)).encode(), "application/json")
        m = re.match(r"^/in/([A-Za-z0-9][A-Za-z0-9._-]*)$", path)
        p = os.path.join(A.indir, m.group(1)) if m else None
        if p and m.group(1) not in A.ghost and os.path.isfile(p):
            with open(p, "rb") as f:
                return self.reply(200, f.read())
        self.reply(404, b"not found")

    def do_PUT(self):
        m = re.match(r"^/out/([A-Za-z0-9][A-Za-z0-9._-]*)$", self.path.split("?")[0])
        if not m:
            return self.reply(404)
        dest = os.path.join(A.outdir, m.group(1))
        if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
            with open(dest, "wb") as f:
                while True:
                    n = int(self.rfile.readline().strip() or b"0", 16)
                    if n == 0:
                        self.rfile.readline()
                        break
                    f.write(self.rfile.read(n))
                    self.rfile.readline()
        else:
            left = int(self.headers.get("Content-Length", 0))
            with open(dest, "wb") as f:
                while left:
                    c = self.rfile.read(min(left, 1 << 20))
                    if not c:
                        break
                    f.write(c)
                    left -= len(c)
        with open(LOG, "a") as f:
            f.write(m.group(1) + "\n")
        self.reply(200)


os.makedirs(A.outdir, exist_ok=True)
http.server.ThreadingHTTPServer((A.host, A.port), H).serve_forever()
