"""Loopback-only routing regression tests with generated non-private audio."""
import argparse
import contextlib
import http.server
import io
import json
import os
import shutil
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
import wave
from unittest.mock import patch
import stt_shim


@contextlib.contextmanager
def serving(handler):
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield server
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


class Upstream(http.server.BaseHTTPRequestHandler):
    received = []
    def log_message(self, *args):
        pass
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
    def do_POST(self):
        self.received.append(self.rfile.read(int(self.headers['Content-Length'])))
        data = b'{"text":"fixture"}'
        self.send_response(200)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)


class RoutingTest(unittest.TestCase):
    def test_reject_off_device_and_invalid_upstream(self):
        for url in ('https://127.0.0.1:8099/inference', 'http://example.com:8099/inference',
                    'http://localhost:8099/inference', 'http://127.0.0.1:0/inference',
                    'http://127.0.0.1:8099/other', 'http://user@127.0.0.1:8099/inference',
                    'http://127.0.0.1:8099/inference?x=1'):
            with self.subTest(url=url), self.assertRaises(argparse.ArgumentTypeError):
                stt_shim.validate_upstream(url)
        self.assertEqual(stt_shim.validate_upstream(stt_shim.DEFAULT_UPSTREAM),
                         'http://127.0.0.1:8099/inference')

    def test_default_upstream_and_redirect_rejection(self):
        self.assertEqual(stt_shim.DEFAULT_UPSTREAM, 'http://127.0.0.1:8099/inference')
        redirect = stt_shim.NoRedirect()
        self.assertIsNone(redirect.redirect_request(None, None, 302, '', {}, 'http://example.com/upload'))
        result = subprocess.run(['python3', str(Path(__file__).parent / 'stt_shim.py'),
                                 '--upstream', 'http://example.com:8099/inference'],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('127.0.0.1', result.stderr)

    def test_generated_audio_reaches_nondefault_upstream(self):
        Upstream.received = []
        with serving(Upstream) as upstream, serving(stt_shim.Handler) as shim:
            shim.upstream = f'http://127.0.0.1:{upstream.server_port}/inference'
            buffer = io.BytesIO()
            with wave.open(buffer, 'wb') as fixture:
                fixture.setnchannels(1)
                fixture.setsampwidth(2)
                fixture.setframerate(16000)
                fixture.writeframes(b'\x00\x00' * 1600)
            request = urllib.request.Request(
                f'http://127.0.0.1:{shim.server_port}/audio/transcriptions',
                data=buffer.getvalue(), headers={'Content-Type': 'audio/wav'})
            with patch('stt_shim.transcode', side_effect=lambda data: data), \
                    patch('stt_shim.urllib.request.Request', wraps=urllib.request.Request) as requests:
                with urllib.request.urlopen(request, timeout=5) as response:
                    self.assertEqual(json.load(response), {'text': 'fixture'})
                self.assertEqual(requests.call_args.args[0], shim.upstream)
                self.assertNotIn(':8099/', requests.call_args.args[0])
            self.assertEqual(len(Upstream.received), 1)
            self.assertIn(b'RIFF', Upstream.received[0])
            with urllib.request.urlopen(f'http://127.0.0.1:{shim.server_port}/health') as response:
                self.assertEqual(json.load(response)['upstream'], shim.upstream)

    @unittest.skipUnless(shutil.which('ffmpeg'), 'codec smoke needs ffmpeg; routing tests do not')
    def test_real_transcode_generated_wav(self):
        buffer = io.BytesIO()
        with wave.open(buffer, 'wb') as fixture:
            fixture.setnchannels(1)
            fixture.setsampwidth(2)
            fixture.setframerate(16000)
            fixture.writeframes(b'\x00\x00' * 1600)
        decoded = stt_shim.transcode(buffer.getvalue())
        with wave.open(io.BytesIO(decoded), 'rb') as result:
            self.assertEqual(result.getframerate(), 16000)
            self.assertEqual(result.getnchannels(), 1)
            self.assertGreater(result.getnframes(), 0)

    def test_launcher_reuses_only_matching_shim(self):
        with serving(Upstream) as upstream, serving(stt_shim.Handler) as shim, tempfile.TemporaryDirectory() as root:
            shim.upstream = f'http://127.0.0.1:{upstream.server_port}/inference'
            binary = Path(root) / 'whisper.cpp/build/bin/whisper-server'
            binary.parent.mkdir(parents=True)
            binary.write_text('#!/bin/sh\nexit 99\n')
            binary.chmod(0o755)
            model = Path(root) / 'model.bin'
            model.touch()
            env = dict(os.environ, STT_ROOT=root, STT_MODEL=str(model),
                       STT_UPSTREAM_PORT=str(upstream.server_port), STT_SHIM_PORT=str(shim.server_port))
            script = str(Path(__file__).parent / 'local_stt.sh')
            good = subprocess.run(['bash', script, 'start'], env=env, capture_output=True, text=True)
            self.assertEqual(good.returncode, 0, good.stderr)
            self.assertIn('stt up:', good.stdout)
            shim.upstream = 'http://127.0.0.1:8099/inference'
            bad = subprocess.run(['bash', script, 'start'], env=env, capture_output=True, text=True)
            self.assertNotEqual(bad.returncode, 0)
            self.assertIn('shim conflict', bad.stderr)
            self.assertNotIn('stt up:', bad.stdout)

    def _stop_env(self, root):
        run = Path(root) / 'run'
        run.mkdir(parents=True)
        env = dict(os.environ, STT_ROOT=root)
        script = str(Path(__file__).parent / 'local_stt.sh')
        return run, env, script

    def test_stop_cleans_up_stale_whisper_and_stops_live_shim(self):
        with tempfile.TemporaryDirectory() as root:
            run, env, script = self._stop_env(root)
            dead = subprocess.Popen(['true'])
            dead.wait()
            (run / 'whisper.pid').write_text(str(dead.pid))
            # A stub whose command line carries the managed marker.
            shim = subprocess.Popen(
                ['python3', '-c', 'import time; time.sleep(60)', 'stt_shim.py'])
            (run / 'shim.pid').write_text(str(shim.pid))
            try:
                for _ in range(2):
                    r = subprocess.run([script, 'stop'], env=env,
                                       capture_output=True, text=True, timeout=20)
                    self.assertEqual(r.returncode, 0, r.stderr)
                self.assertFalse((run / 'whisper.pid').exists())
                self.assertFalse((run / 'shim.pid').exists())
                self.assertIsNotNone(shim.wait(timeout=10))
            finally:
                if shim.poll() is None:
                    shim.kill()

    def test_stop_never_signals_unrelated_pid_and_tolerates_missing_files(self):
        with tempfile.TemporaryDirectory() as root:
            run, env, script = self._stop_env(root)
            other = subprocess.Popen(['sleep', '60'])
            (run / 'whisper.pid').write_text(str(other.pid))
            (run / 'shim.pid').write_text('not-a-pid')
            try:
                r = subprocess.run([script, 'stop'], env=env,
                                   capture_output=True, text=True, timeout=20)
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertIsNone(other.poll(), 'unrelated process was signaled')
                self.assertFalse((run / 'whisper.pid').exists())
                self.assertFalse((run / 'shim.pid').exists())
                r = subprocess.run([script, 'stop'], env=env,
                                   capture_output=True, text=True, timeout=20)
                self.assertEqual(r.returncode, 0, r.stderr)
            finally:
                other.kill()
                other.wait()

    def test_launcher_passes_selected_upstream_to_fresh_shim(self):
        with serving(Upstream) as upstream, tempfile.TemporaryDirectory() as root:
            # Reserve then release a dynamic loopback port for the child shim.
            with serving(Upstream) as reserved:
                port = reserved.server_port
            binary = Path(root) / 'whisper.cpp/build/bin/whisper-server'
            binary.parent.mkdir(parents=True)
            binary.write_text('#!/bin/sh\nexit 99\n')
            binary.chmod(0o755)
            model = Path(root) / 'model.bin'
            model.touch()
            env = dict(os.environ, STT_ROOT=root, STT_MODEL=str(model),
                       STT_UPSTREAM_PORT=str(upstream.server_port), STT_SHIM_PORT=str(port))
            script = str(Path(__file__).parent / 'local_stt.sh')
            try:
                result = subprocess.run(['bash', script, 'start'], env=env, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                with urllib.request.urlopen(f'http://127.0.0.1:{port}/health') as response:
                    self.assertEqual(json.load(response)['upstream'], f'http://127.0.0.1:{upstream.server_port}/inference')
            finally:
                pid = Path(root) / 'run/shim.pid'
                if pid.exists():
                    os.kill(int(pid.read_text()), 15)


if __name__ == '__main__':
    unittest.main()
