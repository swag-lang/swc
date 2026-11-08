#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Audio, Viewers

// Listen to a local recording through the native transport controls, then stop it.
#[Swag.TestTag("integration.desktop.input")]
#test
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()

    var journey: ScopeJourney
    journey.setup()
    let file = Path.combine(journey.root, "recording.wav")
    let recording = testSilentWav(30)
    expect File.writeAllBytes(file, recording.toSlice())
    let window = journey.window
    window.openFile(file)
    journey.waitForFile(file)
    Swag.require(window.choices[window.activeChoiceIndex].key == "sound")
    let player = assume cast(*Sound.Panel, window.currentView)
    Swag.require(player.engineReady and player.playButton.isEnabled())

    var input = Testing.DesktopInput.create(&journey.app, journey.surface)
    input.click(&player.playButton.wnd)
    journey.waitFor("native playback", func|player|()->bool => player.playing)
    input.click(&player.muteButton.wnd)
    journey.waitFor("native mute", func|player|()->bool => player.muted and player.muteButton.isChecked)
    input.click(&player.forwardButton.wnd)
    journey.waitFor("native forward seek", func|player|()->bool => player.elapsed > 0)
    input.click(&player.stopButton.wnd)
    journey.waitFor("native stop", func|player|()->bool => not player.playing and player.elapsed == 0)
}
