using Core, Gui, Pixel

func createModesPage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)

    let left = createPanel(parent, "RichEditCtrl form", "Code-oriented chrome using gui3's own mode page source for a very different visual rhythm.", layout.left)
    {
        let rect = left.getClientRect()
        discard createCodeEditor(left, {18, 88, rect.width - 36, rect.height - 106}, cast(string) SourcePageModes, .ShowFocusSel | .CurLineBorder | .TabToSpaces)
    }

    let right = createPanel(parent, "Edit form", "A softer document presentation for wrapped notes, review summaries and scratch prose.", layout.right)
    {
        let rect = right.getClientRect()
        let ed = createDocumentEditor(right, {18, 88, rect.width - 36, rect.height - 106}, "This variant uses the Edit form.\n\nIt keeps the rich selection model but relaxes the visual framing so notes sit more naturally beside buttons, forms and inspectors.\n\nBecause the control stays the same underneath, switching between prose and code does not mean switching engines.")
        ed.lineSpacing = 2
    }

    let bottom = createPanel(parent, "Flags matrix", "Read-only, blank rendering and wrapping can be combined per instance depending on the job.", layout.bottom)
    {
        let rect = bottom.getClientRect()
        let gutter = 18.0
        let columnWidth = (rect.width - gutter * 4) / 3
        let top = 92.0
        let editorY = top + 28
        let editorHeight = rect.height - editorY - 22

        createCaption(bottom, "Draw blanks", gutter, top, columnWidth)
        let ed0 = createDemoEditor(bottom, {gutter, editorY, columnWidth, editorHeight}, .ShowFocusSel | .DrawBlanks | .TabToSpaces, .Edit)
        ed0.setText("tabs:\tname\tvalue\nspaces: alpha    beta    gamma\n\nVisible blanks are useful when alignment matters.")

        let x1 = gutter * 2 + columnWidth
        createCaption(bottom, "Read only", x1, top, columnWidth)
        let ed1 = createDemoEditor(bottom, {x1, editorY, columnWidth, editorHeight}, .ShowFocusSel | .ReadOnly | .WordWrap)
        ed1.marginLeft  = 16
        ed1.marginRight = 16
        ed1.setText("This panel is read only.\n\nIt still supports selection, copy, theming and the same rendering pipeline as editable instances.")

        let x2 = gutter * 3 + columnWidth * 2
        createCaption(bottom, "Wrapped note", x2, top, columnWidth)
        let ed2 = createDocumentEditor(bottom, {x2, editorY, columnWidth, editorHeight}, "Word wrap can be enabled independently from syntax coloring, which makes the control just as comfortable for editorial notes as it is for code.")
        ed2.lineSpacing = 2
    }
}
