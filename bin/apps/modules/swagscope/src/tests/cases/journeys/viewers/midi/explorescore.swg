#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Viewers

// Inspect a MIDI score by track, zoom into notes, and return to the full score.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let file = journey.copyData("viewer.mid", "short-score.mid")
    let window = journey.window

    window.openFile(file)
    journey.waitForFile(file)
    Swag.require(window.choices[window.activeChoiceIndex].key == "midi")
    let score = assume cast(*Midi.Panel, window.currentView)
    Swag.require(score.roll.document.notes.count == 7)
    score.roll.setTrack(0)
    Swag.require(score.roll.selectedNoteCount() == 7)
    let fit = score.roll.zoom
    score.roll.zoomIn()
    Swag.require(not score.roll.fit and score.roll.zoom > fit)
    score.roll.zoomToFit()
    Swag.require(score.roll.fit and score.roll.selectedNoteCount() == 7)
}
