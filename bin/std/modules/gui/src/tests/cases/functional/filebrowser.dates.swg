#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

// Every minute fits the measured date column, including at fractional display scales.
#test
{
    let root = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("folder-dates-%", Guid64.random()))
    for name in ["chouette", "swag-lang"] do
        expect Directory.create(Path.combine(root, name), recurse: true)
    defer discard catch Directory.delete(root, recurse: true)

    var host: Testing.HeadlessHost
    host.setup(720, 260)
    let browser = FileBrowserCtrl.create(&host.root, {mode: .SelectFolder, initialFolder: root, showLocationsPane: false}, {0, 0, 700, 240})
    browser.listCtrl.selectLine(0)
    for scale in [1.0'f32, 1.25, 1.5, 1.75, 2.0]
    {
        host.surface.setDpiScaleRaw(scale)
        host.root.sendResizeEvent()
        for minute in 60
        {
            discard browser.listCtrl.lines[0]!.setItem(1, Format.toString("3 Nov · 13:%{02}", minute))
            discard browser.listCtrl.lines[1]!.setItem(1, "3 Nov · 15:13")
            browser.fitDateColumn()
            browser.listCtrl.computeLayout()
            var format: RichStringFormat
            format.font          = browser.listCtrl.font()
            format.horzAlignment = .Right
            format.flags         = .Clip | .Ellipsis
            for line, idx in browser.listCtrl.lines
            {
                let item = unwrap line!.items[1]
                item.horzAlign = .Right
                item.name.compute()
                Swag.require(item.name.chunks.count > 0)
                Painter.computeLayout(browser.listCtrl.cellTextRect(cast(u32, idx), 1), &item.name, format, scale)
                for &chunk in item.name.chunks
                {
                    Swag.require(chunk.visible)
                    for glyph in chunk.shaped.glyphs do
                        Swag.require(glyph.glyphIndex != chunk.font.glyphIndex('…'), Format.toString("date was ellipsized at scale % for minute %", scale, minute))
                }
            }
        }
    }
}
