using Core, Gui, Pixel

func fillNarrativeEditor(ed: *RichEditCtrl)
{
    ed.styles[1].colFg     = Argb.SteelBlue
    ed.styles[1].fontMode  = .Bold
    ed.styles[2].colFg     = Argb.SeaGreen
    ed.styles[2].fontMode  = .Italic
    ed.styles[3].colFg     = Argb.White
    ed.styles[3].colBk     = Color.fromArgb(190, Argb.SteelBlue)
    ed.styles[4].colFg     = Argb.DarkOrange
    ed.styles[4].underline = .Underline

    ed.addText("Release notes\n", 1)
    ed.addText("Rich spans let a single control carry headings, ", 0)
    ed.addText("emphasis", 2)
    ed.addText(", compact ", 0)
    ed.addText("badges", 3)
    ed.addText(" and small ", 0)
    ed.addText("underlined cues", 4)
    ed.addText(" without changing widgets.\n\n", 0)
    ed.addText("This is especially useful for inspectors, changelogs and embedded documentation where code and prose live side by side.", 0)
}

func fillPaletteEditor(ed: *RichEditCtrl)
{
    ed.styles[1].colFg     = Argb.SeaGreen
    ed.styles[1].fontMode  = .Bold
    ed.styles[2].colFg     = Argb.DarkOrange
    ed.styles[2].fontMode  = .Bold
    ed.styles[3].colFg     = Argb.Crimson
    ed.styles[3].fontMode  = .Bold
    ed.styles[4].colFg     = Argb.White
    ed.styles[4].colBk     = Color.fromArgb(190, Argb.MidnightBlue)
    ed.styles[5].colFg     = Argb.Purple
    ed.styles[5].underline = .Underline

    ed.addText("Status palette\n", 4)
    ed.addText("info  ", 1)
    ed.addText("content synchronized\n", 0)
    ed.addText("warn  ", 2)
    ed.addText("long line will wrap in note mode\n", 0)
    ed.addText("error ", 3)
    ed.addText("selection crosses protected range\n\n", 0)
    ed.addText("Links, diagnostics and tiny semantic chips can be modeled with a handful of styles.\n", 5)
}

func fillLogEditor(ed: *RichEditCtrl)
{
    ed.styles[1].colFg = Argb.Gray
    ed.styles[2].colFg = Argb.SeaGreen
    ed.styles[3].colFg = Argb.DarkOrange
    ed.styles[4].colFg = Argb.Crimson
    ed.styles[5].colFg = Argb.White
    ed.styles[5].colBk = Color.fromArgb(165, Argb.SlateGray)

    ed.addText("[08:14:03] ", 1)
    ed.addText("INFO ", 2)
    ed.addText("lexer attached to document buffer\n", 0)

    ed.addText("[08:14:07] ", 1)
    ed.addText("WARN ", 3)
    ed.addText("word wrap enabled for long review note\n", 0)

    ed.addText("[08:14:10] ", 1)
    ed.addText("ERROR ", 4)
    ed.addText("selection overlaps a read-only fragment\n", 0)

    ed.addText("[08:14:12] ", 1)
    ed.addText("TIP ", 5)
    ed.addText("use styles to make dense text scannable without extra widgets", 0)
}

func createStylesPage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)

    let left = createPanel(parent, "Narrative spans", "Foreground, background, weight and underline can all be mixed in one flowing document.", layout.left)
    {
        let rect = left.getClientRect()
        let ed = createDocumentEditor(left, {18, 88, rect.width - 36, rect.height - 106}, "", .ShowFocusSel | .WordWrap)
        ed.lineSpacing = 2
        fillNarrativeEditor(ed)
    }

    let right = createPanel(parent, "Semantic palette", "Read-only rich text is handy for summaries, diagnostics and inline metadata.", layout.right)
    {
        let rect = right.getClientRect()
        let ed = createDemoEditor(right, {18, 88, rect.width - 36, rect.height - 106}, .ShowFocusSel | .ReadOnly | .WordWrap, .Edit)
        ed.marginLeft  = 18
        ed.marginRight = 18
        ed.lineSpacing = 2
        fillPaletteEditor(ed)
    }

    let bottom = createPanel(parent, "Styled log", "A single document can read like a live stream once styles are assigned meaningful roles.", layout.bottom)
    {
        let rect = bottom.getClientRect()
        let ed = createDemoEditor(bottom, {20, 92, rect.width - 40, rect.height - 112}, .ShowFocusSel | .ReadOnly | .WordWrap)
        ed.marginLeft  = 18
        ed.marginRight = 18
        ed.lineSpacing = 1
        fillLogEditor(ed)
    }
}
