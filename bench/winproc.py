"""Run a child process under a fresh job object and report time + peak memory.

Why a job object rather than psutil: every compiler here spawns helpers (link.exe,
MSBuild nodes, ILC), so the interesting number is the peak committed memory of the
whole process tree, which is exactly `PeakJobMemoryUsed`.

A timed run is also pinned to one fixed performance core. This machine is a hybrid:
six P cores, eight E cores and two low-power cores that a short process lands on
often enough to double its time. Unpinned, the same binary measured over and over
moved between 38 and 50 ms; pinned, the whole series fits in 2 %.
"""
import ctypes
import ctypes.wintypes as w
import os
import struct
import subprocess
import tempfile
import time

k32 = ctypes.WinDLL("kernel32", use_last_error=True)

INFINITE = 0xFFFFFFFF
CREATE_SUSPENDED = 0x00000004
CREATE_UNICODE_ENVIRONMENT = 0x00000400
CREATE_NO_WINDOW = 0x08000000
STARTF_USESTDHANDLES = 0x00000100
GENERIC_WRITE = 0x40000000
FILE_SHARE_READ = 0x00000001
FILE_SHARE_WRITE = 0x00000002
CREATE_ALWAYS = 2
FILE_ATTRIBUTE_NORMAL = 0x80
JobObjectExtendedLimitInformation = 9
JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000
ERROR_ACCESS_DENIED = 5
ERROR_SHARING_VIOLATION = 32
RETRIES = 12
RETRY_DELAY = 0.15


class SECURITY_ATTRIBUTES(ctypes.Structure):
    _fields_ = [("nLength", w.DWORD), ("lpSecurityDescriptor", w.LPVOID), ("bInheritHandle", w.BOOL)]


class STARTUPINFOW(ctypes.Structure):
    _fields_ = [
        ("cb", w.DWORD), ("lpReserved", w.LPWSTR), ("lpDesktop", w.LPWSTR), ("lpTitle", w.LPWSTR),
        ("dwX", w.DWORD), ("dwY", w.DWORD), ("dwXSize", w.DWORD), ("dwYSize", w.DWORD),
        ("dwXCountChars", w.DWORD), ("dwYCountChars", w.DWORD), ("dwFillAttribute", w.DWORD),
        ("dwFlags", w.DWORD), ("wShowWindow", w.WORD), ("cbReserved2", w.WORD),
        ("lpReserved2", ctypes.POINTER(ctypes.c_byte)),
        ("hStdInput", w.HANDLE), ("hStdOutput", w.HANDLE), ("hStdError", w.HANDLE),
    ]


class PROCESS_INFORMATION(ctypes.Structure):
    _fields_ = [("hProcess", w.HANDLE), ("hThread", w.HANDLE), ("dwProcessId", w.DWORD), ("dwThreadId", w.DWORD)]


class IO_COUNTERS(ctypes.Structure):
    _fields_ = [("ReadOperationCount", ctypes.c_ulonglong), ("WriteOperationCount", ctypes.c_ulonglong),
                ("OtherOperationCount", ctypes.c_ulonglong), ("ReadTransferCount", ctypes.c_ulonglong),
                ("WriteTransferCount", ctypes.c_ulonglong), ("OtherTransferCount", ctypes.c_ulonglong)]


class JOBOBJECT_BASIC_LIMIT_INFORMATION(ctypes.Structure):
    _fields_ = [("PerProcessUserTimeLimit", ctypes.c_longlong), ("PerJobUserTimeLimit", ctypes.c_longlong),
                ("LimitFlags", w.DWORD), ("MinimumWorkingSetSize", ctypes.c_size_t),
                ("MaximumWorkingSetSize", ctypes.c_size_t), ("ActiveProcessLimit", w.DWORD),
                ("Affinity", ctypes.c_size_t), ("PriorityClass", w.DWORD), ("SchedulingClass", w.DWORD)]


class JOBOBJECT_EXTENDED_LIMIT_INFORMATION(ctypes.Structure):
    _fields_ = [("BasicLimitInformation", JOBOBJECT_BASIC_LIMIT_INFORMATION), ("IoInfo", IO_COUNTERS),
                ("ProcessMemoryLimit", ctypes.c_size_t), ("JobMemoryLimit", ctypes.c_size_t),
                ("PeakProcessMemoryUsed", ctypes.c_size_t), ("PeakJobMemoryUsed", ctypes.c_size_t)]


class FILETIME(ctypes.Structure):
    _fields_ = [("dwLowDateTime", w.DWORD), ("dwHighDateTime", w.DWORD)]


