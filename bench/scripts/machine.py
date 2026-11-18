"""What the machine was doing while a sample ran, and what the machine is.

Two cores of somebody else's work slow a pinned run of the reference workload by 17 %,
eight cores by 150 % (measured 2026-10-21: the power budget and the turbo frequency are
shared by every core). A check before the campaign cannot see a build another session
starts ten minutes later, so every sample is judged on its own:

    foreign cores = (busy time of every processor - our job's CPU - this driver's CPU)
                    / sample wall time

The system and job counters advance in clock ticks of 15.6 ms, so the estimate scatters.
More importantly, launching a process is not free for the rest of the machine: on the
benchmark laptop a burst of pinned 40 ms runs kept about three more performance cores busy
outside the job (the antivirus, event-tracing collectors and the editor react to every
process start). That load comes and goes with our own launches, so no fixed limit can
separate it from a visitor. Each family of measurements therefore keeps a running median
of its own readings, and a sample is contended when it exceeds that median by more than
FOREIGN_EXCESS_CORES: a visitor arriving, not the background the measurement causes.
A contended sample stays in the record with its measured load.
"""
import collections
import ctypes
import ctypes.wintypes as w
import os
import platform
import statistics
import subprocess
import sys
import time
if os.name == "nt":
    import winreg

import process as winproc

k32 = getattr(winproc, "k32", None)

# A sample is contended when it reads this many cores above its family's running median.
FOREIGN_EXCESS_CORES = 2.5
# Until a family has a median, a fixed ceiling stands in for it.
FOREIGN_CEILING_CORES = 8.0
BASELINE_WINDOW = 60
BASELINE_MIN = 5


def _busy_ms():
    times = winproc._system_times()
    if not times:
        return None
    idle, total = times
    return total - idle


def _self_cpu_ms():
    if os.name != "nt":
        return time.process_time() * 1000
    creation, exit_, kernel, user = (winproc.FILETIME() for _ in range(4))
    k32.GetProcessTimes(k32.GetCurrentProcess(), ctypes.byref(creation), ctypes.byref(exit_),
                        ctypes.byref(kernel), ctypes.byref(user))
    return winproc._ft(kernel) + winproc._ft(user)


def timed_run(cmd, **kwargs):
    """`winproc.run`, plus the foreign load the machine carried during it."""
    busy0, self0, t0 = _busy_ms(), _self_cpu_ms(), time.perf_counter()
    r = winproc.run(cmd, **kwargs)
    busy1, self1, t1 = _busy_ms(), _self_cpu_ms(), time.perf_counter()
    window_ms = (t1 - t0) * 1000.0
    if busy0 is None or busy1 is None or window_ms <= 0:
        r["foreign_cores"] = None
    else:
        foreign = (busy1 - busy0) - r["job_cpu_ms"] - (self1 - self0)
        r["foreign_cores"] = max(0.0, foreign / window_ms)
    return r


class Baseline:
    """The running median of one family's foreign-load readings, and its contention limit."""

    def __init__(self):
        self.values = collections.deque(maxlen=BASELINE_WINDOW)

    def limit(self):
        if len(self.values) < BASELINE_MIN:
            return FOREIGN_CEILING_CORES
        return statistics.median(self.values) + FOREIGN_EXCESS_CORES

    def judge(self, r):
        """Record the limit on the sample and return whether it was contended."""
        foreign = r.get("foreign_cores")
        r["foreign_limit"] = round(self.limit(), 2)
        return foreign is not None and foreign > r["foreign_limit"]

    def accept(self, r):
        if r.get("foreign_cores") is not None:
            self.values.append(r["foreign_cores"])

    def median(self):
        return statistics.median(self.values) if self.values else None


# ------------------------------------------------------------------ the machine
class SYSTEM_POWER_STATUS(ctypes.Structure):
    _fields_ = [("ACLineStatus", w.BYTE), ("BatteryFlag", w.BYTE), ("BatteryLifePercent", w.BYTE),
                ("SystemStatusFlag", w.BYTE), ("BatteryLifeTime", w.DWORD),
                ("BatteryFullLifeTime", w.DWORD)]


