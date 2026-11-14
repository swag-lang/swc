"""Linux process runner. RSS is labelled separately from Windows committed memory."""
import os
from pathlib import Path
import signal
import subprocess
import threading
import time


def _system_times():
    ticks = list(map(int, Path('/proc/stat').read_text().splitlines()[0].split()[1:9]))
    scale = 1000 / os.sysconf('SC_CLK_TCK')
    return (ticks[3] + ticks[4]) * scale, sum(ticks) * scale


def run(cmd, cwd=None, env=None, pin=False, priority=None, capture_first_stdout=False,
        first_stdout_match=None, timeout=600):
    start = time.perf_counter()
    # taskset establishes affinity before exec, including for compiler subprocesses.
    if pin:
        cmd = ['taskset', '-c', str(min(os.sched_getaffinity(0))), *cmd]
    p = subprocess.Popen(cmd, cwd=cwd, env=env, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, start_new_session=True)
    output, errors, first = [], [], [None]
    def read(stream, dest, stdout=False):
        buffered = b''
        while True:
            chunk = os.read(stream.fileno(), 4096)
            if not chunk:
                break
            dest.append(chunk)
            buffered += chunk
            if stdout and first[0] is None and (first_stdout_match is None or
                    first_stdout_match.encode() in buffered):
                first[0] = (time.perf_counter() - start) * 1000
        stream.close()
    readers = [threading.Thread(target=read, args=(p.stdout, output, True)),
               threading.Thread(target=read, args=(p.stderr, errors))]
    for reader in readers:
        reader.start()
    expired = [False]
    def kill():
        expired[0] = True
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    timer = threading.Timer(timeout, kill)
    timer.start()
    try:
        _, status, usage = os.wait4(p.pid, 0)
        p.returncode = os.waitstatus_to_exitcode(status)
        for reader in readers:
            reader.join()
    finally:
        timer.cancel()
    cpu = (usage.ru_utime + usage.ru_stime) * 1000
    return {'exit': p.returncode, 'wall_ms': (time.perf_counter() - start) * 1000,
            'first_stdout_ms': first[0], 'cpu_ms': cpu, 'job_cpu_ms': cpu,
            'job_processes': None, 'peak_job_bytes': None, 'peak_proc_bytes': usage.ru_maxrss * 1024,
            'peak_working_set_bytes': usage.ru_maxrss * 1024,
            'memory_metric': 'wait4 maximum process RSS; tree committed peak unavailable',
            'timed_out': expired[0], 'stdout': b''.join(output).decode('utf-8', 'replace'),
            'stderr': b''.join(errors).decode('utf-8', 'replace')}
