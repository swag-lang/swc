#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Builds every presentation of a list side by side: a plain list with icons, a separator and the
// row under the pointer; columns sorted on a date, with measures in faint mono and a size column
// set to the right; a tree with a branch open and one closed; a list of check boxes with a drop
// on one row; and an empty list saying so.
func buildListModes(host: *Testing.HeadlessHost)
{
    let root  = &host.root
    let theme = root.theme()
    let faint = root.themeColors().faintText

    // A plain list: icons, a separator, the first row selected and the third under the pointer.
    with let plain = ListCtrl.createSimple(root, {24, 20, 250, 220})
    {
        .updateFlags(.HotTrack)
        for name in ["Sketches", "Captures", "Notes.md", "Report.pdf"] do
            .createLine(name, theme.fileGlyph(name, Utf8.indexOf(name, ".") == Swag.U64.Max))
        let rule = .createLine("")
        rule.separator = true
        .createLine("Archive.zip", theme.fileGlyph("Archive.zip", false))
        .computeLayout()
        .selectLine(0)
    }

    // Columns: names, then a date and a size in faint mono, sorted on the date.
    with let columns = ListCtrl.createMultiColumns(root, {298, 20, 520, 150})
    {
        .addColumn("Name", 240)
        .addColumn("Modified", 140)
        .addColumn("Size", 80, align: .Right)
        .updateFlags(.HotTrack | .StretchFirstColumn)
        let names = ["AGENTS.md", "README.md", "design.silence.md"]
        let dates = ["2026-10-28 21:30", "2026-10-26 09:12", "2026-10-20 18:44"]
        let sizes = ["4.10 KB", "7.91 KB", "12.4 KB"]
        for index in 0 until 3
        {
            let line = .createLine(names[index], theme.fileGlyph(names[index], false))
            let date = line.setItem(1, dates[index])
            date.mono    = true
            date.colorFg = faint
            let size = line.setItem(2, sizes[index])
            size.mono      = true
            size.colorFg   = faint
            size.horzAlign = .Right
        }

        .header.setSortIndicator(1, .Descending)
        .computeLayout()
        .selectLine(1)
    }

    // A tree: one branch open on two levels, one closed.
    with let tree = ListCtrl.createSimple(root, {298, 190, 250, 210})
    {
        .updateFlags(.HotTrack)
        let design = .createLine("design", theme.fileGlyph("design", true))
        let imgs   = .createLine("imgs", theme.fileGlyph("imgs", true), design)
        .createLine("gui.controls.png", theme.fileGlyph("gui.controls.png", false), imgs)
        .createLine("README.md", theme.fileGlyph("README.md", false), design)
        let backlog = .createLine("backlog", theme.fileGlyph("backlog", true))
        .createLine("std.gui.md", theme.fileGlyph("std.gui.md", false), backlog)
        .computeLayout()
        .expand(design)
        .expand(imgs)
        .selectLine(2)
    }

    // Check boxes: two checked, and a drop the third row takes.
    with let checks = ListCtrl.createSimple(root, {568, 190, 250, 150})
    {
        for name in ["Encre", "Papier", "Arc", "Voltage"]
        {
            let line = .createLine(name)
            line.canCheck = true
        }

        .computeLayout()
        .setLineChecked(0, notify: false)
        .setLineChecked(2, notify: false)
        .setDropMark(2, .On)
    }

    // An empty list says so where its rows would be.
    let empty = ListCtrl.createSimple(root, {24, 260, 250, 140})
    empty.setEmptyText("Nothing matches")

    host.root.applyLayout()
    host.moveMouse({60, 20 + plain.lineHeight() * 2.5})
    host.settleAnimations()
}

// Encre.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(840, 420)
    buildListModes(&host)

    var image = host.render()
    Pixel.Testing.assertImageGolden(&image, "listctrl.modes.ink")
}

// Papier.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(840, 420)
    host.theme.setLight()
    host.notify(.ThemeChanged)
    buildListModes(&host)

    var image = host.render()
    Pixel.Testing.assertImageGolden(&image, "listctrl.modes.paper")
}

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
