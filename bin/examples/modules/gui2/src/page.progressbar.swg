using Core, Gui, Pixel

func createProgressBarPage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)
    let left = createPanel(parent, "Finite", "Static progression values cover empty, partial, full and disabled bars.", layout.left)
    {
        createCaption(left, "25 percent", 24, 88, 160)
        var prg = ProgressBar.create(left, {24, 116, 320})
        prg.setProgression(0.25)

        createCaption(left, "75 percent", 24, 154, 160)
        prg = ProgressBar.create(left, {24, 182, 320})
        prg.setProgression(0.75)
    }

    let right = createPanel(parent, "Infinite", "The built-in infinite mode animates itself during paint.", layout.right)
    {
        let prg = ProgressBar.create(right, {24, 116, 330})
        prg.prgBarFlags |= .Infinite
    }

    let bottom = createPanel(parent, "Frame-driven", "One bar is advanced from the application frame callback; another shows disabled rendering.", layout.bottom)
    {
        createCaption(bottom, "Application frame", 24, 92, 180)
        let framePrg = ProgressBar.create(bottom, {24, 124, 420})
        g_Progress = framePrg
        framePrg.setProgression(0.0)

        createCaption(bottom, "Disabled 50 percent", 500, 92, 200)
        let disabled = ProgressBar.create(bottom, {500, 124, 360})
        disabled.setProgression(0.5)
        disabled.disable()
    }
}
