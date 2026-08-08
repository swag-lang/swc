#global if WINDOWS
#global public
#global namespace Env

using Win32, StrConv, Core.Errors

// Bytes taken from a captured pipe in one read.
private const PipeReadChunk = 4096'u32

// Milliseconds a wait sleeps between two drains of the captured streams.
//
// A wait with nothing to capture blocks on the process handle instead, so this only bounds how
// long a byte the child produced sits in a pipe before it is collected.
private const PipePollInterval = 5'u32

// Longest single wait issued to the system, so a very long timeout still fits a native call.
private const MaxWaitStep = 0xFFFFFFFE'u64

// Exit the current process
func exit(exitCode: u32) => ExitProcess(exitCode)

// Returns the environment variables of the current process.
//
// This is a snapshot: changing the returned value does not change the environment of the
// current process, only what a child started with it inherits.
func currentEnvironment()->ProcessEnvironment
{
    var result: retval

    let block = GetEnvironmentStringsW()
    if !block do
        return result
    defer discard FreeEnvironmentStringsW(block)

    // The block is a run of zero-terminated 'name=value' strings closed by an empty one. An
    // entry whose name is empty records a per-drive current directory instead of a variable,
    // and the system rebuilds those for a child on its own.
    let entries = block!
    var offset  = 0'u64
    while entries[offset] != 0
    {
        let start = offset
        while entries[offset] != 0 do
            offset += 1

        let entry = Utf8.fromUtf16(@mkslice(entries + start, offset - start))
        offset += 1

        let text      = entry.toString()
        let separator = Utf8.indexOf(entry.toSlice(), "=")
        if separator != Swag.U64.Max and separator != 0 do
            result.set(text[0 until separator], text[separator + 1 until @countof(text)])
    }

    return result
}

// Returns the value of the environment variable `name` in the current process.
//
// Answers an empty string when the variable is unset, which a variable holding nothing is
// indistinguishable from. Read [[Core.Env.currentEnvironment]] instead when that difference
// matters, or when more than a couple of variables are wanted.
func variable(name: string)->String
{
    let name16 = Utf16.toZeroTerminated(name)

    let needed = GetEnvironmentVariableW(@dataof(name16), null, 0)
    if !needed do
        return ""

    var buffer: Array'u16
    buffer.resize(needed)

    let written = GetEnvironmentVariableW(@dataof(name16), @dataof(buffer.toSlice()), needed)
    if !written or written >= needed do
        return ""
    return Utf8.fromUtf16(@mkslice(@dataof(buffer.toSlice()), cast(u64) written))
}

// Returns `value` spelled so the system parses it back as exactly one argument.
//
// A value holding a space, a tab or a quote is wrapped, and the backslashes in front of a
// wrapping quote are doubled, which is what the command-line grammar needs to give the child the
// string that was passed here. Use it for any argument that comes from a path or from input
// rather than from a literal; [[Core.Env.joinArguments]] does it for a whole list.
func quoteArgument(value: string)->String
{
    var result: retval
    appendQuoted(&result, value)
    return result
}

// Returns `arguments` joined into the one command line the system parses back into them.
//
// This is what [[Core.Env.StartInfo.arguments]] expects when the values are not already a
// command line, so a caller never has to know the quoting rules of the platform.
func joinArguments(arguments: const [..] string)->String
{
    var result: retval
    for argument in arguments
    {
        if @index != 0 do
            result.append(" ")
        appendQuoted(&result, argument)
    }

    return result
}

private func appendQuoted(commandLine: *String, argument: string)
{
    var mustQuote = @countof(argument) == 0
    for [i] in @countof(argument)
    {
        let c = argument[i]
        if c == ' ' or c == '\t' or c == '"' do
            mustQuote = true
    }

    if !mustQuote
    {
        commandLine.append(argument)
        return
    }

    commandLine.append("\"")

    var slashes = 0'u64
    for [i] in @countof(argument)
    {
        let c = argument[i]
        if c == '\\'
        {
            slashes += 1
            continue
        }

        // A run of backslashes is literal unless a quote follows it, where the grammar reads
        // each pair as one backslash; doubling the run is what keeps the pairs balanced.
        if c == '"'
        {
            for slashes * 2 + 1 do
                commandLine.append("\\")
            commandLine.append("\"")
        }
        else
        {
            for slashes do
                commandLine.append("\\")
            commandLine.append(c)
        }

        slashes = 0
    }

    for slashes * 2 do
        commandLine.append("\\")
    commandLine.append("\"")
}

