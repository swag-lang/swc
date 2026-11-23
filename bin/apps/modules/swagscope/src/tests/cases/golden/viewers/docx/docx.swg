#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Viewers

// Word paragraphs and the omitted-image notice in Papier.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.docx"), true, "viewer.docx.page")
}

// Word headings and styled runs in Encre.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.formatted.docx"), false, "viewer.docx.formatted")
}

// An authored Word page break in Papier.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.pagebreak.docx"), true, "viewer.docx.pagebreak")
}

// A Word document with an embedded photo in Papier.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.image.docx"), true, "viewer.docx.image")
}

// Authored Word typography stays readable on paper beside a dark, filterable heading list.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.styles.docx"), false, 1040, 720)
    let view   = assume cast(*Docx.Panel, window.currentView)
    Swag.require(view.outline!.headings.count == 3)
    window.sendCommandEvent(ViewerCommands.Outline)
    window.applyLayout()
    host.finishAnimations()
    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.docx.styles.encre")
}

// Real Word-produced defaults, theme-tinted type and a page separator are visible in Papier.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.poi-sample.docx"), true, "viewer.docx.producer.paper", 960, 660)
}
