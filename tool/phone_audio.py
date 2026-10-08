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
import os
import subprocess
import sys
import tempfile
import time


class LinkError(RuntimeError):
    """The link closed, timed out or sent something unusable."""


class LineReader:
    """Reads newline-delimited JSON and keeps bytes after the first newline.

    TCP may coalesce several packets into one recv, so leftovers must stay
    in this connection-owned buffer for the next call (#268).
    """

    def __init__(self, sock):
        self.sock = sock
        self.buf = b""

    def next(self, timeout=15):
        deadline = time.monotonic() + timeout
        while b"\n" not in self.buf:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise LinkError("timed out waiting for a packet")
            self.sock.settimeout(remaining)
            try:
                chunk = self.sock.recv(4096)
            except socket.timeout:
                raise LinkError("timed out waiting for a packet")
            if not chunk:
                raise LinkError("mac closed the link")
            self.buf += chunk
        line, _, self.buf = self.buf.partition(b"\n")
        try:
            return json.loads(line.decode())
        except ValueError as e:
            raise LinkError(f"unparseable packet: {line[:80]!r}") from e


def send(sock, packet):
    sock.sendall((json.dumps(packet) + "\n").encode())


def handshake(sock, reader, key):
    """Hello, answer the nonce challenge, wait for paired."""
    send(sock, {"hello": "E2E Harness"})
    # The Mac greets with its own hello/broadcasts first, so read until the
    # nonce challenge actually arrives.
    reply = {}
    for _ in range(20):
        reply = reader.next()
        if reply.get("command") == "authRequired":
            break
    if reply.get("command") != "authRequired":
        raise LinkError(f"no challenge; last packet: {reply}")
    nonce = reply["text"]
    answer = hmac.new(key.encode(), nonce.encode(), hashlib.sha256).hexdigest()
    send(sock, {"command": "auth", "text": answer})
    for _ in range(20):
        confirmed = reader.next()
        if confirmed.get("command") == "paired":
            return nonce
        if confirmed.get("command") in ("authFailed", "unauthorized"):
            break
    raise LinkError(f"auth failed: {confirmed}")


def wait_for_answer(reader, timeout=60, per_packet=20):
    """Return the first nonempty production reply ('say'), else raise."""
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        pkt = reader.next(timeout=min(per_packet, max(0.1, end - time.monotonic())))
        if pkt.get("command") in ("status", "say") or pkt.get("text"):
            print(f"<- {json.dumps(pkt)[:220]}")
        if pkt.get("command") == "say" and (pkt.get("text") or "").strip():
            return pkt
    raise LinkError("no answer before the deadline")


def run(port, key, audio, answer_timeout=60):
    """Pair, send audio, require an answer. Returns a process exit code."""
    sock = socket.create_connection(("127.0.0.1", port), timeout=10)
    try:
        reader = LineReader(sock)
        try:
            nonce = handshake(sock, reader, key)
            print(f"nonce: {nonce[:16]}...")
            print("paired")
            send(sock, {"command": "holdAudio",
                        "audio": base64.b64encode(audio).decode()})
            print("holdAudio sent; waiting for Bluey to answer...")
            wait_for_answer(reader, timeout=answer_timeout)
        except LinkError as e:
            print(f"FAIL: {e}", file=sys.stderr)
            return 1
        return 0
    finally:
        sock.close()


def main():
    if len(sys.argv) < 4:
        print("usage: phone_audio.py <port> <link-key> <phrase>", file=sys.stderr)
        return 2
    port, key, phrase = int(sys.argv[1]), sys.argv[2], sys.argv[3]

    # Match the recorder's format: AAC-LC, 16 kHz, mono.
    with tempfile.TemporaryDirectory() as tmp:
        aiff = os.path.join(tmp, "phone_say.aiff")
        m4a = os.path.join(tmp, "phone_say.m4a")
        subprocess.run(["say", "-o", aiff, phrase], check=True, capture_output=True)
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", aiff,
             "-ar", "16000", "-ac", "1", "-c:a", "aac", m4a],
            check=True,
        )
        with open(m4a, "rb") as f:
            audio = f.read()
    print(f"audio: {len(audio)} bytes of AAC-LC 16kHz mono")
    return run(port, key, audio)


if __name__ == "__main__":
    sys.exit(main())