// Returns `path` written with the separator Windows programs expect.
//
// The path helpers of the library produce the portable separator, and the system itself takes
// either one, but a started program reads its own path back from the command line and some
// refuse it there. Translating at the boundary keeps that from being every caller's problem.
private func nativePath(path: string)->String
{
    var result = String.from(path)
    result.replace("/", "\\")
    return result
}

// Closes `handle` and clears it, so a repeated release is a no-op.
private func releaseHandle(handle: *ProcessHandle)
{
    let native = cast(HANDLE) dref handle
    if !native do
        return

    CloseHandle(native)
    dref handle = null
}

// Opens the null device, which throws writes away and reads as an empty stream.
private func openNullDevice()->HANDLE fail
{
    var attributes: SECURITY_ATTRIBUTES
    attributes.nLength        = #sizeof(SECURITY_ATTRIBUTES)
    attributes.bInheritHandle = TRUE

    let name = Utf16.toZeroTerminated("NUL")
    return try CreateFileW(@dataof(name), GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, &attributes, OPEN_EXISTING, 0, null)
}

// Creates one redirection pipe and hands each end to its side.
//
// `childWrites` tells which end the child receives: the writing one for a stream it produces,
// and the reading one for the standard input it consumes. Both ends are stored before anything
// else can fail, so the caller releases them even when this reports an error.
private func createRedirectionPipe(parentEnd, childEnd: *ProcessHandle, childWrites: bool) fail
{
    var attributes: SECURITY_ATTRIBUTES
    attributes.nLength        = #sizeof(SECURITY_ATTRIBUTES)
    attributes.bInheritHandle = TRUE

    var readEnd, writeEnd: HANDLE
    try CreatePipe(&readEnd, &writeEnd, &attributes, 0)

    dref parentEnd = childWrites ? readEnd : writeEnd
    dref childEnd  = childWrites ? writeEnd : readEnd

    // Only the child's end may be inherited. A duplicate of this side living in the child would
    // hold the pipe open after the child exits, and the reader would never see the end of it.
    try SetHandleInformation(cast(HANDLE) dref parentEnd, HANDLE_FLAG_INHERIT, 0)
}

// Returns the standard handle a child inherits, normalizing the absence of one to null.
//
// A process detached from any console has no such handle, and the system rejects the invalid
// value where it accepts nothing at all.
private func inheritableStandardHandle(which: DWORD)->HANDLE
{
    let handle = GetStdHandle(which)
    if handle == INVALID_HANDLE_VALUE do
        return null
    return handle
}

// Prepares one standard stream of the child and returns the handle it is given.
//
// `parentEnd` receives the end the current process keeps, and stays null unless the stream is
// piped. `ownedChildEnd` receives the end the caller has to release once the child owns its own
// copy, which an inherited handle is deliberately not part of. `anyRedirection` is what forces
// an inherited stream to be named explicitly: the system takes the three handles as a set, so a
// stream left out of it would reach the child as no stream at all.
private func prepareChildStream(redirection: StreamRedirection, parentEnd, ownedChildEnd: *ProcessHandle, standardHandle: DWORD, anyRedirection: bool, childWrites: bool)->ProcessHandle fail
{
    switch #complete redirection
    {
    case .Pipe:
        try createRedirectionPipe(parentEnd, ownedChildEnd, childWrites)

    case .Discard:
        dref ownedChildEnd = try openNullDevice()

    case .Inherit:

        // A standard handle belongs to the current process. Naming it for the child must not
        // make this side responsible for closing it, or the stream would be taken away from
        // everyone still using it here.
        if anyRedirection do
            return inheritableStandardHandle(standardHandle)
    }

    return dref ownedChildEnd
}

