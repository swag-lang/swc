#global public
#global namespace Testing

using Swag, Core

// One labelled edit box of a modal to fill before accepting it.
struct AutoEdit
{
    label: String     // Label associated with this value.
    text:  String     // Text associated with this value.
}

// Selects one action performed by the deterministic modal UI driver.
enum AutoStageKind
{
    ModalButton      // Fills staged inputs, then activates a modal button.
    PopupSubMenu     // Opens a submenu by label.
    PopupItem        // Activates a popup item by identifier.
}

// One step of the auto UI driver (see clickModalButtonWhenShown and friends).
struct AutoStage
{
    kind:   AutoStageKind = ModalButton     // Kind associated with this value.
    folder: String                          // Folder associated with this value.
    file:   String                          // File associated with this value.
    label:  String                          // Label associated with this value.
    edits:  Array'AutoEdit                  // Edits associated with this value.
    button: WndId         = undefined       // Button associated with this value.
}

// Hosts deterministic GUI trees, input, timers, modal dialogs, and rendering without an OS window.
struct HeadlessHost
{
    app:        Application     // App associated with this value.
    renderer:   RenderCpu       // Deterministic backend borrowed by `app.renderer`.
    surface:    Surface         // Surface associated with this value.
    surfaceWnd: SurfaceWnd      // Surface wnd associated with this value.
    root:       Wnd             // Root associated with this value.
    #[Swag.Late]
    theme:        *Theme          // Theme associated with this value.
    mousePos:     Math.Point      // Mouse pos associated with this value.
    closed:       bool            // Closed associated with this value.
    commandCount: u32             // Number of command entries.
    lastCommand:  #null WndId     // Last command associated with this value.

    // Auto UI driver state (see clickModalButtonWhenShown and friends). 'autoHandled'
    // is true once every armed stage has completed.
    autoHandled:       bool                // Auto handled associated with this value.
    autoArmed:         bool                // Auto armed associated with this value.
    autoHookInstalled: bool                // Auto hook installed associated with this value.
    autoFrames:        u32                 // Auto frames associated with this value.
    autoMaxFrames:     u32                 // Auto max frames associated with this value.
    autoStages:        Array'AutoStage     // Auto stages associated with this value.
    autoStage:         u32                 // Auto stage associated with this value.
}

impl HeadlessHost
{
    // Initializes a headless application, theme, surface, and root window of the requested size.
    mtd setup(width, height: f32)
    {
        // The OS clipboard is machine-global: another process can hold or rewrite it at
        // any time. Tests use the process-local fake so they stay deterministic and do
        // not clobber the user's own clipboard.
        Clipboard.setFake(true)

        .app.setRenderer(&.renderer)

        .surface.rc = expect .app.renderer.createContext(null, cast(s32) width, cast(s32) height)
        .surface.bindPainterToRenderer(.app.renderer)
        .app.renderer.setCurrentContext(.surface.rc)
        .app.renderer.init()

        .theme = Memory.new'Theme()
        .theme.colors.setDark()
        .theme.setupDefault(.app.renderer)

        .app.theme = .theme
        .app.style.own(.theme)

        .surface.app      = &.app
        .surface.position = {0, 0, width, height}
        .app.mainSurface  = &.surface

        let root = &.root
        root.itf     = cast(IWnd) dref root
        root.type    = Wnd
        root.surface = &.surface
        root.style.share(&.app.style)
        root.position        = {0, 0, width, height}
        root.backgroundStyle = .Dialog
        root.sendCreateEvent()
        root.sendResizeEvent()

        // Wire the surface root window so getTopView()/getTopWnd() resolve to the
        // root view. This enables popup-based widgets (combobox, menus, tabs)
        // which anchor their popups to the top view.
        .surfaceWnd.itf     = cast(IWnd) &.surfaceWnd
        .surfaceWnd.type    = SurfaceWnd
        .surfaceWnd.surface = &.surface
        .surfaceWnd.style.share(&.app.style)
        .surfaceWnd.position      = {0, 0, width, height}
        .surfaceWnd.focusStrategy = .None
        .surface.wnd              = &.surfaceWnd
        .surfaceWnd.view          = root
    }

    // Destroys the hosted window tree, drains queued work, and restores the system clipboard backend.
    mtd shutdown()
    {
        if !.root.isPendingDestroy do
            .root.destroy()
        .pump()
        .surface.destroyRendering()
        Clipboard.setFake(false)
    }

