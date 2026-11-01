#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// The window in each view, at the size of the charter's pictures, in Encre and in Papier.
func assertInspectionSurface(view: PrismView, light: bool)
{
    var host: Testing.HeadlessHost
    let window = testSetupInspectionWindow(&host)
    if light
    {
        host.theme.setLight()
        host.notify(.ThemeChanged)
    }

    showDotFixtures(window)
    window.applyView(view)
    if view == .Stages do
        microcode(window, 0).setStep(3)
    window.refreshStatus()
    window.applyLayout()
    host.settleAnimations(window, 6)

    var image = host.render(&host.surfaceWnd)
    var name: String
    switch #complete view
    {
    case .Columns: name = "surface.columns"
    case .Stages:  name = "surface.stages"
    case .Compare: name = "surface.compare"
    }

    if light do
        name.append(".paper")
    Pixel.Testing.assertImageGolden(&image, name)
}

// The lens open over the window, its commands and choices in Encre and in Papier.
func assertLensSurface(light: bool)
{
    var host: Testing.HeadlessHost
    let window = testSetupInspectionWindow(&host)
    if light
    {
        host.theme.setLight()
        host.notify(.ThemeChanged)
    }

    showDotFixtures(window)
    window.openLens()
    host.settleAnimations(window, 6)
    var image = host.render(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&image, light ? "surface.lens.paper" : "surface.lens")
}

#[Swag.TestTag("golden")]
#test { assertInspectionSurface(.Columns, false) }

#[Swag.TestTag("golden")]
#test { assertInspectionSurface(.Columns, true) }

#[Swag.TestTag("golden")]
#test { assertInspectionSurface(.Stages, false) }

#[Swag.TestTag("golden")]
#test { assertInspectionSurface(.Stages, true) }

#[Swag.TestTag("golden")]
#test { assertInspectionSurface(.Compare, false) }

#[Swag.TestTag("golden")]
#test { assertInspectionSurface(.Compare, true) }

#[Swag.TestTag("golden")]
#test { assertLensSurface(false) }

#[Swag.TestTag("golden")]
#test { assertLensSurface(true) }
