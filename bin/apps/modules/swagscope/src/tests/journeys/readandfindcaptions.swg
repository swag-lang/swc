#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Viewers

// Find a cue in SubRip subtitles, then continue reading a neighboring WebVTT file.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let first = journey.copyData("viewer.srt", "A-dialogue.srt")
    let second = Path.combine(journey.root, "B-dialogue.vtt")
    expect File.writeAllText(second, "WEBVTT\n\n00:00:01.000 --> 00:00:03.000\nAgain in another file.\n")
    let window = journey.window

    window.openFile(first)
    journey.waitForFile(first)
    Swag.require(window.choices[window.activeChoiceIndex].key == "subtitle")
    let captions = assume cast(*Captions.Panel, window.currentView)
    Swag.require(captions.track!.cueCount() == 2)
    window.sendCommandEvent(ViewerCommands.Find)
    window.searchBox.setText("second")
    journey.waitFor("caption found", func|window, captions|()->bool => window.searchComplete and
                                                                  window.searchMatches.count == 1 and
                                                                  captions.currentCue == 1)

    window.sendCommandEvent(ViewerCommands.NextFile)
    journey.waitForFile(second)
    let next = assume cast(*Captions.Panel, window.currentView)
    Swag.require(next.track!.cueCount() == 1 and next.track.sourceFormat() == .WebVtt)
    window.sendCommandEvent(ViewerCommands.Find)
    window.searchBox.setText("Again")
    journey.waitFor("next caption found", func|window|()->bool => window.searchComplete and
                                                                 window.searchMatches.count == 1)
}
