// GUI9 - the dialogs instrument.
//
// Every predefined box, opened from one page: the messages, the prompt and the form, every mode
// of the file box and its two questions, and About. Beside them stands `FileBrowserCtrl`, the
// file box's composite used on its own, on the ground of the page. Each box is a lens entry too:
// `Ctrl K` opens the lens, which reaches every box and the appearance. `--light` opens the window
// on Papier.
//
// The file box asks its own two questions: "New folder" from the glyph at the end of its path
// field, "Replace" when a save names a file that exists. Their two launchers open them directly.

using Core, Gui, Pixel

const W = 1240
const H = 820

const PageMargin   = 48.0
const ColumnGap    = 48.0
const BrowserWidth = 560.0
const TitleSize    = 34'u32
const ButtonGap    = 8.0
const GroupGap     = 32.0

const CmdLens = "gui9.lens"

var app:          Application
var g_Surface:    *Surface?
var g_View:       *Wnd?
var g_Title:      *Label?
var g_SubTitle:   *Label?
var g_Browser:    *FileBrowserCtrl?
var g_Launchers:  *Wnd?
var g_Lens:       *Lens.View?
var g_Appearance: *AppearanceButton?
var g_Light:      bool
var g_StartDir:   String

// Shared by every file box of the session: each one reopens with the previous placement, folder,
// column widths and recent locations.
var g_FileState: FileDlgState

//////////////////////////////////////////////
// The boxes
//////////////////////////////////////////////

func onAbout()
{
    with var params: AboutDlgParams
    {
        .surfaceTitle = "About GUI9"
        .contentTitle = "Swag GUI Dialogs"
        .identity     = "gui9 · predefined dialogs"
        .message      = "One composition for every predefined box: a floating sheet, its title as the first line, the content in one column and the primary action at the bottom right."
        .surfaceIcon  = app.theme.icon(.About, 18)
        .contentIcon  = app.theme.icon(.About, app.theme.metrics.dialog_TileSize)
    }

    discard AboutDlg.create(unwrap g_Surface, params).doModal()
}

func onMsgOk() => MessageDlg.ok(unwrap g_Surface, "The capture was copied to the clipboard.")
func onMsgOkCancel() { discard MessageDlg.okCancel(unwrap g_Surface, "Apply the pending changes?") }
func onMsgYesNo() { discard MessageDlg.yesNo(unwrap g_Surface, "Keep the window on top of the others?") }
func onMsgYesNoCancel() { discard MessageDlg.yesNoCancel(unwrap g_Surface, "Save the document before closing?") }
func onMsgConfirm() { discard MessageDlg.confirm(unwrap g_Surface, "Every setting goes back to its default.") }

func onMsgError()
{
    var opt: MessageDlgOptions
    opt.title  = "Cannot mount the virtual disk."
    opt.detail = "Error code: 0x80070017"
    MessageDlg.error(unwrap g_Surface, "The password is incorrect or the container is damaged.", options: opt)
}

func onEditSingle()
{
    var opt: EditDlgOptions
    opt.title   = "Go to Address"
    opt.message = "Decimal, or hexadecimal preceded by 0x."
    opt.text    = "0x0001F400"
    opt.confirmButtonText = "Go"
    discard EditDlg.createSingleLine(unwrap g_Surface, opt).doModal()
}

func onEditMulti()
{
    var opt: EditDlgOptions
    opt.title = "Edit Description"
    opt.text  = "First line\nSecond line"
    discard EditDlg.createMultiLine(unwrap g_Surface, opt).doModal()
}

func onForm()
{
    var opt: FormDlgOptions
    opt.title = "Change Profile"
    opt.confirmButtonText = "Apply"

    let dlg = FormDlg.create(unwrap g_Surface, opt)
    discard dlg.form.addTextField("Name", "Ada", placeholder: "Display name")
    discard dlg.form.addPasswordField("Password", placeholder: "Optional password", help: "Leave empty to keep the current password.")
    let role = dlg.form.addChoiceField("Role")
    role.addItem("Developer")
    role.addItem("Designer")
    role.setSelectedIndex(0, false)
    dlg.form.computeLayout()
    discard dlg.doModal()
}

// Opens a file box in `mode`, on `folder` when one is given, else where the last one closed.
func openFileBox(mode: FileDlgMode, folder: string = "", name: string = "")
{
    var opt: FileDlgOptions
    opt.mode          = mode
    opt.state         = &g_FileState
    opt.initialFolder = folder
    opt.initialName   = name
    switch mode
    {
    case .SelectFile, .SelectFiles:
        opt.filters.add({name: "All Files", extensions: ""})
        opt.filters.add({name: "Images", extensions: ".png;.jpg;.bmp"})

    case .CreateFile:
        opt.filters.add({name: "PNG Image", extensions: ".png"})
    }

    discard FileDlg.create(unwrap g_Surface, opt).doModal()
}