// Builds the zero-terminated block of 'name=value' entries the system expects.
//
// The entries are ordered without regard to case, which is how the system reads them back.
private func buildEnvironmentBlock(environment: const *ProcessEnvironment)->Array'u16
{
    var entries: Array'String
    for name, [value] in environment.variables do
        entries.add(Format.toString("%=%", name.toString(), value.toString()))
    entries.sort(func||(a, b) { return Utf8.compare(a.toSlice(), b.toSlice(), .Latin1NoCase) })

    var result: retval
    for entry in entries do
        result.add(Utf16.toZeroTerminated(entry.toString()).toSlice())

    // One more zero closes the block. It is the whole block when there is no variable at all,
    // which is a legitimate request: the child then starts with nothing.
    result.add(0)
    return result
}

// Starts the process `info` describes, returning as soon as it is running.
//
// The executable is resolved from the command line, so a bare name is searched along the
// executable search path and a path containing spaces needs no quoting from the caller.
func startProcess(info: StartInfo)->Process fail
{
    Debug.assert(info.fileName != null, "missing process filename")

    var result: retval

    // The ends this side created for the child. Each is released as soon as the child has its
    // own copy: one left open here would hold a pipe open and its reader would never see the
    // end of the stream.
    var ownedInput, ownedOutput, ownedError: ProcessHandle
    defer releaseHandle(&ownedInput)
    defer releaseHandle(&ownedOutput)
    defer releaseHandle(&ownedError)

    let anyRedirection = info.standardInput != .Inherit or info.standardOutput != .Inherit or info.standardError != .Inherit
    let childInput     = try prepareChildStream(info.standardInput, &result.inputPipe, &ownedInput, STD_INPUT_HANDLE, anyRedirection, childWrites: false)
    let childOutput    = try prepareChildStream(info.standardOutput, &result.outputPipe, &ownedOutput, STD_OUTPUT_HANDLE, anyRedirection, childWrites: true)
    let childError     = try prepareChildStream(info.standardError, &result.errorPipe, &ownedError, STD_ERROR_HANDLE, anyRedirection, childWrites: true)

    // The executable is the first token of the command line, quoted so a path holding a space
    // stays one argument. Naming it there rather than through the application-name parameter
    // is what makes the system search the executable path for a bare name.
    let executable = nativePath(info.fileName)

    var commandLine: String
    commandLine.append("\"")
    commandLine.append(executable.toString())
    commandLine.append("\"")
    if info.arguments
    {
        commandLine.append(" ")
        commandLine.append(info.arguments)
    }

    var directory:    String
    var directory16:  Array'u16
    var directoryPtr: LPCWSTR
    if info.workingDirectory
    {
        directory    = nativePath(info.workingDirectory)
        directory16  = Utf16.toZeroTerminated(directory.toString())
        directoryPtr = @dataof(directory16)
    }

    var environmentBlock: Array'u16
    var environmentPtr:   LPVOID
    var creationFlags = 0'u32
    if info.environment
    {
        environmentBlock = buildEnvironmentBlock(info.environment)
        environmentPtr   = cast(LPVOID) @dataof(environmentBlock.toSlice())
        creationFlags    |= CREATE_UNICODE_ENVIRONMENT
    }

    var startup: STARTUPINFOW
    startup.cb = #sizeof(startup)
    if anyRedirection
    {
        startup.dwFlags    = STARTF_USESTDHANDLES
        startup.hStdInput  = cast(HANDLE) childInput
        startup.hStdOutput = cast(HANDLE) childOutput
        startup.hStdError  = cast(HANDLE) childError
    }

    // Accounting and affinity both have to be in place before the first instruction runs: a job
    // only counts what a process does after it joins, and a pinned run that starts anywhere else
    // has already been measured on the wrong core. So the process is created suspended and
    // resumed below, once it has been placed.
    let placeBeforeStart = info.measureResources or info.affinityMask != 0
    if placeBeforeStart do
        creationFlags |= CREATE_SUSPENDED

    let commandLine16 = Utf16.toZeroTerminated(commandLine.toString())
    var information: PROCESS_INFORMATION
    try CreateProcessW(null, @dataof(commandLine16), null, null, anyRedirection ? TRUE : FALSE, creationFlags, environmentPtr, directoryPtr, &startup, &information)

    result.adoptStarted(information.hProcess, information.dwProcessId)

    if placeBeforeStart
    {
        // A placement that fails must not leave a suspended process behind, so the thread is
        // resumed on the way out whether the placement worked or not.
        defer
        {
            discard catch ResumeThread(information.hThread)
            CloseHandle(information.hThread)
        }

        try result.placeStartedProcess(info)
        return result
    }

    CloseHandle(information.hThread)
    return result
}

