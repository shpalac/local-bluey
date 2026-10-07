#!/usr/bin/env python3
"""CI metrics with explicit API failures, never a silently empty table."""
import argparse
import datetime
import json
import statistics
import subprocess
import sys

JOBS = ('static', 'test', 'build', 'build-macos', 'build-ios', 'android',
        'android-integration', 'linux', 'security', 'pinned-actions')


def api(endpoint, expression):
    # One jq option, followed by its expression. Errors must propagate.
    result = subprocess.run(['gh', 'api', endpoint, '--jq', expression],
                            check=True, text=True, capture_output=True)
    return json.loads(result.stdout)


def report(repo, since):
    runs = api(f'repos/{repo}/actions/workflows/ci.yml/runs?created=>={since}&per_page=100',
               '[.workflow_runs[] | {id, conclusion}]')
    failed = sum(run['conclusion'] == 'failure' for run in runs)
    rate = failed * 100 // len(runs) if runs else 0
    rows = ['## CI metrics (last 7 days)', '', f'- Runs: {len(runs)}',
            f'- Failed: {failed} ({rate}%)', '', '| Job | Median duration |',
            '|---|---:|']
    durations = {name: [] for name in JOBS}
    errors = []
    for run in runs:
        try:
            jobs = api(f'repos/{repo}/actions/runs/{run["id"]}/jobs?per_page=100',
                       '[.jobs[] | {name, status, started_at, completed_at}]')
            for job in jobs:
                name = job['name'].split(' (', 1)[0]
                if name not in durations or job['status'] != 'completed':
                    continue
                if not job['started_at'] or not job['completed_at']:
                    continue
                start = datetime.datetime.fromisoformat(job['started_at'].replace('Z', '+00:00'))
                end = datetime.datetime.fromisoformat(job['completed_at'].replace('Z', '+00:00'))
                seconds = (end - start).total_seconds()
                if seconds >= 0:
                    durations[name].append(seconds)
        except (subprocess.CalledProcessError, ValueError, KeyError) as error:
            # Identify the failed read without echoing tokens or raw API content.
            errors.append(f'Run {run["id"]}: job-duration read failed ({type(error).__name__}).')
    for name, values in durations.items():
        if values:
            rows.append(f'| {name} | {statistics.median(values):g}s ({len(values)} jobs) |')
    if errors:
        rows += ['', '### Incomplete report',
                 'Job-duration reads failed. Missing rows are unavailable, not zero jobs.']
        rows += [f'- {error}' for error in errors]
    elif not any(durations.values()):
        rows += ['', 'No matching completed jobs in the selected runs.']
    return '\n'.join(rows) + '\n', len(runs), rate, bool(errors)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', required=True)
    parser.add_argument('--since', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--counts', required=True)
    args = parser.parse_args()
    try:
        text, total, rate, incomplete = report(args.repo, args.since)
    except (subprocess.CalledProcessError, ValueError, KeyError) as error:
        text = f'## CI metrics unavailable\n\nRun enumeration failed ({type(error).__name__}).\n'
        total, rate, incomplete = 0, 0, True
    with open(args.output, 'w', encoding='utf-8') as file:
        file.write(text)
    with open(args.counts, 'w', encoding='utf-8') as file:
        file.write(f'{total} {rate}\n')
    return int(incomplete)


if __name__ == '__main__':
    sys.exit(main())
