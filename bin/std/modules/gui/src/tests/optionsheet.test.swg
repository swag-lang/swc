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
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 520)

    var model: SheetModel
    runSheet(&host, &model, func|host = &host|(sheet)
    {
        Swag.assert(sheet.depth() == 1)
        Swag.assert(sheet.page.rows.count == 4)
        Swag.assert(sheet.page.rows[0].kind == .Link and sheet.page.rows[0].value == "Normal")
        Swag.assert(sheet.page.rows[1].value == "French")
        Swag.assert(sheet.page.rows[3].kind == .Toggle and not sheet.page.rows[3].checked)
        Swag.assert(not sheet.page.isChoiceList())

        Swag.assert(sheet.activateRow("Speed"))
        host.finishAnimations()
        Swag.assert(sheet.depth() == 2)
        Swag.assert(sheet.page.title == "Speed")
        Swag.assert(sheet.page.isChoiceList())

        // The keyboard lands on the value in force.
        Swag.assert(sheet.focusRow == 1)
    })
}

// A choice on a page of choices applies at once, shows its check, then goes back to a first
// page that already shows the new value, with the focus on the setting it came from.
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 520)

    var model: SheetModel
    runSheet(&host, &model, func|host = &host, model = &model|(sheet)
    {
        Swag.assert(sheet.activateRow("Audio track"))
        host.finishAnimations()
        Swag.assert(sheet.activateRow("English"))
        Swag.assert(model.track == 1)
        Swag.assert(sheet.page.rows[1].checked)
        Swag.assert(sheet.depth() == 2)

        host.fireTimers()
        Swag.assert(sheet.depth() == 1)
        Swag.assert(sheet.levels.back().scroll == 0)
        host.finishAnimations()
        Swag.assert(sheet.depth() == 1)
        Swag.assert(sheet.page.rows[1].value == "English")
        Swag.assert(sheet.focusRow == 1)
    })
}

// Staying keeps the page of choices open; closing ends the sheet after the check was shown.
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 520)

    var model: SheetModel
    runSheet(&host,
             &model,
             func|host = &host, model = &model|(sheet)
             {
                 Swag.assert(sheet.activateRow("Speed"))
                 host.finishAnimations()
                 Swag.assert(sheet.activateRow("2x"))
                 Swag.assert(sheet.activateRow("0.5x"))
                 host.fireTimers()
                 Swag.assert(model.rate == 0.5)
                 Swag.assert(sheet.depth() == 2)
                 Swag.assert(sheet.page.rows[0].checked and not sheet.page.rows[3].checked)
             },
             afterChoice: .Stay)

    runSheet(&host,
             &model,
             func|host = &host, model = &model|(sheet)
             {
                 Swag.assert(sheet.activateRow("Speed"))
                 host.finishAnimations()
                 Swag.assert(sheet.activateRow("1.5x"))
                 Swag.assert(not sheet.isClosed())
                 host.fireTimers()
                 Swag.assert(sheet.isClosed())
                 Swag.assert(model.rate == 1.5)
             },
             afterChoice: .Close)
}

// A page that mixes choices with other rows stays open after a choice, whatever the policy.
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 520)

    var model: SheetModel
    runSheet(&host,
             &model,
             func|host = &host, model = &model|(sheet)
             {
                 Swag.assert(sheet.activateRow("Subtitles"))
                 host.finishAnimations()
                 Swag.assert(not sheet.page.isChoiceList())
                 Swag.assert(sheet.activateRow("French"))
                 Swag.assert(sheet.pendingTimer == null)
                 Swag.assert(model.subtitle == 1)
                 Swag.assert(sheet.depth() == 2)
             },
             afterChoice: .Close)
}

