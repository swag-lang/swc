// Every widget of the toolkit, in the states its palette answers for, on one wall.
//
// The sheets report what a color is; this page reports what it does. The two together are
// how a palette is judged: a value can be defensible in isolation and still be wrong next
// to the control it borders. Hover and press states are left to the pointer, which is what
// makes this page worth scrolling through by hand rather than only reading.

using Core, Gui, Pixel

const WallPadding = 16.0
const WallGap     = 10.0
const WallLineGap = 12.0
const SectionTop  = 20.0
const SectionHigh = 28.0
const StdHeight   = 30.0
const CaptionWide = 104.0

// Places the widgets of the wall left to right, wrapping at the right edge.
//
// The wall is a catalogue: its rows carry no meaning a hand-written layout would preserve,
// and pinning two hundred rectangles by hand is how a catalogue stops being updated.
struct Flow
{
    #[Swag.Late]
    view: *Wnd

    width: f32     // Usable width, already inside the padding.
    x:     f32     // Left edge of the next widget.
    y:     f32     // Top edge of the current line.
    high:  f32     // Height of the tallest widget of the current line.
}

impl Flow
{
    mtd reset(view: *Wnd, width: f32)
    {
        .view  = view
        .width = Math.max(width - 2 * WallPadding, 1.0)
        .x     = WallPadding
        .y     = WallPadding
        .high  = 0
    }

    // Closes the current line and starts the next one.
    mtd newLine()
    {
        if .high == 0 do
            return
        .y    += .high + WallLineGap
        .x    = WallPadding
        .high = 0
    }

    // Reserves `width` by `height` for the next widget, wrapping when the line is full.
    mtd next(width: f32, height = StdHeight)->Math.Rectangle
    {
        if .x > WallPadding and .x + width > WallPadding + .width do
            .newLine()

        let result = Math.Rectangle{.x, .y, width, height}
        .x    += width + WallGap
        .high = Math.max(.high, height)
        return result
    }

    // Opens a titled family on its own line.
    mtd section(title: string)
    {
        .newLine()
        .y += SectionTop

        let label = Label.create(.view, title, {WallPadding, .y, .width, SectionHigh})
        label.setTextAlignment(.Left, .Center)
        label.style.setFont(app.theme.createDefaultFont(16, .Bold), .Regular)

        .y    += SectionHigh
        .x    = WallPadding
        .high = 0
    }

    // Labels the row that follows, so a reader knows which state each control is in.
    mtd caption(text: string)
    {
        .newLine()
        let label = Label.create(.view, text, .next(CaptionWide, 24), null, .SecondaryText)
        label.setTextAlignment(.Left, .Center)
    }

    // A window sized by the flow, for the controls that place themselves by docking.
    mtd host(width, height: f32)->*Wnd => Wnd.create'Wnd(.view, .next(width, height))

    // Height the content reached, which is the scroll size of the wall.
    mtd const contentHeight()->f32 => .y + .high + WallPadding
}

// The scrolling wall itself.
struct WidgetWall
{
    using scrollWnd: ScrollWnd

    #[Swag.Late]
    view: *Wnd

    flow:  Flow
    built: bool
}

impl WidgetWall
{
    func create(parent: *Wnd)->*WidgetWall
    {
        let result = Wnd.create'WidgetWall(parent, {})
        result.setFrameForm(.Square)
        result.setFrameFlags(.Borders)
        result.view = result.createView'Wnd()
        return result
    }

    // Builds the wall once the view has a width to wrap against.
    //
    // Every control is created enabled or disabled, checked or not, once and for all:
    // rebuilding the wall on a palette switch would drop the pointer state a reader is in
    // the middle of inspecting.
    mtd build()
    {
        if .built or !Swag.isSet(.view) or .view.clientRect().width < 240 do
            return
        .built = true

        .flow.reset(.view, .view.clientRect().width)
        buildDocuments(&.flow)
        buildButtons(&.flow)
        buildChoices(&.flow)
        buildFields(&.flow)
        buildRanges(&.flow)
        buildContainers(&.flow)
        buildText(&.flow)
        buildDialogs(&.flow)
        .setScrollSize(0, .flow.contentHeight())
    }
}

impl IWnd for WidgetWall
{
    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        .scrollWnd.IWnd.onResizeEvent(evt)
        .build()
    }
}