    // Binds another Application instance to this host: the code under test may read
    // its own module-global Application (theme, renderer, options) while events flow
    // through the host. Both applications borrow the host's CPU backend, theme, and
    // style instead of rebuilding resources.
    mtd bindApplication(app: *Application)
    {
        app.setRenderer(.app.renderer)
        app.theme = .theme

        app.style.share(&.app.style)
    }

    private mtd installAutoHook()
    {
        if .autoHookInstalled do
            return
        .autoHookInstalled = true

        .app.sigFrame += func|host = me|(app) { host.driveAutoStages(app) }
    }

    private mtd runAutoStage(stage: *AutoStage)->bool
    {
        switch stage.kind
        {
        case .PopupSubMenu: return .openPopupSubMenu(stage.label.toString())
        case .PopupItem:    return .clickPopupMenuItem(stage.button)
        }

        if !stage.file.isEmpty()
        {
            if !.setModalFileSelection(stage.folder.toString(), stage.file.toString()) do
                return false
        }

        for &edit in stage.edits
        {
            if !.setModalEditText(edit.label.toString(), edit.text.toString()) do
                return false
        }

        return .clickModalButton(stage.button)
    }

    private mtd driveAutoStages(app: *Application)
    {
        if !.autoArmed do
            return

        .autoFrames += 1

        let stage = (notnull .autoStages.buffer) + .autoStage
        if .runAutoStage(stage)
        {
            .autoStage  += 1
            .autoFrames = 0
            if .autoStage == .autoStages.count
            {
                .autoArmed   = false
                .autoHandled = true
            }
        }
        elif .autoFrames > .autoMaxFrames
        {
            // The expected UI never showed up: unblock the pumping loop so the test
            // can fail on 'autoHandled' instead of hanging.
            .autoArmed = false
            if stage.kind == .ModalButton do
                app.exitModal(Dialog.BtnCancel)
            else do
                discard .dismissPopupMenu()
        }
    }

    private mtd armAutoDriver(maxFrames: u32)
    {
        .installAutoHook()
        .autoStages.clear()
        .autoStage     = 0
        .autoMaxFrames = maxFrames
        .autoFrames    = 0
        .autoHandled   = false
        .autoArmed     = true
    }