// Returns an existing capture in a scratch folder, which the Replace question is asked about.
func scratchCapture()->String
{
    let folder = Path.combine(Env.getSpecialDirectory(.Temp).toString(), "swag-gui9")
    discard catch Directory.create(folder.toString(), recurse: true)
    let file = Path.combine(folder.toString(), "capture.png")
    if not File.exists(file.toString()) do
        discard catch File.writeAllText(file.toString(), "A capture standing in for an existing file.")
    return file
}

// Every box of the page, in the order the page and the lens list them.
enum Box
{
    Information
    Question
    YesNo
    YesNoCancel
    Confirm
    Error
    GoToAddress
    EditDescription
    ChangeProfile
    Open
    OpenSeveral
    Save
    ChooseFolder
    NewFolder
    Replace
    About
}

const BoxCount = 16

func boxName(box: Box)->string
{
    switch #complete box
    {
    case .Information:     return "Information"
    case .Question:        return "Question"
    case .YesNo:           return "Yes or No"
    case .YesNoCancel:     return "Yes, No or Cancel"
    case .Confirm:         return "Confirm"
    case .Error:           return "Error"
    case .GoToAddress:     return "Go to Address…"
    case .EditDescription: return "Edit Description…"
    case .ChangeProfile:   return "Change Profile…"
    case .Open:            return "Open…"
    case .OpenSeveral:     return "Open Several…"
    case .Save:            return "Save…"
    case .ChooseFolder:    return "Choose a Folder…"
    case .NewFolder:       return "New Folder…"
    case .Replace:         return "Replace…"
    case .About:           return "About GUI9"
    }
}

// Returns the section label a box stands under.
func boxGroup(box: Box)->string
{
    switch box
    {
    case .Information, .Question, .YesNo, .YesNoCancel, .Confirm, .Error: return "Messages"
    case .GoToAddress, .EditDescription, .ChangeProfile: return "Prompts and forms"
    case .About: return "About"
    }

    return "File box"
}

func openBox(box: Box)
{
    switch #complete box
    {
    case .Information:     onMsgOk()
    case .Question:        onMsgOkCancel()
    case .YesNo:           onMsgYesNo()
    case .YesNoCancel:     onMsgYesNoCancel()
    case .Confirm:         onMsgConfirm()
    case .Error:           onMsgError()
    case .GoToAddress:     onEditSingle()
    case .EditDescription: onEditMulti()
    case .ChangeProfile:   onForm()
    case .Open:            openFileBox(.SelectFile)
    case .OpenSeveral:     openFileBox(.SelectFiles)
    case .Save:            openFileBox(.CreateFile, name: "capture-2026-10-28.png")
    case .ChooseFolder:    openFileBox(.SelectFolder)
    case .NewFolder:       discard FileDlg.askNewFolderName(unwrap g_Surface, Env.getSpecialDirectory(.UserDocuments).toString(), "Documents")
    case .Replace:         discard FileDlg.askReplace(unwrap g_Surface, scratchCapture().toString())
    case .About:           onAbout()
    }
}

//////////////////////////////////////////////
// The page
//////////////////////////////////////////////

// Sets the launchers in their groups: a section label, then the buttons wrapped to the column.
func layoutLaunchers()
{
    let column = unwrap g_Launchers
    let width  = column.clientRect().width
    for child in column.children do
        child.destroy()

    let metrics = column.themeMetrics()
    var y       = 0.0
    var x       = 0.0
    var group   = ""
    for i in BoxCount
    {
        let box = cast(Box, cast(s32, i))
        if boxGroup(box) != group
        {
            if group.count do
                y += metrics.btnPush_Height + GroupGap
            group = boxGroup(box)
            SectionLabel.create(column, group, Math.Rectangle{0, y, width, 20})
            y += 28
            x = 0
        }

        let btn = PushButton.create(column, boxName(box), Math.Rectangle{0, 0, metrics.btnPush_Width, metrics.btnPush_Height})
        btn.fitWidthToLabel(120)
        if x > 0 and x + btn.position.width > width
        {
            x = 0
            y += metrics.btnPush_Height + ButtonGap
        }

        btn.setPosition(Math.Rectangle{x, y, btn.position.width, metrics.btnPush_Height})
        btn.sigPressed += func|box|(_) { openBox(box) }
        x += btn.position.width + ButtonGap
    }
}

