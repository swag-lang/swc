#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// Load a photo much larger than the viewport and keep zoom and rotation renderable.
#[Swag.TestTag("stress")]
#test
{
    let file = Testing.tempFilePath("scope-large-image-", ".png")
    defer discard catch File.delete(file)
    var source = Image.create(3072, 2048, .RGBA8)
    expect source.save(file)

    var host: Testing.HeadlessHost
    host.setup(820, 520)
    var session = openTestViewer(Picture.viewerPlugin(), &host.root, file,
                                 commandParent: &host.root, actionParent: &host.root)
    Swag.require(session.view != null)
    let view = assume cast(*Picture.Panel, session.view)
    completeViewerBackgroundLoad(&host, &view.load)
    let picture = unwrap view.imageView.picture()
    Swag.require(picture.width == 3072 and picture.height == 2048)

    view.dockStyle = .Center
    view.resize(820, 520)
    view.applyLayout()
    view.imageView.setZoom(2)
    var rendered = host.render(view)
    Swag.require(rendered.isValid() and view.imageView.zoom == 2)

    view.rotateClockwise()
    rendered = host.render(view)
    Swag.require(rendered.isValid() and view.imageView.rotationQuarterTurns == 1)
    view.resetTransform()
    rendered = host.render(view)
    Swag.require(rendered.isValid() and view.imageView.rotationQuarterTurns == 0)
}
