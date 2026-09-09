#global internal
#global namespace Pipeline

using Core

// Immutable inputs and compiler output remain alive while a viewer leases this artifact.
#[Swag.NoCopy]
struct BuildArtifact
{
    request:    BuildRequest
    folder:     Probe
    result:     Result
    executable: String
    task:       Swag.Task
    cancelled:  u32
    users:      u32
    generation: u64
    id:         u64
    elapsedMs:  u64
}

impl BuildArtifact
{
    mtd run() fail
    {
        try .folder.open()
        let module = .request.moduleSource()
        discard try File.writeAllBytes(Path.combine(.folder.root, "module.swg"), cast(const [..] u8) module.toString())
        let inspected = .request.stage.isEmpty() ? .request.source : inspectedSource(.request.source.toString(), .request.stage.toString())
        discard try File.writeAllBytes(Path.combine(.folder.root, "src", "probe.swg"), cast(const [..] u8) inspected.toString())
        let native = .request.kind != .Microcode
        if native
        {
            discard try File.writeAllBytes(Path.combine(.folder.root, "src", "channel.swg"), #include("framechannel.swg"))
            let runner: const [..] u8 = .request.kind == .Gui ? cast(const [..] u8) #include("../../datas/preview/gui.txt") : cast(const [..] u8) #include("../../datas/preview/renderer.txt")
            discard try File.writeAllBytes(Path.combine(.folder.root, "src", "runner.swg"), runner)
        }

        let outDir    = Path.combine(.folder.session, "out")
        let arguments = Format.toString("build --num-cores 6 --module-file \"%/module.swg\" --directory src --out-dir \"%\" --artifact-name prismpreview", .folder.root, outDir)
        let compiler  = compilerPath()
        var process   = try Env.startProcess(Env.StartInfo{fileName: compiler.toString(), arguments: arguments.toString(), standardOutput: .Pipe, standardError: .Pipe, consoleWindow: false})
        defer retireProcess(&process)
        var watch: Time.Stopwatch
        watch.start()
        while !try process.tryWaitForExit(5'ms)
        {
            if Atomic.get(&.cancelled) do
                return
            if watch.elapsedMilliseconds() > 60000
            {
                .result = {text: String.from("Compilation exceeded 60 seconds."), failed: true}
                return
            }
        }

        .elapsedMs     = watch.elapsedMilliseconds()
        .result.text   = process.standardOutput()
        .result.failed = process.exitCode() != 0
        if .result.failed do
            .result.text.append(process.standardError())
        if native do
            .executable = Path.combine(outDir, "prismpreview.exe")
    }
}
