#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// The ground of the row under the pointer comes in over a beat, and the one it left goes out.
#test
{
    var host: Testing.HeadlessHost
    host.setup(300, 260)
    host.setReducedMotion(false)

    with let list = ListCtrl.createSimple(&host.root, {0, 0, 280, 240})
    {
        .updateFlags(.HotTrack)
        for name in ["One", "Two", "Three"] do
            .createLine(name)
        .computeLayout()
    }

    host.root.applyLayout()
    let row = list.lineHeight()
    host.moveMouse({40, row * 0.5})
    Swag.assert(list.hotIndex == 0 and list.hotPresence < 1)
    host.finishAnimations()
    Swag.assert(list.hotPresence == 1)

    host.moveMouse({40, row * 1.5})
    Swag.assert(list.hotIndex == 1 and list.leftIndex == 0 and list.leftPresence == 1)
    host.finishAnimations()
    Swag.assert(list.hotPresence == 1 and list.leftPresence == 0)
}

// Files carry the quiet hue of their kind; folders carry the mark of a place.
#test
{
    var host: Testing.HeadlessHost
    host.setup(100, 100)
    let theme  = host.root.theme()
    let colors = host.root.themeColors()
    Swag.assert(theme.fileGlyph("photo.JPG", false).color == colors.fileKind_Image)
    Swag.assert(theme.fileGlyph("film.mkv", false).color == colors.fileKind_Video)
    Swag.assert(theme.fileGlyph("report.pdf", false).color == colors.fileKind_Document)
    Swag.assert(theme.fileGlyph("notes.txt", false).color.a == 0)
    Swag.assert(theme.fileGlyph("Captures", true).color == colors.arc)
}
