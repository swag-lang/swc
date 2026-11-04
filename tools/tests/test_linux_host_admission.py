"""Exercise admission against host and container resource limits without adding load."""

from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import runpy
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
CHECK = runpy.run_path(str(ROOT / '.agents/skills/modify-swag-codebase/scripts/check-machine-load.py'))['check']
CGROUP = '/sys/fs/cgroup'


class AdmissionTests(unittest.TestCase):
    def measure(self, *, available=14, committed=2, cpu_ticks=10, quota='400000 100000',
                usage=0, maximum=16, current=1, parent_usage=None, total_memory=16):
        gib = 1024 ** 3
        group = CGROUP + '/worker' if parent_usage is not None else CGROUP
        paths = {
            '/proc/self/cgroup': '0::/worker' if parent_usage is not None else '0::/',
            '/proc/meminfo': f'MemTotal: {total_memory * gib // 1024} kB\nMemAvailable: {int(available * gib) // 1024} kB\n'
                             f'CommitLimit: {12 * gib // 1024} kB\nCommitted_AS: {int(committed * gib) // 1024} kB\n',
            group + '/memory.current': str(current * gib),
        }
        if quota is not None:
            paths[group + '/cpu.max'] = quota
        if maximum is not None:
            paths[group + '/memory.max'] = str(maximum * gib)
        counters = {
            '/proc/stat': iter(['cpu 0 0 0 0 0 0 0 0', f'cpu {cpu_ticks} 0 0 {100 - cpu_ticks} 0 0 0 0']),
            group + '/cpu.stat': iter(['usage_usec 0', f'usage_usec {usage}']),
        }
        if parent_usage is not None:
            paths[CGROUP + '/cpu.max'] = '100000 100000'
            paths[CGROUP + '/memory.max'] = 'max'
            counters[CGROUP + '/cpu.stat'] = iter(['usage_usec 0', f'usage_usec {parent_usage}'])

        def read_text(path):
            key = str(path)
            return next(counters[key]) if key in counters else paths[key]

        output = io.StringIO()
        with patch.object(Path, 'read_text', read_text), \
             patch.object(Path, 'exists', lambda path: str(path) in paths), \
             patch('time.sleep'), patch('time.monotonic', side_effect=[0, 5]), \
             patch('os.sched_getaffinity', return_value={0, 1, 2, 3}), redirect_stdout(output):
            result = CHECK()
        return result, json.loads(output.getvalue())

    def test_idle_host_and_unlimited_root(self):
        self.assertEqual(self.measure()[0], 0)
        self.assertEqual(self.measure(quota=None, maximum=None)[0], 0)

    def test_host_cpu_pressure(self):
        self.assertEqual(self.measure(cpu_ticks=66)[0], 2)

    def test_physical_memory_floor(self):
        self.assertEqual(self.measure(available=7.9)[0], 2)

    def test_commit_headroom_floor(self):
        self.assertEqual(self.measure(committed=8.1)[0], 2)

    def test_container_does_not_lower_host_memory_threshold(self):
        self.assertEqual(self.measure(total_memory=64, available=12)[0], 2)

    def test_container_cpu_quota(self):
        # A busy single-CPU container on an otherwise quiet four-CPU host.
        result, report = self.measure(quota='100000 100000', usage=4_000_000)
        self.assertEqual(result, 2)
        self.assertEqual(report['average_cpu_percent'], 80)

    def test_container_memory_headroom(self):
        self.assertEqual(self.measure(maximum=12, current=5)[0], 2)

    def test_busy_shared_parent(self):
        self.assertEqual(self.measure(parent_usage=4_000_000)[0], 2)


if __name__ == '__main__':
    unittest.main()
