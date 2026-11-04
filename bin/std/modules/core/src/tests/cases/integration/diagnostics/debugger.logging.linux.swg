#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

// Owns temporary standard-error redirection only within this isolated diagnostic test.
#[Swag.TestTag("integration.debugger.logging")]
#test
{
    var descriptors: [2]s32
    let opened = Linux.pipe2(descriptors, Linux.O_CLOEXEC | Linux.O_NONBLOCK)
    Swag.require(opened == 0)
    defer discard Linux.close(descriptors[0])
    defer discard Linux.close(descriptors[1])
    let saved = Linux.fcntl(2, Linux.F_DUPFD_CLOEXEC, 0's32)
    Swag.require(saved >= 0)
    defer discard Linux.close(saved)
    defer discard Linux.dup2(saved, 2)
    let redirected = Linux.dup2(descriptors[1], 2)
    Swag.require(redirected == 2)
    const Text = "diagnostic-é\0tail-ignored"
    Debugger.log(Text[until Text.count - 8])
    Debugger.log("")
    let restored = Linux.dup2(saved, 2)
    Swag.require(restored == 2)
    var bytes: [64]u8
    let read = Linux.read(descriptors[0], &bytes, bytes.count)
    Swag.require(read == cast(s64, Text.count - 8))
    Swag.require(cast(string, bytes[until cast(u64, read)]) == Text[until Text.count - 8])
}

// A diagnostic sent to a closed reader cannot terminate the process with SIGPIPE.
#[Swag.TestTag("integration.debugger.logging")]
#test
{
    var descriptors: [2]s32
    let opened = Linux.pipe2(descriptors, Linux.O_CLOEXEC | Linux.O_NONBLOCK)
    Swag.require(opened == 0)
    discard Linux.close(descriptors[0])
    defer discard Linux.close(descriptors[1])
    let saved = Linux.fcntl(2, Linux.F_DUPFD_CLOEXEC, 0's32)
    Swag.require(saved >= 0)
    defer discard Linux.close(saved)
    defer discard Linux.dup2(saved, 2)
    var before, after: Linux.sigset_t
    let queried = Linux.pthread_sigmask(Linux.SIG_BLOCK, null, &before)
    Swag.require(queried == 0)
    let redirected = Linux.dup2(descriptors[1], 2)
    Swag.require(redirected == 2)
    Linux.errno(Linux.EINVAL)
    Debugger.log("closed reader")
    let error    = Linux.errno()
    let restored = Linux.dup2(saved, 2)
    Swag.require(restored == 2 and error == Linux.EINVAL)
    let queriedAfter = Linux.pthread_sigmask(Linux.SIG_BLOCK, null, &after)
    Swag.require(queriedAfter == 0)
    Swag.require(Linux.sigismember(&before, Linux.SIGPIPE) == Linux.sigismember(&after, Linux.SIGPIPE))
}
