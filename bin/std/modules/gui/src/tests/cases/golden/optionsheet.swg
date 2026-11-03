#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// What the settings of the test player are, and how many times the reset ran.
struct SheetModel
{
    rate:     f64 = 1
    track:    u32
    subtitle: u32
    size:     u32 = 1
    delay:    s32
    wrap:     bool
    resets:   u32
    locked:   bool
}

const SheetRates: [4] f64 = [0.5, 1, 1.5, 2]
const SheetSizes          = ["Small", "Normal", "Large"]
const SheetTracks         = ["French", "English", "Commentary"]

func rateText(rate: f64)->String   => rate == 1 ? String.from("Normal") : Format.toString("%x", rate)
func delayText(delay: s32)->String => Format.toString("% ms", delay * 100)

// Builds the pages of the test player: one link per setting, a page of choices with detail
// lines, a mixed page of subtitles, and a page of choices two levels deep.
func sheetRoot(model: *SheetModel)->OptionSheet.Builder
{
    return func|model|(page)
    {
        page.addLink("Speed", rateText(model.rate), func|model|(speeds)
        {
            for rate in SheetRates do
                speeds.addChoice(rateText(rate), rate == model.rate, func|model, rate|() { model.rate = rate })
        })

        page.addLink("Audio track", SheetTracks[model.track], func|model|(tracks)
        {
            for name, index in SheetTracks do
                tracks.addChoice(name, index == model.track, func|model, index|() { model.track = cast(u32, index) }, detail: "Stereo · 48 kHz")
        })

        page.addLink("Subtitles", model.subtitle ? "On" : "Off", func|model|(subtitles)
        {
            subtitles.addHeading("Track")
            subtitles.addChoice("Off", model.subtitle == 0, func|model|() { model.subtitle = 0 })
            subtitles.addChoice("French", model.subtitle == 1, func|model|() { model.subtitle = 1 })
            subtitles.addHeading("Appearance")
            subtitles.addLink("Text size", SheetSizes[model.size], func|model|(sizes)
            {
                for name, index in SheetSizes do
                    sizes.addChoice(name, index == model.size, func|model, index|() { model.size = cast(u32, index) })
            })
            subtitles.addStepper("Delay", delayText(model.delay), func|model|(step) { model.delay = Math.min(model.delay + step, 20) }, canIncrease: model.delay < 20)
            if model.delay do
                subtitles.addAction("Reset the delay", func|model|() { model.delay = 0; model.resets += 1 })
        })

        page.addToggle("Wrap lines", model.wrap, func|model|(on) { model.wrap = on }, disabled: model.locked)
    }
}

// Opens the test sheet from a button at `buttonRect` and runs `drive` once it is on screen.
func runSheet(host: *Gui.Testing.HeadlessHost,
              model: *SheetModel,
              drive: func||(*OptionSheet.View),
              placement = OptionSheet.Placement.Anchored,
              afterChoice = OptionSheet.AfterChoice.Back,
              buttonRect = Math.Rectangle{300, 440, 40, 36})
{
    let button     = IconButton.create(&host.root, host.theme.icon(.Settings, 20), buttonRect, flags: .CenterContent)
    with let sheet = OptionSheet.View.create(button, sheetRoot(model))
    {
        .placement   = placement
        .afterChoice = afterChoice
    }

    // A closure is larger than a capture, so the frame callback reaches the scenario by address.
    var scenario = drive
    var driven: bool
    host.app.sigFrame += func|sheet, scenario = &scenario, driven = &driven|(_)
    {
        if driven[] do
            return
        driven[] = true
        scenario[](sheet)
        if not sheet.isClosed() do
            sheet.close()
    }

    sheet.doModal(button, autoDestroy: true)
    Swag.assert(driven)

    // The callback borrows locals of this call, so it must not outlive it.
    host.app.sigFrame.clear()
    host.pump()
}

// Returns the surface point at the middle of the row worded `label` on the page on screen.
func rowCenter(sheet: *OptionSheet.View, label: string)->Math.Point
{
    let index = sheet.findRow(label)
    Swag.assert(index != Swag.U32.Max)
    let list = sheet.listRect(sheet.depth())
    let y    = list.y + sheet.rowTop(&sheet.page, cast(s32, index)) - sheet.levels.back().scroll
    let rect = sheet.rowRect(list, y, sheet.rowHeight(&sheet.page.rows[index]))
    return sheet.localToSurface(Math.Point{rect.horzCenter(), rect.vertCenter()})
}

