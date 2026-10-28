#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Builds the controls of the charter in the states its pictures show, one family per row:
// buttons, icon buttons and a segment group, fields, choices, values, tabs, a list and notices.
//
// The wall is the contract of `backlog/design/imgs/gui.controls.ink.png` and `.paper.png`: a
// change to any control's colors, corners or measures moves its row of this image.
func buildCharterWall(host: *Testing.HeadlessHost)
{
    let root = &host.root
    const Left = 24.0

    // Buttons: primary, secondary, quiet, destructive, disabled, and a secondary under the pointer.
    var x = Left
    for form, index in [PushButtonForm.Strong, .Normal, .Flat, .Destructive, .Normal, .Normal]
    {
        let names = ["Open", "Cancel", "Later", "Delete", "Disabled", "Hover"]
        let btn   = PushButton.create(root, names[index], {x, 20, 92, 0}, form: form)
        if index == 4 do
            btn.disable()
        if index == 5 do
            btn.isHot = true
        x += 100
    }

    // Icon buttons at rest, under the pointer, checked and disabled, then a segment group.
    x = Left
    for glyph, index in [ThemeIcons.OpenFile, .Folder, .ExploreFolder, .Remove]
    {
        let btn = IconButton.create(root, host.theme.icon(glyph, 16), {x, 64, 32, 32}, flags: .Toggle)
        switch index
        {
        case 1: btn.isHot = true
        case 2: btn.setChecked(true)
        case 3: btn.disable()
        }

        x += 40
    }

    with let segments = Tab.create(root, {Left + 176, 64, 280, 32})
    {
        .setForms(.Round, .Round, .Flat)
        for name in ["Code", "Text", "Hexa", "Binary"] do
            .addItem(name)
        .setSelectedIndex(0)
    }

    // Fields: a placeholder, a field under the pointer, the focused one, a rejected value, a
    // disabled field and a password with its eye.
    let search = EditBox.create(root, "", {Left, 112, 180, 0})
    search.setPlaceholder("Search")
    let hover = EditBox.create(root, "Hover", {Left + 192, 112, 180, 0})
    hover.isHot = true
    let rejected = EditBox.create(root, "1,4", {Left + 384, 112, 180, 0})
    rejected.isInvalid = true
    let disabled = EditBox.create(root, "", {Left + 576, 112, 180, 0})
    disabled.setPlaceholder("Disabled")
    disabled.disable()
    let password = PasswordEdit.create(root, {Left + 192, 156, 180, 32})
    password.setPlaceholder("Password")
    let typing = EditBox.create(root, "Typing", {Left, 156, 180, 0})

    with let combo = ComboBox.create(root, {Left + 384, 156, 180, 0})
    {
        .addItem("Automatic")
        .addItem("2D render")
        .setSelectedIndex(0, notify: false)
    }

    // A stepper beside the combo box: a field holding a measure, a quiet `−` and `+` at its ends.
    with let stepper = Stepper.create(root, {Left + 576, 156, 120, 0})
    {
        .setRange(0, 100)
        .setValue(48)
    }

    // Choices: off, on, mixed and disabled boxes, two radio buttons, and a switch off and on.
    CheckButton.create(root, "No", {Left, 204, 80, 0})
    CheckButton.create(root, "Yes", {Left + 88, 204, 80, 0}).setState(.Checked)
    CheckButton.create(root, "Mixed", {Left + 176, 204, 96, 0}, flags: .TriState).setState(.Indeterminate)
    CheckButton.create(root, "Disabled", {Left + 280, 204, 110, 0}).disable()
    RadioButton.create(root, "Mio", {Left + 400, 204, 80, 0})
    RadioButton.create(root, "Gio", {Left + 488, 204, 80, 0}).setChecked(true)
    ToggleButton.create(root, {Left + 584, 210})
    ToggleButton.create(root, {Left + 632, 210}).setChecked(true)

    // Values: a slider, a determinate progress and the circular progress.
    Slider.create(root, {Left, 248, 200, 0}).setValueWithoutGesture(0.4)
    let progress = ProgressBar.create(root, {Left + 224, 256, 200, 0})
    progress.setValue(0.62)
    Spinner.create(root, {Left + 448, 248, 24, 24})

    // Navigation: words on one hairline, the active one underlined in Arc.
    with let tabs = Tab.create(root, {Left, 288, 320, 40})
    {
        .setForms(.Flat, .Flat, .Flat)
        for name in ["Appearance", "Language", "About"] do
            .addItem(name)
        .setSelectedIndex(0)
    }

    // A list under its header, its first row selected.
    with let list = ListCtrl.createMultiColumns(root, {Left, 344, 400, 140})
    {
        .addColumn("Name", 240)
        .addColumn("Modified", 140)
        .createLine("AGENTS.md").setItem(1, "26/10")
        .createLine("README.md").setItem(1, "20/10")
        .createLine("backlog").setItem(1, "28/10")
        .selectLine(0)
    }

    // Notices: information, caution and failure, each a tinted ground and a dot.
    for kind, index in [InfoBarKind.Information, .Message, .Critical]
    {
        let notice = Wnd.create'Wnd(root, {Left + 440, 344 + cast(f32, index) * 48, 340, 40})
        let texts  = ["These settings apply to the next shapes.", "The reader is busy.", "Wrong password."]
        InfoBar.create(notice, texts[index], kind)
    }

    // Swatches, the chosen one ringed in Arc.
    with let swatches = PalettePicker.create(root, {Left + 600, 248, 200, 28})
    {
        for color in [0xFFE5484D'u32, 0xFFF59E0B, 0xFF22A35A, 0xFF38BDF8, 0xFFF2F2F2] do
            .addColor(Color.fromArgb(color))
        .setSelectedIndex(1, notify: false)
    }

    typing.setFocus()
    host.app.setFocusVisible(true)
    host.root.applyLayout()
    host.settleAnimations()
}

// Encre: Voltage acts, Arc chooses, on a slightly cold graphite.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(840, 500)
    buildCharterWall(&host)

    var image = host.render()
    Pixel.Testing.assertImageGolden(&image, "controls.charter.ink")
}

// Papier: the action is ink on paper, Arc deepens to be read, Voltage is never written.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(840, 500)
    host.theme.setLight()
    host.notify(.ThemeChanged)
    buildCharterWall(&host)

    var image = host.render()
    Pixel.Testing.assertImageGolden(&image, "controls.charter.paper")
}
