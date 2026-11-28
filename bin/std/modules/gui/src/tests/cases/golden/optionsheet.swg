#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

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
                     Swag.require(sheet.activateRow(label))
                     if shot.halfway and label == (shot.second orelse shot.first)
                     {
                         host.advanceAnimations(sheet.themeMetrics().motion_PanelSeconds * 0.5)
                         Swag.require(sheet.bodyHeight == Math.round(sheet.bodyHeight))
                         Swag.require(sheet.position.x == Math.round(sheet.position.x))
                         Swag.require(sheet.position.y == Math.round(sheet.position.y))
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
                     Swag.require(sheet.focusRow == -1)
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
