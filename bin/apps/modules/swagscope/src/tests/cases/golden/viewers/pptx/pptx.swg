#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Viewers

// A presentation's slide text in Papier.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.pptx"), true, "viewer.pptx.slide")
}

// A presentation with an embedded photo in Encre.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.pictures.pptx"), false, "viewer.pptx.picture")
}

// Cached chart categories and values stay visible in Encre.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.chart.pptx"), false, "viewer.pptx.chart")
}

// Cached column categories and values stay visible in Encre.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.column-chart.pptx"), false, "viewer.pptx.column-chart")
}

// Table cells retain their row and column rhythm in Encre.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.table.pptx"), false, "viewer.pptx.table")
}

// Aligned and styled presentation text in Papier.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.formatted.pptx"), true, "viewer.pptx.formatted")
}

// An authored widescreen slide retains its text, photograph and master decoration in Encre.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.geometry.pptx"), false, "viewer.pptx.geometry.encre")
}

// The real producer's inherited title layout is visible beside its slide list in Papier.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.poi-sample.pptx"), true, 1000, 680)
    let view   = assume cast(*Pptx.Panel, window.currentView)
    Swag.require(view.outline.headings.count == 2)
    window.sendCommandEvent(ViewerCommands.Outline)
    window.applyLayout()
    host.finishAnimations()
    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.pptx.inherited-layout.paper")
}

// The second widescreen slide's three cards stay aligned at a narrower window size.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.geometry.pptx"), true, 800, 560)
    let view   = assume cast(*Pptx.Panel, window.currentView)
    view.showSlide(1)
    window.applyLayout()
    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.pptx.cards.paper")
}

// Theme-aware text reading keeps styled content legible without canvas-relative type sizes.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.poi-sample.pptx"), false, 820, 540)
    let view   = assume cast(*Pptx.Panel, window.currentView)
    view.showSlide(1)
    view.setTextMode(true)
    window.applyLayout()
    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.pptx.text.encre")
}
