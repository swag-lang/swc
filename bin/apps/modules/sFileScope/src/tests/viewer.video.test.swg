#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Video

func videoPreviewFile(name: string)->String fail
{
    let fileName = Path.combine(Env.getSpecialDirectory(.Temp).toString(), name)
    let rate     = try FrameRate.create(4, 1)
    var clip     = try Clip.create(160, 90, rate)

    for index in 4
    {
        var frame = Image.create(160, 90, .RGB8)
        frame.fill(index == 0 ? Color.fromRgb(18, 24, 32) : (index == 1 ? Color.fromRgb(56, 189, 248) : (index == 2 ? Color.fromRgb(247, 249, 0) : Color.fromRgb(130, 70, 180))))
        try clip.addFrame(frame)
    }

    try clip.save(fileName.toString())
    return fileName
}

#test
{
    let fileName = expect videoPreviewFile(Format.toString("filescope-video-%.mp4", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()

    let commands = Wnd.create'Wnd(&host.root, {0, 0, 350, 36})
    let request  = ViewerRequest{&host.root, commands, fileName}
    var result: ViewerResult
    createVideoViewer(&request, &result)
    @assert(result.view != null)
    let view = cast(*VideoViewer) result.view!
    @assert(view.video.frameCount() == 4)
    @assert(view.frameIndex == 0 and !view.playing)
    @assert(view.details.indexOf("160") != Swag.U64.Max)
    @assert(view.details.indexOf("4 frames") != Swag.U64.Max)

    view.seekFrame(2)
    @assert(view.frameIndex == 2)
    view.togglePlayback()
    @assert(view.playing)
    view.togglePlayback()
    @assert(!view.playing)
    view.stopPlayback()
    @assert(view.frameIndex == 0 and view.elapsed == 0)
}

#test
{
    let fileName = expect videoPreviewFile("viewer.video.preview.y4m")
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(720, 420)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let commandBar = Wnd.create'Wnd(&host.root, {0, 0, 0, 52})
    commandBar.dockStyle       = .Top
    commandBar.backgroundStyle = .Window
    commandBar.padding         = {16, 8, 16, 8}
    let request = ViewerRequest{&host.root, commandBar, fileName}
    var result: ViewerResult
    createVideoViewer(&request, &result)
    @assert(result.view != null)
    let view = cast(*VideoViewer) result.view!
    view.dockStyle          = .Center
    view.commands.dockStyle = .Right
    view.seekFrame(2)

    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.video.document")
}

#test
{
    let fileName = Gui.Testing.tempFilePath("filescope-video-", ".y4m")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "not a video")

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()
    let request = ViewerRequest{&host.root, &host.root, fileName}
    var result: ViewerResult
    createVideoViewer(&request, &result)
    @assert(result.view == null and result.commands == null)
    @assert(!result.failureReason.isEmpty())
}