// The keyboard walks the rows and the header around the page, opens a link with Right and
// comes back with Left to the row it left from; Escape steps back, then closes.
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 520)

    var model: SheetModel
    runSheet(&host, &model, func|host = &host|(sheet)
    {
        Swag.assert(sheet.focusRow == 0)
        host.keyPress(.Up)
        Swag.assert(sheet.focusRow == 3)
        host.keyPress(.Down)
        Swag.assert(sheet.focusRow == 0)
        host.keyPress(.Down)
        host.keyPress(.Down)
        Swag.assert(sheet.focusRow == 2)
        Swag.assert(host.app.focusVisible)

        host.keyPress(.Right)
        host.finishAnimations()
        Swag.assert(sheet.page.title == "Subtitles")

        // The keyboard lands on the track in force. Headings are not stops; the header is the
        // stop above the first row.
        Swag.assert(sheet.focusRow == 1)
        host.keyPress(.Up)
        Swag.assert(sheet.focusRow == -1)
        host.keyPress(.Up)
        Swag.assert(sheet.page.rows[sheet.focusRow].kind == .Stepper)
        host.keyPress(.Home)
        Swag.assert(sheet.focusRow == -1)
        host.keyPress(.End)
        Swag.assert(sheet.page.rows[sheet.focusRow].kind == .Stepper)

        // On a stepper, Left steps; anywhere else it goes back.
        host.keyPress(.Home)
        host.keyPress(.Left)
        host.finishAnimations()
        Swag.assert(sheet.depth() == 1)
        Swag.assert(sheet.focusRow == 2)

        host.keyPress(.Return)
        host.finishAnimations()
        host.keyPress(.Escape)
        host.finishAnimations()
        Swag.assert(sheet.depth() == 1 and not sheet.isClosed())
        host.keyPress(.Escape)
        Swag.assert(sheet.isClosed())
    })
}

// The header is a way back for the pointer and the keyboard alike, and Backspace takes it too.
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 520)

    var model: SheetModel
    runSheet(&host, &model, func|host = &host|(sheet)
    {
        Swag.assert(sheet.activateRow("Speed"))
        host.finishAnimations()
        let header = sheet.localToSurface(Math.Point{sheet.body.horzCenter(), sheet.body.y + 10})
        host.click(header)
        host.finishAnimations()
        Swag.assert(sheet.depth() == 1)

        Swag.assert(sheet.activateRow("Speed"))
        host.finishAnimations()
        host.keyPress(.Up)
        host.keyPress(.Up)
        host.keyPress(.Return)
        host.finishAnimations()
        Swag.assert(sheet.depth() == 1)

        Swag.assert(sheet.activateRow("Speed"))
        host.finishAnimations()
        host.keyPress(.Back)
        host.finishAnimations()
        Swag.assert(sheet.depth() == 1)
        host.keyPress(.Back)
        Swag.assert(sheet.isClosed())
    })
}

// A stepper steps in place, ten steps at a time with Shift, and stops where it says it cannot
// go further. The reset appears with a delay and, once run, hands its focus to the row above.
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 520)

    var model: SheetModel
    runSheet(&host, &model, func|host = &host, model = &model|(sheet)
    {
        Swag.assert(sheet.activateRow("Subtitles"))
        host.finishAnimations()
        let delayRow = cast(s32, sheet.findRow("Delay"))
        Swag.assert(sheet.findRow("Reset the delay") == Swag.U32.Max)

        sheet.focusRow = delayRow
        host.keyPress(.Right)
        Swag.assert(model.delay == 1)
        Swag.assert(sheet.page.rows[delayRow].value == "100 ms")
        host.keyPress(.Right, .Shift)
        Swag.assert(model.delay == 11)
        host.keyPress(.Left)
        Swag.assert(model.delay == 10)
        Swag.assert(sheet.depth() == 2)

        host.keyPress(.Right, .Shift)
        Swag.assert(model.delay == 20)
        Swag.assert(not sheet.page.rows[delayRow].canIncrease)
        host.keyPress(.Right)
        Swag.assert(model.delay == 20)

        Swag.assert(sheet.findRow("Reset the delay") != Swag.U32.Max)
        host.keyPress(.Down)
        host.keyPress(.Space)
        Swag.assert(model.delay == 0 and model.resets == 1)
        Swag.assert(sheet.findRow("Reset the delay") == Swag.U32.Max)
        Swag.assert(sheet.focusRow == delayRow)

        // The arrows of a stepper answer the pointer too.
        let center = rowCenter(sheet, "Delay")
        let height = sheet.themeMetrics().optionSheet_RowHeight
        let parts  = sheet.stepperParts(sheet.rowRect(sheet.listRect(2), sheet.surfaceToLocal(center).y - height * 0.5, height))
        host.click(sheet.localToSurface(Math.Point{parts.increase.horzCenter(), parts.increase.vertCenter()}))
        Swag.assert(model.delay == 1)
        host.click(sheet.localToSurface(Math.Point{parts.decrease.horzCenter(), parts.decrease.vertCenter()}))
        Swag.assert(model.delay == 0)
    })
}