impl Process
{
    // Records the process the system has just created.
    internal mtd adoptStarted(handle: ProcessHandle, processId: u64)
    {
        .handle    = handle
        .processId = processId
    }

    // Puts a still-suspended process where `info` asks it to run, before it executes anything.
    internal mtd placeStartedProcess(info: StartInfo) fail
    {
        if info.measureResources
        {
            let job = CreateJobObjectW(null, null)
            if !job do
                failWinError(GetLastError())

            .jobHandle = cast(ProcessHandle) job
            try AssignProcessToJobObject(job, cast(HANDLE) .handle)
        }

        if info.affinityMask != 0 do
            try SetProcessAffinityMask(cast(HANDLE) .handle, info.affinityMask)
    }

    // Releases resources owned by this value.
    mtd opDrop()
    {
        .close()
    }

    // Releases every platform handle this value owns, without waiting for the process.
    //
    // Whatever the streams already produced stays readable, so a run can still be inspected
    // once its process is gone. Calling `close` repeatedly is safe.
    mtd close()
    {
        releaseHandle(&.handle)
        releaseHandle(&.jobHandle)
        releaseHandle(&.inputPipe)
        releaseHandle(&.outputPipe)
        releaseHandle(&.errorPipe)
    }

    // Returns what the process and everything it started consumed.
    //
    // Answers zero unless the process was started with `StartInfo.measureResources`. The figures
    // stay readable while this value holds the accounting group, which is until
    // [[Core.Env.Process.close]], so a caller reads them after waiting for the exit.
    mtd const resources()->ProcessResources
    {
        var result: retval
        if !.jobHandle do
            return result

        var accounting: JOBOBJECT_BASIC_ACCOUNTING_INFORMATION
        if QueryInformationJobObject(cast(HANDLE) .jobHandle, JobObjectBasicAccountingInformation, cast(LPVOID) &accounting, #sizeof(accounting), null)
        {
            // A job reports its times in 100-nanosecond units.
            result.userTime     = Time.Duration.fromSeconds(cast(f64) accounting.TotalUserTime / 10_000_000.0)
            result.kernelTime   = Time.Duration.fromSeconds(cast(f64) accounting.TotalKernelTime / 10_000_000.0)
            result.processCount = accounting.TotalProcesses
        }

        var limits: JOBOBJECT_EXTENDED_LIMIT_INFORMATION
        if QueryInformationJobObject(cast(HANDLE) .jobHandle, JobObjectExtendedLimitInformation, cast(LPVOID) &limits, #sizeof(limits), null)
        {
            result.peakMemory        = limits.PeakJobMemoryUsed
            result.peakProcessMemory = limits.PeakProcessMemoryUsed
        }

        return result
    }

    // Records the exit code the system reports for a process that has stopped.
    internal mtd collectExitCode() fail
    {
        var code: DWORD
        try GetExitCodeProcess(cast(HANDLE) .handle, &code)
        .status = cast #bit (s32) code
        .exited = true
    }

    // Reads whatever the redirected streams hold right now, without waiting for more.
    //
    // Every wait already does this, so a caller only needs it to follow a long-running child
    // while it works. Reaching the end of a stream is not a failure: the pipe is released and
    // a later call simply has nothing to do.
    mtd readAvailable()
    {
        .drainPipe(&.outputPipe, &.output)
        .drainPipe(&.errorPipe, &.error)
    }

    // Moves everything one captured pipe currently holds into `text`.
    private mtd drainPipe(pipe: *ProcessHandle, text: *String)
    {
        let handle = cast(HANDLE) dref pipe
        if !handle do
            return

        var buffer: [PipeReadChunk] u8
        for
        {
            // Peeking first is what keeps this from blocking: a read of a pipe that holds
            // nothing waits for the child, and this side may be the one it is waiting on.
            var available: DWORD
            if !PeekNamedPipe(handle, null, 0, null, &available, null)
            {
                // The writing end is gone for good. Releasing the reading end now is what
                // makes the next pass a no-op instead of a peek that fails again.
                releaseHandle(pipe)
                return
            }

            if !available do
                return

            var read: DWORD
            if !ReadFile(handle, &buffer[0], Math.min(available, PipeReadChunk), &read, null) or !read
            {
                releaseHandle(pipe)
                return
            }

            text.append(cast(string) @mkslice(&buffer[0], cast(u64) read))
        }
    }

    // Waits for the process to exit and returns its exit code.
    //
    // The redirected streams are drained while waiting, so a child that produces more output
    // than a pipe holds keeps running instead of blocking on a reader that never reads.
    mtd waitForExit()->s32 fail
    {
        if .exited do
            return .status
        Debug.assert(.handle != null, "invalid process handle")

        let interval: DWORD = .hasCapturedStream() ? PipePollInterval : INFINITE
        while !.exited
        {
            .readAvailable()
            let status = try WaitForSingleObject(cast(HANDLE) .handle, interval)
            if status == WAIT_OBJECT_0 do
                try .collectExitCode()
        }

        // What the child wrote just before exiting is still sitting in the pipes.
        .readAvailable()
        return .status
    }

    // Waits up to `timeout` for the process to exit, and returns whether it did.
    //
    // Drains the redirected streams like [[Core.Env.Process.waitForExit]] does. A zero timeout
    // makes this a single poll, which is how a caller follows a child without blocking on it.
    mtd tryWaitForExit(timeout: Time.Duration)->bool fail
    {
        if .exited do
            return true
        Debug.assert(.handle != null, "invalid process handle")

        var remaining = timeout.milliseconds()
        for
        {
            .readAvailable()

            let step  = .hasCapturedStream() ? cast(u64) PipePollInterval : MaxWaitStep
            let slice = Math.min(remaining, step)

            let status = try WaitForSingleObject(cast(HANDLE) .handle, cast(DWORD) slice)
            if status == WAIT_OBJECT_0
            {
                try .collectExitCode()
                .readAvailable()
                return true
            }

            if slice >= remaining do
                break
            remaining -= slice
        }

        return false
    }

    // Requests the immediate termination of the process, which is then given `exitCode`.
    //
    // The request is asynchronous: the process is still there when this returns, so follow it
    // with [[Core.Env.Process.waitForExit]] to observe the exit and collect what the child left
    // in the captured streams. Killing a process that already exited does nothing.
    mtd kill(exitCode: s32 = 1) fail
    {
        if .exited or !.handle do
            return
        try TerminateProcess(cast(HANDLE) .handle, cast #bit (u32) exitCode)
    }

    // Writes `data` to the standard input of the process.
    //
    // Fails when standard input was not redirected to [[Core.Env.StreamRedirection.Pipe]], and
    // when the child has closed its end. Call [[Core.Env.Process.closeStandardInput]] after the
    // last write: a child reading to the end of its input waits forever otherwise.
    mtd writeStandardInput(data: string) fail
    {
        let handle = cast(HANDLE) .inputPipe
        if !handle do
            fail BadParameterError{"standard input is not redirected to a pipe"}

        var offset = 0'u64
        while offset < @countof(data)
        {
            var written: DWORD
            try WriteFile(handle, @dataof(data) + offset, cast(u32) Math.min(@countof(data) - offset, cast(u64) Swag.U32.Max), &written, null)
            if !written do
                failWinError(ERROR_NO_DATA)
            offset += written
        }
    }

    // Closes the standard-input pipe, which is how a child reading to the end of its input
    // learns that there is nothing more. Calling it repeatedly is safe.
    mtd closeStandardInput()
    {
        releaseHandle(&.inputPipe)
    }

    // Returns the current operating-system process identifier.
    func currentProcessId()->u64 => GetCurrentProcessId()

    // Returns the absolute path of the executable image for the current process.
    //
    // Fails when Windows cannot resolve the image path or the path exceeds the platform limit.
    func currentExecutablePath()->String fail
    {
        var buffer: [32768] u16
        let count = GetModuleFileNameW(null, @dataof(buffer), cast(u32) @countof(buffer))
        if !count do
            failWinError(GetLastError())
        if count >= @countof(buffer) do
            failWinError(ERROR_INSUFFICIENT_BUFFER)
        return Utf8.fromUtf16(@mkslice(@dataof(buffer), count))
    }

    // Returns the current operating-system thread identifier.
    func currentThreadId()->u64 => GetCurrentThreadId()
}
