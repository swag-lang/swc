#global namespace Tool

using Core

// Where the repository is, which compiler the tools drive, and how to start it.
//
// The compiler named here is the one under test, never the one running these tools: `_run.bat`
// pins that one in `tools/` and keeps its own standard library beside it, so a tool can still
// report that a freshly built compiler is broken.
public struct Context
{
    root:       String                     // Repository root, from the launcher.
    binDir:     String                     // The bin directory, which is also the compiler root.
    compiler:   String                     // Compiler the tools drive.
    targetArch: String                     // Architecture every output path is keyed on.
    childEnv:   Env.ProcessEnvironment     // Environment every started compiler inherits.
}

// The three build configurations a campaign repeats, in the order it repeats them.
public func allConfigurations()->const [..] string
{
    return g_AllConfigurations
}

private var g_AllConfigurations: [3] string = ["release", "debug", "fast-debug"]

public impl Context
{
    // Builds the context the launcher describes.
    //
    // `SWAG_TOOL_ROOT` is the repository root the shim resolved from its own location, which is
    // what lets a tool be launched from anywhere rather than only from the root.
    func create(options: Options)->Context fail
    {
        var result: retval

        var root = launcherVariable("SWAG_TOOL_ROOT")
        if root.isEmpty() do
            fail Errors.BadParameterError{"the launcher did not name the repository root"}
        Path.normalize(&root)

        result.root       = root
        result.binDir     = Path.combine(root.toString(), "bin")
        result.targetArch = options.targetArch

        let name = options.devMode ? "swc_devmode.exe" : "swc.exe"
        result.compiler = Path.combine(result.binDir.toString(), name)
        if !File.exists(result.compiler) do
            fail Errors.FileNotFoundError{"the compiler under test has not been built", fileName: result.compiler.toString()}

        // The tools run against their own pinned library, so the compiler they start has to be
        // told where the repository one is rather than inheriting that answer.
        result.childEnv = Env.currentEnvironment()
        result.childEnv.set("SWAG_PATH", result.binDir.toString())

        return result
    }

    // Runs the compiler under test with `arguments` and returns its exit code.
    //
    // The standard streams are inherited, so the compiler reports directly to whoever launched
    // the tool and nothing reformats what it says.
    mtd runCompiler(arguments: const [..] String)->s32 fail
    {
        return try .runProgram(.compiler.toString(), arguments)
    }

    // Runs `program` with `arguments` and returns its exit code, letting its output through.
    mtd runProgram(program: string, arguments: const [..] String)->s32 fail
    {
        let commandLine = joinArguments(arguments)

        var info = Env.StartInfo{fileName: program, arguments: commandLine.toString(), environment: &.childEnv}
        var process = try Env.startProcess(info)
        return try process.waitForExit()
    }

    // Runs `program` and returns what it wrote to standard output.
    //
    // Reserved for a program whose output is data the tool reads. A program whose output is a
    // report for the person watching goes through [[Tool.Context.runProgram]] instead, so it
    // keeps its colors and its progressive display.
    mtd captureProgram(program: string, arguments: const [..] String)->String fail
    {
        let commandLine = joinArguments(arguments)

        var info = Env.StartInfo{fileName: program, arguments: commandLine.toString(), environment: &.childEnv, standardOutput: .Pipe, standardError: .Discard}
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
        let inside    = separator == Swag.U64.Max ? "" : relative[separator + 1 until @countof(relative)]

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

    // Returns the names of the modules a workspace holds, in directory order.
    mtd const workspaceModules(workspace: string)->Array'String
    {
        var result: retval

        let modulesDir = Path.combine(.binDir.toString(), workspace, "modules")
        let entries    = catch Directory.enumerateDirectories(modulesDir.toString()) as err
        if err != null do
            return result

        for entry in entries do
            result.add(String.from(Path.fileName(entry.fullname.toString()) orelse ""))
        return result
    }
}

// Names the two directories one built artifact owns.
public struct ArtifactPaths
{
    outDir:  String     // Where the artifact is written.
    workDir: String     // Where its intermediate state is kept.
}

// Returns `arguments` joined into the one command line the system parses back into them.
public func joinArguments(arguments: const [..] String)->String
{
    var plain: Array'(string)
    for argument in arguments do
        plain.add(argument.toString())
    return Env.joinArguments(plain.toSlice())
}

// Reads the launcher variable `name`.
public func launcherVariable(name: string)->String => Env.variable(name)
