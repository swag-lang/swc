#global public
#global namespace Testing
using Swag, Core

// One labelled edit box of a modal to fill before accepting it.
struct AutoEdit
{
    label:      String
    text:       String
}

enum AutoStageKind
{
    ModalButton         // fill the file browser/edits if any, then click a modal button
    PopupSubMenu        // open a submenu of the captured popup menu by label
    PopupItem           // click an item of the captured popup menu by id
}

// One step of the auto UI driver (see clickModalButtonWhenShown and friends).
struct AutoStage
{
    kind:       AutoStageKind = ModalButton
    folder:     String
    file:       String
    label:      String
    edits:      Array'AutoEdit
    button: WndId = undefined
}

struct HeadlessHost
{
    app:                  Application
    surface:              Surface
    surfaceWnd:           SurfaceWnd
    root:                 Wnd
    theme:                #null *Theme
    mousePos:             Math.Point
    closed:               bool
    commandCount:         u32
    lastCommand:          #null WndId

    // Auto UI driver state (see clickModalButtonWhenShown and friends). 'autoHandled'
    // is true once every armed stage has completed.
    autoHandled:          bool
    autoArmed:            bool
    autoHookInstalled:    bool
    autoFrames:           u32
    autoMaxFrames:        u32
    autoStages:           Array'AutoStage
    autoStage:            u32
}

impl HeadlessHost
{
    mtd setup(width, height: f32)
    {
        // The OS clipboard is machine-global: another process can hold or rewrite it at
        // any time. Tests use the process-local fake so they stay deterministic and do
        // not clobber the user's own clipboard.
        Clipboard.setFake(true)

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
        Clipboard.setFake(false)
    }

    // Binds another Application instance to this host: the code under test may read
    // its own module-global Application (theme, renderer, options) while events flow
    // through the host. The renderer goes headless and the host's theme and style
    // are shared instead of being rebuilt.
    mtd bindApplication(app: *Application)
    {
        app.renderer.setupHeadless()
        app.theme = .theme

        let style = .app.style.refr
        style.count += 1
        app.style.refr = style
    }

    private mtd installAutoHook()
    {
        if .autoHookInstalled do
            return
        .autoHookInstalled = true

        .app.sigFrame += func|host = me|(app)
        {
            host.driveAutoStages(app)
        }
    }

