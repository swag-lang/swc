#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

private func assertTransformedImageReading(light: bool, golden: string)
{
    let file = isolatedScopeFixture("sample.svg")
    defer discardIsolatedScopeFixture(file)

    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, file, light, 400, 600)
    Swag.require(window.choices[window.activeChoiceIndex].key == "image")
    let view = assume cast(*Picture.Panel, window.currentView)
    view.imageView.setZoom(3)
    view.rotateClockwise()
    view.mirrorHorizontally()
    Swag.require(view.imageView.zoom == 3 and
                 view.imageView.rotationQuarterTurns == 3 and
                 view.imageView.isMirrored)
    Swag.require(Utf8.contains(view.transformButton.toolTip, "270°") and
                 Utf8.contains(view.transformButton.toolTip, Picture.texts().word_Mirrored))

    // At a narrow reading width the compact zoom group stays within 84 units, and its button
    // still exposes zoom actions while the separate transform action names the full orientation.
    Swag.require(view.info.itf.measureContent({400, 600}).x <= 84)
    Swag.require(view.zoomLabel.isLocallyVisible() and view.zoomLabel.text() == Viewer.zoomText(300))
    var results = Testing.lensResults("Zoom")
    var entries = Viewer.LensEntries.create(&results, "Image", host.theme)
    view.describeLens(&entries)
    var foundIn: *Lens.Entry?
    var foundOut: *Lens.Entry?
    var foundMenu: *Lens.Entry?
    for &entry in results.sections[0]!.entries
    {
        if entry.title == appStrings().cmd_ZoomIn do foundIn = entry
        if entry.title == appStrings().cmd_ZoomOut do foundOut = entry
        if entry.title == appStrings().cmd_ZoomMenu do foundMenu = entry
    }
    Swag.require(foundIn != null and foundOut != null and foundMenu != null)
    Swag.require(not foundIn.disabled and not foundOut.disabled)
    foundOut.run!()
    Swag.require(view.zoomPercent() < 300)
    view.imageView.setZoom(3)

    window.applyLayout()
    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, golden)
}

// The transformed reading remains legible at a narrow width in both shipped themes.
#[Swag.TestTag("golden")]
#test
{
    assertTransformedImageReading(true, "viewer.image.transformed.paper")
    assertTransformedImageReading(false, "viewer.image.transformed.ink")
}
