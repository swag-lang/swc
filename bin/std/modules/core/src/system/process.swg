#global public
#global namespace Env

using Core.Errors

// Names the process handle type.
alias ProcessHandle = #null const *void

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
// var info = Env.StartInfo{fileName: "swc.exe", arguments: "test", environment: &environment}
// let process = try Env.runProcess(info)
// ```
struct ProcessEnvironment
{
    internal variables: HashTable'(String, String)
}

impl ProcessEnvironment
{
    // Returns the spelling under which the platform stores `name`.
    private func storedName(name: string)->String
    {
        return processEnvironmentStoredName(name)
    }

    // Returns how many variables the environment holds.
    mtd const count()->u64 => .variables.count

    // Returns the value bound to `name`, or `null` when the environment does not hold it.
    //
    // The result is borrowed from this value and stays valid until the binding changes.
    mtd const value(name: string)->#null string
    {
        let entry = .variables.tryFind(ProcessEnvironment.storedName(name))
        if !entry do
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
// Only `fileName` is required. The executable is looked up the way the system resolves a command
// line, so a bare name is searched in the current directory and along the executable search path;
// pass a full path to remove the ambiguity.
struct StartInfo
{
    fileName:         string                              // Executable to start, as a full path or a name to look up.
    arguments:        #null string                        // Command-line arguments, already quoted, or null for none.
    workingDirectory: #null string                        // Directory the child starts in, or null to inherit the current one.
    environment:      #null const *ProcessEnvironment     // Environment the child starts with, or null to inherit the current one. Borrowed for the call only.
    standardInput:    StreamRedirection = .Inherit        // How the child reads standard input.
    standardOutput:   StreamRedirection = .Inherit        // How the child writes standard output.
    standardError:    StreamRedirection = .Inherit        // How the child writes standard error.
    affinityMask:     u64                                 // Logical processors the child may run on, one bit each. Zero inherits the current set.
    measureResources: bool                                // Whether to account the child and everything it starts, which [[Core.Env.Process.resources]] answers.
}

/*
What a measured process and everything it started consumed.

Answered by [[Core.Env.Process.resources]] once the process was started with
`StartInfo.measureResources`. The whole tree is accounted, not just the process that was named:
a program that does its work in helpers it spawns would otherwise report almost nothing.

The peaks are the highest each figure ever reached, so they stay meaningful after the processes
that produced them are gone. Times are totals across the tree.
*/
struct ProcessResources
{
    peakMemory:        u64               // Highest committed memory the whole tree reached at once.
    peakProcessMemory: u64               // Highest committed memory any single process in it reached.
    userTime:          Time.Duration     // Total time the tree spent running its own code.
    kernelTime:        Time.Duration     // Total time the system spent working on its behalf.
    processCount:      u64               // How many processes the tree contained, first and last included.
}

/*
Owns a started child process, its pipes, and everything captured from it.

Start one with [[Core.Env.startProcess]] and drive it, or use [[Core.Env.runProcess]] to start it
and wait for it in one step. The value closes every handle it still owns when it leaves scope, so
a process is never leaked by an early return.

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
    readonly
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
func startProcess(fileName: string, arguments: #null string = null)->Process fail
{
    let info = StartInfo{fileName: fileName, arguments: arguments}
    return try startProcess(info)
}

// Starts a process, waits for it to exit, and returns it with everything it produced.
//
// Standard output and standard error are captured, so the returned value answers
// [[Core.Env.Process.standardOutput]] and [[Core.Env.Process.standardError]] as well as
// [[Core.Env.Process.exitCode]]. Standard input is inherited.
//
// ```swag
// let process = try Env.runProcess("swc.exe", "--help")
// if process.exitCode() != 0 do
//     fail Errors.BadParameterError{"the compiler refused to answer"}
// @print(process.standardOutput())
// ```
func runProcess(fileName: string, arguments: #null string = null)->Process fail
{
    let info = StartInfo{fileName: fileName, arguments: arguments, standardOutput: .Pipe, standardError: .Pipe}
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
    // Returns whether the process is still running as far as the last wait could tell.
    //
    // This reports recorded state and never queries the system, so it stays true until a wait,
    // a kill or a close observes the exit.
    mtd const isRunning()->bool => .handle != null and !.exited

    // Returns the exit code reported by the process.
    //
    // Only meaningful once the process has exited, which [[Core.Env.Process.waitForExit]] or a
    // successful [[Core.Env.Process.tryWaitForExit]] guarantees.
    mtd const exitCode()->s32
    {
        Debug.assert(.exited, "the process has not exited yet")
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
