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
    binary:     String
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
        try writeIfChanged(Path.combine(.folder.root, "module.swg"), module.toString())
        let inspected = .request.stage.isEmpty() ? .request.source : inspectedSource(.request.source.toString(), .request.stage.toString())
        try writeIfChanged(Path.combine(.folder.root, "src", "probe.swg"), inspected.toString())
        let native = .request.kind != .Microcode
        if native
        {
            let wrapper = .request.kind == .Gui ? "public func prismBuild(parent: *Gui.Wnd) { buildView(parent) }" : "public func prismShade(x, y, time: f32)->u32 => shade(x, y, time)"
            try writeIfChanged(Path.combine(.folder.root, "src", "entry.swg"), wrapper)
        }

        let outDir    = Path.combine(.folder.session, "out")
        let arguments = Format.toString("build --num-cores % --module-file \"%/module.swg\" --directory src --out-dir \"%\" --artifact-name prismpreview", compilerWorkerCount(), .folder.root, outDir)
        let compiler  = compilerPath()
        var process   = try Env.startProcess(Env.StartInfo{fileName: compiler.toString(), arguments: arguments.toString(), standardOutput: .Pipe, standardError: .Pipe, consoleWindow: false})
        defer retireProcess(&process)
        var watch: Time.Stopwatch
        watch.start()
        while not try process.tryWaitForExit(5'ms)
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
            .binary = Path.combine(outDir, "prismpreview.dll")
    }
}
