#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// Open a table far larger than its viewport, sort it twice, and reveal its last row by search.
#[Swag.TestTag("stress")]
#test
{
    let file = Testing.tempFilePath("scope-many-rows-", ".csv")
    defer discard catch File.delete(file)
    var source = String.from("name,quantity,group\n")
    for index in 20_000 do
        source += Format.toString("row%,%,group%\n", index, index, index % 7)
    source += "target-final,20000,group0\n"
    expect File.writeAllText(file, source)

    var host: Testing.HeadlessHost
    host.setup(820, 520)
    var session = openTestViewer(Table.viewerPlugin(), &host.root, file, commandParent: &host.root)
    Swag.require(session.view != null and session.collectMatches != null and session.revealMatch != null)
    let view = assume cast(*Table.Panel, session.view)
    completeViewerBackgroundLoad(&host, &view.load)
    Swag.require(view.document.rows.count == 20_001 and view.list.isVirtual)
    Swag.require(view.list.lineCount() == 20_001)

    view.sortBy(1)
    Swag.require(view.order[0] == 0 and view.order[20_000] == 20_000)
    view.sortBy(1)
    Swag.require(view.descending and view.order[0] == 20_000)

    var matches: Array'Viewer.SearchMatch
    collectViewerMatches(session.collectMatches, "target-final", &matches)
    Swag.require(matches.count == 1 and session.revealMatch(matches[0], "target-final"))
    Swag.require(view.searchRow == 20_000 and view.list.focusIndex == 0)
    var image = host.render(&host.root)
    Swag.require(image.isValid())
}
