#global internal
#global namespace Pipeline

using Core, Gui, Pixel

// A shader sees centred coordinates, one unit per half frame height, so its circles stay round.
private const HalfWidth  = cast(f32, FrameChannel.Width) / 2
private const HalfHeight = cast(f32, FrameChannel.Height) / 2

// Snippets run in an isolated process; the renderer is compiled with Prism, once.
// A replacement process gets fresh globals, callbacks and worker state for its module.
func runPreviewHost(channelPath: string, libraryPath: string, gui: bool) fail
{
    Swag.setWorkerCount(6)
    var channel: FrameChannel
    try channel.open(channelPath)
    var library = try NativeLibrary.load(libraryPath)
    let header  = channel.header()
    var host: Gui.Testing.HeadlessHost
    defer if gui do
        host.shutdown()
    var shade: (func(f32, f32, f32)->u32)?
    if gui
    {
        let build = cast(func(*Wnd), library.symbol("prism_build")!)
        host.setup(FrameChannel.Width, FrameChannel.Height)
        host.setReducedMotion(false)
        host.theme.setSwagDark()
        host.notify(.ThemeChanged)
        build(&host.root)
        host.root.applyLayout()
    }
    else
    {
        shade = cast(func(f32, f32, f32)->u32, library.symbol("prism_shade")!)
    }

    var clock: Time.Stopwatch
    clock.start()
    var frame = 0'u32
    for
    {
        channel.waitConsumed()
        var watch: Time.Stopwatch
        watch.start()
        if gui
        {
            let click = Atomic.get(&header.click)
            if click != Atomic.get(&header.clicked)
            {
                host.click({cast(f32, header.clickX), cast(f32, header.clickY)})
                Atomic.exchange(&header.clicked, click)
            }

            host.runFrames(1)
            let image = host.render()
            Memory.copy(channel.pixels(), image.pixels.buffer, FrameChannel.ByteCount)
        }
        else
        {
            let pixels = cast([*] u32, channel.pixels())
            let shader = shade!
            let time   = frame == 0 ? 0.0 : cast(f32, clock.elapsedMicroseconds()) / 1_000_000
            parallel for |pixels, shader, time| y in cast(u64, FrameChannel.Height)
            {
                for x in FrameChannel.Width do
                    pixels[y * FrameChannel.Width + x] = shader((cast(f32, x) - HalfWidth) / HalfHeight,
                                                                (cast(f32, y) - HalfHeight) / HalfHeight,
                                                                time)
            }
        }

        header.renderUs = cast(u32, Math.min(watch.elapsedMicroseconds(), Swag.U32.Max))
        frame += 1
        Atomic.exchange(&header.published, frame)
    }
}

// Also present in the test executable, so preview tests exercise the shipped renderer.
#premain
{
    let arguments = Env.arguments()
    if arguments.count == 5 and arguments[1] == "--prism-preview-host"
    {
        expect runPreviewHost(arguments[2], arguments[3], arguments[4] == "gui")
        Env.exit(0)
    }
}
