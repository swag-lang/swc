#global namespace Tool

using Core

// Where the repository is, which compiler the tools run under and drive, and how to start it.
public struct Context
{
    root:       String                     // Repository root, from the launcher.
    binDir:     String                     // The bin directory, which is also the compiler root.
    compiler:   String                     // Compiler the tools drive.
    targetArch: String                     // Architecture every output path is keyed on.
    childEnv:   Env.ProcessEnvironment     // Environment every started compiler inherits.
}

// The build configurations a campaign repeats, in the order it repeats them.
public func allConfigurations()->const [..] string
{
    return g_AllConfigurations
}

private var g_AllConfigurations: [2] string = ["release", "devmode"]

public impl Context
{
    // Builds the context the launcher describes.
    //
    // `rootDirectory` comes from the calling script's own path, so a tool is launched from
    // anywhere without anything being configured or exported first.
    func create(rootDirectory: string, options: Options)->Context fail
    {
        var result: retval

        var root = String.from(rootDirectory)
        if root.isEmpty() do
            fail Errors.BadParameterError{"the tool could not locate the repository"}
        Path.normalize(&root)

        result.root       = root
        result.binDir     = Path.combine(root.toString(), "bin")
        result.targetArch = options.targetArch

        let name = options.devMode ? "swc.dm.exe" : "swc.exe"
        result.compiler = Path.combine(result.binDir.toString(), name)
        if !File.exists(result.compiler) do
            fail Errors.FileNotFoundError{"the compiler under test has not been built", fileName: result.compiler.toString()}

        // A started compiler takes the library beside itself, and the one started here always sits
        // in this checkout's `bin`. `SWAG_PATH` is set anyway so a child that reads it directly
        // cannot be answered by whichever working tree the ambient environment happens to name.
        result.childEnv = Env.currentEnvironment()
        result.childEnv.set("SWAG_PATH", result.binDir.toString())

        return result
    }

    // Runs the compiler under test with `arguments` and returns its exit code.
    //
    // The standard streams are inherited, so the compiler reports directly to whoever launched
    // the tool and nothing reformats what it says.
    mtd runCompiler(arguments: Arguments)->s32 fail
    {
        return try .runProgram(.compiler.toString(), withCoreBound(arguments))
    }

    // Runs the compiler under test with `arguments` and returns what it wrote to standard output.
    //
    // The core bound of [[Tool.Context.runCompiler]] applies here too, so a captured compiler
    // run costs the machine no more than an open one.
    mtd captureCompiler(arguments: Arguments)->String fail
    {
        return try .captureProgram(.compiler.toString(), withCoreBound(arguments))
    }

    // Runs `program` with a command line written out in place.
    mtd runProgramTokens(program: string, tokens: const [..] string)->s32 fail
    {
        var arguments: Arguments
        arguments.add(tokens)
        return try .runProgram(program, arguments)
    }

    // Runs `program` with `arguments` and returns its exit code, letting its output through.
    mtd runProgram(program: string, arguments: Arguments)->s32 fail
    {
        let commandLine = joinArguments(arguments.toSlice())

        var info    = Env.StartInfo{fileName: program, arguments: commandLine.toString(), environment: &.childEnv}
        var process = try Env.startProcess(info)
        return try process.waitForExit()
    }

    // Runs `program` and returns what it wrote to standard output.
    //
    // Reserved for a program whose output is data the tool reads. A program whose output is a
    // report for the person watching goes through [[Tool.Context.runProgram]] instead, so it
    // keeps its colors and its progressive display.
    mtd captureProgram(program: string, arguments: Arguments)->String fail
    {
        let commandLine = joinArguments(arguments.toSlice())

        var info    = Env.StartInfo{fileName: program, arguments: commandLine.toString(), environment: &.childEnv, standardOutput: .Pipe, standardError: .Discard}
        var process = try Env.runProcess(info)
        return String.from(process.standardOutput())
    }

    // Returns the output and work directories one artifact of one workspace owns.
    //
    // `relative` is the workspace name, optionally followed by a path inside it, so
    // `std/core` and `unittests/jit` key their own trees under the workspace that holds them.
    mtd const artifactPaths(relative: string, label: string, buildCfg: string)->ArtifactPaths
    {
        var result: retval

        let separator = Utf8.indexOf(cast(const [..] u8) relative, "/")
        let workspace = separator == Swag.U64.Max ? relative : relative[0 until separator]
        let inside    = separator == Swag.U64.Max ? "" : relative[separator + 1 until relative.count]

        let outRoot  = Path.combine(.binDir.toString(), workspace, ".output")
        let workRoot = Path.combine(.binDir.toString(), workspace, ".tmp")

        result.outDir  = Path.combine(outRoot.toString(), inside, label, buildCfg, .targetArch.toString())
        result.workDir = Path.combine(workRoot.toString(), inside, label, buildCfg, .targetArch.toString())
        return result
    }