private func buildButtons(flow: *Flow)
{
    flow.section("Push buttons")

    flow.caption("normal")
    for form in [PushButtonForm.Normal, .Default, .Flat, .Strong, .Alternate]
    {
        let btn = PushButton.create(flow.view, "Action", flow.next(116), null, form)
        btn.setIcon(app.theme.icon(.Play, 16))
    }

    flow.caption("disabled")
    for form in [PushButtonForm.Normal, .Default, .Flat, .Strong, .Alternate]
    {
        let btn = PushButton.create(flow.view, "Action", flow.next(116), null, form)
        btn.setIcon(app.theme.icon(.Play, 16))
        btn.disable()
    }

    flow.section("Icon buttons")

    flow.caption("normal")
    IconButton.create(flow.view, app.theme.icon(.Save, 18), flow.next(40))
    IconButton.create(flow.view, app.theme.icon(.Copy, 18), flow.next(40), null, .Flat)

    let checked = IconButton.create(flow.view, app.theme.icon(.Filter, 18), flow.next(40), null, .Toggle)
    checked.setChecked(true)

    let labelled = IconButton.create(flow.view, app.theme.icon(.Export, 18), flow.next(124))
    labelled.setText("Export")
    labelled.setTextPosition(.Right)

    flow.caption("disabled")
    let offPlain = IconButton.create(flow.view, app.theme.icon(.Save, 18), flow.next(40))
    offPlain.disable()

    let offChecked = IconButton.create(flow.view, app.theme.icon(.Filter, 18), flow.next(40), null, .Toggle)
    offChecked.setChecked(true)
    offChecked.disable()
}

private func buildChoices(flow: *Flow)
{
    flow.section("Check and radio buttons")

    flow.caption("normal")
    CheckButton.create(flow.view, "Unchecked", flow.next(140))

    let onCheck = CheckButton.create(flow.view, "Checked", flow.next(140))
    onCheck.setState(.Checked)

    let triCheck = CheckButton.create(flow.view, "Indeterminate", flow.next(160), null, .TriState)
    triCheck.setState(.Indeterminate)

    RadioButton.create(flow.view, "Off", flow.next(100))

    let onRadio = RadioButton.create(flow.view, "On", flow.next(100))
    onRadio.setChecked(true)

    flow.caption("disabled")
    let offCheck = CheckButton.create(flow.view, "Unchecked", flow.next(140))
    offCheck.disable()

    let offOnCheck = CheckButton.create(flow.view, "Checked", flow.next(140))
    offOnCheck.setState(.Checked)
    offOnCheck.disable()

    let offRadio = RadioButton.create(flow.view, "On", flow.next(100))
    offRadio.setChecked(true)
    offRadio.disable()

    flow.section("Toggle buttons")

    flow.caption("normal")
    ToggleButton.create(flow.view, flow.next(56, 26))

    let onToggle = ToggleButton.create(flow.view, flow.next(56, 26))
    onToggle.setChecked(true)

    flow.caption("disabled")
    let offToggle = ToggleButton.create(flow.view, flow.next(56, 26))
    offToggle.disable()

    let offOnToggle = ToggleButton.create(flow.view, flow.next(56, 26))
    offOnToggle.setChecked(true)
    offOnToggle.disable()
}

private func buildFields(flow: *Flow)
{
    flow.section("Edit boxes")

    flow.caption("forms")
    for form in [EditBoxForm.Rectangle, .RoundedRectangle, .Flat, .Transparent]
    {
        let ed = EditBox.create(flow.view, "Editable text", flow.next(180, 32))
        ed.setForm(form)
    }

    flow.caption("states")
    let note = EditBox.create(flow.view, "", flow.next(180, 32))
    note.setPlaceholder("placeholder note")

    let unit = EditBox.create(flow.view, "42", flow.next(140, 32))
    unit.setUnit("kg")

    let readOnly = EditBox.create(flow.view, "Read only", flow.next(180, 32))
    readOnly.updateFlags(.ReadOnly)

    let offEdit = EditBox.create(flow.view, "Disabled", flow.next(180, 32))
    offEdit.disable()

    flow.section("Combo boxes")

    flow.caption("normal")
    let combo = ComboBox.create(flow.view, flow.next(190, 32))
    combo.addItem("First entry")
    combo.addItem("Second entry", null, app.theme.icon(.Filter, 16))
    combo.addSeparator()
    combo.addItem("Third entry")
    combo.setSelectedIndex(0, false)

    let editable = ComboBox.create(flow.view, flow.next(190, 32), mode: .Editable)
    editable.addItem("Editable entry")
    editable.setSelectedIndex(0, false)

    flow.caption("transparent")
    let transparent = ComboBox.create(flow.view, flow.next(190, 32), flags: .TransparentBackground)
    transparent.addItem("Parent ground")
    transparent.setSelectedIndex(0, false)

    flow.caption("disabled")
    let offCombo = ComboBox.create(flow.view, flow.next(190, 32))
    offCombo.addItem("Unavailable")
    offCombo.setSelectedIndex(0, false)
    offCombo.disable()
}

