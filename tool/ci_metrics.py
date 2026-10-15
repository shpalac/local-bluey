#!/usr/bin/env python3
"""CI metrics with explicit API failures, never a silently empty table."""
import argparse
import datetime
import json
import math
import statistics
import subprocess
import sys

JOBS = ('static', 'test', 'build', 'build-macos', 'build-ios', 'android',
        'android-integration', 'linux', 'security', 'pinned-actions')
MAC_JOBS = {'build-macos', 'build-ios', 'simulator'}
UBUNTU_JOBS = set(JOBS) - MAC_JOBS
UBUNTU_JOBS.update({'detect', 'docs', 'acceptance-evidence'})
MAJOR_LANES = {'static', 'test', 'build-macos', 'build-ios', 'android',
               'android-integration', 'linux'}


def seconds_between(start, end):
    if not isinstance(start, str) or not isinstance(end, str):
        return None
    a = datetime.datetime.fromisoformat(start.replace('Z', '+00:00'))
    b = datetime.datetime.fromisoformat(end.replace('Z', '+00:00'))
    seconds = (b - a).total_seconds()
    return seconds if seconds >= 0 else None


def p95(values):
    values = sorted(values)
    return values[math.ceil(len(values) * .95) - 1]


def os_for_job(job, name):
    for label in job.get('labels') or []:
        if not isinstance(label, str):
            continue
        for os_name in ('macos', 'ubuntu', 'windows'):
            if os_name in label.lower():
                return os_name
    if name in MAC_JOBS:
        return 'macos'
    if name in UBUNTU_JOBS:
        return 'ubuntu'
    return 'unknown'


def repeated_setup(name):
    return ('subosito/flutter-action@' in name or 'setup-java@' in name
            or 'flutter pub get' in name)


def api(endpoint, expression):
    # One jq option, followed by its expression. Errors must propagate.
    result = subprocess.run(['gh', 'api', endpoint, '--jq', expression],
                            check=True, text=True, capture_output=True)
    return json.loads(result.stdout)


def report(repo, since):
    runs = api(f'repos/{repo}/actions/workflows/ci.yml/runs?created=>={since}&per_page=100',
               '[.workflow_runs[] | {id, conclusion, event, created_at, updated_at}]')
    # Do not count queued/in-progress workflows as successes.
    finished = [run for run in runs if run.get('conclusion') in {
        'success', 'failure', 'cancelled', 'timed_out', 'neutral',
        'skipped', 'action_required'
    }]
    failed = sum(run['conclusion'] == 'failure' for run in finished)
    rate = failed * 100 // len(finished) if finished else 0
    rows = ['## CI metrics (last 7 days)', '', f'- Runs: {len(runs)}',
            f'- Failed: {failed} ({rate}%)', '', '| Job | Median duration |',
            '|---|---:|']
    durations = {name: [] for name in JOBS}
    errors = []
    if len(runs) == 100:
        errors.append('Run enumeration reached the 100-run page limit.')
    runner_seconds = {'ubuntu': 0.0, 'macos': 0.0, 'windows': 0.0,
                      'unknown': 0.0}
    repeated_seconds = 0.0
    flutter_setup = []
    pr_wall = []
    pr_count = 0
    full_lane_count = 0
    for run in finished:
        try:
            jobs = api(f'repos/{repo}/actions/runs/{run["id"]}/jobs?per_page=100',
                       '[.jobs[] | {name, status, conclusion, started_at, completed_at, labels, steps}]')
            if len(jobs) == 100:
                errors.append(f'Run {run["id"]}: job list reached the 100-job page limit.')
            active_lanes = set()
            for job in jobs:
                name = job['name'].split(' (', 1)[0]
                if name not in durations or job['status'] != 'completed':
                    continue
                if not job['started_at'] or not job['completed_at']:
                    continue
                seconds = seconds_between(job['started_at'], job['completed_at'])
                if seconds is None:
                    continue
                runner_seconds[os_for_job(job, name)] += seconds
                if name in durations:
                    durations[name].append(seconds)
                if job.get('conclusion', 'success') != 'skipped':
                    active_lanes.add(name)
                for step in job.get('steps') or []:
                    if not isinstance(step, dict) or not isinstance(step.get('name'), str):
                        continue
                    duration = seconds_between(step.get('started_at'),
                                               step.get('completed_at'))
                    if duration is None:
                        continue
                    if repeated_setup(step['name']):
                        repeated_seconds += duration
                    if 'subosito/flutter-action@' in step['name']:
                        flutter_setup.append(duration)
            if run.get('event') == 'pull_request':
                pr_count += 1
                if MAJOR_LANES.issubset(active_lanes):
                    full_lane_count += 1
                wall = seconds_between(run.get('created_at'),
                                       run.get('updated_at'))
                if wall is not None:
                    pr_wall.append(wall)
        except (subprocess.CalledProcessError, ValueError, KeyError) as error:
            # Identify the failed read without echoing tokens or raw API content.
            errors.append(f'Run {run["id"]}: job-duration read failed ({type(error).__name__}).')
    for name, values in durations.items():
        if values:
            rows.append(f'| {name} | {statistics.median(values):g}s ({len(values)} jobs) |')
    rows += ['', '### PR wall-clock (includes queue time)']
    if pr_wall:
        rows += [f'- p50: {statistics.median(pr_wall):.0f}s',
                 f'- p95: {p95(pr_wall):.0f}s',
                 f'- Completed PR samples: {len(pr_wall)}']
    else:
        rows.append('- Unavailable: no completed PR runs with timestamps.')
    total_seconds = sum(runner_seconds.values())
    rows += ['', '### Runner utilization (job duration; OS labels / mapped hosted jobs)']
    if total_seconds:
        for os_name, value in runner_seconds.items():
            if value:
                rows.append(f'- {os_name}: {value / 60:.1f} runner-minutes')
        rows += [f'- Total: {total_seconds / 60:.1f} runner-minutes',
                 f'- Repeated setup share: {repeated_seconds / total_seconds * 100:.1f}% '
                 '(Flutter, setup-java and pub get steps)']
    else:
        rows.append('- No completed job durations available.')
    rows += ['', '### Cache/setup diagnostics']
    if flutter_setup:
        rows.append(f'- Flutter setup p50: {statistics.median(flutter_setup):.0f}s; '
                    f'p95: {p95(flutter_setup):.0f}s')
    else:
        rows.append('- Flutter setup timing unavailable.')
    rows.append('- Actual cache hit rates are unavailable from run/job metadata; '
                'setup times are a proxy, not hit/miss evidence.')
    rows += ['', '### Selectivity / repeated work']
    if pr_count:
        rows.append(f'- PR runs selecting all major lanes: {full_lane_count}/{pr_count} '
                    '(proxy; inspect per-PR impact reasons)')
    else:
        rows.append('- No completed PR runs for lane-selection analysis.')
    rows.append('- Repeated setup share is measured; cross-workflow duplicated '
                'tests are not inferable from this metadata alone.')
    rows.append('- Full-CI fallback categories appear in each PR detect job summary.')
    if errors:
        rows += ['', '### Incomplete report',
                 'Job-duration reads failed. Missing rows are unavailable, not zero jobs.']
        rows += [f'- {error}' for error in errors]
    elif not any(durations.values()):
        rows += ['', 'No matching completed jobs in the selected runs.']
    return '\n'.join(rows) + '\n', len(finished), rate, bool(errors)


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
