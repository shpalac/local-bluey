"""Offline inventory of known golden failures, never a privacy/upload approval.

Usage: python3 tool/golden_failure_manifest.py REPO_ROOT
No upload, copy, baseline update or comparison pass is performed. Pixel review
and fixture provenance remain required: structural PNG checks cannot detect PII.
"""
import hashlib
import json
from pathlib import Path
import struct
import sys
import zlib

SUFFIXES = ('masterImage', 'testImage', 'isolatedDiff', 'maskedDiff')
MAX_FILES = 84
MAX_BYTES = 8 * 1024 * 1024
MAX_TOTAL = 64 * 1024 * 1024
MAX_PIXELS = 4_000_000


def png_size(data):
    """Check complete chunk framing and CRCs; not an image decoder."""
    if not data.startswith(b'\x89PNG\r\n\x1a\n'):
        raise ValueError('invalid PNG signature')
    offset, size, ended, image_data = 8, None, False, False
    while offset < len(data):
        if offset + 12 > len(data):
            raise ValueError('truncated PNG chunk')
        length = struct.unpack('>I', data[offset:offset + 4])[0]
        end = offset + 12 + length
        if end > len(data):
            raise ValueError('truncated PNG payload')
        kind = data[offset + 4:offset + 8]
        payload = data[offset + 8:end - 4]
        crc = struct.unpack('>I', data[end - 4:end])[0]
        if zlib.crc32(kind + payload) & 0xffffffff != crc:
            raise ValueError('invalid PNG CRC')
        if size is None:
            if kind != b'IHDR' or length != 13:
                raise ValueError('missing PNG header')
            size = struct.unpack('>II', payload[:8])
            if not all(size) or size[0] * size[1] > MAX_PIXELS:
                raise ValueError('invalid PNG dimensions')
        elif kind == b'IHDR':
            raise ValueError('duplicate PNG header')
        if kind == b'IDAT':
            image_data = True
        if kind == b'IEND':
            if length or end != len(data) or not image_data:
                raise ValueError('invalid PNG end')
            ended = True
        offset = end
    if not ended:
        raise ValueError('missing PNG end')
    return size


def inventory(root):
    root = Path(root)
    baseline = root / 'test/screenshots/goldens'
    failures = baseline / 'failures'
    if any(p.is_symlink() for p in (root, root / 'test',
                                      root / 'test/screenshots', baseline, failures)):
        raise ValueError('symlink directory rejected')
    keys = {p.stem for p in baseline.glob('*.png') if not p.is_symlink()}
    if not keys:
        raise ValueError('no baseline keys')
    files = sorted(failures.iterdir()) if failures.exists() else []
    if len(files) > MAX_FILES:
        raise ValueError('too many failure files')
    names = {f'{key}_{suffix}.png' for key in keys for suffix in SUFFIXES}
    result, total = [], 0
    for path in files:
        if path.name not in names or path.is_symlink() or not path.is_file():
            raise ValueError('unknown or non-regular failure file')
        length = path.stat().st_size
        total += length
        if length > MAX_BYTES or total > MAX_TOTAL:
            raise ValueError('failure byte limit exceeded')
        # Bound the read too, even if a concurrent writer grows the file.
        with path.open('rb') as stream:
            data = stream.read(MAX_BYTES + 1)
        if len(data) != length:
            raise ValueError('failure file changed during inventory')
        width, height = png_size(data)
        result.append(dict(key=path.name, bytes=length, width=width,
                           height=height, sha256=hashlib.sha256(data).hexdigest()))
    return dict(schema=1, status='review-required' if files else 'no-evidence',
                comparison='not-established', privacy='not-established',
                files=result)


if __name__ == '__main__':
    try:
        if len(sys.argv) != 2:
            raise ValueError('expected repository root')
        print(json.dumps(inventory(sys.argv[1]), indent=2, sort_keys=True))
    except (ValueError, OSError):
        # Do not echo raw paths, file contents or untrusted exception text.
        print('Golden failure inventory unavailable; inspect locally.', file=sys.stderr)
        sys.exit(1)
