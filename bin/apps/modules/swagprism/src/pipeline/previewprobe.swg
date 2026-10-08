#global internal
#global namespace Pipeline

using Core

// How long the child may go without publishing a frame before the preview reports it stalled.
private const StallTimeoutMs = 10_000'u64

// The child owns all snippet execution. The UI owns cancellation and joins before releasing
// the mapped channel; a looping compiler or renderer can therefore be stopped at any time.
#[Swag.NoCopy]
struct PreviewProbe
{
    task:        Swag.Task
    request:     BuildRequest
    folder:      Probe
    channel:     FrameChannel
    cancelled:   u32
    ready:       u32
    reused:      bool
    artifactId:  u64
    compileMs:   u64
    failed:      bool
    diagnostics: String
}

impl PreviewProbe
{
    mtd opDrop()
    {
        Atomic.exchange(&.cancelled, 1)
        .task.wait()
    }

    mtd start(request: BuildRequest, cache: *CompilationCache)
    {
        .request = request
        .task.submit(func|probe = me, cache|()
        {
            catch probe.run(cache) as error
            if error != null
            {
                probe.failed      = true
                probe.diagnostics = appStrings().msg_PreviewNotRun
            }
        })
    }

    mtd run(cache: *CompilationCache) fail
    {
        var lease = cache.acquire(.request)
        if not lease.wait(&.cancelled) do
            return

        .compileMs  = lease.artifact!.elapsedMs
        .artifactId = lease.artifact.id
        .reused     = lease.reused
        if lease.artifact.result.failed
        {
            .failed      = true
            .diagnostics = lease.artifact.result.text
            return
        }

        try .folder.open()
        if Atomic.get(&.cancelled) do
            return

        // The child renders into a mapped frame channel; this side only watches that frames keep coming.
        let channelPath = Path.combine(.folder.session, "frame.bin")
        try .channel.open(channelPath, true)
        let outDir    = Path.combine(lease.artifact.folder.session, "out")
        let childArgs = Env.joinArguments(["--prism-preview-host", channelPath, lease.artifact.binary, .request.kind == .Gui ? "gui" : "pixel"])
        var child     = try Env.startProcess(Env.StartInfo{fileName: Env.executablePath(), arguments: childArgs, workingDirectory: outDir, standardOutput: .Pipe, standardError: .Pipe, consoleWindow: false})
        defer retireProcess(&child)
        Atomic.exchange(&.ready, 1)

        var watch: Time.Stopwatch
        watch.start()
        var lastFrame = 0'u32
        while not try child.tryWaitForExit(20'ms)
        {
            if Atomic.get(&.cancelled) do
                return
            let header    = .channel.header()
            let published = Atomic.get(&header.published)
            if published != lastFrame or published != Atomic.get(&header.consumed)
            {
                lastFrame = published
                watch.restart()
            }

            if watch.elapsedMilliseconds() > StallTimeoutMs
            {
                .failed      = true
                .diagnostics = appStrings().msg_PreviewStalled
                return
            }
        }

        // The child only exits on its own when the snippet failed.
        .failed      = true
        .diagnostics = child.standardOutput()
        .diagnostics.append(child.standardError())
        if .diagnostics.isEmpty() do
            .diagnostics.appendFormat(appStrings().msg_PreviewExited, child.exitCode())
    }
}
