using Core, Gui, Pixel

// Every style takes its ink from a role of the theme: a heading in the body ink, emphasis in the
// soft ink, a chip on the Arc selection ground, a cue in the link ink.
func fillNarrativeEditor(ed: *RichEditCtrl)
{
    let colors = ed.themeColors()
    ed.styles[1].colFg     = colors.text
    ed.styles[1].fontMode  = .Bold
    ed.styles[2].colFg     = colors.softText
    ed.styles[2].fontMode  = .Italic
    ed.styles[3].colFg     = colors.arc
    ed.styles[3].colBk     = colors.selection
    ed.styles[4].colFg     = colors.link
    ed.styles[4].underline = .Underline

    ed.addText("Release notes\n", 1)
    ed.addText("Rich spans let a single control carry headings, ", 0)
    ed.addText("emphasis", 2)
    ed.addText(", compact ", 0)
    ed.addText("badges", 3)
    ed.addText(" and small ", 0)
    ed.addText("underlined cues", 4)
    ed.addText(" without changing widgets.\n\n", 0)
    ed.addText("This is especially useful for inspectors, changelogs and embedded documentation where code and prose live side by side.",
               0)
}

// The status words wear the tones of the notices: information in Arc, a warning in caution, an
// error in critical.
func fillPaletteEditor(ed: *RichEditCtrl)
{
    let colors = ed.themeColors()
    ed.styles[1].colFg     = colors.info
    ed.styles[1].fontMode  = .Bold
    ed.styles[2].colFg     = colors.caution
    ed.styles[2].fontMode  = .Bold
    ed.styles[3].colFg     = colors.critical
    ed.styles[3].fontMode  = .Bold
    ed.styles[4].colFg     = colors.text
    ed.styles[4].colBk     = colors.raised
    ed.styles[5].colFg     = colors.link
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

// A log reads by its times in the faint ink and its levels in the tones of the notices.
func fillLogEditor(ed: *RichEditCtrl)
{
    let colors = ed.themeColors()
    ed.styles[1].colFg = colors.faintText
    ed.styles[2].colFg = colors.info
    ed.styles[3].colFg = colors.caution
    ed.styles[4].colFg = colors.critical
    ed.styles[5].colFg = colors.arc
    ed.styles[5].colBk = colors.selection

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

    let left = createPanel(parent,
                           "Narrative spans",
                           "Foreground, background, weight and underline can all be mixed in one flowing document.",
                           layout.left)
    scope
    {
        let ed = createDocumentEditor(left,
                                      editorRect(left),
                                      "",
                                      .ShowFocusSel | .WordWrap)
        ed.lineSpacing = 2
        fillNarrativeEditor(ed)
    }

    let right = createPanel(parent,
                            "Semantic palette",
                            "Read-only rich text is handy for summaries, diagnostics and inline metadata.",
                            layout.right)
    scope
    {
        let ed = createDemoEditor(right,
                                  editorRect(right),
                                  .ShowFocusSel | .ReadOnly | .WordWrap,
                                  .Edit)
        ed.marginLeft  = 18
        ed.marginRight = 18
        ed.lineSpacing = 2
        fillPaletteEditor(ed)
    }

    let bottom = createPanel(parent,
                             "Styled log",
                             "A single document can read like a live stream once styles are assigned meaningful roles.",
                             layout.bottom)
    scope
    {
        let ed = createDemoEditor(bottom,
                                  editorRect(bottom),
                                  .ShowFocusSel | .ReadOnly | .WordWrap)
        ed.marginLeft  = 18
        ed.marginRight = 18
        ed.lineSpacing = 1
        fillLogEditor(ed)
    }
}
