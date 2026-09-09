#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

func waitBuild(lease: *Pipeline.BuildLease)
{
    var cancelled = 0'u32
    Swag.assert(lease.wait(&cancelled))
    if lease.artifact!.result.failed do
        Console.print(lease.artifact!.result.text.toString())
    Swag.assert(!lease.artifact!.result.failed)
}

// Identical requests share an in-flight process and retain completed output for later reuse.
#test
{
    var cache:   Pipeline.CompilationCache
    let request: Pipeline.BuildRequest = {source: String.from(exampleSource(.Dot)), stage: String.from("pre-emit"), settings: {configuration: String.from(Pipeline.BuildSettings.DefaultConfiguration)}}
    {
        var first  = cache.acquire(request)
        var second = cache.acquire(request)
        Swag.assert(first.artifact == second.artifact and second.reused and cache.buildCount == 1)
        waitBuild(&second)
        Swag.assert(!second.artifact!.result.text.isEmpty())
    }

    {
        var cached = cache.acquire(request)
        Swag.assert(cached.reused and cache.buildCount == 1)
        waitBuild(&cached)
    }

    cache.invalidate()
    {
        var fresh = cache.acquire(request)
        Swag.assert(!fresh.reused and cache.buildCount == 2)
        waitBuild(&fresh)
    }
}

// Module configuration is executed by the compiler, and each differing configuration is isolated.
#test
{
    var cache:   Pipeline.CompilationCache
    var request: Pipeline.BuildRequest = {source: String.from("func sum(a, b: s32)->s32 => a + b"), stage: String.from("pre-emit")}
    request.settings.configuration = "#run { let cfg = Swag.compiler().getBuildCfg()!; cfg.safetyGuards = .All; cfg.backend.inlineMode = .Never }"
    {
        var guarded = cache.acquire(request)
        waitBuild(&guarded)
        Swag.assert(Utf8.indexOf(cast(const [..] u8) guarded.artifact!.result.text.toString(), "safetyPanic") != Swag.U64.Max)
    }

    request.settings.configuration = "#run { let cfg = Swag.compiler().getBuildCfg()!; cfg.safetyGuards = .None }"
    {
        var unguarded = cache.acquire(request)
        waitBuild(&unguarded)
        Swag.assert(!unguarded.reused and cache.buildCount == 2)
        Swag.assert(Utf8.indexOf(cast(const [..] u8) unguarded.artifact!.result.text.toString(), "safetyPanic") == Swag.U64.Max)
    }

    request.settings.configuration.append("\n#run { Swag.compiler().getBuildCfg()!.backend.optimLevel = .O1 }")
    request.settings.preset       = .Devmode
    request.settings.optimization = .O2
    {
        var devmode = cache.acquire(request)
        waitBuild(&devmode)
        Swag.assert(!devmode.reused and cache.buildCount == 3)
        var output: CompilerOutput
        output.parse(devmode.artifact!.result.text.toString())
        Swag.assert(Utf8.indexOf(cast(const [..] u8) output.text.toString(), "  optimize : O1") != Swag.U64.Max)
    }
}

// Releasing one subscriber must not interrupt another subscriber's compilation.
#test
{
    var cache:   Pipeline.CompilationCache
    let request: Pipeline.BuildRequest = {source: String.from(exampleSource(.Dot)), stage: String.from("pre-emit")}
    var survivor = cache.acquire(request)
    {
        var cancelled = cache.acquire(request)
        Swag.assert(cancelled.artifact == survivor.artifact)
    }

    waitBuild(&survivor)
    Swag.assert(!Atomic.get(&survivor.artifact!.cancelled))
}

// Pixel execution and inspection consume the same native build when settings match.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()
    window.setComparisonEnabled(true)
    window.panels[1].optimCombo.setSelectedIndex(0, notify: false)
    window.compile()
    let preview = cast(*PreviewViewer) window.panels[0].viewer!.window()
    let micro   = cast(*MicrocodeViewer) window.panels[1].viewer!.window()
    var watch: Time.Stopwatch
    watch.start()
    while (micro.job.running or !preview.frameCount) and watch.elapsedMilliseconds() < 90000
    {
        Threading.Thread.sleep(5'ms)
        if micro.job.running do
            host.fireTimer(micro.job.timer!)
        if preview.running do
            preview.poll()
    }

    if preview.probe.failed do
        Console.print(preview.probe.diagnostics.toString())
    Swag.assert(!micro.job.running and !micro.job.result.failed and preview.frameCount != 0)
    Swag.assert(micro.job.artifactId == preview.probe.artifactId and window.cache.buildCount == 1)
    Swag.assert(micro.outputText.colors.count != 0)
    window.shutdown()
}