// The first page names every setting with the value in force, and a link opens its choices.

// A choice on a page of choices applies at once, shows its check, then goes back to a first
// page that already shows the new value, with the focus on the setting it came from.

// Staying keeps the page of choices open; closing ends the sheet after the check was shown.

// A page that mixes choices with other rows stays open after a choice, whatever the policy.

// The keyboard walks the rows and the header around the page, opens a link with Right and
// comes back with Left to the row it left from; Escape steps back, then closes.

// The header is a way back for the pointer and the keyboard alike, and Backspace takes it too.

// A stepper steps in place, ten steps at a time with Shift, and stops where it says it cannot
// go further. The reset appears with a delay and, once run, hands its focus to the row above.

// A toggle switches in place, from the keyboard and the pointer; a disabled one does nothing.

// The pointer opens a link and picks a value; a press outside the sheet closes it.

// The body follows the height of the page on screen, and a page change lets input settle it.

// With reduced motion, a page changes and the body resizes in one step.

// A checked choice at the end of a page that fits keeps its original position after the sheet grows.

// A page that must scroll positions its checked last choice for the destination height immediately.

// The anchored arrival fades without moving the joined button.

// A sheet whose button sits high in the window hangs below it; one that cannot hold its rows
// scrolls them, and keeps the focused row in view.

// A bottom sheet rises over a veil across the bottom edge, and a side panel covers the trailing
// edge at full height; a press on the veil closes either.

// A sheet describes itself again when the language changes under it.

enum SheetPalette
{
    Dark
    Light
}

func applyPalette(host: *Gui.Testing.HeadlessHost, palette: SheetPalette)
{
    switch palette
    {
    case .Dark:  host.theme.setDark()
    case .Light: host.theme.setLight()
    }

    host.notify(.ThemeChanged)
}

// Settings of one golden capture.
struct SheetShot
{
    palette:   SheetPalette
    golden:    string
    first:     string?
    second:    string?
    placement: OptionSheet.Placement = .Anchored
    keyboard:  bool     // Whether the keyboard moves the focus once before the capture.
    halfway:   bool     // Whether the capture is taken halfway through the last page change.
    high:      bool     // Whether the button sits at the top of the window.
    header:    bool     // Whether the capture focuses the nested page header.
}

// Opens the first page, follows the links of `shot`, and compares the sheet with its golden.
func assertSheetGolden(shot: SheetShot)
{
    var host: Testing.HeadlessHost
    host.setup(480, 520)
    applyPalette(&host, shot.palette)
    host.setReducedMotion(false)

    var model: SheetModel
    model.subtitle = 1
    model.delay    = 3
    model.locked   = shot.keyboard

    // The settings outgrow a capture, so the scenario reads them by address.
    var settings = shot
    runSheet(&host,
             &model,
             func|host = &host, shot = &settings|(sheet)
             {
                 host.finishAnimations()
                 for label in [shot.first, shot.second] where label
                 {
                     Swag.assert(sheet.activateRow(label))
                     if shot.halfway and label == (shot.second orelse shot.first)
                     {
                         host.advanceAnimations(sheet.themeMetrics().motion_PanelSeconds * 0.5)
                         Swag.assert(sheet.bodyHeight == Math.round(sheet.bodyHeight))
                         Swag.assert(sheet.position.x == Math.round(sheet.position.x))
                         Swag.assert(sheet.position.y == Math.round(sheet.position.y))
                     }
                     else
                     {
                         host.finishAnimations()
                     }
                 }

                 if shot.keyboard
                 {
                     host.keyPress(.Down)
                     host.finishAnimations()
                 }

                 if shot.header
                 {
                     host.keyPress(.Home)
                     Swag.assert(sheet.focusRow == -1)
                     host.finishAnimations()
                 }

                 var image = host.render()
                 Pixel.Testing.assertImageGolden(&image, shot.golden)
             },
             shot.placement,
             buttonRect: shot.high ? Math.Rectangle{300, 8, 40, 36} : Math.Rectangle{300, 440, 40, 36})
}

