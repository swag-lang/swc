#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

private func textHistoryRows(view: *PlainText.Panel, host: *Testing.HeadlessHost, query: string)->Lens.Results
{
    var results = Testing.lensResults(query)
    var entries = Viewer.LensEntries.create(&results, PlainText.texts().ui_Name, host.theme)
    view.describeLens(&entries)
    return results
}

// Typed text destinations return to their source offset, move forward again, and start a new branch.
#test
{
    let fileName = Testing.tempFilePath("scope-text-history-", ".txt")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, "first\nsecond\nthird\nfourth\n")

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    var session = openTestViewer(PlainText.viewerPlugin(), &host.root, fileName)
    let view = assume cast(*PlainText.Panel, session.view)
    completeTextReads(&host, view)
    Swag.require(view.lensHistory.isEmpty() and view.lensHistoryIndex == Swag.U64.Max)
    let initial = view.currentByteOffset()
    Swag.require(initial != Swag.U64.Max)

    var lineResults = Testing.lensResults("3", .Line)
    Swag.require(view.describeTypedPosition(&lineResults))
    let firstJump = unwrap lineResults.sections[0]
    firstJump.entries[0].run!()
    completeTextReads(&host, view)
    let thirdLine = view.lines.offsetOfLine(fileName, 3, view.encoding, view.contentStart)
    Swag.require(view.lensHistory.count == 2 and view.lensHistory[0] == initial and view.lensHistory[1] == thirdLine)

    var backResults = textHistoryRows(view, &host, "Back in Text")
    var back: *Lens.Entry?
    for &entry in backResults.sections[0]!.entries where entry.title == PlainText.texts().ui_Back do
        back = entry
    Swag.require(back != null)
    let backEntry = back
    Swag.require(not backEntry.disabled and backEntry.defaultKey.modifiers == .Alt and backEntry.defaultKey.key == .Left)
    backEntry.run!()
    completeTextReads(&host, view)
    Swag.require(view.currentByteOffset() == initial)

    var forwardResults = textHistoryRows(view, &host, "Forward in Text")
    var forward: *Lens.Entry?
    for &entry in forwardResults.sections[0]!.entries where entry.title == PlainText.texts().ui_Forward do
        forward = entry
    Swag.require(forward != null)
    let forwardEntry = forward
    Swag.require(not forwardEntry.disabled and forwardEntry.defaultKey.modifiers == .Alt and forwardEntry.defaultKey.key == .Right)
    forwardEntry.run!()
    completeTextReads(&host, view)
    Swag.require(view.currentByteOffset() == thirdLine)

    var backKey = KeyEvent{kind: .Pressed, key: .Left, modifiers: .Alt}
    Swag.require(view.handleLensHistoryKey(&backKey))
    completeTextReads(&host, view)
    Swag.require(view.currentByteOffset() == initial)
    var forwardKey = KeyEvent{kind: .Pressed, key: .Right, modifiers: .Alt}
    Swag.require(view.handleLensHistoryKey(&forwardKey))
    completeTextReads(&host, view)
    Swag.require(view.currentByteOffset() == thirdLine)

    var again = textHistoryRows(view, &host, "Back in Text")
    for &entry in again.sections[0]!.entries where entry.title == PlainText.texts().ui_Back do
        entry.run!()
    completeTextReads(&host, view)
    lineResults = Testing.lensResults("4", .Line)
    Swag.require(view.describeTypedPosition(&lineResults))
    let fourthJump = unwrap lineResults.sections[0]
    fourthJump.entries[0].run!()
    completeTextReads(&host, view)
    Swag.require(view.lensHistory[view.lensHistoryIndex] == view.lines.offsetOfLine(fileName, 4, view.encoding, view.contentStart))

    let noForward = textHistoryRows(view, &host, "Forward in Text")
    for &entry in noForward.sections[0]!.entries where entry.title == PlainText.texts().ui_Forward do
        Swag.require(entry.disabled)

    let secondLine = view.lines.offsetOfLine(fileName, 2, view.encoding, view.contentStart)
    Swag.require(view.revealOffset(secondLine, "", caret: true))
    completeTextReads(&host, view)
    lineResults = Testing.lensResults("3", .Line)
    Swag.require(view.describeTypedPosition(&lineResults))
    let thirdAgain = unwrap lineResults.sections[0]
    thirdAgain.entries[0].run!()
    completeTextReads(&host, view)
    Swag.require(view.lensHistory[view.lensHistoryIndex - 1] == secondLine)
    var returnResults = textHistoryRows(view, &host, "Back in Text")
    for &entry in returnResults.sections[0]!.entries where entry.title == PlainText.texts().ui_Back do
        entry.run!()
    completeTextReads(&host, view)
    Swag.require(view.currentByteOffset() == secondLine)
}

// The trail is bounded and survives replacing the resident text window with a distant one.
#test
{
    let fileName = Testing.tempFilePath("scope-text-history-stream-", ".txt")
    defer discard catch File.delete(fileName)
    var source: String
    for line in 0 until 50_000 do
        source += Format.toString("line %\n", line)
    discard expect File.writeAllText(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    var session = openTestViewer(PlainText.viewerPlugin(), &host.root, fileName)
    let view = assume cast(*PlainText.Panel, session.view)
    completeTextReads(&host, view)

    for line in 2 until 72
    {
        let offset = view.lines.offsetOfLine(fileName, line, view.encoding, view.contentStart)
        Swag.require(offset != Swag.U64.Max)
        Swag.require(view.revealLensDestination(offset))
        completeTextReads(&host, view)
    }
    Swag.require(view.lensHistory.count == 64)
    let latest = view.lines.offsetOfLine(fileName, 71, view.encoding, view.contentStart)
    Swag.require(view.lensHistory[view.lensHistoryIndex] == latest)

    let distant = 400_000'u64
    Swag.require(view.revealLensDestination(distant))
    completeTextReads(&host, view)
    Swag.require(view.residentStart > 0 and view.lensHistory[view.lensHistoryIndex] == distant)

    var backResults = textHistoryRows(view, &host, "Back in Text")
    for &entry in backResults.sections[0]!.entries where entry.title == PlainText.texts().ui_Back do
        entry.run!()
    completeTextReads(&host, view)
    Swag.require(view.residentStart == 0 and view.currentByteOffset() == latest)
}
