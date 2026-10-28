#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

func waitBuild(lease: *Pipeline.BuildLease)
{
    Swag.assert(lease.wait())
    if lease.artifact!.result.failed do
        Console.print(lease.artifact.result.text)
    Swag.assert(not lease.artifact.result.failed)
}

// Identical requests share an in-flight process and retain completed output for later reuse.
#test
{
    var cache:   Pipeline.CompilationCache
    let request: Pipeline.BuildRequest = Pipeline.BuildRequest{source: exampleSource(.Dot), inspect: true, settings: Pipeline.BuildSettings{configuration: Pipeline.BuildSettings.DefaultConfiguration}}
    scope
    {
        var first  = cache.acquire(request)
        var second = cache.acquire(request)
        Swag.assert(first.artifact == second.artifact and second.reused and cache.buildCount == 1)
        waitBuild(&second)
        Swag.assert(not second.artifact!.result.text.isEmpty())
    }

    scope
    {
        var cached = cache.acquire(request)
        Swag.assert(cached.reused and cache.buildCount == 1)
        waitBuild(&cached)
    }

    cache.invalidate()
    scope
    {
        var fresh = cache.acquire(request)
        Swag.assert(not fresh.reused and cache.buildCount == 2)
        waitBuild(&fresh)
    }
}

// Module configuration is executed by the compiler, and each differing configuration is isolated.
#test
{
    var cache:   Pipeline.CompilationCache
    var request: Pipeline.BuildRequest = Pipeline.BuildRequest{source: "func sum(a, b: s32)->s32 => a + b", inspect: true}
    request.settings.configuration = "#run { let cfg = unwrap Swag.compiler().getBuildCfg(); cfg.safetyGuards = .All; cfg.backend.inlineMode = .Never }"
    scope
    {
        var guarded = cache.acquire(request)
        waitBuild(&guarded)
        Swag.assert(guarded.artifact!.result.text.contains("safetyPanic"))
    }

    request.settings.configuration = "#run { let cfg = unwrap Swag.compiler().getBuildCfg(); cfg.safetyGuards = .None }"
    scope
    {
        var unguarded = cache.acquire(request)
        waitBuild(&unguarded)
        Swag.assert(not unguarded.reused and cache.buildCount == 2)
        Swag.assert(not unguarded.artifact!.result.text.contains("safetyPanic"))
    }

    request.settings.configuration.append("\n#run { Swag.compiler().getBuildCfg()!.backend.optimLevel = .O1 }")
    request.settings.preset       = .Devmode
    request.settings.optimization = .O2
    scope
    {
        var devmode = cache.acquire(request)
        waitBuild(&devmode)
        Swag.assert(not devmode.reused and cache.buildCount == 3)
        var output: CompilerOutput
        output.parse(devmode.artifact!.result.text)
        Swag.assert(output.text.contains("  optimize : O1"))
    }
}

// Releasing one subscriber must not interrupt another subscriber's compilation.
#test
{
    var cache:   Pipeline.CompilationCache
    let request: Pipeline.BuildRequest = Pipeline.BuildRequest{source: exampleSource(.Dot), inspect: true}
    var survivor = cache.acquire(request)
    scope
    {
        var cancelled = cache.acquire(request)
        Swag.assert(cancelled.artifact == survivor.artifact)
    }

    waitBuild(&survivor)
    Swag.assert(not survivor.artifact!.task.isCancelled())
}

// Pixel execution and inspection consume the same native build when settings match.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    window.panels[1].setLevel(.O2, notify: false)
    window.setView(.Compare)
    let preview = assume cast(*PreviewViewer, window.panels[0].viewer!.window())
    let micro   = assume cast(*MicrocodeViewer, window.panels[1].viewer!.window())
    var watch: Time.Stopwatch
    watch.start()
    while (micro.job.running or not preview.frameCount) and watch.elapsedMilliseconds() < 90000
    {
        Threading.Thread.sleep(5'ms)
        if micro.job.running do
            host.pump()
        if preview.running do
            preview.poll()
    }

    if preview.probe.failed do
        Console.print(preview.probe.diagnostics)
    Swag.assert(not micro.job.running and not micro.job.result.failed and preview.frameCount != 0)
    Swag.assert(micro.job.artifactId == preview.probe.artifactId and window.cache.buildCount == 1)
    Swag.assert(not micro.inspection.snapshots.isEmpty())
    window.shutdown()
}

