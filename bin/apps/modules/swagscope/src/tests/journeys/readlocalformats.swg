#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

struct LocalDocument
{
    name:   string
    viewer: string
}

// Walk through distinct local document families in one window and return to each native reader.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let window = journey.window
    let documents = [LocalDocument{"markdown.images.md", "markdown"},
                     LocalDocument{"viewer.pdf", "pdf"},
                     LocalDocument{"viewer.csv", "table"},
                     LocalDocument{"sample.cpp", "code"},
                     LocalDocument{"viewer.srt", "subtitle"},
                     LocalDocument{"segoeui.ttf", "font"},
                     LocalDocument{"viewer.html", "html"},
                     LocalDocument{"sample.svg", "image"}]

    for document in documents
    {
        let file = journey.copyData(document.name, document.name)
        window.openFile(file)
        journey.waitForFile(file)
        Swag.require(window.choices[window.activeChoiceIndex].key == document.viewer)
    }

    Swag.require(window.recent.count == documents.count)
    window.sendCommandEvent(ViewerCommands.Close)
    journey.waitFor("recent documents", func|window|()->bool => window.home.isLocallyVisible() and window.currentView == null)
}
