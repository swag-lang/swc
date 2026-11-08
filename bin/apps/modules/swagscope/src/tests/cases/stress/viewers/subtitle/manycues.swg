#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// Search and reveal the last cue in a subtitle track much larger than the visible sheet.
#[Swag.TestTag("stress")]
#test
{
    let file = Testing.tempFilePath("scope-many-cues-", ".srt")
    defer discard catch File.delete(file)
    var source: String
    for index in 12_000 do
        source += Format.toString("%\n00:00:00,000 --> 00:00:01,000\nCue % has a needle.\n\n", index + 1, index + 1)
    expect File.writeAllText(file, source)

    var host: Testing.HeadlessHost
    host.setup(820, 520)
    var session = openTestViewer(Captions.viewerPlugin(), &host.root, file, infoParent: &host.root)
    Swag.require(session.view != null and session.collectMatches != null and session.revealMatch != null)
    let view = assume cast(*Captions.Panel, session.view)
    Swag.require(view.track!.cueCount() == 12_000)
    view.dockStyle = .Center
    host.root.applyLayout()
    Swag.require(view.sheet.rows.count == 12_000)

    var matches: Array'Viewer.SearchMatch
    collectViewerMatches(session.collectMatches, "needle", &matches)
    Swag.require(matches.count == 12_000)
    Swag.require(session.revealMatch(matches[matches.count - 1], "needle"))
    Swag.require(view.currentCue == 11_999)
    var image = host.render(&host.root)
    Swag.require(image.isValid())
}