// Two execution viewers share a compiled module but keep independent frame channels and playback.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()
    window.setComparisonEnabled(true)
    window.panels[1].optimCombo.setSelectedIndex(0, notify: false)
    window.panels[1].selectViewer(.Render2D)
    window.compile()
    let first  = cast(*PreviewViewer) window.panels[0].viewer!.window()
    let second = cast(*PreviewViewer) window.panels[1].viewer!.window()
    var watch: Time.Stopwatch
    watch.start()
    while (!first.frameCount or !second.frameCount) and watch.elapsedMilliseconds() < 90000
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
    Swag.assert(!first.queued and !second.queued and first.frameCount == pausedFrame)
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

// The settings editor belongs to its panel and restores its original build state.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()
    window.liveEdit.setState(.Unchecked)
    let panel = window.panels[0]
    host.click(panel.optionsButton.localToSurface(Math.Point{18, 18}))
    Swag.assert(panel.options.isVisible() and panel.optionsButton.isChecked and !panel.viewer!.window().isVisible())
    panel.options.presetCombo.setSelectedIndex(1, notify: false)
    panel.options.editor.setText("#run { Swag.compiler().getBuildCfg()!.backend.vectorize = false }")
    panel.optimCombo.setSelectedIndex(2, notify: false)
    let settings = panel.request(window.editor.text().toString()).settings
    panel.selectViewer(.Gui)
    Swag.assert(panel.request(window.editor.text().toString()).settings.matches(settings))
    Swag.assert(!panel.viewer!.window().isVisible())
    panel.selectViewer(.Render2D)
    panel.options.reset()
    Swag.assert(panel.optimCombo.selectedIndex == 0 and panel.options.presetCombo.selectedIndex == 0)
    Swag.assert(panel.options.editor.text().toString() == Pipeline.BuildSettings.DefaultConfiguration)
    Swag.assert(window.panels[1].optimCombo.selectedIndex == 2)
    panel.showOptions(false)
    Swag.assert(panel.viewer!.window().isVisible() and !panel.optionsButton.isChecked)
    window.shutdown()
}

// The precompiled host and edited libraries share the same runtime, including during unload.
#test
{
    var artifact: Pipeline.BuildArtifact
    artifact.request = {kind: .Render2D, source: String.from(exampleSource(.Plasma)), settings: {optimization: .O2}}
    expect artifact.run()
    if artifact.result.failed do
        Console.print(artifact.result.text.toString())
    Swag.assert(!artifact.result.failed)
    for iteration in 3
    {
        discard iteration
        var library = expect NativeLibrary.load(artifact.binary.toString())
        let symbol  = library.symbol("prism_shade")
        Swag.assert(symbol != null)
        let shade = cast(func(f32, f32, f32)->u32) symbol!
        let color = shade(0, 0, 0)
        Swag.assert((color & 0xFF000000) == 0xFF000000)
    }
}

// A microcode snippet is compiled against `core` only when it names the module, and a preview
// always is, because its host program calls into what the snippet declares.
#test
{
    var request: Pipeline.BuildRequest = {source: String.from("func dot(a, b: f32)->f32 => a * b"), stage: String.from("pre-emit")}
    Swag.assert(request.kind == .Microcode and !request.needsDependency())
    Swag.assert(!Utf8.contains(request.moduleSource().toString(), "#import"))

    request.source = String.from("using Core\nfunc value()->f32 => Math.sqrt(2'f32)")
    Swag.assert(request.needsDependency())
    Swag.assert(Utf8.contains(request.moduleSource().toString(), "#import(\"core\""))

    request.kind   = .Render2D
    request.source = String.from("func shade(x, y, time: f32)->u32 => 0")
    Swag.assert(request.needsDependency())
    Swag.assert(Utf8.contains(request.moduleSource().toString(), "#import(\"pixel\""))

    request.kind = .Gui
    Swag.assert(request.needsDependency())
    Swag.assert(Utf8.contains(request.moduleSource().toString(), "#import(\"gui\""))
}

// A snippet that reaches into `core` still reaches the compiler with the import the scan asked for.
#test
{
    var cache:   Pipeline.CompilationCache
    let request: Pipeline.BuildRequest = {source: String.from("using Core\nfunc value()->f32 => Math.sqrt(2'f32)"), stage: String.from("pre-emit")}
    var lease = cache.acquire(request)
    waitBuild(&lease)

    var output: CompilerOutput
    output.parse(lease.artifact!.result.text.toString())
    Swag.assert(Utf8.indexOf(cast(const [..] u8) output.text.toString(), "  stage    : pre-emit") != Swag.U64.Max)
}
