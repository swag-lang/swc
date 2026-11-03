#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

#[Swag.TestTag("golden")]
#test
{
    let fileName = scopeTestDataPath("imageset-real-review.webp")
    var host: Testing.HeadlessHost
    host.setup(1000, 760)
    var session = openTestViewer(Picture.viewerPlugin(), &host.root, fileName)
    let view    = assume cast(*Picture.Panel, session.view)
    completeViewerBackgroundLoad(&host, &view.load)
    let movie = &view.imageView.movie
    Swag.require(view.failureReason.isEmpty() and movie.isValid())
    Swag.require(movie.frameCount == 33 and movie.frame.width == 512 and movie.frame.height == 512)
    Swag.require(movie.currentFrameDuration() == 0.062)
    let first = movie.frame
    view.dockStyle = .Center
    session.commands!.hide()
    session.info!.hide()
    host.root.applyLayout()
    view.imageView.setPaused(true)
    view.imageView.setFrameIndex(32)
    Swag.require(movie.frameIndex == 32 and movie.isPaused and movie.failureReason.isEmpty())
    Swag.require(not Slice.equals(first.pixels.toSlice(), movie.frame.pixels.toSlice()))
    view.imageView.setFrameIndex(0)
    Swag.require(movie.frameIndex == 0 and movie.isPaused)
    view.dockStyle = .Center
    session.commands.hide()
    session.info.hide()
    host.root.applyLayout()
    var image = host.render(&host.root)
    assertScopeImageGolden(&image, "imageset-real-review")
}
