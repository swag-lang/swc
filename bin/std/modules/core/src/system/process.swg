#global public
#global namespace Env

using Core.Errors

// Opaque platform handle of a process or of one of its pipes.
alias ProcessHandle = const *void?

// Selects how one standard stream of a child process is connected.
enum StreamRedirection
{
    Inherit     // The child shares the corresponding stream of the current process.
    Pipe        // The stream is connected to a pipe owned by the started [[Core.Env.Process]].
    Discard     // Output is thrown away, and standard input reads the end of the stream at once.
}

// Holds the environment variables a child process is started with.
//
// A [[Core.Env.StartInfo]] naming no environment lets the child inherit the one of the current
// process unchanged. Start from [[Core.Env.currentEnvironment]] to add or override a few
// variables, or from an empty value to give the child exactly what it lists and nothing else.
//
// Names follow the rule of the platform: Windows compares them without regard to case and stores
// them folded, so setting `path` there replaces the `Path` the system reported instead of adding
// a second variable beside it. A platform that distinguishes the case keeps a name as given.
//
// ```swag
// var environment = Env.currentEnvironment()
// environment.set("SWAG_PATH", "c:/swag/bin")
//
// var info = Env.StartInfo{fileName: "swc.exe", arguments: ["test"], environment: &environment}
// let process = try Env.runProcess(info)
// ```
struct ProcessEnvironment
{
    internal variables: HashTable'(String, String)
}

impl ProcessEnvironment
{
    // Returns the spelling under which the platform stores `name`.
    private func storedName(name: string)->String => processEnvironmentStoredName(name)

    // Returns how many variables the environment holds.
    mtd const count()->u64 => .variables.count

    // Returns the value bound to `name`, or `null` when the environment does not hold it.
    //
    // The result is borrowed from this value and stays valid until the binding changes.
    mtd const value(name: string)->string?
    {
        let entry = .variables.tryFind(ProcessEnvironment.storedName(name))
        if not entry do
            return null
        return entry.value.toString()
    }

    // Binds `name` to `value`, replacing any previous binding.
    mtd set(name, value: string)
    {
        .variables[ProcessEnvironment.storedName(name)] = String.from(value)
    }

    // Removes `name`. Removing a name the environment does not hold does nothing.
    mtd remove(name: string)
    {
        .variables.remove(ProcessEnvironment.storedName(name))
    }

    // Removes every variable, leaving the environment empty.
    mtd clear()
    {
        .variables.clear()
    }
}

// Describes the process to start and how it is connected to the current one.
//
// Only `fileName` is required. Arguments are separate values, excluding the executable name;
// empty values, spaces, quotes and backslashes are preserved. All views are borrowed only for
// the start call. No shell is selected implicitly. Bare executable names follow the host's
// search rules; pass a full path when the selected executable must be unambiguous. Linux uses
// the parent's PATH to search, even when `environment` supplies a different PATH for the child.
// Synchronize starts that inherit the environment with native environment mutation.
//
// Linux rejects `nativeArguments`, nonzero `affinityMask` and `measureResources` as unsupported
// before starting a child. It inherits the current terminal/session; `consoleWindow` has no effect.
//
// Windows alone serializes the vector with its C-runtime quoting rules. Programs with another
// grammar, such as cmd.exe, can instead use `nativeArguments`; that Windows escape hatch must
// not be combined with a nonempty argument vector. Embedded zero bytes are rejected.
struct StartInfo
{
    public
    {
        fileName:         string                           // Executable to start, as a full path or a name to look up.
        arguments:        const [..] string?               // Argument values after argv[0]; null or an empty slice supplies none.
        nativeArguments:  string?                          // Windows-only verbatim argument text for a program with its own command-line grammar.
        workingDirectory: string?                          // Directory the child starts in, or null to inherit the current one.
        environment:      const *ProcessEnvironment?       // Environment the child starts with, or null to inherit the current one. Borrowed for the call only.
        standardInput:    StreamRedirection = .Inherit     // How the child reads standard input.
        standardOutput:   StreamRedirection = .Inherit     // How the child writes standard output.
        standardError:    StreamRedirection = .Inherit     // How the child writes standard error.
        affinityMask:     u64                              // Logical processors the child may run on, one bit each. Zero inherits the current set.
        measureResources: bool                             // Whether to account the child and everything it starts, which [[Core.Env.Process.resources]] answers.

        /*
        Whether a console child may be given a console of its own.

        A console program started from another console program shares the one already there and
        opens nothing either way, so this decides only what happens when there is none to share:
        a windowed program starting a console one. The system then builds a console and the host
        process that draws it, which flashes a window and can cost several times what the child
        itself costs — a price worth paying for a child the caller wants a reader to watch, and
        pure waste for one whose streams are already redirected here.
        */
        consoleWindow = true
    }
}

