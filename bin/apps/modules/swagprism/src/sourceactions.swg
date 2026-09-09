#global internal

using Core, Gui

// One source toolbar: labels yield to icons before the example selector loses its space.
struct SourceActions
{
    using wnd: Wnd
}

impl SourceActions
{
    mtd layoutFields()
    {
        if .children.count != 4 do
            return
        let compile   = cast(*PushButton) .children[0]
        let format    = cast(*PushButton) .children[1]
        let automatic = cast(*CheckButton) .children[2]
        let examples  = .children[3]
        let rect      = .paddedClientRect()
        compile.setText(rect.width >= 400 ? appStrings().ui_CompileVisible : "")
        format.setText(rect.width >= 560 ? appStrings().ui_Format : "")
        automatic.setText(rect.width >= 400 ? appStrings().ui_AutoCompile : "")
        let compileWidth = Math.max(36.0, compile.IWnd.measureContent({}).x)
        let formatWidth  = Math.max(36.0, format.IWnd.measureContent({}).x)
        let autoWidth    = Math.max(36.0, automatic.IWnd.measureContent({}).x)
        var x            = rect.x
        compile.arrange({x, rect.y, compileWidth, 36})
        x += compileWidth + 8
        format.arrange({x, rect.y, formatWidth, 36})
        x += formatWidth + 8
        automatic.arrange({x, rect.y, autoWidth, 36})
        x += autoWidth + 8
        examples.arrange({x, rect.y, Math.max(0.0, rect.right() - x), 36})
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
