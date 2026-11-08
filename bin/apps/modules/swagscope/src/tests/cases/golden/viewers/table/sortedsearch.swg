#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// A sorted numeric table keeps its found cell and selected row legible in Papier.
#[Swag.TestTag("golden")]
#test
{
    let folder = Testing.tempFilePath("scope-table-sorted-", "")
    expect Directory.create(folder)
    defer discard catch Directory.delete(folder, recurse: true)
    let file = Path.combine(folder, "sorted-quantities.csv")
    expect File.writeAllText(file, "Name,Quantity,Status\nAtlas,120,Ready\nBeacon,4,Waiting\nCedar,38,Ready\nTarget,15,Review\nDelta,240,Ready\nEmber,7,Waiting\n")

    var host: Testing.HeadlessHost
    host.setup(900, 560)
    host.theme.setLight()
    host.notify(.ThemeChanged)
    var session = openTestViewer(Table.viewerPlugin(), &host.root, file, commandParent: &host.root)
    Swag.require(session.view != null and session.collectMatches != null and session.revealMatch != null)
    let view = assume cast(*Table.Panel, session.view)
    completeViewerBackgroundLoad(&host, &view.load)
    view.dockStyle = .Center
    host.root.applyLayout()
    discard host.render(&host.root)
    Swag.require(view.list.lineCount() == 6 and view.list.position.height > 100)
    view.sortBy(1)
    Swag.require(view.numeric[1] and view.order[0] == 1 and view.order[5] == 4)

    var matches: Array'Viewer.SearchMatch
    collectViewerMatches(session.collectMatches, "Target", &matches)
    Swag.require(matches.count == 1 and session.revealMatch(matches[0], "Target"))
    Swag.require(view.searchRow == 3 and view.list.focusIndex == view.lineOfRow(3))
    view.list.selectLine(view.lineOfRow(3))
    var image = host.renderSettled(&host.root)
    assertScopeImageGolden(&image, "viewer.table.sorted-search.paper")
}
