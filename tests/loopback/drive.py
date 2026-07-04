#!/usr/bin/env python3
# Drive a two-node MercuryFM ARQ link to trigger the gear-shift to qam16fm.
import socket, time, os

H = '127.0.0.1'
A_CTL, A_DATA = 8300, 8301   # node A: listener/callee (IRS)
B_CTL, B_DATA = 8302, 8303   # node B: caller/ISS (sender -> its log shows the gear-shift)
N = int(os.environ.get('PAYLOAD', '40000'))

def conn(p, tries=60):
    for _ in range(tries):
        try:
            s = socket.create_connection((H, p), timeout=2); s.setblocking(True); return s
        except OSError:
            time.sleep(0.25)
    raise SystemExit(f'could not connect to :{p}')

a_ctl, a_dat = conn(A_CTL), conn(A_DATA)
b_ctl, b_dat = conn(B_CTL), conn(B_DATA)

def cmd(sock, s, tag):
    sock.sendall(s.encode() + b'\r'); time.sleep(0.3)
    sock.setblocking(False)
    try: r = sock.recv(256)
    except (BlockingIOError, OSError): r = b''
    sock.setblocking(True)
    print(f'  {tag}: {s!r} -> {r!r}', flush=True)

def connected_seg(buf):
    for seg in buf.split(b'\r'):
        if seg.startswith(b'CONNECTED'):   # NOT DISCONNECTED
            return seg
    return None

print('== setup ==', flush=True)
cmd(a_ctl, 'MYCALL AAAA', 'A'); cmd(a_ctl, 'BW2300', 'A'); cmd(a_ctl, 'LISTEN ON', 'A')
cmd(b_ctl, 'MYCALL BBBB', 'B'); cmd(b_ctl, 'BW2300', 'B')
print('== connect ==', flush=True)
cmd(b_ctl, 'CONNECT BBBB AAAA', 'B')

b_ctl.settimeout(120); buf = b''; ok = False
try:
    while connected_seg(buf) is None:
        d = b_ctl.recv(256)
        if not d: break
        buf += d
    seg = connected_seg(buf)
    if seg:
        ok = True; print('  CONNECTED:', seg, flush=True)
    else:
        print('  !! socket closed before CONNECTED; buf=', buf[-200:], flush=True)
except socket.timeout:
    print('  !! timed out waiting for CONNECTED; buf=', buf[-200:], flush=True)
b_ctl.settimeout(None)

if ok:
    b_dat.sendall(b'X' * N)
    print(f'== sent {N} bytes on B data; draining A + holding session ~100s ==', flush=True)
    a_dat.settimeout(1.0); got = 0; deadline = time.time() + 100
    while got < N and time.time() < deadline:
        try:
            c = a_dat.recv(8192)
            if not c: break
            got += len(c)
        except socket.timeout:
            pass
    print(f'  A received {got}/{N} bytes  match={got==N}', flush=True)
    b_ctl.settimeout(20)
    cmd(b_ctl, 'BUFFER', 'B'); cmd(b_ctl, 'DISCONNECT', 'B')

for s in (a_ctl, a_dat, b_ctl, b_dat):
    try: s.close()
    except OSError: pass
print('== drive done ==', flush=True)