    // Returns the directory a workspace publishes its module APIs in.
    mtd const workspaceOutput(workspace: string)->String
    {
        return Path.combine(.binDir.toString(), workspace, ".output")
    }

    // Returns the path of a workspace inside the repository.
    mtd const workspacePath(workspace: string)->String
    {
        return Path.combine(.binDir.toString(), workspace)
    }

    // Returns the independently selectable units a workspace family holds, in directory order.
    //
    // Every workspace exposes its selectable units under `modules`.
    mtd const workspaceModules(workspace: string)->Array'String
    {
        var result: retval

        let workspaceDir = Path.combine(.binDir.toString(), workspace)
        let unitsDir     = Path.combine(workspaceDir.toString(), "modules")
        let entries      = catch Directory.enumerateDirectories(unitsDir.toString()) as err
        if err != null do
            return result

        for entry in entries
        {
            result.add(String.from(Path.fileName(entry.fullname.toString()) orelse ""))
        }

        return result
    }
}

// Reports whether a tool was relaunched and the exit code of that selected-compiler run.
struct RelaunchResult
{
    didRun:   bool
    exitCode: s32
}

// Relaunches a tool when the compiler hosting its script is not the one its arguments selected.
//
// A script resolves its imports before its entry point runs. Rebuilding on the selected compiler
// is therefore required even though the first host has already loaded Core: it makes that same
// compiler generate the dependency APIs which the tool's child commands will consume.
func relaunchToolIfNeeded(context: *Context, script: string, tokens: const [..] string)->RelaunchResult fail
{
    var running  = try Env.Process.currentExecutablePath()
    var selected = String.from(context.compiler.toString())
    Path.normalize(&running)
    Path.normalize(&selected)

    var result: retval
    if Utf8.compare(cast(const [..] u8) running.toString(), cast(const [..] u8) selected.toString(), .Latin1NoCase) == 0 do
        return result

    var arguments: Arguments
    arguments.add(["--rebuild", script])
    arguments.add(tokens)

    result.didRun   = true
    result.exitCode = try context.runProgram(selected.toString(), withCoreBound(arguments))
    return result
}

// Names the two directories one built artifact owns.
public struct ArtifactPaths
{
    outDir:  String     // Where the artifact is written.
    workDir: String     // Where its intermediate state is kept.
}

// Returns `arguments` with a default '--num-cores' bound added, unless the caller chose one.
//
// A compiler left to detect its core count takes the whole machine, and a campaign that starts
// one compiler after another starves everything else running on it. A few cores are therefore
// kept free by default, while an explicit '--num-cores' or '-j' anywhere in the arguments
// still wins.
private func withCoreBound(arguments: Arguments)->Arguments
{
    for value in arguments.values
    {
        let text = value.toString()
        if text == "--num-cores" or text == "-j" or value.startsWith("--num-cores=") or value.startsWith("-j=") do
            return arguments
    }

    var result: retval
    let bound = Format.toString("%", defaultCoreCount())

    // A script names itself on the command line, and everything after the script path is the
    // script's own command line, so the bound goes in front there. After a command, every token
    // is an option, so the end is always safe.
    if isScriptInvocation(arguments)
    {
        result.add(["--num-cores", bound.toString()])
        result.addAll(arguments)
        return result
    }

    result.addAll(arguments)
    result.add(["--num-cores", bound.toString()])
    return result
}

// Returns how many cores a started compiler uses when nothing was asked: all of them minus a
// few, so the machine stays responsive for whoever and whatever else is working on it.
private func defaultCoreCount()->u32
{
    let cores = Hardware.processorCount()
    return cores > 4 ? cores - 4 : 1
}

// Reports whether `arguments` starts the compiler in script mode rather than with a command.
//
// A script invocation opens with an option or with the script path itself; a command invocation
// opens with the command word.
private func isScriptInvocation(arguments: Arguments)->bool
{
    if arguments.count() == 0 do
        return false

    let first = arguments.values[0]
    if first.startsWith("-") do
        return true
    return first.endsWith(".swgs", .Latin1NoCase)
}

// Returns `arguments` joined into the one command line the system parses back into them.
public func joinArguments(arguments: const [..] String)->String
{
    var plain: Array'(string)
    for argument in arguments do
        plain.add(argument.toString())
    return Env.joinArguments(plain.toSlice())
}
