#global public
using Swag, Core

struct GuiHeadlessHost
{
    app:             Application
    surface:         Surface
    surfaceWnd:      SurfaceWnd
    root:            Wnd
    theme:           *Theme
    mousePos:        Math.Point
    closed:          bool
    commandCount:    u32
    lastCommand:     WndId
}

impl GuiHeadlessHost
{
    mtd setup(width, height: f32)
    {
        .app.renderer.setupHeadless()

        .theme = Memory.new'Theme()
        .theme.colors.setDark()
        .theme.setupDefault(&.app.renderer)

        let style = Memory.new'ThemeStyleRef()
        style.theme = .theme
        style.count = 3

        .app.theme = .theme
        .app.style.refr = style

        .surface.app = &.app
        .surface.position = {0, 0, width, height}
        .surface.rc.width = cast(s32) width
        .surface.rc.height = cast(s32) height
        .app.mainSurface = &.surface

        let root = &.root
        root.itf = cast(IWnd) dref root
        root.type = Wnd
        root.surface = &.surface
        root.style.refr = style
        root.position = {0, 0, width, height}
        root.backgroundStyle = .Dialog
        root.sendCreateEvent()
        root.sendResizeEvent()

        // Wire the surface root window so getTopView()/getTopWnd() resolve to the
        // root view. This enables popup-based widgets (combobox, menus, tabs)
        // which anchor their popups to the top view.
        .surfaceWnd.itf           = cast(IWnd) &.surfaceWnd
        .surfaceWnd.type          = SurfaceWnd
        .surfaceWnd.surface       = &.surface
        .surfaceWnd.style.refr    = style
        .surfaceWnd.position      = {0, 0, width, height}
        .surfaceWnd.focusStrategy = .None
        .surfaceWnd.view          = root
        .surface.wnd              = &.surfaceWnd
    }

    mtd shutdown()
    {
        if !.root.isPendingDestroy do
            .root.destroy()
        .pump()
    }

    mtd close()
    {
        .closed = true
        .root.destroy()
    }

    mtd recordCommands()
    {
        .root.hookOnEvent = func|host = me|(wnd, evt)
        {
            switch evt
            {
            case CommandEvent as cmd:
                host.commandCount += 1
                host.lastCommand = cmd.id
                cmd.accepted = true
                return true
            }

            return false
        }
    }

    mtd closeOnCommand(cmdId: WndId)
    {
        .root.hookOnEvent = func|host = me, cmdId|(wnd, evt)
        {
            switch evt
            {
            case CommandEvent as cmd:
                host.commandCount += 1
                host.lastCommand = cmd.id
                if cmd.id == cmdId
                {
                    cmd.accepted = true
                    host.close()
                    return true
                }
            }

            return false
        }
    }

    mtd wndAt(pt: Math.Point)->#null *Wnd
    {
        let surface = .app.getSurfaceAt(pt.x, pt.y)
        if surface
        {
            var surfacePt = pt
            surface.screenToSurface(&surfacePt)
            if !surface.isMaximized and surface.wnd.hitTestBorders(surfacePt) != SizingBorder.Zero do
                return surface.wnd
            return surface.wnd.getWndAt(surfacePt.x, surfacePt.y, true)
        }

        return .root.getWndAt(pt.x, pt.y, true)
    }

    mtd pump()
    {
        .pumpPostedEvents()
        .pumpDestroyEvents()
        .deleteQueuedObjects()
    }

    mtd runFrames(count: u32)
    {
        for count
        {
            .app.sendFrameEvents()
            .pump()
        }
    }

    mtd fireTimer(timer: *Timer)
    {
        if !timer or timer.toDelete do
            return

        .app.duringTimerEvents = true
        var evt = TimerEvent{}
        evt.timer = timer
        timer.target.sendEvent(&evt)
        .app.duringTimerEvents = false

        .pumpTimerQueues()
        .pump()
    }

    mtd fireTimers()
    {
        let timers = .app.timers
        foreach timer in timers do
            .fireTimer(timer)
    }

    mtd setKeyState(key: Input.Key, pressed: bool)
    {
        .app.keyb.currentState.pressed[key] = pressed
    }

    mtd setModifierKeys(modifiers: Input.KeyModifiers, pressed: bool)
    {
        if modifiers & .Shift
        {
            .setKeyState(.Shift, pressed)
            .setKeyState(.LShift, pressed)
        }

        if modifiers & .Control
        {
            .setKeyState(.Control, pressed)
            .setKeyState(.LControl, pressed)
        }

        if modifiers & .Alt
        {
            .setKeyState(.MenuCtrl, pressed)
            .setKeyState(.LMenu, pressed)
        }
    }

    mtd moveMouse(pt: Math.Point, modifiers: Input.KeyModifiers = Zero)
    {
        .app.mouse.previousState.position = .app.mouse.currentState.position
        .app.mouse.currentState.position  = pt

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

        .app.mouse.currentState.pressed[button] = true
        let target = .getMouseTarget(pt)
        if target do
            .sendMouseEvent(target, .MousePressed, pt, button, modifiers)
    }

    mtd mouseUp(pt: Math.Point, button: Input.MouseButton = Left, modifiers: Input.KeyModifiers = Zero)
    {
        .app.mouse.currentState.pressed[button] = false
        let target = .getMouseTarget(pt)
        if target do
            .sendMouseEvent(target, .MouseReleased, pt, button, modifiers)
        .pump()
    }