private func buildRanges(flow: *Flow)
{
    flow.section("Sliders and dials")

    flow.caption("normal")
    let slider = Slider.create(flow.view, flow.next(200, 26))
    slider.setValue(0.35)

    let range = Slider.create(flow.view, flow.next(200, 26), range: true)
    range.setRange(0.25, 0.75)

    let stepped = Slider.create(flow.view, flow.next(200, 26))
    stepped.setBounds(0, 1, 0.1)
    stepped.flags.add(.ShowSteps)
    stepped.setValue(0.5)

    let dial = Circular.create(flow.view, flow.next(44, 44))
    dial.setValue(0.6)

    flow.caption("disabled")
    let offSlider = Slider.create(flow.view, flow.next(200, 26))
    offSlider.setValue(0.35)
    offSlider.disable()

    let offDial = Circular.create(flow.view, flow.next(44, 44))
    offDial.setValue(0.6)
    offDial.disable()

    flow.section("Progress")

    flow.caption("normal")
    let bar = ProgressBar.create(flow.view, flow.next(220, 18))
    bar.setValue(0.45)

    let infinite = ProgressBar.create(flow.view, flow.next(220, 18))
    infinite.updateFlags(.Indeterminate)

    Spinner.create(flow.view, flow.next(26, 26))

    flow.caption("disabled")
    let offBar = ProgressBar.create(flow.view, flow.next(220, 18))
    offBar.setValue(0.45)
    offBar.disable()
}

private func buildContainers(flow: *Flow)
{
    flow.section("Tabs")
    for form in [TabForm.Flat, .Round, .Button, .PushButton]
    {
        let tab = Tab.create(flow.view, flow.next(236, 100))
        tab.setForm(form)
        for name in ["One", "Two", "Three"]
        {
            let page = Wnd.create'Wnd(tab)
            tab.addItem(name, {}, page)
        }
    }

    flow.section("Lists and headers")
    flow.newLine()

    let list = ListCtrl.createSimple(flow.view, flow.next(340, 170))
    list.setFrameForm(.Square)
    list.updateFlags(.HotTrack)
    list.setIconSize(16)
    for name, i in ["Selected row", "Plain row", "Another row", "A longer row label"] do
        list.createLine(name, app.theme.icon(.OpenFile, 16))
    list.computeLayout()
    list.selectLine(0)

    let header = Header.create(flow.view, flow.next(340, 36))
    header.addColumn("Name", 180)
    header.addColumn("Size", 80)
    header.addColumn("Date", 80)

    flow.section("Notices")
    flow.newLine()
    for kind in [InfoBarKind.Critical, .Information, .Message]
    {
        let host = flow.host(340, 44)
        InfoBar.create(host, "A notice the palette answers for.", kind)
    }
}

private func buildText(flow: *Flow)
{
    flow.section("Text")

    flow.caption("emphasis")
    Label.create(flow.view, "Primary label", flow.next(150, 24))
    Label.create(flow.view, "Secondary label", flow.next(150, 24), null, .SecondaryText)

    let offLabel = Label.create(flow.view, "Disabled label", flow.next(150, 24))
    offLabel.disable()

    Label.create(flow.view, "A <url>link</url> in a sentence.", flow.next(240, 24))
    Label.create(flow.view, "<p1>one <p2>two <p3>three", flow.next(180, 24))

    flow.caption("rules")
    let hairline = flow.host(200, 30)
    Separator.create(hairline, .Top, .Hairline)

    let accent = flow.host(200, 30)
    Separator.create(accent, .Top, .Accent)
}

private func buildDocuments(flow: *Flow)
{
    flow.section("Markdown document")
    let host     = flow.host(flow.width, 360)
    let markdown = Markdown.View.createText(host, "# Themed Markdown\n\nA reusable reading surface with **strong text**, `code`, and inline math $x^2$.\n\n> [!NOTE]\n> Notice colors follow the active palette.\n\n| Part | Result |\n|:---|---:|\n| Table | Aligned |\n\n$$\\frac{a}{b}$$", Markdown.Style.theme())
    markdown.dockStyle = .Center
}

private func showMessageDialog(_button: *Button)
{
    var options: MessageDlgOptions
    options.title = "Save changes"
    discard MessageDlg.yesNoCancel(g_Surface!, "Save the current changes before continuing?", options: options)
}

private func showEditDialog(_button: *Button)
{
    var options: EditDlgOptions
    options.title   = "Rename item"
    options.message = "Enter a concise name."
    options.text    = "Current name"
    discard EditDlg.createSingleLine(g_Surface!, options).doModal()
}

private func showAboutDialog(_button: *Button)
{
    let params = AboutDlgParams{
        surfaceTitle: "About GUI10",
        contentTitle: "Theme inspector",
        message: "The reference surface for every palette and standard widget.",
        surfaceIcon: {},
        contentIcon: app.theme.icon(.About, 64)}
    discard AboutDlg.create(g_Surface!, params).doModal()
}

private func buildDialogs(flow: *Flow)
{
    flow.section("Dialogs")
    flow.caption("launch")

    let message = PushButton.create(flow.view, "Message", flow.next(128))
    message.sigPressed += &showMessageDialog

    let edit = PushButton.create(flow.view, "Edit", flow.next(128))
    edit.sigPressed += &showEditDialog

    let about = PushButton.create(flow.view, "About", flow.next(128))
    about.sigPressed += &showAboutDialog
}
