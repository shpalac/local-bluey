"""Offline input preflight for run_bench.sh; never downloads assets."""
import json
import sys
from pathlib import Path

from wer import load_refs


def validate(root, fixtures, out, backend_selection='', clip_selection=''):
    root, fixtures, out = Path(root), Path(fixtures), Path(out)
    models = {
        'whispercpp-turbo': root / 'models/ggml-large-v3-turbo.bin',
        'whispercpp-ivrit': root / 'models/ggml-ivrit-turbo.bin',
        'whispercpp-v3': root / 'whisper.cpp/models/ggml-large-v3.bin',
    }
    selected = backend_selection.split() or [n for n, p in models.items() if p.is_file()]
    if not selected:
        sys.exit('no selected models available: install a model or select --backend NAME')
    if len(selected) != len(set(selected)):
        sys.exit('duplicate selected backend')
    for name in selected:
        if name not in models:
            sys.exit(f'unknown selected backend: {name}')
        if not models[name].is_file():
            sys.exit(f'missing selected model: {models[name]}')
    clips = clip_selection.split()
    if not clips and fixtures.is_dir():
        clips = sorted(p.name for p in fixtures.iterdir()
                       if p.is_file() and p.suffix in ('.wav', '.m4a'))
    if not clips:
        sys.exit(f'no selected audio fixtures in {fixtures}')
    if len(clips) != len(set(clips)):
        sys.exit('duplicate selected clip')
    for name in clips:
        if (Path(name).name != name or Path(name).suffix not in ('.wav', '.m4a')
                or any(c in name for c in (',', '\n', '\r'))):
            sys.exit(f'invalid selected audio name: {name}')
        if not (fixtures / name).is_file():
            sys.exit(f'missing selected audio fixture: {fixtures / name}')
    refs = load_refs(str(fixtures / 'refs.csv'))
    missing = set(clips) - set(refs)
    if missing:
        sys.exit(f'missing selected reference transcripts: {sorted(missing)}')
    out.mkdir(parents=True, exist_ok=True)
    (out / 'expected.json').write_text(json.dumps({'backends': selected, 'clips': clips,
                                                  'refs_path': str((fixtures / 'refs.csv').resolve())}))
    (out / 'backends.txt').write_text('\n'.join(selected) + '\n')
    (out / 'clips.txt').write_text('\n'.join(clips) + '\n')


if __name__ == '__main__':
    validate(*sys.argv[1:])
