#global #if #command == Swag.CompilerCommand.Test
#global public
using Swag, Core

const GuiTest_CloseWindow = "GuiTest.CloseWindow"

struct GuiTestHost
{
    app:        Application
    surface:    Surface
    root:       Wnd
    theme:      *Theme
    mousePos:   Math.Point
    closed:     bool
}

impl GuiTestHost
{
    mtd setup(width, height: f32)
    {
        .theme = Memory.new'Theme()
        .theme.colors.setDark()

        let style = Memory.new'ThemeStyleRef()
        style.theme = .theme
        style.count = 2

        .app.theme = .theme
        .app.style.refr = style

        .surface.app = &.app
        .surface.position = {0, 0, width, height}

        let root = &.root
        root.itf = cast(IWnd) dref root
        root.type = Wnd
        root.surface = &.surface
        root.style.refr = style
        root.position = {0, 0, width, height}
        root.backgroundStyle = .Dialog
        root.sendCreateEvent()
        root.sendResizeEvent()
    }

    mtd close()
    {
        .closed = true
        .root.destroy()
    }

    mtd closeOnCommand(cmdId: WndId)
    {
        let host = me
        .root.hookOnEvent = func|host, cmdId|(wnd, evt)
        {
            switch evt
            {
            case CommandEvent as cmd where cmd.id == cmdId:
                cmd.accepted = true
                host.close()
                return true
            }

            return false
        }
    }

    mtd wndAt(pt: Math.Point)->#null *Wnd
    {
        return .root.getWndAt(pt.x, pt.y, true)
    }

    mtd pump()
    {
        .pumpPostedEvents()
        .pumpDestroyEvents()
        .deleteQueuedObjects()
    }

    mtd moveMouse(pt: Math.Point, modifiers: Input.KeyModifiers = Zero)
    {
        let target = .getMouseTarget(pt)

        if target != .app.mouseEnterWnd
        {
            if target do
                .sendMouseEvent(target, .MouseEnter, pt, Input.MouseButton.Left, modifiers)
            if .app.mouseEnterWnd do
                .sendMouseEvent(.app.mouseEnterWnd, .MouseLeave, pt, Input.MouseButton.Left, modifiers)
            .app.mouseEnterWnd = target
        }

        if target do
            .sendMouseEvent(target, .MouseMove, pt, Input.MouseButton.Left, modifiers)
        .mousePos = pt
    }

    mtd mouseDown(pt: Math.Point, button: Input.MouseButton = Left, modifiers: Input.KeyModifiers = Zero)
    {
        .moveMouse(pt, modifiers)

        let target = .getMouseTarget(pt)
        Debug.assert(target != null)
        .sendMouseEvent(assume target, .MousePressed, pt, button, modifiers)
    }

    mtd mouseUp(pt: Math.Point, button: Input.MouseButton = Left, modifiers: Input.KeyModifiers = Zero)
    {
        let target = .getMouseTarget(pt)
        Debug.assert(target != null)
        .sendMouseEvent(assume target, .MouseReleased, pt, button, modifiers)
        .pump()
    }

    mtd click(pt: Math.Point, button: Input.MouseButton = Left, modifiers: Input.KeyModifiers = Zero)
    {
        .mouseDown(pt, button, modifiers)
        .mouseUp(pt, button, modifiers)
    }

    mtd focus(wnd: *Wnd)
    {
        .app.keybFocusWnd = wnd
    }

    mtd keyPress(key: Input.Key, modifiers: Input.KeyModifiers = Zero)
    {
        let target = .app.keybFocusWnd
        Debug.assert(target != null)

        var evt = KeyEvent{kind: .KeyPressed}
        evt.key = key
        evt.modifiers = modifiers
        target.sendEvent(&evt)

        evt.kind = .KeyReleased
        target.sendEvent(&evt)
        .pump()
    }

    mtd sendRune(key: Input.Key, char: rune, modifiers: Input.KeyModifiers = Zero)
    {
        let target = .app.keybFocusWnd
        Debug.assert(target != null)

        var evt = KeyEvent{kind: .Rune}
        evt.key = key
        evt.char = char
        evt.modifiers = modifiers
        target.sendEvent(&evt)
        .pump()
    }

    mtd getMouseTarget(pt: Math.Point)->#null *Wnd
    {
        if .app.mouseCaptureWnd do
            return .app.mouseCaptureWnd
        return .wndAt(pt)
    }

    mtd sendMouseEvent(target: *Wnd, kind: MouseEvent.Kind, pt: Math.Point, button: Input.MouseButton, modifiers: Input.KeyModifiers)
    {
        var evt = MouseEvent{kind: kind}
        evt.button = button
        evt.surfacePos = pt
        evt.move.x = pt.x - .mousePos.x
        evt.move.y = pt.y - .mousePos.y
        evt.modifiers = modifiers
        target.sendEvent(&evt)
    }

    mtd pumpPostedEvents()
    {
        let copy = .app.postedEvents
        .app.postedEvents.clear()

        foreach it in copy
        {
            let evt = it as Event
            if it is InvalidateEvent
            {
                if evt.target do
                    evt.target.invalidate()
            }
            else do
                .app.sendEvent(it)

            Memory.delete(evt, evt.type)
        }
    }

    mtd pumpDestroyEvents()
    {
        let copy = .app.postDestroy
        .app.postDestroy.clear()

        foreach wnd in copy do
            .app.destroyWnd(wnd)
    }

    mtd deleteQueuedObjects()
    {
        foreach item in .app.toDelete do
            Memory.delete(item.ptr, item.type)
        .app.toDelete.clear()
    }
}

#test
{
    var host: GuiTestHost
    host.setup(240, 120)
    host.closeOnCommand(GuiTest_CloseWindow)

    let button = PushButton.create(&host.root, "Close", {20, 20, 90, 30}, GuiTest_CloseWindow)

    @assert(!host.closed)
    @assert(host.wndAt({40, 30}) == button)

    host.click({40, 30})

    @assert(host.closed)
    @assert(host.root.isPendingDestroy)
    @assert(host.root.wndFlags.has(.Hidden))
    @assert(host.app.mouseCaptureWnd == null)
}