// Places the header under the window strip, the browser at the left and the launchers at the
// right, keeping the foot clear for the hint line.
func layoutRootView()
{
    if not g_View or not g_Browser do
        return

    let view    = unwrap g_View
    let metrics = view.themeMetrics()
    let rect    = view.clientRect()
    let top     = view.stripInset()
    let width   = Math.max(rect.width - 2 * PageMargin, 1.0)

    let titleHeight = view.theme().createDefaultFont(TitleSize, .Bold).height
    g_Title!.setPosition(Math.Rectangle{PageMargin, top, width, titleHeight})
    g_SubTitle!.setPosition(Math.Rectangle{PageMargin, top + titleHeight + 4, width, 22})

    let bodyY      = top + titleHeight + 4 + 22 + 32
    let bottom     = rect.height - metrics.hintLine_Bottom - metrics.hintLine_Height - 16
    let bodyHeight = Math.max(bottom - bodyY, 1.0)
    let browserW   = Math.min(BrowserWidth, width * 0.5)
    g_Browser!.setPosition(Math.Rectangle{PageMargin, bodyY, browserW, bodyHeight})

    let columnX = PageMargin + browserW + ColumnGap
    g_Launchers!.setPosition(Math.Rectangle{columnX, bodyY, Math.max(rect.width - PageMargin - columnX, 1.0), bodyHeight})
    layoutLaunchers()
}

// Answers the lens with every box, under the label of its group.
func describeBoxes(results: *Lens.Results)
{
    var section: *Lens.Section?
    var group = ""
    for i in BoxCount
    {
        let box = cast(Box, cast(s32, i))
        if not Lens.match(results.query, boxGroup(box)).matched and not Lens.match(results.query, boxName(box)).matched do
            continue
        if boxGroup(box) != group
        {
            group   = boxGroup(box)
            section = results.addSection(group)
        }

        section!.addEntry(boxName(box)).run = func|box|() { openBox(box) }
    }
}

func onRootEvent(_: *Wnd, evt: IEvent)->bool
{
    switch evt
    {
    case ResizeEvent:
        layoutRootView()

    case CommandEvent as cmd where cmd.id == CmdLens:
        g_Lens!.open()
        cmd.accepted = true
        return true

    case DestroyEvent:
        app.sigFrame.disable()
        g_Surface, g_View, g_Title, g_SubTitle, g_Browser, g_Launchers, g_Lens, g_Appearance = null
    }

    return false
}

func createRootView()
{
    let view = g_Surface!.view()
    g_View = view
    view.backgroundStyle = .Window

    with g_Title = Label.create(view, "Dialogs", {})
    {
        .setTextAlignment(.Left, .Center)
        .style.setFont(view.theme().createDefaultFont(TitleSize, .Bold), .Regular)
    }

    with g_SubTitle = Label.create(view, "Every predefined box, and the file browser they share, on its own.", {}, null, .SecondaryText | .Ellipsis)
    {
        .setTextAlignment(.Left, .Center)
    }

    // The file box's composite, on the ground of the page rather than in a box.
    g_StartDir = Env.getSpecialDirectory(.UserDocuments)
    var opt: FileDlgOptions
    opt.mode = .SelectFile
    opt.initialFolder = g_StartDir.toString()
    opt.filters.add({name: "All Files", extensions: ""})
    opt.filters.add({name: "Text", extensions: ".txt"})
    opt.shortcuts.add({type: Env.SpecialDirectory.UserDocuments, name: "Documents"})
    opt.shortcuts.add({type: Env.SpecialDirectory.Desktop, name: "Desktop"})
    g_Browser = FileBrowserCtrl.create(view, opt)

    with g_Launchers = Wnd.create'Wnd(view, {})
    {
        .backgroundStyle = .Transparent
    }

    with let hint = HintLine.create(view)
    {
        .addHint("Ctrl K", "every box, appearance")
    }

    // The appearance is a lens entry like every box; the button only owns the choice.
    with g_Appearance = AppearanceButton.create(unwrap g_Surface)
    {
        .hide()
        .setAppearanceTheme(g_Light ? .Light : .Dark)
    }

    with g_Lens = Lens.View.create(view)
    {
        .addSource(.None, &describeBoxes)
    }

    g_Appearance!.addToLens(unwrap g_Lens)

    view.registerKeyShortcut(.Control, .K, CmdLens)
    view.hookOnEvent = &onRootEvent
    layoutRootView()
}

var g_SmokeFrame: u32

func onSmokeFrame(_: *Application)
{
    g_SmokeFrame += 1
    if g_SmokeFrame == 15 do
        g_Lens?.open("file")
    elif g_SmokeFrame == 30 do
        g_Lens?.close()
    elif g_SmokeFrame == 40 do
        g_Appearance?.setAppearanceTheme(g_Light ? .Dark : .Light)
}

#main
{
    let surface = try app.createSurface(100, 60, W, H, SurfaceFlags.StandardWindow)
    g_Surface = surface
    surface.setTitle("GUI9 Dialogs")
    surface.minSize = {960, 640}

    for arg in Env.arguments() where arg == "--light" do
        g_Light = true
    createRootView()

    // A smoke run builds the page and the composite, opens the lens once and turns the theme over;
    // the boxes are modal and wait for a hand, so they are left to the reader.
    if Env.isSmokeRun()
    {
        app.maxRunFrame = 60
        app.sigFrame    += &onSmokeFrame
    }

    surface.show()
    app.run()
}
