"""Conservative lane selection and fail-closed aggregate checks for Actions."""

import argparse
import json
import os
import subprocess

LANES = ('dart', 'macos', 'ios', 'android', 'linux', 'integration', 'swift', 'kotlin', 'doc_contracts')


def classify(paths):
    selected = dict.fromkeys(LANES, False)
    for path in paths:
        if path in ('README.md', 'docs/USER_GUIDE.md', 'docs/index.html'):
            selected['doc_contracts'] = True
        if path.endswith('.md') or path.startswith('docs/') or path == 'LICENSE':
            continue
        if path.startswith(('lib/', 'assets/')):
            lanes = ('dart', 'macos', 'ios', 'android', 'linux', 'integration')
        elif path.startswith('integration_test/'):
            lanes = ('dart', 'integration')
        elif path.startswith('test/'):
            lanes = ('dart', 'linux') if 'linux' in path or 'e2e_phone_host' in path else ('dart',)
        elif path.startswith('android/'):
            lanes = ('android', 'integration', 'kotlin')
        elif path.startswith('macos/'):
            lanes = ('macos', 'swift')
        elif path.startswith('ios/'):
            lanes = ('ios', 'swift')
        elif path.startswith('linux/'):
            lanes = ('linux',)
        else:
            # New configuration, deleted files and unfamiliar build inputs
            # receive full validation until explicitly classified.
            lanes = LANES
        for lane in lanes:
            selected[lane] = True
    return selected


def verify_gate(expected, results):
    errors = []
    for job, required in expected.items():
        result = results.get(job, {}).get('result')
        print(f'{job}: {result} (required={required})')
        allowed = ('success',) if required else ('success', 'skipped')
        if result not in allowed:
            errors.append(f'{job}: expected {allowed}, got {result}')
    if errors:
        raise ValueError('; '.join(errors))


def select(event, event_name):
    if event_name == 'schedule':
        return dict.fromkeys(LANES, False)
    if event_name == 'workflow_dispatch':
        return dict.fromkeys(LANES, True)
    if event_name == 'pull_request':
        base = event['pull_request']['base']['sha']
        head = event['pull_request']['head']['sha']
        revision = f'{base}...{head}'
    else:
        base, head = event.get('before'), event.get('after')
        if not base or not head or base == '0' * 40:
            return dict.fromkeys(LANES, True)
        revision = f'{base}..{head}'
    try:
        diff = subprocess.check_output(
            ['git', 'diff', '--no-renames', '--name-only', '-z', revision], stderr=subprocess.PIPE
        )
    except subprocess.CalledProcessError:
        # A force-push or unavailable ancestor must never silently skip CI.
        return dict.fromkeys(LANES, True)
    return classify(diff.decode('utf-8', errors='replace').split('\0')[:-1])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('select', 'gate'))
    args = parser.parse_args()
    if args.command == 'gate':
        verify_gate(json.loads(os.environ['CI_EXPECTED_JOBS']),
                    json.loads(os.environ['CI_JOB_RESULTS']))
        return
    with open(os.environ['GITHUB_EVENT_PATH'], encoding='utf-8') as source:
        selected = select(json.load(source), os.environ['GITHUB_EVENT_NAME'])
    with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
        for lane, enabled in selected.items():
            output.write(f'{lane}={str(enabled).lower()}\n')
    print(json.dumps(selected, indent=2))


if __name__ == '__main__':
    main()