    private mtd addAutoStage(kind: AutoStageKind, button: #null WndId = null, folder, file, label: #null string = null)->*AutoStage
    {
        let stage = cast(*AutoStage) .autoStages.emplaceInitAddress()
        stage.kind   = kind
        stage.button = button orelse ""
        stage.folder = folder
        stage.file   = file
        stage.label  = label
        return stage
    }

    // Arms the auto UI driver to click 'button' in the topmost modal surface as soon
    // as it exists. Modal loops pump sigFrame every frame, so this drives dialogs
    // opened by the code under test without any test-side closure. If the expected
    // UI never shows up within 'maxFrames' frames, the pending loop is cancelled and
    // 'autoHandled' stays false.
    mtd clickModalButtonWhenShown(button: WndId, maxFrames: u32 = 60)
    {
        .armAutoDriver(maxFrames)
        discard .addAutoStage(.ModalButton, button)
    }

    // Same auto-driver as clickModalButtonWhenShown for a file dialog: fills the
    // modal file browser with 'fileName' (folder + name), then accepts it with
    // 'button'. The folder part must exist.
    mtd acceptModalFileDialog(fileName: string, button: WndId = Dialog.BtnOk, maxFrames: u32 = 60)
    {
        .armAutoDriver(maxFrames)
        let stage = .addAutoStage(.ModalButton, button)
        stage.folder = Path.directoryName(fileName) orelse ""
        stage.file   = Path.fileName(fileName) orelse fileName
    }

    // Arms the auto UI driver to click item 'id' of the captured popup menu as soon
    // as the popup exists (e.g. after a right-click opening a context menu).
    mtd clickPopupMenuItemWhenShown(id: WndId, maxFrames: u32 = 60)
    {
        .armAutoDriver(maxFrames)
        discard .addAutoStage(.PopupItem, id)
    }

    // Arms the auto UI driver to open the submenu labelled 'label' of the captured
    // popup menu as soon as the popup exists.
    mtd openPopupSubMenuWhenShown(label: string, maxFrames: u32 = 60)
    {
        .armAutoDriver(maxFrames)
        discard .addAutoStage(.PopupSubMenu, label: label)
    }

    // Appends one more step to the armed sequence: once the previous step succeeded,
    // click 'button' in the next modal that shows up (e.g. a nested overwrite
    // confirmation after accepting a file dialog).
    mtd thenClickModalButton(button: WndId)
    {
        Debug.assert(.autoArmed)
        discard .addAutoStage(.ModalButton, button)
    }

    // Appends one more step to the armed sequence: click item 'id' of the captured
    // popup menu (e.g. inside a submenu opened by the previous step).
    mtd thenClickPopupMenuItem(id: WndId)
    {
        Debug.assert(.autoArmed)
        discard .addAutoStage(.PopupItem, id)
    }

    // Appends one more step to the armed sequence: open the submenu labelled 'label'
    // of the captured popup menu.
    mtd thenOpenPopupSubMenu(label: string)
    {
        Debug.assert(.autoArmed)
        discard .addAutoStage(.PopupSubMenu, label: label)
    }

    // Fills the labelled edit box of the modal with 'text' before the last armed
    // stage's button is clicked. May be called several times for several edits.
    mtd withModalEdit(label, text: string)
    {
        Debug.assert(.autoArmed and .autoStages.count > 0)
        let stage = (notnull .autoStages.buffer) + .autoStages.count - 1
        let edit  = cast(*AutoEdit) stage.edits.emplaceInitAddress()
        edit.label = label
        edit.text  = text
    }

    // Marks the host closed and queues destruction of its root window.
    mtd close()
    {
        .closed = true
        .root.destroy()
    }

    // Records command count and the most recent identifier at the root event boundary.
    mtd recordCommands()
    {
        .root.hookOnEvent = func|host = me|(wnd, evt)
        {
            switch evt
            {
            case CommandEvent as cmd:
                host.commandCount += 1
                host.lastCommand  = cmd.id
                cmd.accepted      = true
                return true
            }

            return false
        }
    }

    // Records commands and closes the host when `cmdId` reaches the root.
    mtd closeOnCommand(cmdId: WndId)
    {
        .root.hookOnEvent = func|host = me, cmdId|(wnd, evt)
        {
            switch evt
            {
            case CommandEvent as cmd:
                host.commandCount += 1
                host.lastCommand  = cmd.id
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

    // Returns the deepest visible window at a screen position, including surface borders.
    mtd wndAt(pt: Math.Point)->#null *Wnd
    {
        let surface = .app.surfaceAt(pt.x, pt.y)
        if surface
        {
            var surfacePt = pt
            surface.screenToSurface(&surfacePt)
            if !surface.isMaximized and surface.wnd.hitTestBorders(surfacePt) != SizingBorder.None do
                return surface.wnd
            return surface.wnd.windowAt(surfacePt.x, surfacePt.y, true)
        }

        return .root.windowAt(pt.x, pt.y, true)
    }

    // Drains posted events, destruction events, and deferred object deletion.
    mtd pump()
    {
        .pumpPostedEvents()
        .pumpDestroyEvents()
        .deleteQueuedObjects()
    }

    // Sends and drains exactly `count` application frames.
    mtd runFrames(count: u32)
    {
        for count
        {
            .app.sendFrameEvents()
            .pump()
        }
    }

    // Paints the complete hosted tree with the software renderer and returns owned BGRA pixels.
    //
    // Pending events are drained first so layout and widget state match the image. The returned
    // image has the requested host dimensions; callers own it and may compare, encode, or inspect it.
    mtd render()->Pixel.Image
    {
        .pump()
        .surface.invalidate()
        .surface.paintWnd(&.root)
        return .app.renderer.readRenderTarget(&.surface.rt, 0, 0, .surface.rc.width, .surface.rc.height)
    }

    // Fires one active timer immediately and drains resulting queues.
    mtd fireTimer(timer: #null *Timer)
    {
        if !timer or timer.isPendingRemoval do
            return

        .app.duringTimerEvents = true
        var evt = TimerEvent{}
        evt.timer = timer
        timer.target.sendEvent(&evt)
        .app.duringTimerEvents = false

        .pumpTimerQueues()
        .pump()
    }

    // Fires every currently registered timer once.
    mtd fireTimers()
    {
        let timers = .app.timers
        for timer in timers do
            .fireTimer(timer)
    }

    // Sets key state.
    mtd setKeyState(key: Input.Key, pressed: bool)
    {
        .app.keyboard.setCurrentKeyState(key, pressed)
    }

    // Sets modifier keys.
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

    // Moves the simulated pointer and emits enter, leave, and move events.
    mtd moveMouse(pt: Math.Point, modifiers: Input.KeyModifiers = None)
    {
        .app.mouse.setPositions(.app.mouse.currentState.position, pt)

        let target = .mouseTargetAt(pt)

        if target != .app.mouseEnterWnd
        {
            if target do
                .sendMouseEvent(target, .Enter, pt, Input.MouseButton.Left, modifiers)
            if .app.mouseEnterWnd do
                .sendMouseEvent(.app.mouseEnterWnd, .Leave, pt, Input.MouseButton.Left, modifiers)
            .app.mouseEnterWnd = target
        }

        if target do
            .sendMouseEvent(target, .Move, pt, Input.MouseButton.Left, modifiers)
        .mousePos = pt
    }

    // Presses a simulated mouse button at a screen position.
    mtd mouseDown(pt: Math.Point, button: Input.MouseButton = Left, modifiers: Input.KeyModifiers = None)
    {
        .moveMouse(pt, modifiers)

        .app.mouse.setCurrentButtonState(button, true)
        let target = .mouseTargetAt(pt)
        if target do
            .sendMouseEvent(target, .Pressed, pt, button, modifiers)
    }

    // Releases a simulated mouse button at a screen position.
    mtd mouseUp(pt: Math.Point, button: Input.MouseButton = Left, modifiers: Input.KeyModifiers = None)
    {
        .app.mouse.setCurrentButtonState(button, false)
        let target = .mouseTargetAt(pt)
        if target do
            .sendMouseEvent(target, .Released, pt, button, modifiers)
        .pump()
    }

    // Performs one complete simulated mouse click at a screen position.
    mtd click(pt: Math.Point, button: Input.MouseButton = Left, modifiers: Input.KeyModifiers = None)
    {
        .mouseDown(pt, button, modifiers)
        .mouseUp(pt, button, modifiers)
    }

    // Clicks the center of a window.
    mtd clickWnd(wnd: *Wnd, button: Input.MouseButton = Left, modifiers: Input.KeyModifiers = None)
    {
        Debug.assert(wnd != null)

        var pt  = wnd.surfaceRect().center()
        let srf = notnull wnd.surface
        srf.surfaceToScreen(&pt)
        .click(pt, button, modifiers)
    }

    // Activates a visible modal button by identifier and reports whether it was found.
    mtd clickModalButton(id: WndId)->bool
    {
        if .app.modalSurfaces.isEmpty() do
            return false

        var wnd: #null *Wnd
        for #reverse surface in .app.modalSurfaces
        {
            let view = surface.view()
            if !view do
                continue

            wnd = view.childById(notnull id)
            if wnd do
                break
        }

        if !wnd do
            return false
        .clickWnd(wnd)
        return true
    }

    // Finds edit ctrl by label.
    mtd findEditCtrlByLabel(wnd: *Wnd, label: string)->#null *EditCtrl
    {
        if wnd.type == EditCtrl
        {
            let ctrl = cast(*EditCtrl) wnd
            if @isset(ctrl.label) and ctrl.label.name.raw == label do
                return ctrl
        }

        for child in wnd.children
        {
            let ctrl = .findEditCtrlByLabel(child, label)
            if ctrl do
                return ctrl
        }

        return null
    }

    // Sets modal edit text.
    mtd setModalEditText(label: string, text: string)->bool
    {
        if .app.modalSurfaces.isEmpty() do
            return false

        let ctrl = .findEditCtrlByLabel(.app.modalSurfaces.back().wnd.view, label)
        if !ctrl do
            return false

        ctrl.edit.setText(text)
        .pump()
        return true
    }

    // Finds file browser ctrl.
    mtd findFileBrowserCtrl(wnd: *Wnd)->#null *FileBrowserCtrl
    {
        if wnd.type == FileBrowserCtrl do
            return cast(*FileBrowserCtrl) wnd

        for child in wnd.children
        {
            let ctrl = .findFileBrowserCtrl(child)
            if ctrl do
                return ctrl
        }

        return null
    }

    // Sets modal file selection.
    mtd setModalFileSelection(folder: string, fileName: string)->bool
    {
        if .app.modalSurfaces.isEmpty() do
            return false

        var browser: #null *FileBrowserCtrl
        for surface in .app.modalSurfaces
        {
            let view = surface.view()
            if !view do
                continue

            browser = .findFileBrowserCtrl(view)
            if browser do
                break
        }

        if !browser or !@isset(browser.editFile) do
            return false

        if folder
        {
            if !Directory.exists(folder) do
                return false
            browser.setCurrentFolder(folder)
        }

        browser.editFile.setText(fileName)
        .pump()
        return true
    }

    // Returns captured popup menu.
    mtd capturedPopupMenu()->#null *MenuCtrl
    {
        if !.app.mouseCaptureWnd or .app.mouseCaptureWnd.type != MenuCtrl do
            return null

        let menu = cast(#null *MenuCtrl) .app.mouseCaptureWnd
        if menu.bar do
            return null

        return menu
    }

    // Activates an item in the captured popup menu and reports whether it was found.
    mtd clickPopupMenuItem(id: WndId)->bool
    {
        let menu = .capturedPopupMenu()
        if !menu do
            return false

        for itemIt in menu.items
        {
            let item = notnull itemIt
            if item.id != id do
                continue
            if item.hidden or item.separator or item.disabled do
                return false

            let clientRect = menu.clientRect()
            var pt         = Math.Point{clientRect.x + clientRect.width * 0.5, item.pos + item.size * 0.5}
            pt = menu.localToSurface(pt)
            let srf = notnull menu.surface
            srf.surfaceToScreen(&pt)
            .click(pt)
            return true
        }

        return false
    }

    // Moves the simulated pointer to a captured popup item found by label.
    mtd moveToPopupMenuItem(label: string)->bool
    {
        let menu = .capturedPopupMenu()
        if !menu do
            return false

        for itemIt in menu.items
        {
            let item = notnull itemIt
            if item.name.raw != label do
                continue
            if item.hidden or item.separator or item.disabled do
                return false

            let clientRect = menu.clientRect()
            var pt         = Math.Point{clientRect.x + clientRect.width * 0.5, item.pos + item.size * 0.5}
            pt = menu.localToSurface(pt)
            let srf = notnull menu.surface
            srf.surfaceToScreen(&pt)
            .moveMouse(pt)
            return true
        }

        return false
    }

    // Opens a captured popup submenu found by label.
    mtd openPopupSubMenu(label: string)->bool
    {
        let menu = .capturedPopupMenu()
        if !menu do
            return false

        if !.moveToPopupMenuItem(label) do
            return false

        .pumpTimerQueues()
        let timer = menu.timer
        if timer do
            .fireTimer(timer)

        let subMenu = .capturedPopupMenu()
        return subMenu and subMenu != menu
    }

    // Dismisses the captured popup menu, returning false when none is open.
    mtd dismissPopupMenu()->bool
    {
        let menu = .capturedPopupMenu()
        if !menu do
            return false

        let rect = menu.surfaceRect()
        var pt   = Math.Point{rect.right() + 4, rect.bottom() + 4}
        let srf  = notnull menu.surface
        srf.surfaceToScreen(&pt)
        .click(pt)
        return true
    }

    // Performs one simulated double click at a screen position.
    mtd doubleClick(pt: Math.Point, button: Input.MouseButton = Left, modifiers: Input.KeyModifiers = None)
    {
        .moveMouse(pt, modifiers)

        let target = .mouseTargetAt(pt)
        if target do
            .sendMouseEvent(target, .DoubleClick, pt, button, modifiers)
        .pump()
    }

    // Drags a simulated mouse button between two screen positions.
    mtd drag(fromPt, toPt: Math.Point, button: Input.MouseButton = Left, modifiers: Input.KeyModifiers = None)
    {
        .mouseDown(fromPt, button, modifiers)
        .moveMouse(toPt, modifiers)
        .mouseUp(toPt, button, modifiers)
    }

    // Sends one simulated mouse-wheel event at a screen position.
    mtd mouseWheel(pt: Math.Point, delta: s32, modifiers: Input.KeyModifiers = None)
    {
        .moveMouse(pt, modifiers)

        let target = .mouseTargetAt(pt)
        if !target do
            return

        .setModifierKeys(modifiers, true)
        defer
        {
            me.setModifierKeys(modifiers, false)
        }

        var evt = MouseEvent{kind: .Wheel}
        evt.button     = Input.MouseButton.Left
        evt.surfacePos = target.screenToSurface(pt)
        evt.delta.y    = delta
        evt.modifiers  = modifiers
        target.sendEvent(&evt)
        .pump()
    }

    // Gives keyboard focus to a window and drains resulting events.
    mtd focus(wnd: *Wnd)
    {
        .app.keyboardFocusWnd = wnd
    }

    // Sends one complete simulated key press to the focused window.
    mtd keyPress(key: Input.Key, modifiers: Input.KeyModifiers = None)
    {
        let target = notnull .app.keyboardFocusWnd

        .setModifierKeys(modifiers, true)
        .setKeyState(key, true)

        var evt = KeyEvent{kind: .Pressed}
        evt.key       = key
        evt.modifiers = modifiers
        target.sendEvent(&evt)

        if !evt.accepted
        {
            let cmdId = target.keyShortcut(modifiers, key)
            if cmdId != null do
                target.sendCommandEvent(cmdId)
        }

        .setKeyState(key, false)
        evt.kind = .Released
        target.sendEvent(&evt)
        .setModifierKeys(modifiers, false)
        .pump()
    }

    // Sends one simulated shortcut key press with explicit modifiers.
    mtd shortcut(key: Input.Key, modifiers: Input.KeyModifiers)
    {
        .keyPress(key, modifiers)
    }

    // Sends rune.
    mtd sendRune(key: Input.Key, char: rune, modifiers: Input.KeyModifiers = None)
    {
        let target = notnull .app.keyboardFocusWnd

        .setModifierKeys(modifiers, true)
        .setKeyState(key, true)

        var evt = KeyEvent{kind: .Character}
        evt.key       = key
        evt.character = char
        evt.modifiers = modifiers
        target.sendEvent(&evt)

        .setKeyState(key, false)
        .setModifierKeys(modifiers, false)
        .pump()
    }

    // Returns mouse target.
    mtd mouseTargetAt(pt: Math.Point)->#null *Wnd
    {
        if .app.mouseCaptureWnd do
            return .app.mouseCaptureWnd

        let target = .wndAt(pt)
        if !target or !target.isEnabled() do
            return null

        return target
    }

    // Sends mouse event.
    mtd sendMouseEvent(target: *Wnd, kind: MouseEvent.Kind, pt: Math.Point, button: Input.MouseButton, modifiers: Input.KeyModifiers)
    {
        .setModifierKeys(modifiers, true)
        defer
        {
            me.setModifierKeys(modifiers, false)
        }

        var evt = MouseEvent{kind: kind}
        evt.button     = button
        evt.surfacePos = target.screenToSurface(pt)
        evt.delta.x    = pt.x - .mousePos.x
        evt.delta.y    = pt.y - .mousePos.y
        evt.modifiers  = modifiers
        target.sendEvent(&evt)
    }

    // Drains the application's posted event queue.
    mtd pumpPostedEvents()
    {
        let copy = .app.postedEvents
        .app.postedEvents.clear()

        var needUpdateState = false
        for it in copy
        {
            let evt = notnull (it as Event)
            if it is InvalidateEvent
            {
                let target = evt.target
                if target do
                    target.invalidate()
            }
            else do
                .app.sendEvent(it)

            if it is CommandEvent do
                needUpdateState = true

            Memory.delete(evt, notnull evt.type)
        }

        if needUpdateState and !.root.isPendingDestroy do
            .root.updateCommandState()
    }

    // Drains pending window-destruction events.
    mtd pumpDestroyEvents()
    {
        let copy = .app.postDestroy
        .app.postDestroy.clear()

        for wnd in copy do
            .app.destroyWnd(wnd)
    }

    // Applies deferred timer additions and removals.
    mtd pumpTimerQueues()
    {
        for timer in .app.timersToAdd do
            .app.timers.add(timer)
        .app.timersToAdd.clear()

        for timer in .app.timersToDelete
        {
            timer.isPendingRemoval = false
            .app.removeTimer(timer)
        }

        .app.timersToDelete.clear()
    }

    // Releases objects queued for deferred deletion.
    mtd deleteQueuedObjects()
    {
        for item in .app.toDelete do
            Memory.delete(item.ptr, item.type)
        .app.toDelete.clear()
    }
}