// A toggle switches in place, from the keyboard and the pointer; a disabled one does nothing.
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 520)

    var model: SheetModel
    runSheet(&host, &model, func|host = &host, model = &model|(sheet)
    {
        host.keyPress(.End)
        host.keyPress(.Return)
        Swag.assert(model.wrap)
        Swag.assert(sheet.page.rows[3].checked)
        host.click(rowCenter(sheet, "Wrap lines"))
        Swag.assert(not model.wrap)
        Swag.assert(sheet.depth() == 1)

        model.locked = true
        sheet.refresh()
        Swag.assert(not sheet.activateRow("Wrap lines"))
        host.click(rowCenter(sheet, "Wrap lines"))
        Swag.assert(not model.wrap)
    })
}

// The pointer opens a link and picks a value; a press outside the sheet closes it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 520)

    var model: SheetModel
    runSheet(&host, &model, func|host = &host, model = &model|(sheet)
    {
        host.moveMouse(rowCenter(sheet, "Subtitles"))
        Swag.assert(sheet.focusRow == 2 and sheet.pointerOnRow)
        host.click(rowCenter(sheet, "Subtitles"))
        host.finishAnimations()
        Swag.assert(sheet.page.title == "Subtitles")

        host.click(rowCenter(sheet, "Text size"))
        host.finishAnimations()
        Swag.assert(sheet.depth() == 3)
        host.click(rowCenter(sheet, "Large"))
        Swag.assert(model.size == 2)
        host.fireTimers()
        host.finishAnimations()
        Swag.assert(sheet.page.title == "Subtitles")
        Swag.assert(sheet.page.rows[sheet.findRow("Text size")].value == "Large")

        host.click(host.surface.wnd.localToSurface(Math.Point{20, 20}))
        Swag.assert(sheet.isClosed())
    })
}

// The body follows the height of the page on screen, and a page change lets input settle it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 520)
    host.setReducedMotion(false)

    var model: SheetModel
    runSheet(&host, &model, func|host = &host|(sheet)
    {
        host.finishAnimations()
        let rootHeight = sheet.bodyHeight
        Swag.assert(rootHeight == sheet.contentHeight(&sheet.page, 1))

        Swag.assert(sheet.activateRow("Subtitles"))
        Swag.assert(sheet.slideProgress < 1)
        host.advanceAnimations(0.05)
        Swag.assert(sheet.bodyHeight > rootHeight and sheet.bodyHeight < sheet.contentHeight(&sheet.page, 2))

        // A key pressed while the page moves acts on the page as it will settle.
        host.keyPress(.Down)
        Swag.assert(sheet.slideProgress == 1)
        host.finishAnimations()
        Swag.assert(sheet.bodyHeight == sheet.contentHeight(&sheet.page, 2))

        // The body hangs from its button: it grows upward and keeps its tab joined to it.
        Swag.assert(sheet.opensUp)
        Swag.assert(sheet.body.bottom() == sheet.tab.y)
    })
}

// With reduced motion, a page changes and the body resizes in one step.
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 520)
    host.setReducedMotion(true)

    var model: SheetModel
    runSheet(&host, &model, func|host = &host|(sheet)
    {
        Swag.assert(sheet.activateRow("Speed"))
        host.advanceAnimations(0)
        Swag.assert(sheet.slideProgress == 1)
        Swag.assert(sheet.bodyHeight == sheet.contentHeight(&sheet.page, 2))
    })
}

// A checked choice at the end of a page that fits keeps its original position after the sheet grows.
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 520)

    var model: SheetModel
    model.rate = 2
    runSheet(&host, &model, func|host = &host|(sheet)
    {
        Swag.assert(sheet.activateRow("Speed"))
        host.finishAnimations()
        Swag.assert(sheet.focusRow == 3)
        Swag.assert(sheet.bodyHeight == sheet.contentHeight(&sheet.page, 2))
        Swag.assert(sheet.levels.back().scroll == 0)
    })
}

// A page that must scroll positions its checked last choice for the destination height immediately.
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 240)
    host.setReducedMotion(false)

    var model: SheetModel
    model.rate = 2
    runSheet(&host,
             &model,
             func||(sheet)
             {
                 Swag.assert(sheet.activateRow("Speed"))
                 let targetHeight = Math.min(sheet.contentHeight(&sheet.page, sheet.depth()), sheet.maxBodyHeight)
                 let metrics      = sheet.themeMetrics()
                 let targetList   = Math.max(targetHeight - metrics.optionSheet_HeaderHeight - metrics.menuPopup_BarItemOverlap, 0)
                 let focusBottom  = sheet.rowTop(&sheet.page, sheet.focusRow) + sheet.rowHeight(&sheet.page.rows[sheet.focusRow]) + metrics.optionSheet_Inset
                 Swag.assert(sheet.bodyHeight != targetHeight)
                 Swag.assert(sheet.levels.back().scroll > 0)
                 Swag.assert(focusBottom <= sheet.levels.back().scroll + targetList)
             },
             buttonRect: {300, 8, 40, 36})
}

