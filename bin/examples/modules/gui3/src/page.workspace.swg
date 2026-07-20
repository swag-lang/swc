using Core, Gui, Pixel

func createWorkspacePage(parent: #nonull *Wnd)
{
    let panel = createPanel(parent, "Workspace composition", "A fuller gui3-only composition: one code pane, one note pane and one read-only preview pane.", getFullPageRect(parent))
    let rect = panel.getClientRect()

    // This page keeps only the enclosing panel and the splitter bars: every
    // richedit/splitter frame border is removed so the panes read as a single
    // continuous composition.
    let split = SplitterCtrl.create(panel, {18, 88, rect.width - 36, rect.height - 106}, vertical: false)
    split.setFrameFlags(.Zero, .Borders | .FocusBorder)

    let code = createCodeEditor(split, {}, cast(#nonull string) SourcePageWorkspace, .ShowFocusSel | .CurLineBorder | .TabToSpaces)
    code.setFrameFlags(.Zero, .Borders | .FocusBorder)
    code.marginLeft  = 18
    code.marginRight = 22
    split.addPane(code, 760)

    let side = SplitterCtrl.create(split, {}, vertical: true)
    side.setFrameFlags(.Zero, .Borders | .FocusBorder)
    let sideItem = split.addPane(side, 420)
    sideItem.tryPreserveSize = true

    let notes = createDocumentEditor(side, {}, "Design note\n\nUse the left editor for source exploration, keep short conclusions here, and reserve the lower pane for a read-only reference.\n\nThis kind of composition is where RichEditCtrl becomes really practical: one implementation, several roles.", .ShowFocusSel | .WordWrap)
    notes.setFrameFlags(.Zero, .Borders | .FocusBorder)
    notes.lineSpacing = 2
    let noteItem = side.addPane(notes, 230)
    noteItem.tryPreserveSize = true

    let preview = createCodeEditor(side, {}, cast(#nonull string) SourcePageLexer, .ShowFocusSel | .ReadOnly | .DrawBlanks | .TabToSpaces)
    preview.setFrameFlags(.Zero, .Borders | .FocusBorder)
    preview.marginLeft  = 16
    preview.marginRight = 20
    side.addPane(preview, 260)
}
