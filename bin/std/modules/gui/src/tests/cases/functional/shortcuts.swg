#global if #command == Swag.CompilerCommand.Test
#global private

using Core

const First  = "shortcuts.first"
const Second = "shortcuts.second"
const Source = "shortcuts.source"

func shortcutState(_: *Wnd, evt: IEvent)->bool
{
    if evt is CommandStateEvent as state where state.kind == .Compute
    {
        switch state.id
        {
        case First:  state.name = "First command"
        case Second: state.name = "Second command"
        default:     return false
        }

        state.updatedFields.add(.Name)
        return true
    }

    return false
}

// Local overrides replace every default, including aliases, and survive a new application.
#test
{
    let path = Testing.tempFilePath("gui-shortcuts-", ".scc")
    defer
    {
        catch File.delete(path)
    }

    scope
    {
        var host: Testing.HeadlessHost
        host.setup(800, 600)
        host.root.hookOnEvent = &shortcutState
        host.app.setStatePath(path)
        host.root.registerKeyShortcut(.Control, .F1, First)
        host.root.registerKeyShortcut(.Control, .F2, First)
        host.root.registerKeyShortcut(.Control, .F3, Second)
        var draft: Array'ShortcutOverride
        setShortcutOverride(&draft, First, .Control, .F3)
        setShortcutOverride(&draft, Second, .None, .None)
        expect host.app.updateShortcuts(draft)
        Swag.require(File.exists(path), path)
        Swag.require(host.root.keyShortcut(.Control, .F1) == null)
        Swag.require(host.root.keyShortcut(.Control, .F2) == null)
        Swag.require(host.root.keyShortcut(.Control, .F3) == First)
        let state = host.root.sendComputeCommandStateEvent(Second)
        Swag.require(state.updatedFields.has(.Shortcut) and state.shortcut.isEmpty())
    }

    var host: Testing.HeadlessHost
    host.setup(800, 600)
    host.root.hookOnEvent = &shortcutState
    host.app.setStatePath(path)
    host.root.registerKeyShortcut(.Control, .F1, First)
    host.root.registerKeyShortcut(.Control, .F2, First)
    host.root.registerKeyShortcut(.Control, .F3, Second)
    Swag.require(File.exists(path), path)
    expect host.app.loadState()
    Swag.require(host.root.keyShortcut(.Control, .F3) == First)
    expect host.app.updateShortcuts({})
    Swag.require(host.root.keyShortcut(.Control, .F1) == First)
    Swag.require(host.root.keyShortcut(.Control, .F2) == First)
    Swag.require(host.root.keyShortcut(.Control, .F3) == Second)
}

// Replacing and clearing a system binding changes dispatch and leaves defaults recoverable.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    host.app.setGlobalHotKeysEnabled(false)
    expect host.app.registerUserHotKey(.CtrlShift, .F6, First, &host.root)
    expect host.app.registerUserHotKey(.CtrlShift, .F7, Second, &host.root)
    var draft: Array'ShortcutOverride
    setShortcutOverride(&draft, First, .CtrlShift, .F7)
    var error: Swag.Error
    catch host.app.updateShortcuts(draft) as error
    Swag.require(not error.isEmpty())
    Swag.require(host.app.hotKeyShortcut(.CtrlShift, .F6).id == First)
    Swag.require(host.app.hotKeyShortcut(.CtrlShift, .F7).id == Second)

    setShortcutOverride(&draft, Second, .None, .None)
    expect host.app.updateShortcuts(draft)
    Swag.require(host.app.hotKeyShortcut(.CtrlShift, .F6).id == null)
    Swag.require(host.app.hotKeyShortcut(.CtrlShift, .F7).id == First)
    expect host.app.updateShortcuts({})
    Swag.require(host.app.hotKeyShortcut(.CtrlShift, .F6).id == First)
    Swag.require(host.app.hotKeyShortcut(.CtrlShift, .F7).id == Second)
}

// A chord held outside the managed registry and a write error leave the current binding active.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    host.app.setGlobalHotKeysEnabled(false)
    expect host.app.registerUserHotKey(.CtrlShift, .F6, First, &host.root)
    expect host.app.registerHotKey(.CtrlShift, .F7, Second, &host.root)
    var draft: Array'ShortcutOverride
    setShortcutOverride(&draft, First, .CtrlShift, .F7)
    var error: Swag.Error
    catch host.app.updateShortcuts(draft) as error
    Swag.require(not error.isEmpty())
    Swag.require(host.app.hotKeyShortcut(.CtrlShift, .F7).id == Second)

    let path = Testing.tempFilePath("gui-shortcuts-", ".scc")
    discard expect File.writeAllText(path, "blocked")
    defer catch File.delete(path)
    host.app.setStatePath(Path.combine(path, "preferences.scc"))
    setShortcutOverride(&draft, First, .CtrlShift, .F8)
    var saveError: Swag.Error
    catch host.app.updateShortcuts(draft) as saveError
    Swag.require(not saveError.isEmpty())
    Swag.require(host.app.shortcutOverrides.isEmpty())
    Swag.require(host.app.hotKeyShortcut(.CtrlShift, .F6).id == First)
    Swag.require(host.app.hotKeyShortcut(.CtrlShift, .F8).id == null)
}