// The anchored arrival fades without moving the joined button.
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 520)
    host.setReducedMotion(false)

    var model: SheetModel
    runSheet(&host, &model, func|host = &host|(sheet)
    {
        host.advanceAnimations(sheet.themeMetrics().motion_PanelSeconds * 0.37)
        Swag.assert(sheet.presentationOffset == Math.Point{})
        host.finishAnimations()
    })
}

// A sheet whose button sits high in the window hangs below it; one that cannot hold its rows
// scrolls them, and keeps the focused row in view.
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 240)

    var model: SheetModel
    runSheet(&host,
             &model,
             func|host = &host|(sheet)
             {
                 Swag.assert(not sheet.opensUp)
                 Swag.assert(sheet.tab.bottom() == sheet.body.y)

                 Swag.assert(sheet.activateRow("Subtitles"))
                 host.finishAnimations()
                 Swag.assert(sheet.bodyHeight < sheet.contentHeight(&sheet.page, 2))
                 host.keyPress(.End)
                 Swag.assert(sheet.levels.back().scroll > 0)
                 host.keyPress(.Home)
                 Swag.assert(sheet.levels.back().scroll == 0)

                 host.mouseWheel(rowCenter(sheet, "Off"), -1)
                 Swag.assert(sheet.levels.back().scroll > 0)
             },
             buttonRect: {300, 8, 40, 36})
}

// A bottom sheet rises over a veil across the bottom edge, and a side panel covers the trailing
// edge at full height; a press on the veil closes either.
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 520)

    var model: SheetModel
    runSheet(&host,
             &model,
             func|host = &host|(sheet)
             {
                 host.finishAnimations()
                 Swag.assert(sheet.position == host.root.clientRect())
                 Swag.assert(sheet.body.bottom() == sheet.clientRect().bottom())
                 Swag.assert(sheet.ground.bottom() > sheet.clientRect().bottom())
                 Swag.assert(sheet.page.title == "Options")
                 host.click(host.root.localToSurface(Math.Point{20, 20}))
                 Swag.assert(sheet.isClosed())
             },
             placement: .BottomSheet)

    runSheet(&host,
             &model,
             func|host = &host|(sheet)
             {
                 host.finishAnimations()
                 Swag.assert(sheet.body.right() == sheet.clientRect().right())
                 Swag.assert(sheet.ground.right() > sheet.clientRect().right())
                 Swag.assert(sheet.ground.y < 0 and sheet.ground.bottom() > sheet.clientRect().bottom())
                 Swag.assert(sheet.activateRow("Speed"))
                 host.finishAnimations()
                 Swag.assert(sheet.depth() == 2)
             },
             placement: .SidePanel)
}

// A sheet describes itself again when the language changes under it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 520)

    var model: SheetModel
    runSheet(&host, &model, func|host = &host, model = &model|(sheet)
    {
        model.rate = 2
        host.notify(.LanguageChanged)
        Swag.assert(sheet.page.rows[0].value == "2x")
    })
}

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
                     else do
                         host.finishAnimations()
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
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    let target = Wnd.create'SheetCommandTarget(&host.root, {0, 0, 100, 100})
    target.mode = 1

    var page: OptionSheet.Page
    page.addCommandLink("Mode", SheetModeIds, target)
    page.addCommand("Test.Sheet.Flag", target)
    page.addCommand("Test.Sheet.Run", target)
    page.addCommand("Test.Sheet.Hidden", target)
    Swag.assert(page.rows.count == 3)
    Swag.assert(page.rows[0].kind == .Link and page.rows[0].value == "Mode B")
    Swag.assert(page.rows[1].kind == .Toggle and
                page.rows[1].label == "Show the flag" and
                not page.rows[1].checked)
    Swag.assert(page.rows[2].kind == .Action)

    var modes: OptionSheet.Page
    page.rows[0].buildLink(&modes)
    Swag.assert(modes.title == "Mode" and modes.isChoiceList())
    Swag.assert(not modes.rows[0].checked and modes.rows[1].checked)

    (unwrap modes.rows[0].choose)()
    (unwrap page.rows[1].toggle)(true)
    (unwrap page.rows[2].run)()
    Swag.assert(target.mode == 0 and target.flag and target.runs == 1)
}