class GUID(ctypes.Structure):
    _fields_ = [("Data1", w.DWORD), ("Data2", w.WORD), ("Data3", w.WORD), ("Data4", w.BYTE * 8)]

    def __str__(self):
        tail = bytes(self.Data4)
        return "%08x-%04x-%04x-%s-%s" % (self.Data1, self.Data2, self.Data3, tail[:2].hex(), tail[2:].hex())


# The power mode slider of Windows 11. It moves the processors' frequency policy, which is
# why a campaign records it and two campaigns in different modes are not comparable.
POWER_MODES = {
    "961cc777-2547-4f9d-8174-7d86181b8a7a": "best power efficiency",
    "00000000-0000-0000-0000-000000000000": "balanced",
    "3af9b8d9-7c97-431d-ad78-34a8bfea439f": "better performance",
    "ded574b5-45a0-4f42-8737-46345c09c238": "best performance",
}


def power():
    status = SYSTEM_POWER_STATUS()
    ok = k32.GetSystemPowerStatus(ctypes.byref(status))
    mode = None
    try:
        guid = GUID()
        if ctypes.WinDLL("powrprof").PowerGetEffectiveOverlayScheme(ctypes.byref(guid)) == 0:
            mode = POWER_MODES.get(str(guid), str(guid))
    except (OSError, AttributeError):
        pass
    return {
        "ac": bool(ok) and status.ACLineStatus == 1,
        "battery_percent": status.BatteryLifePercent if ok and status.BatteryLifePercent != 255 else None,
        "saver": bool(ok) and status.SystemStatusFlag == 1,
        "mode": mode,
    }


def power_problem(state):
    """Why the machine cannot be measured right now, or None."""
    if not state["ac"]:
        return "the machine runs on battery; plug it in, the processors are throttled otherwise"
    if state["saver"]:
        return "battery saver is on; it caps the processors' frequency"
    return None


def describe():
    """Everything about the machine that changes a timing, recorded with every campaign."""
    cpu = None
    try:
        with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE,
                            r"HARDWARE\DESCRIPTION\System\CentralProcessor\0") as key:
            cpu = winreg.QueryValueEx(key, "ProcessorNameString")[0].strip()
    except OSError:
        pass

    class MEMORYSTATUSEX(ctypes.Structure):
        _fields_ = [("dwLength", w.DWORD), ("dwMemoryLoad", w.DWORD),
                    ("ullTotalPhys", ctypes.c_ulonglong), ("ullAvailPhys", ctypes.c_ulonglong),
                    ("ullTotalPageFile", ctypes.c_ulonglong), ("ullAvailPageFile", ctypes.c_ulonglong),
                    ("ullTotalVirtual", ctypes.c_ulonglong), ("ullAvailVirtual", ctypes.c_ulonglong),
                    ("ullAvailExtendedVirtual", ctypes.c_ulonglong)]

    memory = MEMORYSTATUSEX()
    memory.dwLength = ctypes.sizeof(memory)
    k32.GlobalMemoryStatusEx(ctypes.byref(memory))
    cpus = winproc.topology()
    best = max((e for _, _, e in cpus), default=0)
    version = sys.getwindowsversion()
    return {
        "cpu": cpu,
        "logical_processors": os.cpu_count(),
        "performance_cores": len({c for _, c, e in cpus if e == best}),
        "memory_gib": round(memory.ullTotalPhys / 2 ** 30, 1),
        "os": "Windows %d.%d build %d" % (version.major, version.minor, version.build),
        "python": platform.python_version(),
        "power": power(),
    }


def tool_version(cmd, env=None):
    """First meaningful line a toolchain prints about its version, or None."""
    try:
        done = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=60,
                              encoding="utf-8", errors="replace")
    except (OSError, subprocess.TimeoutExpired):
        return None
    for line in (done.stdout + "\n" + done.stderr).splitlines():
        line = line.strip()
        if line:
            return line[:160]
    return None


if os.name != "nt":
    from linuxmachine import power, power_problem, describe
    from linuxproc import _system_times
    def _busy_ms():
        idle, total = _system_times()
        return total - idle
