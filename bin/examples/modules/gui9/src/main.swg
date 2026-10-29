// Use --dark for Encre or --light for Papier to inspect the dialogs and file browser.
using Core, Gui, Pixel

// GUI9 - showcase of the predefined dialogs and of the reusable FileBrowserCtrl
// composite (the file-browsing control extracted from FileDlg, usable on its own).

const W = 960
const H = 680

var app:           Application
var g_Surface:     *Surface?
var g_View:        *Wnd?
var g_Browser:     *FileBrowserCtrl?
var g_ThemeButton: *PushButton?
var g_StartDir:    String
var g_DarkTheme:   bool

// Shared by every file dialog of the session: each one reopens with the previous
// placement, folder, column widths and recent locations.
var g_FileState: FileDlgState

//
// Modal dialog launchers (run on button click in interactive mode).
//

func onAbout(_: *Button)
{
    with var params: AboutDlgParams
    {
        .surfaceTitle = "About GUI9"
        .contentTitle = "Swag GUI dialogs"
        .identity     = "gui9 · predefined dialogs"
        .message      = "One composition for every predefined box: a floating sheet, its title as the first line, the content in one column and the primary action at the bottom right."
        .surfaceIcon  = app.theme.icon(.About, 18)
        .contentIcon  = app.theme.icon(.About, app.theme.metrics.dialog_TileSize)
    }

    discard AboutDlg.create(unwrap g_Surface, params).doModal()
}

func onMsgOk(_: *Button)
{
    MessageDlg.ok(unwrap g_Surface, "This is a simple information message.")
}

func onMsgOkCancel(_: *Button)
{
    discard MessageDlg.okCancel(unwrap g_Surface, "Apply the pending changes?")
}

func onMsgYesNo(_: *Button)
{
    discard MessageDlg.yesNo(unwrap g_Surface, "Do you enjoy this showcase?")
}

func onMsgYesNoCancel(_: *Button)
{
    discard MessageDlg.yesNoCancel(unwrap g_Surface, "Save the document before closing?")
}

func onMsgConfirm(_: *Button)
{
    discard MessageDlg.confirm(unwrap g_Surface, "This will reset everything.")
}

func onMsgError(_: *Button)
{
    var opt: MessageDlgOptions
    opt.title  = "Cannot mount the virtual disk."
    opt.detail = "Error code: 0x80070017"
    MessageDlg.error(unwrap g_Surface, "The password is incorrect or the container is damaged.", options: opt)
}

func onEditSingle(_: *Button)
{
    var opt: EditDlgOptions
    opt.title   = "Go to Address"
    opt.message = "Decimal, or hexadecimal preceded by 0x."
    opt.text    = "0x0001F400"
    opt.confirmButtonText = "Go"
    discard EditDlg.createSingleLine(unwrap g_Surface, opt).doModal()
}

func onEditMulti(_: *Button)
{
    var opt: EditDlgOptions
    opt.title = "Edit Description"
    opt.text  = "First line\nSecond line"
    discard EditDlg.createMultiLine(unwrap g_Surface, opt).doModal()
}

func onForm(_: *Button)
{
    var opt: FormDlgOptions
    opt.title = "Change Profile"
    opt.confirmButtonText = "Apply"

    let dlg = FormDlg.create(unwrap g_Surface, opt)
    discard dlg.form.addTextField("Name", "Ada", placeholder: "Display name")
    discard dlg.form.addPasswordField("Password",
                                      placeholder: "Optional password",
                                      help: "Leave empty to keep the current password.")
    let role = dlg.form.addChoiceField("Role")
    role.addItem("Developer")
    role.addItem("Designer")
    role.setSelectedIndex(0, false)
    dlg.form.computeLayout()
    discard dlg.doModal()
}

func onFileOpen(_: *Button)
{
    var opt: FileDlgOptions
    opt.mode  = .SelectFile
    opt.state = &g_FileState
    opt.filters.add({name: "All files", extensions: ""})
    opt.filters.add({name: "Images", extensions: ".png;.jpg;.bmp"})
    discard FileDlg.create(unwrap g_Surface, opt).doModal()
}

func onFileSave(_: *Button)
{
    var opt: FileDlgOptions
    opt.mode  = .CreateFile
    opt.state = &g_FileState
    opt.filters.add({name: "Text", extensions: ".txt"})
    discard FileDlg.create(unwrap g_Surface, opt).doModal()
}

func onSelectFolder(_: *Button)
{
    var opt: FileDlgOptions
    opt.mode  = .SelectFolder
    opt.state = &g_FileState
    discard FileDlg.create(unwrap g_Surface, opt).doModal()
}

//
// View
//