// A callback command keeps its identity and replaces its old key before the view handles it.
#test
{
    var oldCount, newCount: u32
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    let lens = Lens.View.create(&host.root)
    host.root.hookOnEvent = func|&oldCount|(_, event)->bool
    {
        if event is KeyEvent as key where key.kind == .Pressed and key.key == .F8
        {
            oldCount += 1
            return true
        }

        return false
    }

    lens.addSource(.Action, func|&newCount|(results)
    {
        with let entry = results.addSection("Document").addEntry("Read next page")
        {
            .bindId     = Source
            .defaultKey = {key: .F8}
            .run        = func|&newCount|() { newCount += 1 }
        }
    })
    host.keyPress(.F8)
    Swag.require(oldCount == 1)
    var draft: Array'ShortcutOverride
    setShortcutOverride(&draft, Source, .Control, .F8, source: true)
    expect host.app.updateShortcuts(draft)
    host.keyPress(.F8)
    Swag.require(oldCount == 1)
    host.keyPress(.F8, .Control)
    Swag.require(newCount == 1)
    Swag.require(host.root.keyShortcutName(Source, "F8") == Input.formatKeyShortcut(.Control, .F8))
    setShortcutOverride(&draft, Source, .None, .None, source: true)
    expect host.app.updateShortcuts(draft)
    Swag.require(host.root.keyShortcutName(Source, "F8").isEmpty())
}

// Searching, capturing a chord already in use, and accepting replacement all work in the editor.
#test
{
    var stage: u32
    var host:  Testing.HeadlessHost
    host.setup(1000, 750)
    host.root.hookOnEvent = &shortcutState
    host.root.registerKeyShortcut(.Control, .F1, First)
    host.root.registerKeyShortcut(.Control, .F3, Second)
    let lens = Lens.View.create(&host.root)
    lens.addCommands("Commands", [First, Second])

    host.app.sigFrame += func|host = &host, &stage|(_)
    {
        if host.app.modalSurfaces.isEmpty() do
            return
        let surface = host.app.modalSurfaces.back()
        switch stage
        {
        case 0:
            let root   = surface.wnd.view
            let filter = assume cast(*EditBox, unwrap root.childById("gui.shortcuts.filter"))
            let list   = assume cast(*ListCtrl, unwrap root.childById("gui.shortcuts.list"))
            let change = assume cast(*PushButton, unwrap root.childById("gui.shortcuts.change"))
            filter.setText("First")
            Swag.require(list.lines.count == 1 and list.selectedLine() != null)
            stage = 1
            change.sigPressed.call(change)
            Swag.require(stage == 3)
            stage = 4
            Swag.require(host.clickModalButton(Dialog.BtnOk))

        case 1:
            Swag.require(host.app.modalSurfaces.count == 2)
            stage = 2
            host.keyPress(.F3, .Control)

        case 2:
            Swag.require(host.app.modalSurfaces.count == 2)
            stage = 3
            Swag.require(host.clickModalButton(Dialog.BtnYes))
        }
    }

    lens.showKeyboardShortcuts()
    host.app.sigFrame.clear()
    Swag.require(stage == 4)
    Swag.require(host.root.keyShortcut(.Control, .F1) == null)
    Swag.require(host.root.keyShortcut(.Control, .F3) == First)
}

// System combinations can be chosen without pressing a shortcut held by another process.
#test
{
    var stage: u32
    var host:  Testing.HeadlessHost
    host.setup(1000, 750)
    host.app.setGlobalHotKeysEnabled(false)
    host.root.hookOnEvent = &shortcutState
    expect host.app.registerUserHotKey(.Control, .F6, First, &host.root)
    let lens = Lens.View.create(&host.root)
    lens.addCommands("Commands", [First])

    host.app.sigFrame += func|host = &host, &stage|(_)
    {
        if host.app.modalSurfaces.isEmpty() do
            return
        let root = host.app.modalSurfaces.back().wnd.view
        switch stage
        {
        case 0:
            let change = assume cast(*PushButton, unwrap root.childById("gui.shortcuts.change"))
            stage = 1
            change.sigPressed.call(change)
            Swag.require(stage == 2)
            stage = 3
            Swag.require(host.clickModalButton(Dialog.BtnOk))

        case 1:
            let mods = assume cast(*ComboBox, unwrap root.childById("gui.shortcuts.modifiers"))
            let keys = assume cast(*ComboBox, unwrap root.childById("gui.shortcuts.key"))
            mods.setSelectedIndex(3)
            for item, index in keys.items where item!.name.text == "F9"
            {
                keys.setSelectedIndex(cast(u32, index))
                break
            }

            stage = 2
            Swag.require(host.clickModalButton(Dialog.BtnOk))
        }
    }

    lens.showKeyboardShortcuts()
    host.app.sigFrame.clear()
    Swag.require(stage == 3)
    Swag.require(host.app.hotKeyShortcut(.Control, .F6).id == null)
    Swag.require(host.app.hotKeyShortcut(.CtrlShift, .F9).id == First)
}
