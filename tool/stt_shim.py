#!/usr/bin/env python3
"""Bridge Bluey's OpenAI-style STT contract to whisper.cpp's /inference.

Two mismatches have to be papered over:

1. Route. Bluey's HttpSttProvider POSTs multipart to
   {base}/audio/transcriptions and expects {"text": ...}
   (lib/services/stt.dart). whisper.cpp only serves POST /inference.

2. Codec. Bluey records AAC-LC in an .m4a container (AudioRecorderDriver uses
   RecordConfig(encoder: AudioEncoder.aacLc)); whisper.cpp wants 16 kHz mono
   PCM. Without transcoding the server answers 400 "Invalid request", which is
   what Bluey surfaced before this existed.

So: pull the uploaded file out of the multipart body, transcode with ffmpeg,
forward the WAV, and pass the JSON straight back. Everything stays on loopback,
which Bluey's local-only mode requires.
"""
import argparse
import http.server
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import urllib.parse

DEFAULT_UPSTREAM = "http://127.0.0.1:8099/inference"
TIMEOUT = 120


def validate_upstream(url):
    """Accept only the literal IPv4 loopback inference route, no credentials."""
    try:
        parsed = urllib.parse.urlsplit(url)
        if (parsed.scheme != 'http' or parsed.hostname != '127.0.0.1'
                or parsed.username is not None or parsed.password is not None
                or parsed.path != '/inference' or parsed.query or parsed.fragment
                or parsed.port is None or not 1 <= parsed.port <= 65535):
            raise ValueError('upstream must be http://127.0.0.1:<port>/inference')
    except (ValueError, TypeError) as error:
        raise argparse.ArgumentTypeError(str(error)) from error
    return f'http://127.0.0.1:{parsed.port}/inference'


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # A loopback service must not redirect audio to a different destination.
        return None


def extract_upload(body: bytes, content_type: str):
    """Pull the first file part's bytes out of a multipart body.

    Deliberately minimal: we only need the audio, and re-implementing a full
    MIME parser would add failure modes for no benefit here.
    """
    m = re.search(r'boundary="?([^";]+)"?', content_type)
    if not m:
        # Not multipart (bare body). Pass it through untouched.
        return body
    boundary = ("--" + m.group(1)).encode()
    for part in body.split(boundary):
        if b"filename" not in part:
            continue
        head, _, data = part.partition(b"\r\n\r\n")
        return data.rstrip(b"\r\n")
    return None


def transcode(data: bytes) -> bytes:
    """Any input audio -> 16 kHz mono WAV bytes, as whisper.cpp expects."""
    if not shutil.which("ffmpeg"):
        raise RuntimeError("ffmpeg not found; cannot decode the upload")
    src = tempfile.NamedTemporaryFile(delete=False, suffix=".m4a")
    dst = tempfile.NamedTemporaryFile(delete=False, suffix=".wav")
    try:
        src.write(data)
        src.close()
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", src.name,
             "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", dst.name],
            check=True, capture_output=True,
        )
        with open(dst.name, "rb") as f:
            return f.read()
    finally:
        for p in (src.name, dst.name):
            try:
                os.unlink(p)
            except OSError:
                pass


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("shim: " + fmt % args + "\n")

    def _json(self, status: int, payload: bytes):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_POST(self):
        if self.path.rstrip("/") not in ("/audio/transcriptions",):
            self.send_error(404, "Not Found")
            return
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        content_type = self.headers.get("Content-Type", "")

        try:
            upload = extract_upload(body, content_type)
            if upload is None:
                self._json(400, json.dumps({"error": "no file part"}).encode())
                return
            wav = transcode(upload)
        except subprocess.CalledProcessError as e:
            self._json(
                400,
                json.dumps({"error": f"decode failed: {e.stderr[:200]!r}"}).encode(),
            )
            return
        except Exception as e:  # noqa: BLE001 - report, never crash the server
            self._json(502, json.dumps({"error": str(e)}).encode())
            return

        # Re-wrap as multipart so whisper's file-field parser accepts it.
        boundary = "----blueyshimboundary"
        parts = [
            f"--{boundary}\r\n".encode(),
            b'Content-Disposition: form-data; name="file"; filename="audio.wav"\r\n',
            b"Content-Type: audio/wav\r\n\r\n",
            wav,
            f"\r\n--{boundary}--\r\n".encode(),
        ]
        req = urllib.request.Request(
            self.server.upstream,
            data=b"".join(parts),
            headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
            method="POST",
        )
        try:
            with urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect()).open(req, timeout=TIMEOUT) as resp:
                self._json(resp.status, resp.read())
        except urllib.error.HTTPError as e:
            self._json(e.code, e.read())
        except Exception as e:  # noqa: BLE001
            self._json(502, json.dumps({"error": str(e)}).encode())

    def do_GET(self):
        if self.path != '/health':
            self.send_error(404, 'Not Found')
            return
        self._json(200, json.dumps({
            'service': 'bluey-stt-shim', 'upstream': self.server.upstream,
        }).encode())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('port', nargs='?', type=int, default=8098)
    parser.add_argument('--upstream', type=validate_upstream, default=DEFAULT_UPSTREAM)
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error('shim port must be between 1 and 65535')
    srv = http.server.ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    srv.upstream = args.upstream
    print(f'STT shim on http://127.0.0.1:{args.port} -> {srv.upstream}', flush=True)
    srv.serve_forever()


if __name__ == '__main__':
    main()
