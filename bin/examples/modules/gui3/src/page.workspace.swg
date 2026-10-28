using Core, Gui, Pixel

func createWorkspacePage(parent: *Wnd)
{
    let panel = createPanel(parent,
                            "Workspace composition",
                            "One code pane, one note pane and one read-only preview, parted by splitter bars alone.",
                            getFullPageRect(parent))

    // Only the splitter bars part the panes: every editor and splitter frame is removed, so the
    // panes read as one composition rather than three boxes.
    let split = SplitterCtrl.create(panel, editorRect(panel), vertical: false)
    split.setFrameFlags(.None, .Borders | .FocusBorder)

    let code = createCodeEditor(split,
                                {},
                                cast(string, SourcePageWorkspace),
                                .ShowFocusSel | .CurLineBorder | .TabToSpaces)
    code.setFrameFlags(.None, .Borders | .FocusBorder)
    code.marginLeft  = 18
    code.marginRight = 22
    split.addPane(code, 760)

    let side = SplitterCtrl.create(split, {}, vertical: true)
    side.setFrameFlags(.None, .Borders | .FocusBorder)
    let sideItem = split.addPane(side, 420)
    sideItem.preserveSize = true

    let notes = createDocumentEditor(side,
                                     {},
                                     "Design note\n\nUse the left editor for source exploration, keep short conclusions here, and reserve the lower pane for a read-only reference.\n\nThis kind of composition is where RichEditCtrl becomes really practical: one implementation, several roles.",
                                     .ShowFocusSel | .WordWrap)
    notes.setFrameFlags(.None, .Borders | .FocusBorder)
    notes.lineSpacing = 2
    let noteItem = side.addPane(notes, 230)
    noteItem.preserveSize = true

    let preview = createCodeEditor(side,
                                   {},
                                   cast(string, SourcePageLexer),
                                   .ShowFocusSel | .ReadOnly | .DrawBlanks | .TabToSpaces)
    preview.setFrameFlags(.None, .Borders | .FocusBorder)
    preview.marginLeft  = 16
    preview.marginRight = 20
    side.addPane(preview, 260)
}
