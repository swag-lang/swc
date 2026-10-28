using Core, Gui, Pixel

func createLexerPage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)

    let left = createPanel(parent,
                           "Lexer and wrap",
                           "The source of this page, highlighted by the Swag lexer and wrapped for reading.",
                           layout.left)
    scope
    {
        discard createCodeEditor(left,
                                 editorRect(left),
                                 cast(string, SourcePageLexer),
                                 .ShowFocusSel | .CurLineBorder | .TabToSpaces | .WordWrap)
    }

    let right = createPanel(parent,
                            "Visible blanks",
                            "The source of the styles page with its blanks drawn, so spacing decisions stay visible.",
                            layout.right)
    scope
    {
        discard createCodeEditor(right,
                                 editorRect(right),
                                 cast(string, SourcePageStyles),
                                 .ShowFocusSel | .CurLineBorder | .DrawBlanks | .TabToSpaces)
    }

    let bottom = createPanel(parent,
                             "Document mode",
                             "The same engine can lean toward prose: softer chrome, line spacing and word wrap.",
                             layout.bottom)
    scope
    {
        let ed = createDocumentEditor(bottom,
                                      editorRect(bottom),
                                      "RichEditCtrl keeps the same selection, undo and caret engine in both forms.\n\nThis page switches to the lighter Edit form so wrapped notes feel closer to a document editor than a code viewer.\n\nTry inserting text, selecting blocks and switching themes to check how the control holds up across both palettes.")
        ed.marginLeft  = 24
        ed.marginRight = 24
        ed.lineSpacing = 2
    }
}
