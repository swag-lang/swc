#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Audio, Viewers

// Open a local recording, move through it, mute it, then stop and close the player.
#[Swag.TestTag("integration.application.journey")]
#test
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()

    var journey: ScopeJourney
    journey.setup()
    let file = journey.copyData("pacman_beginning.wav", "short-recording.wav")
    let window = journey.window

    window.openFile(file)
    journey.waitForFile(file)
    Swag.require(window.choices[window.activeChoiceIndex].key == "sound")
    let player = assume cast(*Sound.Panel, window.currentView)
    Swag.require(player.engineReady and player.duration > 0 and player.playButton.isEnabled())
    Swag.require(player.waveform.readyCount > 0)

    player.seekSeconds(player.duration * 0.5)
    Swag.require(player.elapsed > 0)
    player.setMuted(true)
    Swag.require(player.muted and player.muteButton.isChecked)
    player.togglePlayback()
    journey.waitFor("sound playing", func|player|()->bool => player.playing)
    player.stopPlayback()
    Swag.require(not player.playing and player.elapsed == 0)

    window.sendCommandEvent(ViewerCommands.Close)
    journey.waitFor("sound returned to recent files", func|window|()->bool =>
        window.home.isLocallyVisible() and window.currentView == null and window.recent.count == 1)
}