def _ft(f):
    return ((f.dwHighDateTime << 32) | f.dwLowDateTime) / 10000.0  # ms


def _env_block(env):
    items = sorted(("%s=%s" % (k, v) for k, v in env.items()), key=lambda s: s.upper())
    return ctypes.create_unicode_buffer("\0".join(items) + "\0\0")


def _system_times():
    idle, kernel, user = FILETIME(), FILETIME(), FILETIME()
    if not k32.GetSystemTimes(ctypes.byref(idle), ctypes.byref(kernel),
                              ctypes.byref(user)):
        return None
    # Kernel time includes idle time, so total is kernel + user and busy is what is
    # left once idle is taken out.
    return _ft(idle), _ft(kernel) + _ft(user)


def system_busy_pct(window_s=1.0):
    """Share of the machine somebody else is using, over `window_s`.

    Nothing of ours is running while this samples, so whatever it reports belongs to
    another process. A campaign measured against a busy machine is not a measurement,
    and this is how the driver knows before spending twenty minutes finding out.
    """
    first = _system_times()
    if not first:
        return 0.0
    time.sleep(window_s)
    second = _system_times()
    if not second:
        return 0.0
    idle = second[0] - first[0]
    total = second[1] - first[1]
    if total <= 0:
        return 0.0
    return max(0.0, min(100.0, (1.0 - idle / total) * 100.0))


def topology():
    """Every logical processor as (index, core, efficiency class), highest class first.

    `GetSystemCpuSetInformation` is the only interface that names the efficiency class,
    which is what separates a P core from an E core on a hybrid part.
    """
    buf = ctypes.create_string_buffer(1 << 16)
    returned = w.ULONG()
    if not k32.GetSystemCpuSetInformation(buf, ctypes.sizeof(buf), ctypes.byref(returned),
                                          w.HANDLE(0), 0):
        return []
    cpus = []
    offset = 0
    while offset < returned.value:
        size, kind = struct.unpack_from("<II", buf, offset)
        if not size:
            break
        if kind == 0:  # CpuSetInformation
            _, _, logical, core, _, _, efficiency, _ = struct.unpack_from("<IHBBBBBB", buf,
                                                                          offset + 8)
            cpus.append((logical, core, efficiency))
        offset += size
    return cpus


def _pin_mask():
    """The performance cores, one logical processor each, as an affinity mask.

    Both halves of that sentence were measured. Leaving the choice to the scheduler
    lets a short process land on an E core or on one of the two low-power cores, and
    the ratio between two unchanged binaries then moves by 10 % from one block of
    measurements to the next. Pinning to a *single* P core is worse still: the ratio
    is no steadier and the core is 5 % slower than the one the scheduler would have
    picked, because it is not the favoured core of this part. One logical processor
    per physical core keeps a hyperthread sibling from stealing half the core, and
    leaving all six available lets the scheduler still avoid a core that is busy.
    Same mask for every runtime — a comparison has to be fair, not maximal.
    """
    cpus = topology()
    if not cpus:
        return 0
    best = max(efficiency for _, _, efficiency in cpus)
    cores = sorted({core for _, core, efficiency in cpus if efficiency == best})
    mask = 0
    for core in cores:
        mask |= 1 << min(logical for logical, c, e in cpus if c == core and e == best)
    return mask


PIN_MASK = _pin_mask()


