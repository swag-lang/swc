#global if #os == Swag.TargetOs.Linux
#global public
#global namespace Debugger

// Returns whether the calling Linux thread is being traced.
//
// Reads TracerPid from `/proc/thread-self/status`. Linux can trace individual threads, so a
// trace attached only to another thread does not make this query true. Unavailable procfs or
// an unreadable/malformed status returns `false`. This query performs file I/O and allocation;
// it is not safe to call from a signal handler.
func isAttached()->bool
{
    let status = catch File.readAllText("/proc/thread-self/status") { return false }
    for line in Tokenize.splitLines(status.toString()) where Utf8.startsWith(line, "TracerPid:")
    {
        let tracer = catch StrConv.toU32(Latin1.trim(line[10 to])) { return false }
        return tracer != 0
    }

    return false
}

// Emits a breakpoint instruction on the calling thread.
//
// An attached debugger can resume execution after the trap. Without a tracer or a handler,
// Linux's default SIGTRAP action terminates the process. This call does not attach a debugger
// or test whether one is present; callers can use [[Core.Debugger.isAttached]] for that query.
func debugBreak() => Swag.breakpoint()