/*
What a measured process and everything it started consumed.

Answered by [[Core.Env.Process.resources]] once the process was started with
`StartInfo.measureResources`. Query [[Core.Env.Process.supportsResourceMeasurement]] before
requesting it; unsupported hosts reject the request before starting a child. The whole tree is
accounted, not just the process that was named: a program that does its work in helpers it spawns
would otherwise report almost nothing.

The peaks are the highest each figure ever reached, so they stay meaningful after the processes
that produced them are gone. Times are totals across the tree.
*/
struct ProcessResources
{
    public
    {
        peakMemory:        u64               // Highest committed memory the whole tree reached at once.
        peakProcessMemory: u64               // Highest committed memory any single process in it reached.
        userTime:          Time.Duration     // Total time the tree spent running its own code.
        kernelTime:        Time.Duration     // Total time the system spent working on its behalf.
        processCount:      u64               // How many processes the tree contained, first and last included.
    }
}

/*
Owns a started child process, its pipes, and everything captured from it.

Start one with [[Core.Env.startProcess]] and drive it, or use [[Core.Env.runProcess]] to start it
and wait for it in one step. The value closes every handle it still owns when it leaves scope, so
its native resources are released on an early return. Serialize all operations on the same owner.

On Linux, `close` transfers a live child to Core's reaper without killing it or waiting. Core's
module shutdown waits for those children before unloading the worker code. A late global
destructor after shutdown waits for its own child. Do not externally reap an owned child or
configure automatic SIGCHLD reaping; that loses its exit status and makes a wait fail.

Text captured from a redirected stream accumulates inside the value and outlives
[[Core.Env.Process.close]], which is what lets a run be inspected after the child is gone.

> ATTENTION:
> A pipe holds a bounded amount of data, so a child that writes more than that blocks until this
> side reads it. Every wait on this type drains the redirected streams while it waits, which is
> what keeps the pair from deadlocking; a caller that waits on the platform handle by other means
> loses that guarantee.
*/
#[Swag.NoCopy]
struct Process
{
    public readonly
    {
        processId: u64     // Operating-system identifier of the started process.
    }

    internal
    {
        handle:     ProcessHandle     // Platform handle of the spawned process, owned by this value.
        jobHandle:  ProcessHandle     // Accounting group holding the process and its children, when measured.
        inputPipe:  ProcessHandle     // Writable end of the standard-input pipe, when redirected.
        outputPipe: ProcessHandle     // Readable end of the standard-output pipe, when redirected.
        errorPipe:  ProcessHandle     // Readable end of the standard-error pipe, when redirected.
        output:     String            // Everything captured from standard output so far.
        error:      String            // Everything captured from standard error so far.
        status:     s32               // Exit code reported by the system, meaningful once 'exited' is set.
        exited:     bool              // Whether the exit of the process has been observed.
    }
}

// Starts a new process, returning as soon as it is running.
//
// The child inherits the standard streams, the working directory and the environment of the
// current process. Use [[Core.Env.startProcess]] with a [[Core.Env.StartInfo]] to change any
// of that.
func startProcess(fileName: string)->Process fail => try startProcess(StartInfo{fileName: fileName})

