#global if #command == Swag.CompilerCommand.Test and WINDOWS and #hastag("vault.preview.benchmark")
#global private

using Core, Gui, Pixel, Video, Viewers

const PreviewBenchmarkCount = 8'u64

#[Swag.Propagate]
func measureVideoOpen(paths: const [..] String)->u64 fail
{
    var timer: Time.Stopwatch
    timer.start()
    for &path in paths
    {
        var reader = Reader.open(path.toString(), pictureOnly: true)
        Swag.require(reader.durationInSeconds() > 0)
    }
    return timer.elapsedMicroseconds()
}

#[Swag.Propagate]
func measureKeyPicture(paths: const [..] String)->u64 fail
{
    var timer: Time.Stopwatch
    timer.start()
    for &path in paths
    {
        var reader = Reader.open(path.toString(), pictureOnly: true)
        let image = reader.decodeKeyPicture(reader.durationInSeconds() * 0.3)
        Swag.require(image.isValid())
    }
    return timer.elapsedMicroseconds()
}

#[Swag.Propagate]
func measureThumbnail(paths: const [..] String)->u64 fail
{
    var timer: Time.Stopwatch
    timer.start()
    for &path in paths
    {
        let image = Film.loadThumbnail(path.toString())
        Swag.require(image.isValid())
    }
    return timer.elapsedMicroseconds()
}

func measureThumbnailParallel(paths: const [..] String)->u64
{
    var failures = 0'u64
    var timer: Time.Stopwatch
    timer.start()
    parallel for |paths, &failures| index in paths.count
    {
        var image: Image
        image = catch Film.loadThumbnail(paths[index].toString())
        {
            Atomic.add(&failures, 1)
            continue
        }
        if not image.isValid() do
            Atomic.add(&failures, 1)
    }
    Swag.require(failures == 0)
    return timer.elapsedMicroseconds()
}

func reportPreviewTime(stage: string, local, mounted: u64)
{
    Console.println(Format.toString("%: local % us, vault % us, ratio %{f2}x",
                                    stage,
                                    local,
                                    mounted,
                                    cast(f64, mounted) / cast(f64, local)))
}

// A large real video makes frame I/O visible instead of hiding it behind a tiny compressed clip.
#[Swag.TestTag("integration.vault.frame.generate")]
#test
{
    let name = Format.toString("frame-pressure-%.mp4", Guid64.random())
    let hostPath = Path.combine(Env.getSpecialDirectory(.Temp), name)

    var frame = Image.create(1920, 1080, .RGB8)
    let pixels = cast([*] u8, frame.pixels.storage())
    var random = 0x12345678'u32
    for index in frame.pixels.count
    {
        random = random ^ (random << 13)
        random = random ^ (random >> 17)
        random = random ^ (random << 5)
        pixels[index] = cast(u8, random >> 24)
    }

    let rate = expect FrameRate.create(24, 1)
    var writer = expect Writer.create(hostPath, 1920, 1080, rate, Mp4.EncodeOptions{quality: 95})
    for 24
    {
        expect writer.addFrame(frame)
    }
    expect writer.end()
    let size = (expect File.info(hostPath)).size
    Swag.require(size > 8 * 1024 * 1024 and size < 160 * 1024 * 1024)
    Console.println(Format.toString("Frame pressure video: % (% bytes)", hostPath, size))
}

