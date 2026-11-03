#global if #command == Swag.CompilerCommand.Test
#global internal

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
