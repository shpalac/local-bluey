#!/usr/bin/env python3
"""Drive Bluey's speech pipeline without a microphone.

Bluey's hold-to-talk records from the mic, which macOS will not grant without
a human click on System Settings. But the phone link already accepts a
holdAudio packet and feeds it through the identical transcription path
(lib/main.dart `_onPhoneAudio` -> `_processUtterance`). So speaking to the
STT endpoint can be proven end to end over loopback TCP without touching TCC.

Protocol (lib/link/phone_server.dart):
  1. newline-delimited JSON, connect to the Mac's advertised port
  2. {"hello": name}
  3. Mac replies {"command":"authRequired","text":nonce}
  4. answer {"command":"auth","text":HMAC-SHA256(key, nonce)}
  5. {"command":"holdAudio","audio":base64(audio)}
"""
import base64
import hashlib
import hmac
import json
import socket
import subprocess
import sys
import time


def recv_json(sock, timeout=15):
    sock.settimeout(timeout)
    buf = b""
    while b"\n" not in buf:
        chunk = sock.recv(4096)
        if not chunk:
            raise RuntimeError("mac closed the link")
        buf += chunk
    line, _, rest = buf.partition(b"\n")
    return json.loads(line.decode())


def main():
    if len(sys.argv) < 4:
        print("usage: phone_audio.py <port> <link-key> <phrase>", file=sys.stderr)
        return 2
    port, key, phrase = int(sys.argv[1]), sys.argv[2], sys.argv[3]

    # Match the recorder's format: AAC-LC, 16 kHz, mono.
    aiff = "/tmp/phone_say.aiff"
    m4a = "/tmp/phone_say.m4a"
    subprocess.run(["say", "-o", aiff, phrase], check=True, capture_output=True)
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", aiff,
         "-ar", "16000", "-ac", "1", "-c:a", "aac", m4a],
        check=True,
    )
    audio = open(m4a, "rb").read()
    print(f"audio: {len(audio)} bytes of AAC-LC 16kHz mono")

    sock = socket.create_connection(("127.0.0.1", port), timeout=10)
    sock.sendall((json.dumps({"hello": "E2E Harness"}) + "\n").encode())

    # The Mac greets with its own hello/broadcasts first, so read until the
    # nonce challenge actually arrives.
    reply = {}
    for _ in range(20):
        reply = recv_json(sock)
        if reply.get("command") == "authRequired":
            break
    if reply.get("command") != "authRequired":
        print(f"no challenge; last packet: {reply}", file=sys.stderr)
        return 1
    nonce = reply["text"]
    print(f"nonce: {nonce[:16]}...")

    answer = hmac.new(key.encode(), nonce.encode(), hashlib.sha256).hexdigest()
    sock.sendall((json.dumps({"command": "auth", "text": answer}) + "\n").encode())

    confirmed = recv_json(sock)
    if confirmed.get("command") != "paired":
        print(f"auth failed: {confirmed}", file=sys.stderr)
        return 1
    print("paired")

    sock.sendall(
        (json.dumps({"command": "holdAudio",
                     "audio": base64.b64encode(audio).decode()}) + "\n").encode()
    )
    print("holdAudio sent; waiting for Bluey to answer...")

    # Bluey pushes face/status back over the link; print whatever arrives.
    end = time.time() + 60
    while time.time() < end:
        try:
            pkt = recv_json(sock, timeout=20)
        except (socket.timeout, RuntimeError):
            break
        if pkt.get("command") in ("status", "speech", "say") or pkt.get("text"):
            print(f"<- {json.dumps(pkt)[:220]}")
        if pkt.get("command") == "speech":
            break
    return 0


if __name__ == "__main__":
    sys.exit(main())
