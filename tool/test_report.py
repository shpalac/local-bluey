"""Render Flutter JSON reports without treating partial or failed runs as green."""

import argparse
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET


def parse_report(stream):
    tests, suites, problems = {}, {}, []
    terminal = None
    protocol = False
    elapsed = 0
    for line in stream.splitlines():
        if not line.strip():
            continue
        try:
            event = json.loads(line)
            if not isinstance(event, dict):
                raise ValueError('reporter event is not an object')
            kind = event['type']
            time = event.get('time', 0)
            if not isinstance(time, int) or time < 0:
                raise ValueError('invalid event time')
            elapsed = max(elapsed, time)
            if kind == 'start':
                protocol = event.get('protocolVersion') == '0.1.1'
                if not protocol:
                    problems.append('Unsupported reporter protocol')
            elif kind == 'suite':
                suite = event['suite']
                suites[suite['id']] = suite['path']
            elif kind == 'testStart':
                test = event['test']
                if test['id'] in tests:
                    raise ValueError('duplicate test id')
                if not isinstance(test['name'], str):
                    raise ValueError('invalid test name')
                tests[test['id']] = dict(name=test['name'], suite=test['suiteID'],
                                         start=time, duration=0, result=None,
                                         skipped=False, hidden=False, errors=[])
            elif kind == 'testDone':
                test = tests[event['testID']]
                if test['result'] is not None or time < test['start']:
                    raise ValueError('invalid test completion')
                result = event['result']
                if result not in ('success', 'failure', 'error'):
                    raise ValueError('invalid test result')
                test.update(result=result, duration=time - test['start'],
                            skipped=event.get('skipped', False), hidden=event.get('hidden', False))
            elif kind in ('error', 'lateError'):
                test = tests[event['testID']]
                test['errors'].append('failure' if event.get('isFailure') else 'error')
            elif kind == 'done':
                if terminal is not None:
                    raise ValueError('duplicate terminal event')
                terminal = event.get('success')
        except (ValueError, TypeError, KeyError):
            # Preserve usable results, but never turn corrupted input green.
            problems.append('Malformed reporter event')
    unfinished = [test for test in tests.values() if test['result'] is None]
    if terminal is not True and terminal is not False:
        problems.append('Missing successful/failed terminal event')
    if not protocol:
        problems.append('Missing supported reporter start')
    if unfinished:
        problems.append(f'{len(unfinished)} unfinished tests')
    if any(test['suite'] not in suites for test in tests.values()):
        problems.append('Missing suite metadata')
    failed = any(test['result'] in ('failure', 'error') or test['errors'] for test in tests.values())
    return dict(tests=tests, suites=suites, problems=problems, elapsed=elapsed,
                terminal_failed=terminal is False,
                success=terminal is True and not problems and not failed)


def visible_tests(report):
    # Hidden loader failures still belong in the exported report.
    return [test for test in report['tests'].values()
            if not test['hidden'] or test['result'] != 'success' or test['errors']]


def render_markdown(report):
    tests = visible_tests(report)
    failed = [test for test in tests if test['result'] in ('failure', 'error') or test['errors']]
    skipped = sum(bool(test['skipped']) for test in tests)
    state = 'INCOMPLETE' if report['problems'] else ('PASSED' if report['success'] else 'FAILED')
    lines = ['## Test report', '', f'**{state}** — {len(tests)} tests, '
             f'{len(failed)} failed, {skipped} skipped; {report["elapsed"] / 1000:.1f}s elapsed.', '',
             '| Slowest tests | Seconds |', '|---|---:|']
    for test in sorted(tests, key=lambda test: test['duration'], reverse=True)[:10]:
        name = test['name'].replace('|', '\\|').replace('\n', ' ')
        lines.append(f'| {name} | {test["duration"] / 1000:.3f} |')
    if failed:
        lines.extend(['', '**Failed tests:**'])
        lines.extend(f'- {test["name"]}' for test in failed)
    if report['problems']:
        lines.extend(['', '**Report integrity:**', *[f'- {problem}' for problem in report['problems']]])
    return '\n'.join(lines) + '\n'


def xml_text(value):
    return re.sub(r'[^\x09\x0a\x0d\x20-\ud7ff\ue000-\ufffd\U00010000-\U0010ffff]', '', str(value))


def render_junit(report):
    tests = visible_tests(report)
    suite = ET.Element('testsuite', name='Flutter', tests=str(len(tests) + bool(report['problems'])),
                       time=f'{report["elapsed"] / 1000:.3f}')
    failures = errors = skipped = 0
    for test in tests:
        path = report['suites'].get(test['suite'], 'unknown')
        # Use repository-relative names; raw stack traces stay in the artifact.
        path = path.replace('\\', '/').split('/test/')[-1]
        case = ET.SubElement(suite, 'testcase', name=xml_text(test['name']),
                             classname=xml_text(path), time=f'{test["duration"] / 1000:.3f}')
        if test['result'] == 'error' or 'error' in test['errors'] or test['result'] is None:
            ET.SubElement(case, 'error', message='Test error or incomplete execution; see JSON artifact')
            errors += 1
        elif test['result'] == 'failure' or test['errors']:
            ET.SubElement(case, 'failure', message='Test assertion failed; see JSON artifact')
            failures += 1
        elif test['skipped']:
            ET.SubElement(case, 'skipped')
            skipped += 1
    if report['problems']:
        case = ET.SubElement(suite, 'testcase', name='Reporter integrity', classname='ci', time='0')
        ET.SubElement(case, 'error', message='; '.join(report['problems']))
        errors += 1
    if report['terminal_failed'] and not failures and not errors:
        case = ET.SubElement(suite, 'testcase', name='Runner outcome', classname='ci', time='0')
        ET.SubElement(case, 'failure', message='The test runner reported failure')
        failures += 1
        suite.set('tests', str(len(tests) + 1))
    suite.set('failures', str(failures))
    suite.set('errors', str(errors))
    suite.set('skipped', str(skipped))
    return ET.tostring(suite, encoding='unicode') + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path', nargs='?', default='test-report.jsonl')
    parser.add_argument('--junit')
    parser.add_argument('--failed-files', action='store_true')
    args = parser.parse_args()
    try:
        stream = Path(args.path).read_text(encoding='utf-8')
    except OSError:
        stream = ''
    report = parse_report(stream)
    if args.junit:
        Path(args.junit).write_text(render_junit(report), encoding='utf-8')
    if args.failed_files:
        files = {report['suites'].get(test['suite'], '') for test in report['tests'].values()
                 if test['result'] in ('failure', 'error') or test['errors']}
        print(' '.join(sorted(path for path in files if path)))
    else:
        print(render_markdown(report), end='')
    return 0 if report['success'] else 1


if __name__ == '__main__':
    sys.exit(main())
