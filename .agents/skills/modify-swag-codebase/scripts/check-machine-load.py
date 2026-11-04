"""Linux build/test admission with the same thresholds as check-machine-load.ps1."""

import json
import os
from pathlib import Path
import time


GIB = 1024 ** 3


def cpu_sample():
    fields = Path('/proc/stat').read_text().splitlines()[0].split()
    # Guest time is already included in user/nice. I/O wait is idle time.
    ticks = [int(value) for value in fields[1:9]]
    return sum(ticks), ticks[3] + ticks[4]


def cgroup_roots():
    # Resolve the current cgroup, including when the process shares the host's namespace.
    entry = next(line for line in Path('/proc/self/cgroup').read_text().splitlines()
                 if line.startswith('0::'))
    root = Path('/sys/fs/cgroup') / entry[3:].lstrip('/')
    groups = []
    for group in (root, *root.parents):
        if group == Path('/sys/fs'):
            break
        groups.append(group)
    return groups


def cgroup_usage(group):
    usage = dict(line.split() for line in (group / 'cpu.stat').read_text().splitlines())
    return int(usage['usage_usec'])


def check():
    before = cpu_sample()
    groups = cgroup_roots()
    usage_before = {group: cgroup_usage(group) for group in groups}
    start = time.monotonic()
    time.sleep(5)
    after = cpu_sample()
    usage_after = {group: cgroup_usage(group) for group in groups}
    elapsed = time.monotonic() - start
    ticks = after[0] - before[0]
    if ticks <= 0:
        raise ValueError('the CPU performance counter did not advance')
    cpu = 100 * (1 - (after[1] - before[1]) / ticks)

    memory = {line.split(':')[0]: int(line.split()[1]) * 1024
              for line in Path('/proc/meminfo').read_text().splitlines()}
    total = memory['MemTotal']
    available = memory['MemAvailable']
    limit = memory['CommitLimit']
    headroom = limit - memory['Committed_AS']

    # A quiet host cannot admit work into a saturated or memory-limited container.
    # Check each visible ancestor because a parent can impose a tighter shared limit.
    capacity = len(os.sched_getaffinity(0))
    cgroup_limits = []
    cgroup_memory_ready = True
    for group in groups:
        # The actual host root has no limits; a container's visible root can have them.
        host_root = group == Path('/sys/fs/cgroup')
        cpu_limit = group / 'cpu.max'
        quota, period = ('max', '100000') if host_root and not cpu_limit.exists() else cpu_limit.read_text().split()
        if quota != 'max':
            quota_capacity = int(quota) / int(period)
            capacity = min(capacity, quota_capacity)
            cpu = max(cpu, 100 * (usage_after[group] - usage_before[group]) / (elapsed * 1_000_000 * quota_capacity))
        memory_limit = group / 'memory.max'
        maximum = 'max' if host_root and not memory_limit.exists() else memory_limit.read_text().strip()
        if maximum != 'max':
            maximum = int(maximum)
            remaining = max(0, maximum - int((group / 'memory.current').read_text()))
            # Ignoring swap is conservative: it cannot replace available physical memory.
            required_group_memory = max(8 * GIB, maximum * 0.25)
            required_group_commit = max(4 * GIB, maximum * 0.10)
            cgroup_memory_ready &= remaining >= max(required_group_memory, required_group_commit)
            cgroup_limits.append({
                'path': str(group),
                'available_gib': round(remaining / GIB, 1),
                'required_physical_gib': round(required_group_memory / GIB, 1),
                'required_commit_headroom_gib': round(required_group_commit / GIB, 1),
            })
    cpu = max(cpu, 100 * (usage_after[groups[0]] - usage_before[groups[0]]) / (elapsed * 1_000_000 * capacity))
    required_memory = max(8 * GIB, total * 0.25)
    required_commit = max(4 * GIB, limit * 0.10)
    ready = cpu <= 65 and available >= required_memory and headroom >= required_commit and cgroup_memory_ready
    print(json.dumps({
        'status': 'ready' if ready else 'wait',
        'average_cpu_percent': round(cpu, 1),
        'maximum_cpu_percent': 65,
        'available_physical_gib': round(available / GIB, 1),
        'required_physical_gib': round(required_memory / GIB, 1),
        'commit_headroom_gib': round(headroom / GIB, 1),
        'required_commit_headroom_gib': round(required_commit / GIB, 1),
        'cgroup_limits': cgroup_limits,
    }), flush=True)
    return 0 if ready else 2


if __name__ == '__main__':
    try:
        raise SystemExit(check())
    except (OSError, ValueError, KeyError, StopIteration) as error:
        print(f'cannot measure machine load: {error}', flush=True)
        raise SystemExit(1)
