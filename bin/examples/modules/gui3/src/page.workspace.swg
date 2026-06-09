using Core, Gui, Pixel

func createWorkspacePage(parent: *Wnd)
{
    let panel = createPanel(parent, "Workspace composition", "A fuller surface inspired by the wnd sample: one code pane, one note pane, one preview pane.", getFullPageRect(parent))
    let rect = panel.getClientRect()

    let split = SplitterCtrl.create(panel, {18, 88, rect.width - 36, rect.height - 106}, vertical: false)
    split.setFrameForm(.Round)
    split.setFrameFlags(.FocusBorder)

    let code = createCodeEditor(split, {}, cast(string) SampleLexer, .ShowFocusSel | .CurLineBorder | .TabToSpaces)
    code.marginLeft  = 18
    code.marginRight = 22
    split.addPane(code, 760)

    let side = SplitterCtrl.create(split, {}, vertical: true)
    side.setFrameForm(.Square)
    side.setFrameFlags(.FocusBorder)
    let sideItem = split.addPane(side, 420)
    sideItem.tryPreserveSize = true

    let notes = createDocumentEditor(side, {}, "Design note\n\nUse the left editor for source exploration, keep short conclusions here, and reserve the lower pane for a read-only reference.\n\nThis kind of composition is where RichEditCtrl becomes really practical: one implementation, several roles.", .ShowFocusSel | .WordWrap)
    notes.lineSpacing = 2
    let noteItem = side.addPane(notes, 230)
    noteItem.tryPreserveSize = true

    let preview = createCodeEditor(side, {}, cast(string) SampleWorkspace, .ShowFocusSel | .ReadOnly | .DrawBlanks | .TabToSpaces)
    preview.marginLeft  = 16
    preview.marginRight = 20
    side.addPane(preview, 260)
}
