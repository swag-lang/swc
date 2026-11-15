#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Video

// A private short recording gets its final local picture even in online poster mode. The
// privacy mark follows navigation into a document, live policy changes and a public folder.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let folder       = Path.combine(journey.root, "Private")
    let publicFolder = Path.combine(journey.root, "Public")
    expect Directory.create(folder)
    expect Directory.create(publicFolder)
    let recording = Path.combine(folder, "Recording (2026).y4m")
    var clip      = expect Clip.create(32, 24, expect FrameRate.create(24, 1))
    for 24
    {
        var image = Image.create(32, 24, .RGB8)
        image.fill(Color.fromRgb(56, 189, 248))
        expect clip.addFrame(image)
    }

    expect clip.save(recording)
    let document = Path.combine(folder, "note.txt")
    discard expect File.writeAllText(document, "A private note.")
    var publisher: File.MountPrivacyPublisher
    expect publisher.open(folder, true)
    let window = journey.window
    window.onlineMovies = true
    window.openExplorer(folder)
    journey.waitFor("private folder", func|window|()->bool => window.isExploring() and
                                                              not window.explorer!.load.started and
                                                              window.explorer!.entries.count == 2)
    let explorer = unwrap window.explorer
    explorer.forceBoard(true, .Posters)
    explorer.setMode(.Large)
    journey.waitFor("short recording in online posters", func|explorer|()->bool
    {
        for &entry in explorer.entries where Path.hasExtension(entry.path, ".y4m") do
            return entry.texture.isValid() and
                   entry.duration == 1 and
                   not entry.onlinePending and
                   entry.movie.title.isEmpty()
        return false
    })
    let caption = unwrap window.privacy.caption
    Swag.require(caption.isLocallyVisible())
    window.queueFile(document)
    journey.waitForFile(document)
    Swag.require(caption.isLocallyVisible())
    publisher.setPrivateMode(false)
    journey.waitFor("privacy disabled", func|caption|()->bool => not caption.isLocallyVisible())
    publisher.setPrivateMode(true)
    journey.waitFor("privacy restored", func|caption|()->bool => caption.isLocallyVisible())
    window.openExplorer(publicFolder)
    journey.waitFor("public folder", func|window, caption|()->bool => window.isExploring() and
                                                                      not window.explorer!.load.started and
                                                                      window.explorer!.entries.isEmpty() and
                                                                      not caption.isLocallyVisible())
}
