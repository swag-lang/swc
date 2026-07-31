"""Run a child process under a fresh job object and report time + peak memory.

Why a job object rather than psutil: every compiler here spawns helpers (link.exe,
MSBuild nodes, ILC), so the interesting number is the peak committed memory of the
whole process tree, which is exactly `PeakJobMemoryUsed`.
"""
import ctypes
import ctypes.wintypes as w
import os
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


def run(cmd, cwd=None, env=None):
    """Run `cmd` (list) and return timings, peak memory and captured output."""
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
