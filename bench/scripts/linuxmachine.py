"""Record Linux power, affinity and cgroup context without changing host policy."""
import os
from pathlib import Path
import platform


def power():
    supplies = Path('/sys/class/power_supply')
    batteries = list(supplies.glob('BAT*'))
    ac = not batteries or any(p.read_text().strip() == '1' for p in supplies.glob('*/online'))
    governors = sorted({p.read_text().strip() for p in Path('/sys/devices/system/cpu').glob('cpu*/cpufreq/scaling_governor')})
    return {'ac': ac, 'battery_percent': None, 'saver': False, 'mode': ','.join(governors) or 'unavailable'}


def power_problem(state):
    return None if state['ac'] else 'the machine runs on battery'


def describe():
    info = Path('/proc/cpuinfo').read_text()
    cpu = next((s.split(':', 1)[1].strip() for s in info.splitlines() if s.startswith('model name')), platform.machine())
    memory = int(Path('/proc/meminfo').read_text().splitlines()[0].split()[1])
    cgroup = {}
    for name in ['cpu.max', 'memory.max']:
        p = Path('/sys/fs/cgroup') / name
        if p.exists():
            cgroup[name] = p.read_text().strip()
    return {'cpu': cpu, 'logical_processors': os.cpu_count(), 'performance_cores': None,
            'affinity': sorted(os.sched_getaffinity(0)), 'memory_gib': round(memory / 1024**2, 1),
            'os': platform.platform(), 'python': platform.python_version(), 'power': power(),
            'cgroup': cgroup, 'measurement_backend': 'linux-wait4-v1'}
