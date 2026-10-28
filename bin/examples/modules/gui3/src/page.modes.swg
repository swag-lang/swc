using Core, Gui, Pixel

func createModesPage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)

    let left = createPanel(parent,
                           "RichEditCtrl form",
                           "The code form, its current line marked, on the source of this page.",
                           layout.left)
    scope
    {
        discard createCodeEditor(left,
                                 editorRect(left),
                                 cast(string, SourcePageModes),
                                 .ShowFocusSel | .CurLineBorder | .TabToSpaces)
    }

    let right = createPanel(parent,
                            "Edit form",
                            "A softer document presentation for wrapped notes, review summaries and scratch prose.",
                            layout.right)
    scope
    {
        let ed = createDocumentEditor(right,
                                      editorRect(right),
                                      "This variant uses the Edit form.\n\nIt keeps the rich selection model but relaxes the visual framing so notes sit more naturally beside buttons, forms and inspectors.\n\nBecause the control stays the same underneath, switching between prose and code does not mean switching engines.")
        ed.lineSpacing = 2
    }

    let bottom = createPanel(parent,
                             "Flags matrix",
                             "Read-only, blank rendering and wrapping can be combined per instance depending on the job.",
                             layout.bottom)
    scope
    {
        // Three columns on the inset of the section, parted by the gap the sections keep.
        let rect         = bottom.clientRect()
        let columnWidth  = (rect.width - 2 * SectionInset - 2 * SectionGap) / 3
        let top          = 88.0
        let editorY      = top + 28
        let editorHeight = rect.height - editorY

        createCaption(bottom, "Draw blanks", SectionInset, top, columnWidth)
        let ed0 = createDemoEditor(bottom,
                                   Math.Rectangle{SectionInset, editorY, columnWidth, editorHeight},
                                   .ShowFocusSel | .DrawBlanks | .TabToSpaces,
                                   .Edit)
        ed0.setText("tabs:\tname\tvalue\nspaces: alpha    beta    gamma\n\nVisible blanks are useful when alignment matters.")

        let x1 = SectionInset + columnWidth + SectionGap
        createCaption(bottom, "Read only", x1, top, columnWidth)
        let ed1 = createDemoEditor(bottom,
                                   Math.Rectangle{x1, editorY, columnWidth, editorHeight},
                                   .ShowFocusSel | .ReadOnly | .WordWrap)
        ed1.marginLeft  = 16
        ed1.marginRight = 16
        ed1.setText("This panel is read only.\n\nIt still supports selection, copy, theming and the same rendering pipeline as editable instances.")

        let x2 = SectionInset + 2 * (columnWidth + SectionGap)
        createCaption(bottom, "Wrapped note", x2, top, columnWidth)
        let ed2 = createDocumentEditor(bottom,
                                       Math.Rectangle{x2, editorY, columnWidth, editorHeight},
                                       "Word wrap can be enabled independently from syntax coloring, which makes the control just as comfortable for editorial notes as it is for code.")
        ed2.lineSpacing = 2
    }
}
