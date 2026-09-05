#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

#[Swag.TestTag("golden")]
#test
{
    let fileName = Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/imageset-real-review.webp")
    var host: Testing.HeadlessHost
    host.setup(1000, 760)
    defer host.shutdown()
    var session = openTestViewer(imageViewerPlugin(), &host.root, fileName)
    let view = cast(*ImageViewer) session.view!
    completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
    let movie = &view.imageView.movie
    Swag.assert(view.failureReason.isEmpty() and movie.isValid())
    Swag.assert(movie.frameCount == 33 and movie.frame.width == 512 and movie.frame.height == 512)
    Swag.assert(movie.currentFrameDuration() == 0.062)
    let first = movie.frame
    view.dockStyle = .Center
    session.commands!.hide()
    session.info!.hide()
    host.root.applyLayout()
    host.app.timing.minimumDeltaSeconds = 0.062
    host.app.timing.maximumDeltaSeconds = 0.062
    host.app.timing.update()
    host.app.timing.update()
    for 32 do discard host.render(&host.root)
    Swag.assert(movie.frameIndex == 32 and movie.failureReason.isEmpty())
    Swag.assert(Memory.compare(first.pixels.buffer, movie.frame.pixels.buffer, first.byteCount) != 0)
    discard host.render(&host.root)
    Swag.assert(movie.frameIndex == 0 and !movie.isPaused)
    view.imageView.setPaused(true)
    view.dockStyle = .Center
    session.commands!.hide()
    session.info!.hide()
    host.root.applyLayout()
    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "imageset-real-review")
}