func addDlgButton(parent: *Wnd, text: string, fn: func(*Button))
{
    let btn = PushButton.create(parent, text, {0, 0, 220, 32})
    btn.sigPressed += fn
}

func applyTheme()
{
    if g_DarkTheme do
        app.theme.setDark()
    else do
        app.theme.setLight()

    let btn = g_ThemeButton
    if btn do
        btn.setText(g_DarkTheme ? "Switch to Papier" : "Switch to Encre")

    app.notifyThemeChanged()
}

func toggleTheme(_: *Button)
{
    g_DarkTheme = not g_DarkTheme
    applyTheme()
}

func createRootView()
{
    let view = g_Surface!.view()
    g_View = view
    view.backgroundStyle = .View

    // Title bar (docked top so the layout reflows on resize).
    with let title = Label.create(unwrap g_View, "GUI9 - Dialogs & FileBrowserCtrl", {0, 0, 0, 46})
    {
        .dockStyle = .Top
        .margin    = {16, 12, 16, 0}
        .setTextAlignment(.Left, .Center)
        .style.setFont(view.theme().createDefaultFont(24), .Regular)
    }

    // Content area below the title.
    let content = Wnd.create'Wnd(unwrap g_View, {})
    content.dockStyle       = .Center
    content.backgroundStyle = .Transparent

    // Left: the reusable file-browsing composite (no dialog involved).
    g_StartDir = Env.getSpecialDirectory(.UserDocuments)

    var opt: FileDlgOptions
    opt.mode = .SelectFile
    opt.initialFolder = g_StartDir.toString()
    opt.filters.add({name: "All files", extensions: ""})
    opt.filters.add({name: "Text", extensions: ".txt"})
    opt.shortcuts.add({type: Env.SpecialDirectory.UserDocuments, name: "Documents"})
    opt.shortcuts.add({type: Env.SpecialDirectory.Desktop, name: "Desktop"})

    with g_Browser = FileBrowserCtrl.create(content, opt, {0, 0, 620, 600})
    {
        .dockStyle = .Left
        .margin    = {16, 8, 12, 16}
    }

    // Right: a column of buttons launching each predefined dialog.
    let panel = Wnd.create'Wnd(content, {})
    panel.dockStyle       = .Center
    panel.backgroundStyle = .Transparent

    with let stack = StackLayoutCtrl.create(panel, .Top, {})
    {
        .dockStyle = .Center
        .spacing   = 6
        .setAllPaddings(16)

        addDlgButton(stack, "About", &onAbout)
        addDlgButton(stack, "Message: OK", &onMsgOk)
        addDlgButton(stack, "Message: OK / Cancel", &onMsgOkCancel)
        addDlgButton(stack, "Message: Yes / No", &onMsgYesNo)
        addDlgButton(stack, "Message: Yes / No / Cancel", &onMsgYesNoCancel)
        addDlgButton(stack, "Message: Confirm", &onMsgConfirm)
        addDlgButton(stack, "Message: Error", &onMsgError)
        addDlgButton(stack, "Edit: single line", &onEditSingle)
        addDlgButton(stack, "Edit: multi line", &onEditMulti)
        addDlgButton(stack, "Form", &onForm)
        addDlgButton(stack, "File: open", &onFileOpen)
        addDlgButton(stack, "File: save", &onFileSave)
        addDlgButton(stack, "File: select folder", &onSelectFolder)

        with g_ThemeButton = PushButton.create(stack, "Switch to Encre", {0, 0, 220, 32})
        {
            .sigPressed += &toggleTheme
        }
    }

    view.applyLayout()
}

func onRootEvent(_: *Wnd, evt: IEvent)->bool
{
    if evt is DestroyEvent
    {
        app.sigFrame.disable()
        g_Surface     = null
        g_View        = null
        g_Browser     = null
        g_ThemeButton = null
        return true
    }

    return false
}

#main
{
    for arg in Env.arguments()
    {
        if arg == "--dark" do
            g_DarkTheme = true
        elif arg == "--light" do
            g_DarkTheme = false
    }

    let flags = SurfaceFlags.LargeCaption |
                SurfaceFlags.MinimizeButton |
                SurfaceFlags.CloseButton |
                SurfaceFlags.Border |
                SurfaceFlags.Resizable
    let surface = try app.createSurface(120, 90, W - 46, H - 31, flags)
    g_Surface = surface
    surface.setTitle("GUI9 dialogs showcase")

    createRootView()
    g_View!.hookOnEvent = &onRootEvent
    applyTheme()

    // In automated test mode we just exercise the composite/build and exit;
    // the modal dialogs require interaction so they are not auto-opened.
    if Env.isSmokeRun() do
        app.maxRunFrame = 30

    applyTheme()
    surface.show()
    app.run()
}
