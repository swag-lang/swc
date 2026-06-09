using Core, Gui, Pixel

func createLexerPage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)

    let left = createPanel(parent, "Lexer + wrap", "This page now renders gui3's own source, with wrap enabled for long review-style reading.", layout.left)
    {
        let rect = left.getClientRect()
        discard createCodeEditor(left, {18, 88, rect.width - 36, rect.height - 106}, cast(string) SourcePageLexer, .ShowFocusSel | .CurLineBorder | .TabToSpaces | .WordWrap)
    }

    let right = createPanel(parent, "Visible blanks", "A second local gui3 page is shown with blanks enabled so spacing decisions stay obvious.", layout.right)
    {
        let rect = right.getClientRect()
        discard createCodeEditor(right, {18, 88, rect.width - 36, rect.height - 106}, cast(string) SourcePageStyles, .ShowFocusSel | .CurLineBorder | .DrawBlanks | .TabToSpaces)
    }

    let bottom = createPanel(parent, "Document mode", "The same engine can lean toward prose: softer chrome, line spacing and word wrap.", layout.bottom)
    {
        let rect = bottom.getClientRect()
        let ed = createDocumentEditor(bottom, {20, 92, rect.width - 40, rect.height - 112}, "RichEditCtrl keeps the same selection, undo and caret engine in both forms.\n\nThis page switches to the lighter Edit form so wrapped notes feel closer to a document editor than a code viewer.\n\nTry inserting text, selecting blocks and switching themes to check how the control holds up across both palettes.")
        ed.marginLeft  = 24
        ed.marginRight = 24
        ed.lineSpacing = 2
    }
}