// The launcher copies the generated file to the mounted volume after the sandboxed generator exits.
#[Swag.TestTag("integration.vault.frame")]
#test
{
    let hostPath = Env.variable("SWAG_VAULT_PREVIEW_VIDEO")
    let mountRoot = Env.variable("SWAG_VAULT_PREVIEW_ROOT")
    Swag.require(File.exists(hostPath) and Directory.exists(mountRoot))
    let vaultPath = Path.combine(mountRoot, Path.fileName(hostPath) orelse "")
    Swag.require(File.exists(vaultPath))

    var local: [1] String = [hostPath]
    var mounted: [1] String = [vaultPath]
    reportPreviewTime("large video open", expect measureVideoOpen(local), expect measureVideoOpen(mounted))
    reportPreviewTime("large video key picture", expect measureKeyPicture(local), expect measureKeyPicture(mounted))
    var reader = expect Reader.open(hostPath, pictureOnly: true)
    var candidate: Viewers.Film.ThumbnailCandidate
    candidate.image = expect reader.decodeKeyPicture(reader.durationInSeconds() * 0.3)
    candidate.analyze()
    Swag.require(candidate.lively)
    candidate.image.resize(256, 144, .Bilinear)
    let center = candidate.image.pixelColor(128, 72)
    Console.println(Format.toString("First key picture: usable %, lively %, center %/%/%",
                                    candidate.usable,
                                    candidate.lively,
                                    center.r, center.g, center.b))
    reportPreviewTime("large video thumbnail", expect measureThumbnail(local), expect measureThumbnail(mounted))
}

// Compares the same long H.264 video on the host and through a mounted Swag Vault volume.
#[Swag.TestTag("integration.vault.preview")]
#test
{
    let mountRoot = Env.variable("SWAG_VAULT_PREVIEW_ROOT")
    let source    = Env.variable("SWAG_VAULT_PREVIEW_VIDEO")
    Swag.require(Directory.exists(mountRoot) and File.exists(source))

    let hostRoot  = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("scope-preview-%", Guid64.random()))
    let vaultRoot = mountRoot
    expect Directory.create(hostRoot)
    defer expect Directory.delete(hostRoot, recurse: true)

    var hostPaths:  Array'String
    var vaultPaths: Array'String
    for index in PreviewBenchmarkCount
    {
        let name      = Format.toString("film-%{02}.mkv", index)
        let hostPath  = Path.combine(hostRoot, name)
        let vaultPath = Path.combine(vaultRoot, name)
        expect File.duplicate(hostPath, source)
        Swag.require(File.exists(vaultPath))
        hostPaths.add(hostPath)
        vaultPaths.add(vaultPath)
    }

    Console.println("Preview benchmark vault directory: ", vaultRoot)
    reportPreviewTime("open and parse", expect measureVideoOpen(hostPaths.toSlice()), expect measureVideoOpen(vaultPaths.toSlice()))
    reportPreviewTime("open and seek key picture", expect measureKeyPicture(hostPaths.toSlice()), expect measureKeyPicture(vaultPaths.toSlice()))
    reportPreviewTime("complete thumbnail", expect measureThumbnail(hostPaths.toSlice()), expect measureThumbnail(vaultPaths.toSlice()))
    reportPreviewTime("parallel thumbnails", measureThumbnailParallel(hostPaths.toSlice()), measureThumbnailParallel(vaultPaths.toSlice()))
}

// Measures the first visible preview pass through the actual Explorer background pipeline.
#[Swag.TestTag("integration.vault.explorer")]
#test
{
    let mountRoot = Env.variable("SWAG_VAULT_PREVIEW_ROOT")
    Swag.require(Directory.exists(mountRoot))

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.onlineMovies = Env.variable("SWAG_VAULT_PREVIEW_ONLINE") == "1"

    var timer: Time.Stopwatch
    var firstPictureMicroseconds = 0'u64
    var pictured = 0'u64
    timer.start()
    window.openExplorer(mountRoot)
    let explorer = unwrap window.explorer
    for 2000
    {
        host.pump()
        pictured = 0
        for &entry in explorer.entries where entry.texture.isValid()
        {
            pictured += 1
            if not firstPictureMicroseconds do
                firstPictureMicroseconds = timer.elapsedMicroseconds()
        }
        if pictured and pictured == explorer.entries.count do
            break
        Threading.Thread.sleep(20'ms)
    }
    Swag.require(pictured > 0)
    for &entry in explorer.entries where entry.texture.isValid() do
        Swag.require(entry.attempted and not entry.onlinePending)
    Console.println(Format.toString("Explorer previews: % pictured; first in % us; all pictured in % us",
                                    pictured,
                                    firstPictureMicroseconds,
                                    timer.elapsedMicroseconds()))
}
