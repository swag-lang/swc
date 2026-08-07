#global namespace Tool

using Core

// Formats every Swag source workspace in the repository, in place.
//
// This rewrites tracked sources. It is a maintenance step, never a test.
public func runFormat(context: *Context, options: *Options)->s32 fail
{
    var arguments: Array'String
    arguments.add(String.from("format"))
    for workspace in ["examples", "apps", "reference", "runtime", "std", "unittests"]
    {
        arguments.add(String.from("-d"))
        arguments.add(Path.combine(context.binDir.toString(), workspace))
    }

    // The tools are Swag sources of this repository too, and are held to the same shape.
    arguments.add(String.from("-d"))
    arguments.add(Path.combine(context.root.toString(), "tools", "src"))

    options.appendExtra(&arguments)
    return try context.runCompiler(arguments.toSlice())
}

// Promotes the snapshots a failing test left behind into the goldens they diverged from.
//
// A golden mismatch writes `<name>.actual.txt` or `<name>.actual.png` next to its reference and
// fails. Once reviewed, this moves every actual over its golden. Recording is deliberately a
// separate, explicit step: it accepts whatever the code currently produces.
public func runGoldens(context: *Context, _options: *Options)->s32 fail
{
    var accepted = 0'u64
    for suffix in [".actual.txt", ".actual.png"]
    {
        let extension = suffix == ".actual.txt" ? ".txt" : ".png"
        let entries   = catch Directory.enumerateFiles(context.binDir.toString(), extension, recurse: true) as err
        if err != null do
            continue

        for entry in entries
        {
            let full = entry.fullname.toString()
            if !Utf8.endsWith(cast(const [..] u8) full, suffix) do
                continue

            var golden = String.from(full[0 until @countof(full) - @countof(suffix)])
            golden += extension

            try File.move(golden.toString(), full)
            @print("accepted ", Path.fileName(full) orelse "", "\n")
            accepted += 1
        }
    }

    if accepted == 0 do
        @print("no pending snapshot to accept\n")
    else do
        @print(accepted, " golden(s) accepted - review them with git diff before committing\n")
    return 0
}

// Regenerates the brand assets and the complete website under web/.
//
// The brand assets come first: the pages link them, and cutting them again is what keeps the
// mark, the icons and the favicons in step with their definition. The generator writes relative
// to the repository root, so it runs from there whatever the caller's own directory.
public func runWeb(context: *Context, options: *Options)->s32 fail
{
    let webDir = Path.combine(context.root.toString(), "web")
    if !Directory.exists(webDir) do
        try Directory.create(webDir.toString())

    var brand: Array'String
    options.appendExtra(&brand)
    brand.add(Path.combine(webDir.toString(), "tools", "brand.swgs"))

    let brandLine = joinArguments(brand.toSlice())

    var info = Env.StartInfo{fileName: context.compiler.toString(), arguments: brandLine.toString(), workingDirectory: context.root.toString(), environment: &context.childEnv}
    var process = try Env.startProcess(info)
    let branded = try process.waitForExit()
    if branded != 0 do
        return branded

    for workspace in ["std", "reference"]
    {
        var arguments: Array'String
        arguments.add(String.from("doc"))
        arguments.add(String.from("--workspace"))
        arguments.add(context.workspacePath(workspace))
        arguments.add(String.from("--doc-output-dir"))
        arguments.add(webDir)
        arguments.add(String.from("--rebuild"))
        options.appendExtra(&arguments)

        let code = try context.runCompiler(arguments.toSlice())
        if code != 0 do
            return code
    }

    return 0
}

// Packages the VSCode extension after refreshing its generated image assets.
//
// Install Node.js, then `npm install -g vsce`, before using this.
public func runVsix(context: *Context, _options: *Options)->s32 fail
{
    let vscodeDir = Path.combine(context.root.toString(), "vscode")
    let imagesDir = Path.combine(vscodeDir.toString(), "images")
    if !Directory.exists(imagesDir) do
        try Directory.create(imagesDir.toString())

    for image in ["swag_icon.png", "syntax.png"]
    {
        let source = Path.combine(context.root.toString(), "web", "imgs", image)
        let target = Path.combine(imagesDir.toString(), image)
        try File.duplicate(target.toString(), source.toString())
    }

    var info = Env.StartInfo{fileName: "vsce.cmd", arguments: "package", workingDirectory: vscodeDir.toString(), environment: &context.childEnv}
    var process = try Env.startProcess(info)
    return try process.waitForExit()
}

