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

// Writes the exact bytes of `msg` to standard error, without adding a newline.
//
// Linux has no debugger output window; the diagnostic is visible even without an attached
// debugger. Interrupted writes are retried. A failed or closed destination discards the
// unwritten suffix without raising an error or changing the process's SIGPIPE disposition.
// Concurrent callers can interleave their output. This call does not allocate.
func log(msg: string)
{
    if msg.count == 0 do
        return
    let previousError = Linux.errno()
    defer Linux.errno(previousError)
    var blocked, previous, pending: Linux.sigset_t
    if Linux.sigemptyset(&blocked) != 0 or Linux.sigaddset(&blocked, Linux.SIGPIPE) != 0 do
        return
    if Linux.pthread_sigmask(Linux.SIG_BLOCK, &blocked, &previous) != 0 do
        return
    defer discard Linux.pthread_sigmask(Linux.SIG_SETMASK, &previous, null)
    if Linux.sigpending(&pending) != 0 do
        return
    let alreadyPending = Linux.sigismember(&pending, Linux.SIGPIPE) == 1
    var offset         = 0'u64
    while offset < msg.count
    {
        let written = Linux.write(2, msg.buffer + offset, Math.min(msg.count - offset, 0x7FFFF000'u64))
        if written > 0
        {
            offset += cast(u64, written)
            continue
        }

        let error = Linux.errno()
        if written < 0 and error == Linux.EINTR do
            continue
        if written < 0 and error == Linux.EPIPE and not alreadyPending
        {
            var noWait: Linux.timespec
            while Linux.sigtimedwait(&blocked, null, &noWait) < 0 and Linux.errno() == Linux.EINTR {}
        }

        return
    }
}
