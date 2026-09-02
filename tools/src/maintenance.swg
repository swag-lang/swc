#global namespace Tool

using Core

// Formats every Swag source workspace in the repository, in place.
//
// This rewrites tracked sources. It is a maintenance step, never a test.
public func runFormat(context: *Context, options: *Options)->s32 fail
{
    var arguments: Arguments
    arguments.add(["format"])
    for workspace in ["examples", "apps", "reference", "runtime", "std", "unittests"] do
        arguments.add(["-d", Path.combine(context.binDir.toString(), workspace).toString()])

    // The tools are Swag sources of this repository too, and are held to the same shape.
    arguments.add(["-d", Path.combine(context.root.toString(), "tools", "src").toString()])

    options.appendExtra(&arguments)
    return try context.runCompiler(arguments)
}

// Tests every tagged golden, or promotes the snapshots a failing test left behind into the
// goldens they diverged from.
//
// A golden mismatch writes `<name>.actual.txt` or `<name>.actual.png` next to its reference and
// fails. Once reviewed, this moves every actual over its golden. Recording is deliberately a
// separate, explicit step: it accepts whatever the code currently produces.
public func runGoldens(context: *Context, options: *Options)->s32 fail
{
    if options.command == "test" do
        return try runGoldenTests(context, options)
    return try acceptGoldens(context)
}

// Runs every '#test' tagged as a text or image golden.
//
// Modules run separately and the campaign continues after a failing one, leaving every
// divergent `.actual` available for one review. The tag is explicit test metadata; assertion
// helpers and implementation details therefore cannot hide a golden from this pass.
private func runGoldenTests(context: *Context, options: *Options)->s32 fail
{
    let before = try goldenSnapshots(context)

    var ran    = false
    var failed = false
    for cfg in options.configurations()
    {
        var sub = forConfiguration(options, cfg.toString())
        sub.command = String.from("test")
        sub.module.clear()
        sub.test.values.clear()
        sub.test.add(["--test-tag", "golden"])

        for workspace in ["std", "examples", "apps"]
        {
            for module in try goldenModules(context, workspace)
            {
                ran        = true
                sub.module = String.from(module.toString())
                Console.println()
                Console.println("golden tests: ", workspace, "/", module.toString(), " (", cfg.toString(), ")")

                var code = 0's32
                switch workspace
                {
                case "std":      code = try runStd(context, &sub)
                case "examples": code = try runExamples(context, &sub)
                case "apps":     code = try runApps(context, &sub)
                }

                failed = failed or code != 0
            }
        }

        if try directoryHasGoldens(context.workspacePath("reference").toString())
        {
            ran = true
            sub.module.clear()
            Console.println()
            Console.println("golden tests: reference (", cfg.toString(), ")")
            let code = try runReference(context, &sub)
            failed = failed or code != 0
        }
    }

    let actuals = actualSnapshots(context)
    if actuals.count
    {
        Console.println()
        Console.println("golden differences:")
        for actual in actuals do
            Console.println("  ", actual.toString())
        failed = true
    }

    let after   = try goldenSnapshots(context)
    var created = 0'u64
    for snapshot in after
    {
        if before.contains(snapshot.toString()) do
            continue
        if created == 0
        {
            Console.println()
            Console.println("new goldens created during the test:")
        }

        Console.println("  ", snapshot.toString())
        created += 1
    }

    if !ran
    {
        Console.println("no golden directory found")
        return 1
    }

    if failed or created != 0 do
        return 1

    Console.println()
    Console.println("all golden tests passed")
    return 0
}

// Returns the independently runnable modules that own a canonical `goldens` directory.
private func goldenModules(context: *Context, workspace: string)->Array'String fail
{
    var result: retval
    for module in context.workspaceModules(workspace)
    {
        let moduleDir = Path.combine(context.workspacePath(workspace).toString(), "modules", module.toString())
        if try directoryHasGoldens(moduleDir.toString()) do
            result.add(String.from(module.toString()))
    }

    return result
}

