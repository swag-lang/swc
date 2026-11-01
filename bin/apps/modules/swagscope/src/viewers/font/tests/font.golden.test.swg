#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, TrueType, Viewers

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 720)

    // The commands float over the document only while the pointer asks for them: at rest the
    // window shows the document alone.
    let commands = Wnd.create'Wnd(&host.root)
    commands.hide()

    let fixture = fontFixturePath()
    var result  = openTestViewer(Typeface.viewerPlugin(), &host.root, fixture, commandParent: commands)
    Swag.assert(result.view != null)
    let view = assume cast(*Typeface.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)
    view.dockStyle = .Center

    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)

    // Scrolled, because the document draws in content coordinates and the host translates it: a
    // view that also subtracted the position itself would scroll twice and leave the viewport empty
    // long before the end of the page, which the top of the page would never show.
    let document = view.document
    document.scroll.setScrollPos(0, document.layout.gridTop + document.layout.cellHeight * 1.5)
    var scrolled = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&scrolled, "viewer.font.scrolled")
}