// Two execution viewers share a compiled module but keep independent frame channels and playback.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    window.panels[1].setLevel(.O2, notify: false)
    window.panels[1].selectViewer(.Render2D)
    window.setView(.Compare)
    let first  = assume cast(*PreviewViewer, window.panels[0].viewer!.window())
    let second = assume cast(*PreviewViewer, window.panels[1].viewer!.window())
    var watch: Time.Stopwatch
    watch.start()
    while (not first.frameCount or not second.frameCount) and watch.elapsedMilliseconds() < 90000
    {
        Threading.Thread.sleep(5'ms)
        if first.running do
            first.poll()
        if second.running do
            second.poll()
    }

    Swag.assert(first.frameCount != 0 and second.frameCount != 0)
    Swag.assert(first.probe.artifactId == second.probe.artifactId and window.cache.buildCount == 1)
    Swag.assert(first.probe.folder.session != second.probe.folder.session)
    first.paused = true
    let pausedFrame = first.frameCount
    let otherFrame  = second.frameCount
    window.compile()
    Swag.assert(not first.queued and not second.queued and first.frameCount == pausedFrame)
    while second.frameCount == otherFrame and watch.elapsedMilliseconds() < 90000
    {
        Threading.Thread.sleep(5'ms)
        first.poll()
        second.poll()
    }

    Swag.assert(first.frameCount == pausedFrame and second.frameCount > otherFrame)
    first.stop()
    let remainingFrame = second.frameCount
    while second.frameCount == remainingFrame and watch.elapsedMilliseconds() < 90000
    {
        Threading.Thread.sleep(5'ms)
        second.poll()
    }

    Swag.assert(second.frameCount > remainingFrame)
    window.shutdown()
}

// The build configuration belongs to its panel, takes the viewer's place, and restores the panel's
// original build state.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    window.setLiveEdit(false)
    let panel = window.panels[0]
    Swag.assert(window.runCommand(PrismCommands.BuildConfiguration))
    Swag.assert(panel.showingOptions and panel.options.isVisible() and not panel.viewer!.window().isVisible())
    Swag.assert(panel.closeButton.isVisible() and
                panel.restoreButton.isVisible() and
                not panel.viewMenu.isVisible())
    panel.options.setPreset(.Devmode, notify: false)
    panel.options.editor.setText("#run { Swag.compiler().getBuildCfg()!.backend.vectorize = false }")
    panel.setLevel(.O1, notify: false)
    let settings = panel.request(window.editor.text()).settings
    panel.selectViewer(.Gui)
    Swag.assert(panel.request(window.editor.text()).settings.matches(settings))
    Swag.assert(not panel.viewer!.window().isVisible())
    panel.selectViewer(.Render2D)
    panel.options.reset()
    Swag.assert(panel.level == .O2 and panel.options.preset == .Release)
    Swag.assert(panel.options.editor.text() == Pipeline.BuildSettings.DefaultConfiguration)
    Swag.assert(window.panels[1].level == .O0)
    host.click(panel.closeButton.localToSurface(Math.Point{8, 8}))
    Swag.assert(panel.viewer.window().isVisible() and not panel.showingOptions)
    window.shutdown()
}

// The precompiled host and edited libraries share the same runtime, including during unload.
#test
{
    var artifact: Pipeline.BuildArtifact
    artifact.request = {kind: .Render2D, source: exampleSource(.Plasma), settings: {optimization: .O2}}
    expect artifact.run()
    if artifact.result.failed do
        Console.print(artifact.result.text)
    Swag.assert(not artifact.result.failed)
    for 3
    {
        var library = expect NativeLibrary.load(artifact.binary)
        let symbol  = library.symbol("prism_shade")
        Swag.assert(symbol != null)
        let shade = cast(func(f32, f32, f32)->u32, symbol)
        let color = shade(0, 0, 0)
        Swag.assert((color & 0xFF000000) == 0xFF000000)
    }
}

// A microcode snippet is compiled against `core` only when it names the module, and a preview
// always is, because its host program calls into what the snippet declares.
#test
{
    var request: Pipeline.BuildRequest = Pipeline.BuildRequest{source: "func dot(a, b: f32)->f32 => a * b", inspect: true}
    Swag.assert(request.kind == .Microcode and not request.needsDependency())
    Swag.assert(not request.moduleSource().contains("#import"))

    request.source = "using Core\nfunc value()->f32 => Math.sqrt(2'f32)"
    Swag.assert(request.needsDependency())
    Swag.assert(request.moduleSource().contains("#import(\"core\""))

    request.kind   = .Render2D
    request.source = "func shade(_: f32, _: f32, _: f32)->u32 => 0"
    Swag.assert(request.needsDependency())
    Swag.assert(request.moduleSource().contains("#import(\"pixel\""))

    request.kind = .Gui
    Swag.assert(request.needsDependency())
    Swag.assert(request.moduleSource().contains("#import(\"gui\""))
}

// The module template keeps its layout once the indentation of its source is stripped: one line
// per statement, the nested block indented, and the closing brace ending the last line.
#test
{
    Swag.assert(Pipeline.BuildRequest.ModuleTemplate == "%\n#run { Swag.compiler().getBuildCfg()!.backend.optimLevel = .O% }\n%\n#run\n{\n    with let cfg = unwrap Swag.compiler().getBuildCfg()\n    {\n        .backendKind = .%\n        .publishDependencies = true\n    }\n}\n")
}

// A snippet that reaches into `core` still reaches the compiler with the import the scan asked for.
#test
{
    var cache:   Pipeline.CompilationCache
    let request: Pipeline.BuildRequest = Pipeline.BuildRequest{source: "using Core\nfunc value()->f32 => Math.sqrt(2'f32)", inspect: true}
    var lease = cache.acquire(request)
    waitBuild(&lease)

    var output: CompilerOutput
    output.parse(lease.artifact!.result.text)
    Swag.assert(output.text.contains("  stage    : pre-emit"))
}
