#global internal
#global namespace Pipeline

using Core

// Entry points the preview host calls, one for each kind of native preview.
private const GuiEntry   = "public func prismBuild(parent: *Gui.Wnd) { buildView(parent) }"
private const ShadeEntry = "public func prismShade(x, y, time: f32)->u32 => shade(x, y, time)"

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
    // Writes the probe module and builds it out of process, keeping the binary or the
    // diagnostics.
    mtd run() fail
    {
        // Lays out the probe module. Unchanged files keep their time stamps, so the compiler
        // answers the module setup from its cache.
        try .folder.open()
        try writeIfChanged(Path.combine(.folder.root, "module.swg"), .request.moduleSource())
        try writeIfChanged(Path.combine(.folder.root, "src", "probe.swg"),
                           .request.stage.isEmpty()
                           ? .request.source
                           : inspectedSource(.request.source, .request.stage))
        let native = .request.kind != .Microcode
        if native do
            try writeIfChanged(Path.combine(.folder.root, "src", "entry.swg"), .request.kind == .Gui ? GuiEntry : ShadeEntry)

        // Builds the module out of process, so a snippet that crashes the compiler cannot take the
        // interface down, and gives up on a build the reader cancelled or that never ends.
        let outDir    = Path.combine(.folder.session, "out")
        let arguments = Format.toString("build --num-cores % --module-file \"%/module.swg\" --directory src --out-dir \"%\" --artifact-name prismpreview",
                                        compilerWorkerCount(),
                                        .folder.root,
                                        outDir)
        var process = try startPiped(compilerPath(), arguments)
        defer retireProcess(&process)

        var watch: Time.Stopwatch
        watch.start()
        while not try process.tryWaitForExit(5'ms)
        {
            if Atomic.get(&.cancelled) do
                return
            if watch.elapsedMilliseconds() > CompilerTimeoutMs
            {
                .result = {text: appStrings().msg_BuildTimeout, failed: true}
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
