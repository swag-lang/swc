using Core, Gui, Pixel

// GUI9 - showcase of the predefined dialogs and of the reusable FileBrowserCtrl
// composite (the file-browsing control extracted from FileDlg, usable on its own).

const W = 1120
const H = 760

var app:        Application
var g_Surface:  #null *Surface
var g_View:     #null *Wnd
var g_Browser:  #null *FileBrowserCtrl
var g_StartDir: String

//
// Modal dialog launchers (run on button click in interactive mode).
//

func onMsgOk(_b: #nonull *Button)          { MessageDlg.ok(assume g_Surface, "This is a simple information message.") }
func onMsgOkCancel(_b: #nonull *Button)    { discard MessageDlg.okCancel(assume g_Surface, "Apply the pending changes?") }
func onMsgYesNo(_b: #nonull *Button)       { discard MessageDlg.yesNo(assume g_Surface, "Do you enjoy this showcase?") }
func onMsgYesNoCancel(_b: #nonull *Button) { discard MessageDlg.yesNoCancel(assume g_Surface, "Save the document before closing?") }
func onMsgConfirm(_b: #nonull *Button)     { discard MessageDlg.confirm(assume g_Surface, "This will reset everything.") }
func onMsgError(_b: #nonull *Button)       { MessageDlg.error(assume g_Surface, "Something went wrong while saving.") }

func onEditSingle(_b: #nonull *Button)
{
    with let dlg = EditDlg.createSingleLine(assume g_Surface)
    {
        .setMessage("Enter your name:")
        .setText("John Doe")
        .surface.setTitle("Single line edit")
        .surface.center(assume g_Surface)
    }
    discard dlg.doModal()
}

func onEditMulti(_b: #nonull *Button)
{
    with let dlg = EditDlg.createMultiLine(assume g_Surface)
    {
        .setMessage("Enter a description:")
        .setText("First line\nSecond line")
        .surface.setTitle("Multi line edit")
        .surface.center(assume g_Surface)
    }
    discard dlg.doModal()
}

func onFileOpen(_b: #nonull *Button)
{
    var opt: FileDlgOptions
    opt.mode = .SelectOneFile
    opt.filters.add({"All files", ""})
    opt.filters.add({"Images", ".png;.jpg;.bmp"})
    discard FileDlg.create(assume g_Surface, opt).doModal()
}

func onFileSave(_b: #nonull *Button)
{
    var opt: FileDlgOptions
    opt.mode      = .CreateFile
    opt.btnOkName = "Save"
    opt.filters.add({"Text", ".txt"})
    discard FileDlg.create(assume g_Surface, opt).doModal()
}

func onSelectFolder(_b: #nonull *Button)
{
    var opt: FileDlgOptions
    opt.mode = .SelectFolder
    discard FileDlg.create(assume g_Surface, opt).doModal()
}

//
// View
//

func addDlgButton(parent: #nonull *Wnd, text: #nonull string, fn: func(#nonull *Button))
{
    let btn = PushButton.create(parent, text, {0, 0, 240, 34})
    btn.sigPressed += fn
}

func createRootView()
{
    g_View = g_Surface.getView()
    g_View.backgroundStyle = .View

    // Title bar (docked top so the layout reflows on resize).
    with let title = Label.create(assume g_View, "GUI9 - Dialogs & FileBrowserCtrl", {0, 0, 0, 46})
    {
        .dockStyle         = .Top
        .margin            = {16, 12, 16, 0}
        .horzAlignmentText = .Left
        .vertAlignmentText = .Center
        .style.setFont(g_View.getTheme().createDefaultFont(24), .Regular)
    }

    // Content area below the title.
    let content = Wnd.create'Wnd(assume g_View, {})
    content.dockStyle       = .Center
    content.backgroundStyle = .Transparent

    // Left: the reusable file-browsing composite (no dialog involved).
    g_StartDir = Env.getSpecialDirectory(.UserDocuments)

    var opt: FileDlgOptions
    opt.mode       = .SelectOneFile
    opt.openFolder = g_StartDir.toString()
    opt.filters.add({"All files", ""})
    opt.filters.add({"Text", ".txt"})
    opt.shortcuts.add({Env.SpecialDirectory.UserDocuments, "Documents"})
    opt.shortcuts.add({Env.SpecialDirectory.Desktop, "Desktop"})

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
        .spacing   = 8
        .setAllPaddings(16)

        addDlgButton(stack, "Message: OK", &onMsgOk)
        addDlgButton(stack, "Message: OK / Cancel", &onMsgOkCancel)
        addDlgButton(stack, "Message: Yes / No", &onMsgYesNo)
        addDlgButton(stack, "Message: Yes / No / Cancel", &onMsgYesNoCancel)
        addDlgButton(stack, "Message: Confirm", &onMsgConfirm)
        addDlgButton(stack, "Message: Error", &onMsgError)
        addDlgButton(stack, "Edit: single line", &onEditSingle)
        addDlgButton(stack, "Edit: multi line", &onEditMulti)
        addDlgButton(stack, "File: open", &onFileOpen)
        addDlgButton(stack, "File: save", &onFileSave)
        addDlgButton(stack, "File: select folder", &onSelectFolder)
    }

    g_View.applyLayout()
}

func onRootEvent(_view: #nonull *Wnd, evt: IEvent)->bool
{
    if evt is DestroyEvent
    {
        app.sigFrame.disable()
        g_Surface = null
        g_View    = null
        g_Browser = null
        return true
    }

    return false
}

#main
{
    let flags = SurfaceFlags.BigCaption | SurfaceFlags.MinimizeBtn | SurfaceFlags.CloseBtn | SurfaceFlags.Border | SurfaceFlags.Sizeable
    g_Surface = try app.createSurface(120, 90, W - 46, H - 31, flags)
    g_Surface.setTitle("GUI9 dialogs showcase")

    createRootView()
    g_View.hookOnEvent = &onRootEvent

    // In automated test mode we just exercise the composite/build and exit;
    // the modal dialogs require interaction so they are not auto-opened.
    if Env.hasArg("swag.test") do
        app.maxRunFrame = 30

    g_Surface.show()
    app.run()
}