// A nested page header sits beneath the opening tab, so its focus ground remains fully visible.
#[Swag.TestTag("golden")]
#test
{
    assertSheetGolden({palette: .Dark, golden: "optionsheet.header.keyboard.below.dark", first: "Speed", high: true, header: true})
    assertSheetGolden({palette: .Light, golden: "optionsheet.header.keyboard.below.light", first: "Speed", high: true, header: true})
}

// The first page in each shipped theme: a link per setting with its value, and a switch.
#[Swag.TestTag("golden")]
#test
{
    assertSheetGolden({palette: .Dark, golden: "optionsheet.root.dark"})
    assertSheetGolden({palette: .Light, golden: "optionsheet.root.light"})
}

// A page mixing headings, choices, a nested link, a stepper and an action, in each palette.
#[Swag.TestTag("golden")]
#test
{
    assertSheetGolden({palette: .Dark, golden: "optionsheet.mixed.dark", first: "Subtitles"})
    assertSheetGolden({palette: .Light, golden: "optionsheet.mixed.light", first: "Subtitles"})
}

// The keyboard grounds and rings the row it is on, around a disabled switch, in each palette.
#[Swag.TestTag("golden")]
#test
{
    assertSheetGolden({palette: .Dark, golden: "optionsheet.keyboard.dark", keyboard: true})
    assertSheetGolden({palette: .Light, golden: "optionsheet.keyboard.light", keyboard: true})
}

// Choices with a detail line, in a sheet hanging below a button at the top of the window.
#[Swag.TestTag("golden")]
#test
{
    assertSheetGolden({palette: .Dark, golden: "optionsheet.details.below", first: "Audio track", high: true})
}

// Halfway through a page change, the first page leaves under the edge while the next arrives.
#[Swag.TestTag("golden")]
#test
{
    assertSheetGolden({palette: .Dark, golden: "optionsheet.slide.half", first: "Subtitles", halfway: true})
}

// The two placements over a veil, for a touch screen and for a screen read from afar.
#[Swag.TestTag("golden")]
#test
{
    assertSheetGolden({palette: .Dark, golden: "optionsheet.bottomsheet.dark", first: "Subtitles", placement: .BottomSheet})
    assertSheetGolden({palette: .Light, golden: "optionsheet.sidepanel.light", first: "Subtitles", placement: .SidePanel})
}

// A window answering the state of five commands, the way an application's actions do.
struct SheetCommandTarget
{
    using wnd: Wnd
    mode:      u32
    flag:      bool
    runs:      u32
}

const SheetModeIds = ["Test.Sheet.ModeA", "Test.Sheet.ModeB"]

impl IWnd for SheetCommandTarget
{
    mtd impl onComputeStateEvent(evt: *CommandStateEvent)
    {
        switch evt.id
        {
        case "Test.Sheet.ModeA", "Test.Sheet.ModeB":
            let mode = evt.id == SheetModeIds[0] ? 0'u32 : 1
            evt.updatedFields.add(.Name | .Checked | .RenderingHint)
            evt.name          = mode ? "Mode B" : "Mode A"
            evt.checked       = .mode == mode
            evt.renderingHint = .ExclusiveGroup

        case "Test.Sheet.Flag":
            evt.updatedFields.add(.Name | .LongName | .Checked)
            evt.name     = "Flag"
            evt.longName = "Show the flag"
            evt.checked  = .flag

        case "Test.Sheet.Run":
            evt.updatedFields.add(.Name)
            evt.name = "Run"

        case "Test.Sheet.Hidden":
            evt.updatedFields.add(.Name | .Hidden)
            evt.name   = "Hidden"
            evt.hidden = true
        }
    }

    mtd impl onCommandEvent(evt: *CommandEvent)
    {
        switch evt.id
        {
        case "Test.Sheet.ModeA": .mode = 0
        case "Test.Sheet.ModeB": .mode = 1
        case "Test.Sheet.Flag":  .flag = not .flag
        case "Test.Sheet.Run":   .runs += 1
        }
    }
}

// Rows bound to commands take their wording and kind from the command state, and run the command
// on the target when activated; a link over an exclusive group is valued by the command in force.
