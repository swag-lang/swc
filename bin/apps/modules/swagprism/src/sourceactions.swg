#global internal

using Core, Gui

// The source toolbar: compile, format, automatic compilation, and the example selector.
//
// As the toolbar narrows, the labels yield to their icons before the example selector loses its
// space.
struct SourceActions
{
    using wnd: Wnd

    late
    {
        runButton:    *PushButton
        formatButton: *PushButton
        liveEdit:     *CheckButton
        exampleCombo: *ComboBox
    }
}

impl SourceActions
{
    // Writes the tooltips and example names in the active language, keeping `selected` chosen.
    mtd retranslate(selected: ExampleKind)
    {
        .exampleCombo.clear()
        for label in [appStrings().ui_Plasma, appStrings().ui_Julia, appStrings().ui_GuiExample, appStrings().ui_Dot] do
            .exampleCombo.addItem(label)
        .exampleCombo.setSelectedIndex(cast(u32) selected, notify: false)
        .exampleCombo.toolTip = appStrings().ui_Examples
        .liveEdit.toolTip     = appStrings().ui_LiveEdit
        .formatButton.toolTip = appStrings().ui_FormatHint
        .runButton.toolTip    = appStrings().ui_CompileVisibleHint
        .layoutFields()
    }

    // Labels the buttons for the width the toolbar has, then places them in one row.
    mtd layoutFields()
    {
        // The window lays itself out while its controls are still being created.
        if .exampleCombo == null do
            return

        let rect = .paddedClientRect()
        .runButton.setText(rect.width >= 440 ? appStrings().ui_CompileVisible : "")
        .formatButton.setText(rect.width >= 560 ? appStrings().ui_Format : "")
        .liveEdit.setText(rect.width >= 440 ? appStrings().ui_AutoCompile : "")
        let runWidth    = Math.max(36.0, .runButton.IWnd.measureContent({}).x)
        let formatWidth = Math.max(36.0, .formatButton.IWnd.measureContent({}).x)
        let autoWidth   = Math.max(36.0, .liveEdit.IWnd.measureContent({}).x)
        var x           = rect.x
        .runButton.arrange({x, rect.y, runWidth, 36})
        x += runWidth + 8
        .formatButton.arrange({x, rect.y, formatWidth, 36})
        x += formatWidth + 8
        .liveEdit.arrange({x, rect.y, autoWidth, 36})
        x += autoWidth + 8
        .exampleCombo.arrange({x, rect.y, Math.max(0.0, rect.right() - x), 36})
    }
}

impl IWnd for SourceActions
{
    mtd impl measureContent(available: Math.Point)->Math.Point
    {
        discard available
        return {0, 36}
    }

    mtd impl onLayout() { .layoutFields() }

    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        .layoutFields()
        .wnd.IWnd.onResizeEvent(evt)
    }
}