    mtd click(pt: Math.Point, button: Input.MouseButton = Left, modifiers: Input.KeyModifiers = Zero)
    {
        .mouseDown(pt, button, modifiers)
        .mouseUp(pt, button, modifiers)
    }

    mtd clickWnd(wnd: *Wnd, button: Input.MouseButton = Left, modifiers: Input.KeyModifiers = Zero)
    {
        Debug.assert(wnd != null)

        var pt = wnd.getSurfaceRect().center()
        wnd.surface.surfaceToScreen(&pt)
        .click(pt, button, modifiers)
    }

    mtd clickModalButton(id: WndId)->bool
    {
        if .app.modalSurfaces.count == 0 do
            return false

        let wnd = .app.modalSurfaces.back().wnd.view.getChildById(id)
        if !wnd do
            return false

        .clickWnd(wnd)
        return true
    }

    mtd doubleClick(pt: Math.Point, button: Input.MouseButton = Left, modifiers: Input.KeyModifiers = Zero)
    {
        .moveMouse(pt, modifiers)

        let target = .getMouseTarget(pt)
        if target do
            .sendMouseEvent(target, .MouseDoubleClick, pt, button, modifiers)
        .pump()
    }

    mtd drag(fromPt, toPt: Math.Point, button: Input.MouseButton = Left, modifiers: Input.KeyModifiers = Zero)
    {
        .mouseDown(fromPt, button, modifiers)
        .moveMouse(toPt, modifiers)
        .mouseUp(toPt, button, modifiers)
    }

    mtd mouseWheel(pt: Math.Point, delta: s32, modifiers: Input.KeyModifiers = Zero)
    {
        .moveMouse(pt, modifiers)

        let target = .getMouseTarget(pt)
        if !target do
            return

        .setModifierKeys(modifiers, true)
        defer { me.setModifierKeys(modifiers, false) }

        var evt = MouseEvent{kind: .MouseWheel}
        evt.button = Input.MouseButton.Left
        evt.surfacePos = target.screenToSurface(pt)
        evt.move.y = delta
        evt.modifiers = modifiers
        target.sendEvent(&evt)
        .pump()
    }

    mtd focus(wnd: *Wnd)
    {
        .app.keybFocusWnd = wnd
    }

    mtd keyPress(key: Input.Key, modifiers: Input.KeyModifiers = Zero)
    {
        let target = .app.keybFocusWnd
        Debug.assert(target != null)

        .setModifierKeys(modifiers, true)
        .setKeyState(key, true)

        var evt = KeyEvent{kind: .KeyPressed}
        evt.key = key
        evt.modifiers = modifiers
        target.sendEvent(&evt)

        if !evt.accepted
        {
            let cmdId = target.getKeyShortcut(modifiers, key)
            if cmdId != null do
                target.sendCommandEvent(cmdId)
        }

        .setKeyState(key, false)
        evt.kind = .KeyReleased
        target.sendEvent(&evt)
        .setModifierKeys(modifiers, false)
        .pump()
    }

    mtd shortcut(key: Input.Key, modifiers: Input.KeyModifiers)
    {
        .keyPress(key, modifiers)
    }

    mtd sendRune(key: Input.Key, char: rune, modifiers: Input.KeyModifiers = Zero)
    {
        let target = .app.keybFocusWnd
        Debug.assert(target != null)

        .setModifierKeys(modifiers, true)
        .setKeyState(key, true)

        var evt = KeyEvent{kind: .Rune}
        evt.key = key
        evt.char = char
        evt.modifiers = modifiers
        target.sendEvent(&evt)

        .setKeyState(key, false)
        .setModifierKeys(modifiers, false)
        .pump()
    }

    mtd getMouseTarget(pt: Math.Point)->#null *Wnd
    {
        if .app.mouseCaptureWnd do
            return .app.mouseCaptureWnd

        let target = .wndAt(pt)
        if !target or !target.isEnabled() do
            return null

        return target
    }

    mtd sendMouseEvent(target: *Wnd, kind: MouseEvent.Kind, pt: Math.Point, button: Input.MouseButton, modifiers: Input.KeyModifiers)
    {
        .setModifierKeys(modifiers, true)
        defer { me.setModifierKeys(modifiers, false) }

        var evt = MouseEvent{kind: kind}
        evt.button = button
        evt.surfacePos = target.screenToSurface(pt)
        evt.move.x = pt.x - .mousePos.x
        evt.move.y = pt.y - .mousePos.y
        evt.modifiers = modifiers
        target.sendEvent(&evt)
    }

    mtd pumpPostedEvents()
    {
        let copy = .app.postedEvents
        .app.postedEvents.clear()

        var needUpdateState = false
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

            if it is CommandEvent do
                needUpdateState = true

            Memory.delete(evt, evt.type)
        }

        if needUpdateState and !.root.isPendingDestroy do
            .root.updateCommandState()
    }

    mtd pumpDestroyEvents()
    {
        let copy = .app.postDestroy
        .app.postDestroy.clear()

        foreach wnd in copy do
            .app.destroyWnd(wnd)
    }

    mtd pumpTimerQueues()
    {
        foreach timer in .app.timersToAdd do
            .app.timers.add(timer)
        .app.timersToAdd.clear()

        foreach timer in .app.timersToDelete
        {
            timer.toDelete = false
            .app.deleteTimer(timer)
        }
        .app.timersToDelete.clear()
    }

    mtd deleteQueuedObjects()
    {
        foreach item in .app.toDelete do
            Memory.delete(item.ptr, item.type)
        .app.toDelete.clear()
    }
}
