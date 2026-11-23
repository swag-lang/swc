#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// The wide transcript keeps the current cue, its time range and its words on the same row.
#[Swag.TestTag("golden")]
#test
{
    let fileName = scopeTestDataPath("viewer.reading.srt")
    var host: Testing.HeadlessHost
    let window   = framedViewerWindow(&host, fileName.toString(), false)
    let view     = assume cast(*Captions.Panel, window.instances[window.activeChoiceIndex].view)
    Swag.require(view.revealCue(1))
    window.applyLayout()
    host.settleAnimations(window, 4)

    var image = host.render(&host.surfaceWnd)
    assertScopeImageGolden(&image, "viewer.subtitle.ink")
}

// A narrow transcript stacks the words below the clock. The adjoining specimen uses its own script.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host, light: true, width: 740, height: 560)
    defer host.shutdown()
    workspace.openScene([scopeTestDataPath("viewer.reading.srt"), openTypeFixturePath()], .SideBySide)
    openViews(&host, workspace)
    let scene = unwrap workspace.scene()
    let transcript = assume cast(*Captions.Panel, scene.views[0].document!.currentView)
    let font = assume cast(*Typeface.Panel, scene.views[1].document!.currentView)
    Swag.require(transcript.sheet.wordsOrigin.y >= Captions.CueSheet.TimesHeight)
    Swag.require(font.document.specimenMark.count and font.document.specimenMark != "Aa")
    let image = host.renderSettled(&host.surfaceWnd)
    assertScopeImageGolden(&image, "viewer.subtitle.font.compact.paper")
}
