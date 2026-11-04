#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Returns the surface point at the middle of the row worded `label` on the page on screen.
func rowCenter(sheet: *OptionSheet.View, label: string)->Math.Point
{
    let index = sheet.findRow(label)
    Swag.require(index != Swag.U32.Max)
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
        Swag.require(sheet.depth() == 1)
        Swag.require(sheet.page.rows.count == 4)
        Swag.require(sheet.page.rows[0].kind == .Link and sheet.page.rows[0].value == "Normal")
        Swag.require(sheet.page.rows[1].value == "French")
        Swag.require(sheet.page.rows[3].kind == .Toggle and not sheet.page.rows[3].checked)
        Swag.require(not sheet.page.isChoiceList())

        Swag.require(sheet.activateRow("Speed"))
        host.finishAnimations()
        Swag.require(sheet.depth() == 2)
        Swag.require(sheet.page.title == "Speed")
        Swag.require(sheet.page.isChoiceList())

        // The keyboard lands on the value in force.
        Swag.require(sheet.focusRow == 1)
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
        Swag.require(sheet.activateRow("Audio track"))
        host.finishAnimations()
        Swag.require(sheet.activateRow("English"))
        Swag.require(model.track == 1)
        Swag.require(sheet.page.rows[1].checked)
        Swag.require(sheet.depth() == 2)

        host.fireTimers()
        Swag.require(sheet.depth() == 1)
        Swag.require(sheet.levels.back().scroll == 0)
        host.finishAnimations()
        Swag.require(sheet.depth() == 1)
        Swag.require(sheet.page.rows[1].value == "English")
        Swag.require(sheet.focusRow == 1)
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
                 Swag.require(sheet.activateRow("Speed"))
                 host.finishAnimations()
                 Swag.require(sheet.activateRow("2x"))
                 Swag.require(sheet.activateRow("0.5x"))
                 host.fireTimers()
                 Swag.require(model.rate == 0.5)
                 Swag.require(sheet.depth() == 2)
                 Swag.require(sheet.page.rows[0].checked and not sheet.page.rows[3].checked)
             },
             afterChoice: .Stay)

    runSheet(&host,
             &model,
             func|host = &host, model = &model|(sheet)
             {
                 Swag.require(sheet.activateRow("Speed"))
                 host.finishAnimations()
                 Swag.require(sheet.activateRow("1.5x"))
                 Swag.require(not sheet.isClosed())
                 host.fireTimers()
                 Swag.require(sheet.isClosed())
                 Swag.require(model.rate == 1.5)
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
                 Swag.require(sheet.activateRow("Subtitles"))
                 host.finishAnimations()
                 Swag.require(not sheet.page.isChoiceList())
                 Swag.require(sheet.activateRow("French"))
                 Swag.require(sheet.pendingTimer == null)
                 Swag.require(model.subtitle == 1)
                 Swag.require(sheet.depth() == 2)
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
        Swag.require(sheet.focusRow == 0)
        host.keyPress(.Up)
        Swag.require(sheet.focusRow == 3)
        host.keyPress(.Down)
        Swag.require(sheet.focusRow == 0)
        host.keyPress(.Down)
        host.keyPress(.Down)
        Swag.require(sheet.focusRow == 2)
        Swag.require(host.app.focusVisible)

        host.keyPress(.Right)
        host.finishAnimations()
        Swag.require(sheet.page.title == "Subtitles")

        // The keyboard lands on the track in force. Headings are not stops; the header is the
        // stop above the first row.
        Swag.require(sheet.focusRow == 1)
        host.keyPress(.Up)
        Swag.require(sheet.focusRow == -1)
        host.keyPress(.Up)
        Swag.require(sheet.page.rows[sheet.focusRow].kind == .Stepper)
        host.keyPress(.Home)
        Swag.require(sheet.focusRow == -1)
        host.keyPress(.End)
        Swag.require(sheet.page.rows[sheet.focusRow].kind == .Stepper)

        // On a stepper, Left steps; anywhere else it goes back.
        host.keyPress(.Home)
        host.keyPress(.Left)
        host.finishAnimations()
        Swag.require(sheet.depth() == 1)
        Swag.require(sheet.focusRow == 2)

        host.keyPress(.Return)
        host.finishAnimations()
        host.keyPress(.Escape)
        host.finishAnimations()
        Swag.require(sheet.depth() == 1 and not sheet.isClosed())
        host.keyPress(.Escape)
        Swag.require(sheet.isClosed())
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
        Swag.require(sheet.activateRow("Speed"))
        host.finishAnimations()
        let header = sheet.localToSurface(Math.Point{sheet.body.horzCenter(), sheet.body.y + 10})
        host.click(header)
        host.finishAnimations()
        Swag.require(sheet.depth() == 1)

        Swag.require(sheet.activateRow("Speed"))
        host.finishAnimations()
        host.keyPress(.Up)
        host.keyPress(.Up)
        host.keyPress(.Return)
        host.finishAnimations()
        Swag.require(sheet.depth() == 1)

        Swag.require(sheet.activateRow("Speed"))
        host.finishAnimations()
        host.keyPress(.Back)
        host.finishAnimations()
        Swag.require(sheet.depth() == 1)
        host.keyPress(.Back)
        Swag.require(sheet.isClosed())
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
        Swag.require(sheet.activateRow("Subtitles"))
        host.finishAnimations()
        let delayRow = cast(s32, sheet.findRow("Delay"))
        Swag.require(sheet.findRow("Reset the delay") == Swag.U32.Max)

        sheet.focusRow = delayRow
        host.keyPress(.Right)
        Swag.require(model.delay == 1)
        Swag.require(sheet.page.rows[delayRow].value == "100 ms")
        host.keyPress(.Right, .Shift)
        Swag.require(model.delay == 11)
        host.keyPress(.Left)
        Swag.require(model.delay == 10)
        Swag.require(sheet.depth() == 2)

        host.keyPress(.Right, .Shift)
        Swag.require(model.delay == 20)
        Swag.require(not sheet.page.rows[delayRow].canIncrease)
        host.keyPress(.Right)
        Swag.require(model.delay == 20)

        Swag.require(sheet.findRow("Reset the delay") != Swag.U32.Max)
        host.keyPress(.Down)
        host.keyPress(.Space)
        Swag.require(model.delay == 0 and model.resets == 1)
        Swag.require(sheet.findRow("Reset the delay") == Swag.U32.Max)
        Swag.require(sheet.focusRow == delayRow)

        // The arrows of a stepper answer the pointer too.
        let center = rowCenter(sheet, "Delay")
        let height = sheet.themeMetrics().optionSheet_RowHeight
        let parts  = sheet.stepperParts(sheet.rowRect(sheet.listRect(2), sheet.surfaceToLocal(center).y - height * 0.5, height))
        host.click(sheet.localToSurface(Math.Point{parts.increase.horzCenter(), parts.increase.vertCenter()}))
        Swag.require(model.delay == 1)
        host.click(sheet.localToSurface(Math.Point{parts.decrease.horzCenter(), parts.decrease.vertCenter()}))
        Swag.require(model.delay == 0)
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
        Swag.require(model.wrap)
        Swag.require(sheet.page.rows[3].checked)
        host.click(rowCenter(sheet, "Wrap lines"))
        Swag.require(not model.wrap)
        Swag.require(sheet.depth() == 1)

        model.locked = true
        sheet.refresh()
        Swag.require(not sheet.activateRow("Wrap lines"))
        host.click(rowCenter(sheet, "Wrap lines"))
        Swag.require(not model.wrap)
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
        Swag.require(sheet.focusRow == 2 and sheet.pointerOnRow)
        host.click(rowCenter(sheet, "Subtitles"))
        host.finishAnimations()
        Swag.require(sheet.page.title == "Subtitles")

        host.click(rowCenter(sheet, "Text size"))
        host.finishAnimations()
        Swag.require(sheet.depth() == 3)
        host.click(rowCenter(sheet, "Large"))
        Swag.require(model.size == 2)
        host.fireTimers()
        host.finishAnimations()
        Swag.require(sheet.page.title == "Subtitles")
        Swag.require(sheet.page.rows[sheet.findRow("Text size")].value == "Large")

        host.click(host.surface.wnd.localToSurface(Math.Point{20, 20}))
        Swag.require(sheet.isClosed())
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
        Swag.require(rootHeight == sheet.contentHeight(&sheet.page, 1))

        Swag.require(sheet.activateRow("Subtitles"))
        Swag.require(sheet.slideProgress < 1)
        host.advanceAnimations(0.05)
        Swag.require(sheet.bodyHeight > rootHeight and sheet.bodyHeight < sheet.contentHeight(&sheet.page, 2))

        // A key pressed while the page moves acts on the page as it will settle.
        host.keyPress(.Down)
        Swag.require(sheet.slideProgress == 1)
        host.finishAnimations()
        Swag.require(sheet.bodyHeight == sheet.contentHeight(&sheet.page, 2))

        // The body hangs from its button: it grows upward and keeps its tab joined to it.
        Swag.require(sheet.opensUp)
        Swag.require(sheet.body.bottom() + sheet.themeMetrics().menuPopup_AnchorGap == sheet.tab.y)
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
        Swag.require(sheet.activateRow("Speed"))
        host.advanceAnimations(0)
        Swag.require(sheet.slideProgress == 1)
        Swag.require(sheet.bodyHeight == sheet.contentHeight(&sheet.page, 2))
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
        Swag.require(sheet.activateRow("Speed"))
        host.finishAnimations()
        Swag.require(sheet.focusRow == 3)
        Swag.require(sheet.bodyHeight == sheet.contentHeight(&sheet.page, 2))
        Swag.require(sheet.levels.back().scroll == 0)
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
                 Swag.require(sheet.activateRow("Speed"))
                 let targetHeight = Math.min(sheet.contentHeight(&sheet.page, sheet.depth()), sheet.maxBodyHeight)
                 let metrics      = sheet.themeMetrics()
                 let targetList   = Math.max(targetHeight - metrics.optionSheet_HeaderHeight, 0)
                 let focusBottom  = sheet.rowTop(&sheet.page, sheet.focusRow) + sheet.rowHeight(&sheet.page.rows[sheet.focusRow]) + metrics.optionSheet_Inset
                 Swag.require(sheet.bodyHeight != targetHeight)
                 Swag.require(sheet.levels.back().scroll > 0)
                 Swag.require(focusBottom <= sheet.levels.back().scroll + targetList)
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
        Swag.require(sheet.presentationOffset == Math.Point{})
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
                 Swag.require(not sheet.opensUp)
                 Swag.require(sheet.tab.bottom() + sheet.themeMetrics().menuPopup_AnchorGap == sheet.body.y)

                 Swag.require(sheet.activateRow("Subtitles"))
                 host.finishAnimations()
                 Swag.require(sheet.bodyHeight < sheet.contentHeight(&sheet.page, 2))
                 host.keyPress(.End)
                 Swag.require(sheet.levels.back().scroll > 0)
                 host.keyPress(.Home)
                 Swag.require(sheet.levels.back().scroll == 0)

                 host.mouseWheel(rowCenter(sheet, "Off"), -1)
                 Swag.require(sheet.levels.back().scroll > 0)
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
                 Swag.require(sheet.position == host.root.clientRect())
                 Swag.require(sheet.body.bottom() == sheet.clientRect().bottom())
                 Swag.require(sheet.ground.bottom() > sheet.clientRect().bottom())
                 Swag.require(sheet.page.title == "Options")
                 host.click(host.root.localToSurface(Math.Point{20, 20}))
                 Swag.require(sheet.isClosed())
             },
             placement: .BottomSheet)

    runSheet(&host,
             &model,
             func|host = &host|(sheet)
             {
                 host.finishAnimations()
                 Swag.require(sheet.body.right() == sheet.clientRect().right())
                 Swag.require(sheet.ground.right() > sheet.clientRect().right())
                 Swag.require(sheet.ground.y < 0 and sheet.ground.bottom() > sheet.clientRect().bottom())
                 Swag.require(sheet.activateRow("Speed"))
                 host.finishAnimations()
                 Swag.require(sheet.depth() == 2)
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
        Swag.require(sheet.page.rows[0].value == "2x")
    })
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
    Swag.require(page.rows.count == 3)
    Swag.require(page.rows[0].kind == .Link and page.rows[0].value == "Mode B")
    Swag.require(page.rows[1].kind == .Toggle and
                 page.rows[1].label == "Show the flag" and
                 not page.rows[1].checked)
    Swag.require(page.rows[2].kind == .Action)

    var modes: OptionSheet.Page
    page.rows[0].buildLink(&modes)
    Swag.require(modes.title == "Mode" and modes.isChoiceList())
    Swag.require(not modes.rows[0].checked and modes.rows[1].checked)

    (unwrap modes.rows[0].choose)()
    (unwrap page.rows[1].toggle)(true)
    (unwrap page.rows[2].run)()
    Swag.require(target.mode == 0 and target.flag and target.runs == 1)
}