// Reports whether one independently runnable root owns a canonical `goldens` directory.
private func directoryHasGoldens(root: string)->bool fail
{
    let directories = try Directory.enumerateDirectories(root, recurse: true)
    for directory in directories where Path.fileName(directory.fullname.toString()) == "goldens" do
        return true

    return false
}

// Promotes every pending actual snapshot after it has been reviewed.
private func acceptGoldens(context: *Context)->s32 fail
{
    var accepted = 0'u64
    for full in actualSnapshots(context)
    {
        let suffix    = full.endsWith(".actual.txt") ? ".actual.txt" : ".actual.png"
        let extension = suffix == ".actual.txt" ? ".txt" : ".png"

        var golden = String.from(full.toString()[0 until full.count - suffix.count])
        golden += extension

        try File.move(golden.toString(), full.toString())
        Console.println("accepted ", Path.fileName(full.toString()) orelse "")
        accepted += 1
    }

    if accepted == 0 do
        Console.println("no pending snapshot to accept")
    else do
        Console.println(accepted, " golden(s) accepted - review them with git diff before committing")
    return 0
}

// Returns every text or image snapshot left by a failed golden comparison.
private func actualSnapshots(context: *Context)->Array'String
{
    var result: retval
    for suffix in [".actual.txt", ".actual.png"]
    {
        let extension = suffix == ".actual.txt" ? ".txt" : ".png"
        let entries   = catch Directory.enumerateFiles(context.binDir.toString(), extension, recurse: true) as err
        if err != null do
            continue

        for entry in entries
        {
            let full = entry.fullname.toString()
            if Utf8.endsWith(cast(const [..] u8) full, suffix) do
                result.add(entry.fullname)
        }
    }

    return result
}