// Starts a process with separate argument values, inheriting streams, directory and environment.
func startProcess(fileName: string, arguments: const [..] string)->Process fail
{
    return try startProcess(StartInfo{fileName: fileName, arguments: arguments})
}

// Starts the process `info` describes, returning as soon as it is running.
//
// Rejects empty executable/directory names, embedded zero bytes, invalid environment names and
// conflicting argument forms before creating native resources. A path containing spaces needs
// no quoting from the caller; executable search and native options follow the host contract.
func startProcess(info: StartInfo)->Process fail
{
    try validateProcessStartInfo(info)
    return try startProcessNative(info)
}

// Starts a process, waits for it to exit, and returns it with everything it produced.
//
// Standard output and standard error are captured, so the returned value answers
// [[Core.Env.Process.standardOutput]] and [[Core.Env.Process.standardError]] as well as
// [[Core.Env.Process.exitCode]]. Standard input is inherited.
//
// ```swag
// let process = try Env.runProcess("swc.exe", ["--help"])
// if process.exitCode() != 0 do
//     fail Errors.BadParameterError{"the compiler refused to answer"}
// Swag.print(process.standardOutput())
// ```
func runProcess(fileName: string)->Process fail
{
    return try runProcess(StartInfo{fileName: fileName, standardOutput: .Pipe, standardError: .Pipe})
}

// Runs a process with separate argument values and captures both output streams.
func runProcess(fileName: string, arguments: const [..] string)->Process fail
{
    with var info = StartInfo{fileName: fileName, arguments: arguments}
    {
        .standardOutput = .Pipe
        .standardError  = .Pipe
    }

    return try runProcess(info)
}

// Starts the process `info` describes, waits for it to exit, and returns it.
//
// Redirection follows `info`: a stream left to [[Core.Env.StreamRedirection.Inherit]] is not
// captured, and the matching accessor stays empty.
func runProcess(info: StartInfo)->Process fail
{
    var result = try startProcess(info)
    discard try result.waitForExit()
    return result
}

impl Process
{
    // Releases the process and pipe resources when this owner leaves scope.
    mtd opDrop() => .close()

    // Releases owned resources, retaining captured text and any observed exit code.
    //
    // Repeated calls are safe. Closing does not kill a child. Linux queues a live child for
    // reaping; Core shutdown waits for it, and a close after shutdown waits synchronously.
    mtd close() => .closeNative()

    // Reads currently available output without waiting, at most 64 KiB from each stream.
    //
    // Bounded reads keep a continuously writing stream from starving its peer or a timeout.
    // EOF or a native pipe-read failure closes that stream; already captured text is retained.
    mtd readAvailable()
    {
        .drainPipeNative(&.outputPipe, &.output, 65536)
        .drainPipeNative(&.errorPipe, &.error, 65536)
    }

    internal mtd captureExitOutput()
    {
        // Each native drain snapshots availability; inherited pipes in grandchildren do not
        // make a process wait promise EOF or wait for those grandchildren to terminate.
        .drainPipeNative(&.outputPipe, &.output, Swag.U64.Max)
        .drainPipeNative(&.errorPipe, &.error, Swag.U64.Max)
    }

    // Waits for the child, draining both captured streams while it runs, and returns its status.
    //
    // After exit, captures bytes available at that instant without waiting for descendant-held
    // pipes to close. Linux reports normal exit codes 0..255, or 128 plus the terminating signal.
    mtd waitForExit()->s32 fail
    {
        if .exited do
            return .status
        Swag.assert(.handle != null, "invalid process handle")
        while not .exited
        {
            .readAvailable()
            try .pollExitNative(.hasCapturedStream() ? 5 : Swag.U32.Max)
        }

        .captureExitOutput()
        return .status
    }

