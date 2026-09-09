#global internal
#global namespace Pipeline

using Core

// The child owns all snippet execution. The UI owns cancellation and joins before releasing
// the mapped channel; a looping compiler or renderer can therefore be stopped at any time.
#[Swag.NoCopy]
struct PreviewProbe
{
    folder:      Probe
    channel:     FrameChannel
    cancelled:   u32
    ready:       u32
    compileMs:   u64
    failed:      bool
    diagnostics: String
}

impl PreviewProbe
{
    mtd run(source: string, gui: bool, level: Swag.BuildCfgBackendOptimLevel) fail
    {
        try .folder.open()
        let moduleSource = "#import(\"gui\", location: \"swag@std\")\n#run { with let cfg = Swag.compiler().getBuildCfg()! { .backendKind = .Executable; .publishDependencies = true } }\n"
        discard try File.writeAllBytes(Path.combine(.folder.root, "module.swg"), cast(const [..] u8) moduleSource)
        discard try File.writeAllBytes(Path.combine(.folder.root, "src", "probe.swg"), cast(const [..] u8) source)
        discard try File.writeAllBytes(Path.combine(.folder.root, "src", "channel.swg"), #include("framechannel.swg"))
        let runner: const [..] u8 = gui ? cast(const [..] u8) #include("../../datas/preview/gui.txt") : cast(const [..] u8) #include("../../datas/preview/renderer.txt")
        discard try File.writeAllBytes(Path.combine(.folder.root, "src", "runner.swg"), runner)
        let outDir    = Path.combine(.folder.session, "out")
        let arguments = Format.toString("build --num-cores 6 --build-cfg release --optim-level % --module-file \"%/module.swg\" --directory src --out-dir \"%\" --artifact-name prismpreview", cast(u8) level, .folder.root, outDir)
        var watch: Time.Stopwatch
        watch.start()
        let compiler = compilerPath()
        var build    = try Env.startProcess(Env.StartInfo{fileName: compiler.toString(), arguments: arguments.toString(), standardOutput: .Pipe, standardError: .Pipe, consoleWindow: false})
        defer retireProcess(&build)
        while !try build.tryWaitForExit(20'ms)
        {
            if Atomic.get(&.cancelled) do
                return
            if watch.elapsedMilliseconds() > 60000
            {
                .failed      = true
                .diagnostics = "Compilation exceeded 60 seconds."
                return
            }
        }

        .compileMs = watch.elapsedMilliseconds()
        if build.exitCode() != 0
        {
            .failed      = true
            .diagnostics = build.standardOutput()
            .diagnostics.append(build.standardError())
            return
        }

        if Atomic.get(&.cancelled) do
            return
        let channelPath = Path.combine(.folder.session, "frame.bin")
        try .channel.open(channelPath.toString(), true)
        let executable = Path.combine(outDir, "prismpreview.exe")
        let childArgs  = Env.joinArguments([channelPath.toString()])
        var child      = try Env.startProcess(Env.StartInfo{fileName: executable.toString(), arguments: childArgs.toString(), workingDirectory: outDir.toString(), standardOutput: .Pipe, standardError: .Pipe, consoleWindow: false})
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
