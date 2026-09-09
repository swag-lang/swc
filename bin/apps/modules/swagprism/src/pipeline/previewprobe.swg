#global internal
#global namespace Pipeline

using Core

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
            catch probe.run(probe.request, cache) as error
            if error != null
            {
                probe.failed      = true
                probe.diagnostics = "The preview could not be started."
            }
        })
    }

    mtd run(request: BuildRequest, cache: *CompilationCache) fail
    {
        var lease = cache.acquire(request)
        if !lease.wait(&.cancelled) do
            return
        .compileMs  = lease.artifact!.elapsedMs
        .artifactId = lease.artifact!.id
        .reused     = lease.reused
        if lease.artifact!.result.failed
        {
            .failed      = true
            .diagnostics = lease.artifact!.result.text
            return
        }

        try .folder.open()
        var watch: Time.Stopwatch
        if Atomic.get(&.cancelled) do
            return
        let channelPath = Path.combine(.folder.session, "frame.bin")
        try .channel.open(channelPath.toString(), true)
        let executable = Env.executablePath()
        let outDir     = Path.combine(lease.artifact!.folder.session, "out")
        let childArgs  = Env.joinArguments(["--prism-preview-host", channelPath.toString(), lease.artifact!.binary.toString(), request.kind == .Gui ? "gui" : "pixel"])
        var child      = try Env.startProcess(Env.StartInfo{fileName: executable, arguments: childArgs.toString(), workingDirectory: outDir.toString(), standardOutput: .Pipe, standardError: .Pipe, consoleWindow: false})
        defer retireProcess(&child)
        Atomic.exchange(&.ready, 1)
        watch.restart()
        var lastFrame = 0'u32
        while !try child.tryWaitForExit(20'ms)
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

            if watch.elapsedMilliseconds() > 10000
            {
                .failed      = true
                .diagnostics = "The preview did not produce a frame for 10 seconds."
                return
            }
        }

        .failed      = true
        .diagnostics = child.standardOutput()
        .diagnostics.append(child.standardError())
        if .diagnostics.isEmpty() do
            .diagnostics.appendFormat("The preview exited with code %.", child.exitCode())
    }
}