// Returns every recorded text or image snapshot below a canonical `goldens` directory.
private func goldenSnapshots(context: *Context)->Array'String fail
{
    var result: retval
    let directories = try Directory.enumerateDirectories(context.binDir.toString(), recurse: true)
    for directory in directories
    {
        if Path.fileName(directory.fullname.toString()) != "goldens" do
            continue

        for extension in [".txt", ".png"]
        {
            let entries = try Directory.enumerateFiles(directory.fullname.toString(), extension, recurse: true)
            for entry in entries
            {
                let full = entry.fullname.toString()
                if !Utf8.endsWith(cast(const [..] u8) full, ".actual.txt") and !Utf8.endsWith(cast(const [..] u8) full, ".actual.png") do
                    result.add(entry.fullname)
            }
        }
    }

    return result
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

    var brand: Arguments
    options.appendExtra(&brand)
    brand.add([Path.combine(webDir.toString(), "tools", "brand.swgs").toString()])

    let brandLine = joinArguments(brand.toSlice())

    var info    = Env.StartInfo{fileName: context.compiler.toString(), arguments: brandLine.toString(), workingDirectory: context.root.toString(), environment: &context.childEnv}
    var process = try Env.startProcess(info)
    let branded = try process.waitForExit()
    if branded != 0 do
        return branded

    // A removed module must not leave its generated page behind. Root HTML files are all
    // documentation outputs; assets and source tools live in their own directories.
    let oldPages = try Directory.enumerateFiles(webDir.toString(), ".html")
    for page in oldPages do
        try File.delete(page.fullname.toString())

    for workspace in ["std", "reference"]
    {
        var arguments: Arguments
        arguments.add(["doc", "--workspace", context.workspacePath(workspace).toString()])
        arguments.add(["--doc-output-dir", webDir.toString(), "--rebuild"])
        options.appendExtra(&arguments)

        let code = try context.runCompiler(arguments)
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

    var info    = Env.StartInfo{fileName: "vsce.cmd", arguments: "package", workingDirectory: vscodeDir.toString(), environment: &context.childEnv}
    var process = try Env.startProcess(info)
    return try process.waitForExit()
}

// Registers the repository compiler directory in the current user's environment, and hands it
// the `.swgs` extension.
//
// Claiming the extension is what lets the desktop run a tool: after this, double-clicking a
// `.swgs` runs it, arguments and exit code included. A shell still names the compiler, because
// `cmd` resolves an extension through the machine-wide association that only an elevated
// `assoc`/`ftype` writes.
public func runSetup(context: *Context, _options: *Options)->s32 fail
{
    var native = context.binDir
    native.replace("/", "\\")

    let environment = Env.currentEnvironment()
    let current     = environment.value("PATH") orelse ""

    if Utf8.indexOf(cast(const [..] u8) current, native.toString(), 0, .Latin1NoCase) != Swag.U64.Max
    {
        Console.println("\"", native.toString(), "\" is already in PATH.")
    }
    else
    {
        Console.println("Adding \"", native.toString(), "\" to user PATH...")

        var updated = String.from(current)
        if !updated.isEmpty() do
            updated += ";"
        updated += native

        let code = try context.runProgramTokens("setx.exe", ["PATH", updated.toString()])
        if code != 0 do
            return code
    }

    Console.println("Setting SWAG_PATH to \"", native.toString(), "\"...")
    let code = try context.runProgramTokens("setx.exe", ["SWAG_PATH", native.toString()])
    if code != 0 do
        return code

    let compiler = Path.combine(context.binDir.toString(), "swc.exe")
    Console.println("Associating \".swgs\" with \"", compiler.toString(), "\"...")
    if !Env.claimFileExtension(".swgs", "Swag.Script", "Swag script", compiler.toString())
    {
        Console.println("error: the file association could not be written")
        return 1
    }

    Console.println("Done. You may need to restart your terminal.")
    return 0
}

// Runs the privileged Swag Vault/WinFsp end-to-end sandbox, then restores a normal build.
//
// The integration build mounts a real volume, so it is kept out of the default test set and run
// on demand. The final rebuild is what puts a plain Swag Vault back in the output directory.
public func runVaultIntegration(context: *Context, options: *Options)->s32 fail
{
    var integration = options[]
    integration.command  = String.from("build")
    integration.module   = String.from("swagvault")
    integration.buildCfg = String.from("release")
    integration.extra.add(["--tag", "vault.integration", "--rebuild"])

    let tagged = try runApps(context, &integration)
    if tagged != 0 do
        return tagged

    let appDir = Path.combine(context.workspacePath("apps").toString(), ".output", "swagvault", "executable", "release", context.targetArch.toString())
    let report = Path.combine(appDir.toString(), "integration-result.txt")
    if File.exists(report) do
        discard catch File.delete(report.toString())

    let executable = Path.combine(appDir.toString(), "swagvault.exe")

    var info    = Env.StartInfo{fileName: executable.toString(), workingDirectory: appDir.toString(), environment: &context.childEnv}
    var process = try Env.startProcess(info)
    var result  = try process.waitForExit()

    if File.exists(report)
    {
        let content = catch File.readAllText(report.toString()) as err
        if err == null do
            Console.print(content.toString())
    }

    Console.println()

    var restore = options[]
    restore.command  = String.from("build")
    restore.module   = String.from("swagvault")
    restore.buildCfg = String.from("release")
    restore.extra.add(["--rebuild"])

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

    var arguments: Arguments
    arguments.add([campaign.toString()])
    options.appendExtra(&arguments)

    var code = catch context.runProgram("python.exe", arguments) as err
    if err == null do
        return code

    // The Windows launcher can select an incomplete registered installation, so a directly
    // installed interpreter is preferred and the launcher is only the fallback.
    var launched: Arguments
    launched.add(["-3", campaign.toString()])
    options.appendExtra(&launched)

    code = catch context.runProgram("py.exe", launched) as launcherError
    if launcherError != null
    {
        Console.println("Python 3 is required to run the benchmark, and neither `py` nor `python` is on PATH.")
        return 1
    }

    return code
}