// Registers the repository compiler directory in the current user's environment.
public func runSetup(context: *Context, _options: *Options)->s32 fail
{
    var native = context.binDir
    native.replace("/", "\\")

    let environment = Env.currentEnvironment()
    let current     = environment.value("PATH") orelse ""

    if Utf8.indexOf(cast(const [..] u8) current, native.toString(), 0, .Latin1NoCase) != Swag.U64.Max
    {
        @print("\"", native.toString(), "\" is already in PATH.\n")
    }
    else
    {
        @print("Adding \"", native.toString(), "\" to user PATH...\n")

        var updated = String.from(current)
        if !updated.isEmpty() do
            updated += ";"
        updated += native

        let code = try context.runProgram("setx.exe", ["PATH", updated])
        if code != 0 do
            return code
    }

    @print("Setting SWAG_PATH to \"", native.toString(), "\"...\n")
    let code = try context.runProgram("setx.exe", ["SWAG_PATH", native])
    if code != 0 do
        return code

    @print("Done. You may need to restart your terminal.\n")
    return 0
}

// Runs the privileged sCrypt/WinFsp end-to-end sandbox, then restores a normal build.
//
// The integration build mounts a real volume, so it is kept out of the default test set and run
// on demand. The final rebuild is what puts a plain sCrypt back in the output directory.
public func runScrypt(context: *Context, options: *Options)->s32 fail
{
    var integration = dref options
    integration.command  = String.from("build")
    integration.module   = String.from("sCrypt")
    integration.buildCfg = String.from("release")
    integration.extra.add(String.from("--tag"))
    integration.extra.add(String.from("SCrypt.Integration"))
    integration.extra.add(String.from("--rebuild"))

    let tagged = try runApps(context, &integration)
    if tagged != 0 do
        return tagged

    let appDir = Path.combine(context.workspacePath("apps").toString(), ".output", "sCrypt", "executable", "release", context.targetArch.toString())
    let report = Path.combine(appDir.toString(), "sCrypt-integration-result.txt")
    if File.exists(report) do
        discard catch File.delete(report.toString())

    let executable = Path.combine(appDir.toString(), "sCrypt.exe")

    var info = Env.StartInfo{fileName: executable.toString(), workingDirectory: appDir.toString(), environment: &context.childEnv}
    var process = try Env.startProcess(info)
    var result  = try process.waitForExit()

    if File.exists(report)
    {
        let content = catch File.readAllText(report.toString()) as err
        if err == null do
            @print(content.toString())
    }

    @print("\n")

    var restore = dref options
    restore.command  = String.from("build")
    restore.module   = String.from("sCrypt")
    restore.buildCfg = String.from("release")
    restore.extra.add(String.from("--rebuild"))

    let restored = try runApps(context, &restore)
    if restored != 0 and result == 0 do
        result = 1
    return result
}

// Runs or regenerates the cross-language performance campaign.
//
// The campaign itself is a Python program, and stays one: it drives the other toolchains as much
// as it drives this one, and rewriting it here would only move that dependency.
public func runBench(context: *Context, options: *Options)->s32 fail
{
    let campaign = Path.combine(context.root.toString(), "bench", "campaign.py")

    var arguments: Array'String
    arguments.add(campaign)
    options.appendExtra(&arguments)

    var code = catch context.runProgram("python.exe", arguments.toSlice()) as err
    if err == null do
        return code

    // The Windows launcher can select an incomplete registered installation, so a directly
    // installed interpreter is preferred and the launcher is only the fallback.
    var launched: Array'String
    launched.add(String.from("-3"))
    launched.add(campaign)
    options.appendExtra(&launched)

    code = catch context.runProgram("py.exe", launched.toSlice()) as launcherError
    if launcherError != null
    {
        @print("Python 3 is required to run the benchmark, and neither `py` nor `python` is on PATH.\n")
        return 1
    }

    return code
}