def run(cmd, cwd=None, env=None, pin=False, priority=None):
    """Run `cmd` (list) and return timings, peak memory and captured output.

    `pin` confines the process to the performance cores. Use it for anything whose
    duration is the result — never for a build, which is meant to use the whole machine.
    """
    sa = SECURITY_ATTRIBUTES(ctypes.sizeof(SECURITY_ATTRIBUTES), None, True)
    fd_out, path_out = tempfile.mkstemp(suffix=".out")
    fd_err, path_err = tempfile.mkstemp(suffix=".err")
    os.close(fd_out)
    os.close(fd_err)

    h_out = k32.CreateFileW(path_out, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                            ctypes.byref(sa), CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, None)
    h_err = k32.CreateFileW(path_err, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                            ctypes.byref(sa), CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, None)

    si = STARTUPINFOW()
    si.cb = ctypes.sizeof(STARTUPINFOW)
    si.dwFlags = STARTF_USESTDHANDLES
    si.hStdInput = None
    si.hStdOutput = w.HANDLE(h_out)
    si.hStdError = w.HANDLE(h_err)

    pi = PROCESS_INFORMATION()
    h_job = k32.CreateJobObjectW(None, None)
    if not h_job:
        raise ctypes.WinError(ctypes.get_last_error())

    # Kill the whole tree when the last handle to the job goes away. The normal path
    # already terminates the job after the wait, so this only matters when the driver
    # itself dies — interrupted at the keyboard, or killed by whatever launched it.
    # Without it, a campaign stopped in the middle of a NativeAOT publish leaves the
    # compiler running, and it is still burning the machine when the next campaign
    # starts: a reference workload that takes 45 ms measured 873 ms that way. The one
    # rule this file already had, applied to its own death.
    limits = JOBOBJECT_EXTENDED_LIMIT_INFORMATION()
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
    k32.SetInformationJobObject(h_job, JobObjectExtendedLimitInformation,
                                ctypes.byref(limits), ctypes.sizeof(limits))

    cmdline = subprocess.list2cmdline(cmd)
    envblock = _env_block(env if env is not None else dict(os.environ))

    freq = ctypes.c_longlong()
    t0 = ctypes.c_longlong()
    t1 = ctypes.c_longlong()
    k32.QueryPerformanceFrequency(ctypes.byref(freq))
    k32.QueryPerformanceCounter(ctypes.byref(t0))

    # An executable written moments ago can still be held by the linker's last handle
    # or by an antivirus scanning it, and CreateProcessW then fails with a sharing
    # violation. That is a race, not a benchmark result, so retry it briefly. The
    # clock is restarted after each failed attempt, so a retry never inflates a timing.
    ok = 0
    for attempt in range(RETRIES):
        k32.QueryPerformanceCounter(ctypes.byref(t0))
        ok = k32.CreateProcessW(None, ctypes.create_unicode_buffer(cmdline), None, None, True,
                                CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW,
                                envblock, cwd, ctypes.byref(si), ctypes.byref(pi))
        if ok:
            break
        err = ctypes.get_last_error()
        if err not in (ERROR_ACCESS_DENIED, ERROR_SHARING_VIOLATION) or attempt == RETRIES - 1:
            k32.CloseHandle(h_out)
            k32.CloseHandle(h_err)
            k32.CloseHandle(h_job)
            raise ctypes.WinError(err)
        time.sleep(RETRY_DELAY)

    k32.AssignProcessToJobObject(h_job, pi.hProcess)
    # The process is still suspended, so the affinity is in place before its first
    # instruction: it can never start on one core and be measured on another.
    mask = PIN_MASK if pin is True else (pin or 0)
    if mask:
        k32.SetProcessAffinityMask(pi.hProcess, ctypes.c_size_t(mask))
    if priority:
        k32.SetPriorityClass(pi.hProcess, priority)
    k32.ResumeThread(pi.hThread)
    k32.WaitForSingleObject(pi.hProcess, INFINITE)
    k32.QueryPerformanceCounter(ctypes.byref(t1))

    code = w.DWORD()
    k32.GetExitCodeProcess(pi.hProcess, ctypes.byref(code))

    creation, exit_, kernel, user = FILETIME(), FILETIME(), FILETIME(), FILETIME()
    k32.GetProcessTimes(pi.hProcess, ctypes.byref(creation), ctypes.byref(exit_),
                        ctypes.byref(kernel), ctypes.byref(user))

    info = JOBOBJECT_EXTENDED_LIMIT_INFORMATION()
    ret = w.DWORD()
    k32.QueryInformationJobObject(h_job, JobObjectExtendedLimitInformation, ctypes.byref(info),
                                  ctypes.sizeof(info), ctypes.byref(ret))

    # Some compilers leave helper processes behind (cl.exe did, 46 of them over a
    # full sweep) and they quietly skew every later measurement. The job object is
    # the reliable way to reap them once the process we timed has exited.
    k32.TerminateJobObject(h_job, 0)

    k32.CloseHandle(pi.hThread)
    k32.CloseHandle(pi.hProcess)
    k32.CloseHandle(h_job)
    k32.CloseHandle(h_out)
    k32.CloseHandle(h_err)

    with open(path_out, "rb") as f:
        out = f.read().decode("utf-8", "replace")
    with open(path_err, "rb") as f:
        err_txt = f.read().decode("utf-8", "replace")
    os.unlink(path_out)
    os.unlink(path_err)

    return {
        "exit": code.value,
        "wall_ms": (t1.value - t0.value) * 1000.0 / freq.value,
        "cpu_ms": _ft(kernel) + _ft(user),
        "peak_job_bytes": info.PeakJobMemoryUsed,
        "peak_proc_bytes": info.PeakProcessMemoryUsed,
        "stdout": out,
        "stderr": err_txt,
    }
