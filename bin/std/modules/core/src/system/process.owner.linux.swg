#global if #os == Swag.TargetOs.Linux
#global public
#global namespace Env

private func nativeProcess(handle: ProcessHandle)->*LinuxProcessState => cast #unconst (*LinuxProcessState, unwrap handle)

private func processPipeDescriptor(handle: ProcessHandle)->s32 => cast(s32, cast(u64, handle) - 1)
private func processPipeHandle(fd: s32)->ProcessHandle         => cast(ProcessHandle, cast(u64, fd) + 1)

private func closeProcessPipe(handle: *ProcessHandle)
{
    if not handle[] do
        return
    let fd = processPipeDescriptor(handle[])
    handle[] = null

    // Linux releases the descriptor even when close reports EINTR; never retry a reused number.
    discard Linux.close(fd)
}

private func checkSpawnError(error: s32) fail
{
    if error != 0 do
        try Errors.failLinuxError(error)
}

private func prepareProcessStream(actions: *Linux.posix_spawn_file_actions_t, redirection: StreamRedirection, target: s32, parentEnd, childEnd: *ProcessHandle) fail
{
    if redirection == .Inherit do
        return
    if redirection == .Discard
    {
        try checkSpawnError(Linux.posix_spawn_file_actions_addopen(actions,
                                                                   target,
                                                                   "/dev/null".buffer,
                                                                   target == 0 ? Linux.O_RDONLY : Linux.O_WRONLY,
                                                                   0))
        return
    }

    var pipes: [2] s32
    if Linux.pipe2(pipes.buffer, Linux.O_CLOEXEC) != 0 do
        try Errors.failLinuxError(Linux.errno())
    parentEnd[] = processPipeHandle(pipes[target == 0 ? 1 : 0])
    childEnd[]  = processPipeHandle(pipes[target == 0 ? 0 : 1])

    // A caller may have closed fd 0/1/2. Keep sources out of the dup2 destination range.
    func normalize(handle: *ProcessHandle) fail
    {
        let fd = processPipeDescriptor(handle[])
        if fd >= 3 do
            return
        let replacement = Linux.fcntl(fd, Linux.F_DUPFD_CLOEXEC, 3's32)
        if replacement < 0 do
            try Errors.failLinuxError(Linux.errno())
        closeProcessPipe(handle)
        handle[] = processPipeHandle(replacement)
    }

    try normalize(parentEnd)
    try normalize(childEnd)
    let parent = processPipeDescriptor(parentEnd[])
    let flags  = Linux.fcntl(parent, Linux.F_GETFL)
    if flags < 0 do
        try Errors.failLinuxError(Linux.errno())
    if Linux.fcntl(parent, Linux.F_SETFL, flags | Linux.O_NONBLOCK) < 0 do
        try Errors.failLinuxError(Linux.errno())
    try checkSpawnError(Linux.posix_spawn_file_actions_adddup2(actions, processPipeDescriptor(childEnd[]), target))
}

internal func startProcessNative(info: StartInfo)->Process fail
{
    if info.nativeArguments or info.affinityMask != 0 or info.measureResources do
        try Errors.failLinuxError(Linux.ENOTSUP)

    var arguments: Array'String
    arguments.add(String.from(info.fileName))
    if info.arguments do
        for argument in info.arguments do
            arguments.add(String.from(argument))
    var argv: Array'([*] u8?)
    for &argument in arguments do
        argv.add(argument.storage())
    argv.add(cast([*] u8?, null))

    var environment:       Array'String
    var envp:              Array'([*] u8?)
    var nativeEnvironment: const [*] ([*] u8?)?
    if info.environment
    {
        for name, value in info.environment.variables do
            environment.add(Format.toString("%=%", name.toString(), value.toString()))
        for &entry in environment do
            envp.add(entry.storage())
        envp.add(cast([*] u8?, null))
        nativeEnvironment = envp.storage()
    }
    else
    {
        let address = try nativeEnvironmentAddress()
        nativeEnvironment = address[]
    }

    var actions: Linux.posix_spawn_file_actions_t
    try checkSpawnError(Linux.posix_spawn_file_actions_init(&actions))
    defer discard Linux.posix_spawn_file_actions_destroy(&actions)
    var directory: String
    if info.workingDirectory
    {
        directory = String.from(info.workingDirectory)
        try checkSpawnError(Linux.posix_spawn_file_actions_addchdir_np(&actions, directory.storage()))
    }

    var result: #returntype
    var childInput, childOutput, childError: ProcessHandle
    defer closeProcessPipe(&childInput)
    defer closeProcessPipe(&childOutput)
    defer closeProcessPipe(&childError)
    try prepareProcessStream(&actions, info.standardInput, 0, &result.inputPipe, &childInput)
    try prepareProcessStream(&actions, info.standardOutput, 1, &result.outputPipe, &childOutput)
    try prepareProcessStream(&actions, info.standardError, 2, &result.errorPipe, &childError)

    let memory = Linux.calloc(1, #sizeof(LinuxProcessState))
    if not memory do
        try Errors.failLinuxError(Linux.ENOMEM)
    let state     = cast(*LinuxProcessState, unwrap memory)
    var published = false
    defer
    {
        if not published do
            Linux.free(state)
    }

    // Start the reaper before spawning, so no later close needs to allocate or start a thread.
    try ensureProcessReaperNative()
    try checkSpawnError(Linux.posix_spawnp(&state.pid, arguments[0].storage(), &actions, null, argv.storage(), nativeEnvironment))
    result.handle    = state
    result.processId = cast(u64, state.pid)
    published        = true
    return result
}

impl Process
{
    internal mtd closeNative()
    {
        closeProcessPipe(&.inputPipe)
        closeProcessPipe(&.outputPipe)
        closeProcessPipe(&.errorPipe)
        if .handle
        {
            let state = nativeProcess(.handle)
            .handle = null
            releaseProcessNative(state)
        }
    }

    internal mtd closeStandardInputNative() => closeProcessPipe(&.inputPipe)

    internal mtd drainPipeNative(pipe: *ProcessHandle, text: *String, limit: u64)
    {
        if not pipe[] do
            return
        let fd = processPipeDescriptor(pipe[])
        var available: s32
        for
        {
            if Linux.ioctl(fd, Linux.FIONREAD, &available) == 0 do
                break
            if Linux.errno() != Linux.EINTR
            {
                closeProcessPipe(pipe)
                return
            }
        }

        // Probe an empty pipe once to distinguish EOF from temporarily unavailable data.
        var remaining = Math.min(Math.max(cast(u64, available), 1'u64), limit)
        var buffer: [4096] u8
        while remaining != 0
        {
            let count = Linux.read(fd, buffer.buffer, Math.min(remaining, buffer.count))
            if count < 0
            {
                let error = Linux.errno()
                if error == Linux.EINTR do
                    continue
                if error != Linux.EAGAIN do
                    closeProcessPipe(pipe)
                return
            }

            if count == 0
            {
                closeProcessPipe(pipe)
                return
            }

            text.append(cast(string, buffer[until cast(u64, count)]))
            remaining -= cast(u64, count)
        }
    }

    internal mtd pollExitNative(milliseconds: u32) fail
    {
        let state    = nativeProcess(.handle)
        let blocking = milliseconds == Swag.U32.Max
        var slept    = false
        for
        {
            var status: s32
            let result = Linux.waitpid(state.pid, &status, blocking ? 0 : Linux.WNOHANG)
            if result < 0
            {
                let error = Linux.errno()
                if error == Linux.EINTR do
                    continue
                try Errors.failLinuxError(error)
            }

            if result > 0 and (Linux.WIFEXITED(status) or Linux.WIFSIGNALED(status))
            {
                state.pid = 0
                .status   = Linux.WIFEXITED(status) ? Linux.WEXITSTATUS(status) : 128 + Linux.WTERMSIG(status)
                .exited   = true
                return
            }

            if not blocking
            {
                if slept or milliseconds == 0 do
                    return
                Threading.Thread.sleep(Time.Duration.fromMilliseconds(milliseconds))
                slept = true
            }
        }
    }

    internal mtd killNative() fail
    {
        if .exited or not .handle do
            return

        // Observe an already exited child first; a zombie still owns its PID until this wait.
        try .pollExitNative(0)
        if .exited
        {
            .captureExitOutput()
            return
        }

        let state = nativeProcess(.handle)
        if Linux.kill(state.pid, Linux.SIGKILL) != 0 do
            try Errors.failLinuxError(Linux.errno())
    }

    // Returns false: Linux does not yet implement the process-tree accounting contract.
    func supportsResourceMeasurement()->bool => false

    // Returns zero for an unmeasured Linux process; requesting measurement at start fails.
    mtd const resources()->ProcessResources => {}

    // Writes all bytes to the child's input, draining captured output when the pipe is full.
    //
    // Fails for an absent or closed input pipe. A closed reader raises an error without changing
    // process-wide SIGPIPE handling. Call closeStandardInput after the last write to send EOF.
    mtd writeStandardInput(data: string) fail
    {
        if not .inputPipe do
            fail Errors.BadParameterError{"standard input is not redirected to a pipe"}
        let fd = processPipeDescriptor(.inputPipe)
        var blocked, previous, pending: Linux.sigset_t
        if Linux.sigemptyset(&blocked) != 0 or Linux.sigaddset(&blocked, Linux.SIGPIPE) != 0 do
            try Errors.failLinuxError(Linux.errno())
        try checkSpawnError(Linux.pthread_sigmask(Linux.SIG_BLOCK, &blocked, &previous))
        defer discard Linux.pthread_sigmask(Linux.SIG_SETMASK, &previous, null)
        if Linux.sigpending(&pending) != 0 do
            try Errors.failLinuxError(Linux.errno())
        let alreadyPending = Linux.sigismember(&pending, Linux.SIGPIPE) == 1
        var broken         = false
        defer
        {
            if broken and not alreadyPending
            {
                var noWait: Linux.timespec
                while Linux.sigtimedwait(&blocked, null, &noWait) < 0 and Linux.errno() == Linux.EINTR {}
            }
        }

        var offset = 0'u64
        while offset < data.count
        {
            let written = Linux.write(fd, data.buffer + offset, Math.min(data.count - offset, 0x7FFFF000'u64))
            if written < 0
            {
                let error = Linux.errno()
                if error == Linux.EINTR do
                    continue
                if error == Linux.EAGAIN
                {
                    .readAvailable()
                    Threading.Thread.sleep(Time.Duration.fromMilliseconds(1))
                    continue
                }

                broken = error == Linux.EPIPE
                try Errors.failLinuxError(error)
            }

            if written == 0 do
                try Errors.failLinuxError(Linux.EIO)
            offset += cast(u64, written)
        }
    }
}