    private mtd runAutoStage(stage: *AutoStage)->bool
    {
        switch stage.kind
        {
        case PopupSubMenu:
            return .openPopupSubMenu(stage.label.toString())

        case PopupItem:
            return .clickPopupMenuItem(stage.button)
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

        let stage = .autoStages.buffer + .autoStage
        if .runAutoStage(notnull stage)
        {
            .autoStage += 1
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
        stage.folder = Path.getDirectoryName(fileName) orelse ""
        stage.file   = Path.getFileName(fileName) orelse fileName
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
        let stage = .autoStages.buffer + .autoStages.count - 1
        let edit  = cast(*AutoEdit) stage.edits.emplaceInitAddress()
        edit.label = label
        edit.text  = text
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

    mtd fireTimer(timer: #null *Timer)
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
        for timer in timers do
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

        var wnd: #null *Wnd
        for #reverse surface in .app.modalSurfaces
        {
            let view = surface.getView()
            if !view do
                continue

            wnd = view.getChildById(notnull id)
            if wnd do
                break
        }

        if !wnd do
            return false
        .clickWnd(wnd)
        return true
    }

    mtd findEditCtrlByLabel(wnd: *Wnd, label: string)->#null *EditCtrl
    {
        if wnd.type == EditCtrl
        {
            let ctrl = cast(*EditCtrl) wnd
            if ctrl.label and ctrl.label.name.raw == label do
                return ctrl
        }

        for child in wnd.childs
        {
            let ctrl = .findEditCtrlByLabel(child, label)
            if ctrl do
                return ctrl
        }

        return null
    }

    mtd setModalEditText(label: string, text: string)->bool
    {
        if .app.modalSurfaces.count == 0 do
            return false

        let ctrl = .findEditCtrlByLabel(notnull .app.modalSurfaces.back().wnd.view, label)
        if !ctrl do
            return false

        ctrl.edit.setText(text)
        .pump()
        return true
    }

    mtd findFileBrowserCtrl(wnd: *Wnd)->#null *FileBrowserCtrl
    {
        if wnd.type == FileBrowserCtrl do
            return cast(*FileBrowserCtrl) wnd

        for child in wnd.childs
        {
            let ctrl = .findFileBrowserCtrl(child)
            if ctrl do
                return ctrl
        }

        return null
    }

    mtd setModalFileSelection(folder: string, fileName: string)->bool
    {
        if .app.modalSurfaces.count == 0 do
            return false

        var browser: #null *FileBrowserCtrl
        for surface in .app.modalSurfaces
        {
            let view = surface.getView()
            if !view do
                continue

            browser = .findFileBrowserCtrl(view)
            if browser do
                break
        }

        if !browser or !browser.editFile do
            return false

        if folder
        {
            if !Directory.exists(folder) do
                return false
            browser.setCurFolder(folder)
        }

        browser.editFile.setText(fileName)
        .pump()
        return true
    }

    mtd getCapturedPopupMenu()->#null *MenuCtrl
    {
        if !.app.mouseCaptureWnd or .app.mouseCaptureWnd.type != MenuCtrl do
            return null

        let menu = cast(#null *MenuCtrl) .app.mouseCaptureWnd
        if menu.bar do
            return null

        return menu
    }

    mtd clickPopupMenuItem(id: WndId)->bool
    {
        let menu = .getCapturedPopupMenu()
        if !menu do
            return false

        for item in menu.items
        {
            if item.id != id do
                continue
            if item.hidden or item.separator or item.disabled do
                return false

            let clientRect = menu.getClientRect()
            var pt = Math.Point{clientRect.x + clientRect.width * 0.5, item.pos + item.size * 0.5}
            pt = menu.localToSurface(pt)
            menu.surface.surfaceToScreen(&pt)
            .click(pt)
            return true
        }

        return false
    }

    mtd moveToPopupMenuItem(label: string)->bool
    {
        let menu = .getCapturedPopupMenu()
        if !menu do
            return false

        for item in menu.items
        {
            if item.name.raw != label do
                continue
            if item.hidden or item.separator or item.disabled do
                return false

            let clientRect = menu.getClientRect()
            var pt = Math.Point{clientRect.x + clientRect.width * 0.5, item.pos + item.size * 0.5}
            pt = menu.localToSurface(pt)
            menu.surface.surfaceToScreen(&pt)
            .moveMouse(pt)
            return true
        }

        return false
    }

    mtd openPopupSubMenu(label: string)->bool
    {
        let menu = .getCapturedPopupMenu()
        if !menu do
            return false

        if !.moveToPopupMenuItem(label) do
            return false

        .pumpTimerQueues()
        let timer = menu.timer
        if timer do
            .fireTimer(timer)

        let subMenu = .getCapturedPopupMenu()
        return subMenu != null and subMenu != menu
    }

    mtd dismissPopupMenu()->bool
    {
        let menu = .getCapturedPopupMenu()
        if !menu do
            return false

        let rect = menu.getSurfaceRect()
        var pt = Math.Point{rect.right() + 4, rect.bottom() + 4}
        menu.surface.surfaceToScreen(&pt)
        .click(pt)
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
        for it in copy
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

            Memory.delete(evt, notnull evt.type)
        }

        if needUpdateState and !.root.isPendingDestroy do
            .root.updateCommandState()
    }

    mtd pumpDestroyEvents()
    {
        let copy = .app.postDestroy
        .app.postDestroy.clear()

        for wnd in copy do
            .app.destroyWnd(wnd)
    }

    mtd pumpTimerQueues()
    {
        for timer in .app.timersToAdd do
            .app.timers.add(timer)
        .app.timersToAdd.clear()

        for timer in .app.timersToDelete
        {
            timer.toDelete = false
            .app.deleteTimer(timer)
        }
        .app.timersToDelete.clear()
    }

    mtd deleteQueuedObjects()
    {
        for item in .app.toDelete do
            Memory.delete(item.ptr, item.type)
        .app.toDelete.clear()
    }
}
