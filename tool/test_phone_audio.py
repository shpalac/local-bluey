"""Model-free loopback tests for the phone-audio harness (#268)."""
import hashlib
import hmac
import json
import socket
import threading
import unittest

import phone_audio

KEY = "k"


def line(packet):
    return (json.dumps(packet) + "\n").encode()


class FakeMac:
    """Loopback server. `script(conn, read)` drives the Mac side."""

    def __init__(self, script):
        self.server = socket.socket()
        self.server.bind(("127.0.0.1", 0))
        self.server.listen(1)
        self.port = self.server.getsockname()[1]
        self.received = []
        self.thread = threading.Thread(target=self._serve, args=(script,), daemon=True)
        self.thread.start()

    def _serve(self, script):
        conn, _ = self.server.accept()
        buf = [b""]

        def read():
            while b"\n" not in buf[0]:
                chunk = conn.recv(65536)
                if not chunk:
                    return None
                buf[0] += chunk
            l, _, buf[0] = buf[0].partition(b"\n")
            pkt = json.loads(l)
            self.received.append(pkt)
            return pkt

        try:
            script(conn, read)
        finally:
            conn.close()

    def close(self):
        self.thread.join(timeout=5)
        self.server.close()


def pair_coalesced(conn, read):
    # hello and authRequired in ONE send.
    read()
    conn.sendall(line({"command": "hello"}) + line({"command": "authRequired", "text": "n0nce"}))
    auth = read()
    expect = hmac.new(KEY.encode(), b"n0nce", hashlib.sha256).hexdigest()
    assert auth["text"] == expect, auth
    conn.sendall(line({"command": "paired"}))


class HarnessTest(unittest.TestCase):
    def run_harness(self, script, timeout=3):
        mac = FakeMac(script)
        try:
            return phone_audio.run(mac.port, KEY, b"audio", answer_timeout=timeout), mac
        finally:
            mac.close()

    def test_coalesced_hello_and_challenge_pair(self):
        def script(conn, read):
            pair_coalesced(conn, read)
            read()  # holdAudio
            conn.sendall(line({"command": "say", "text": "hi"}))
        code, mac = self.run_harness(script)
        self.assertEqual(code, 0)
        self.assertEqual(mac.received[-1]["command"], "holdAudio")

    def test_face_and_say_in_one_packet_keep_the_answer(self):
        def script(conn, read):
            pair_coalesced(conn, read)
            read()
            conn.sendall(line({"command": "status", "text": "thinking"})
                         + line({"command": "say", "text": "the answer"}))
        self.assertEqual(self.run_harness(script)[0], 0)

    def test_reader_handles_split_and_batched_packets_in_order(self):
        a, b = socket.socketpair()
        try:
            reader = phone_audio.LineReader(a)
            payload = line({"n": 1}) + line({"n": 2}) + line({"n": 3})
            b.sendall(payload[:5])
            b.sendall(payload[5:])
            self.assertEqual([reader.next()["n"] for _ in range(3)], [1, 2, 3])
        finally:
            a.close()
            b.close()

    def test_missing_answer_fails(self):
        def script(conn, read):
            pair_coalesced(conn, read)
            read()
            conn.sendall(line({"command": "status", "text": "thinking"}))
            threading.Event().wait(1.5)
        self.assertEqual(self.run_harness(script, timeout=1)[0], 1)

    def test_empty_say_is_not_an_answer(self):
        def script(conn, read):
            pair_coalesced(conn, read)
            read()
            conn.sendall(line({"command": "say", "text": "  "}))
            threading.Event().wait(1.5)
        self.assertEqual(self.run_harness(script, timeout=1)[0], 1)

    def test_disconnect_fails(self):
        def script(conn, read):
            pair_coalesced(conn, read)
            read()
        self.assertEqual(self.run_harness(script)[0], 1)

    def test_old_speech_command_is_not_the_reply(self):
        def script(conn, read):
            pair_coalesced(conn, read)
            read()
            conn.sendall(line({"command": "speech", "text": "x"}))
        self.assertEqual(self.run_harness(script, timeout=1)[0], 1)


if __name__ == "__main__":
    unittest.main()