    // Waits up to a finite nonnegative timeout while draining both captured streams.
    //
    // Zero performs one poll. Elapsed drain time counts against the deadline. Scheduling and
    // a single bounded drain can delay return beyond it. Timeout retains ownership of the child.
    mtd tryWaitForExit(timeout: Time.Duration)->bool fail
    {
        if not Math.isFinite(timeout.seconds) or
           timeout.seconds < 0 or
           timeout.seconds >= 18_446_744_073_709_550.0 do
            fail BadParameterError{"process timeout is outside the supported range"}
        if .exited do
            return true
        Swag.assert(.handle != null, "invalid process handle")
        let duration = timeout.milliseconds()
        var clock: Time.Stopwatch
        clock.start()
        for
        {
            .readAvailable()
            let elapsed   = clock.elapsedMilliseconds()
            let remaining = elapsed >= duration ? 0'u64 : duration - elapsed
            try .pollExitNative(cast(u32, Math.min(remaining, 5'u64)))
            if .exited
            {
                .captureExitOutput()
                return true
            }

            if clock.elapsedMilliseconds() >= duration do
                return false
        }
    }

    // Requests immediate termination; wait afterward to observe the status and capture output.
    //
    // Linux sends SIGKILL (observed status 137); Windows requests exit code 1. An already exited
    // or closed owner is unchanged. Windows also provides an overload taking a native exit code.
    mtd kill() fail
    {
        try .killNative()
    }

    // Closes the input pipe so a child waiting for EOF can finish. Repeated calls are safe.
    mtd closeStandardInput() => .closeStandardInputNative()

    // Returns whether the process is still running as far as the last wait could tell.
    //
    // This reports recorded state and never queries the system. A successful termination
    // request does not by itself guarantee the child has exited; wait to observe its status.
    mtd const isRunning()->bool => .handle != null and not .exited

    // Returns the exit code reported by the process.
    //
    // Only meaningful once the process has exited, which [[Core.Env.Process.waitForExit]] or a
    // successful [[Core.Env.Process.tryWaitForExit]] guarantees.
    mtd const exitCode()->s32
    {
        Swag.assert(.exited, "the process has not exited yet")
        return .status
    }

    // Returns everything captured from standard output so far.
    //
    // Empty unless the stream was redirected to [[Core.Env.StreamRedirection.Pipe]]. The result
    // is borrowed from this value and stays valid until the next read.
    mtd const standardOutput()->string => .output.toString()

    // Returns everything captured from standard error so far.
    //
    // Empty unless the stream was redirected to [[Core.Env.StreamRedirection.Pipe]]. The result
    // is borrowed from this value and stays valid until the next read.
    mtd const standardError()->string => .error.toString()

    // Returns whether at least one stream of the child is captured through a pipe.
    internal mtd const hasCapturedStream()->bool => .outputPipe != null or .errorPipe != null
}

// Validate shared string/ownership boundaries before a backend allocates pipes or starts a child.
internal func validateProcessStartInfo(info: StartInfo) fail
{
    func rejectZero(value: string) fail
    {
        for byte in value where byte == 0 do
            fail BadParameterError{"process strings must not contain zero bytes"}
    }

    if not info.fileName.count do
        fail BadParameterError{"process filename must not be empty"}
    try rejectZero(info.fileName)
    if info.arguments do
        for argument in info.arguments do
            try rejectZero(argument)
    if info.nativeArguments
    {
        if info.arguments and info.arguments.count != 0 do
            fail BadParameterError{"argument values and native argument text cannot be combined"}
        try rejectZero(info.nativeArguments)
    }

    if info.workingDirectory
    {
        if not info.workingDirectory.count do
            fail BadParameterError{"process working directory must not be empty"}
        try rejectZero(info.workingDirectory)
    }

    if info.environment
    {
        for name, value in info.environment.variables
        {
            if name.isEmpty() do
                fail BadParameterError{"process environment names must not be empty"}
            try rejectZero(name.toString())
            try rejectZero(value.toString())
            for byte in name.toString() where byte == '=' do
                fail BadParameterError{"process environment names must not contain '='"}
        }
    }
}

#drop
{
    shutdownProcessesNative()
}
