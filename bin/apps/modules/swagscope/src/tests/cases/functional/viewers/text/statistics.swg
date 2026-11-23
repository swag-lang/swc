#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// The full-file profile keeps source bytes, the first longest-line location, and exact scope.
#test
{
    var counter: TextStatisticsCounter
    counter.append("short\nlong", 10)
    counter.append("est line\r", 9)
    counter.append("\nlast", 5)

    let statistics = counter.finish(.Exact)
    Swag.require(statistics.bytes == 24)
    Swag.require(statistics.lines == 3 and statistics.longest == 12 and statistics.longestLine == 2)
    Swag.require(statistics.extent == .Exact)

    var data: MediaInfoData
    data.addTextStatistics(&statistics)
    var byteCount: String
    var coverageLabel: String
    var longest: String
    for row in data.rows
    {
        if row.field == .ByteCount do
            byteCount = row.value
        elif row.field == .CountExtent do
            coverageLabel = row.value
        elif row.field == .LongestLine do
            longest = row.value
    }

    Swag.require(byteCount == "24")
    Swag.require(coverageLabel == mediaInfoStrings().exactExtent)
    Swag.require(longest == Format.toString(mediaInfoStrings().longestLineValue, "12 characters", 2))
}

// An empty file is still an exact count and reports zero source bytes.
#test
{
    var counter: TextStatisticsCounter
    let statistics = counter.finish(.Exact)

    var data: MediaInfoData
    data.addTextStatistics(&statistics)
    var byteCount: String
    var coverageLabel: String
    for row in data.rows
    {
        if row.field == .ByteCount do
            byteCount = row.value
        elif row.field == .CountExtent do
            coverageLabel = row.value
    }

    Swag.require(byteCount == "0" and coverageLabel == mediaInfoStrings().exactExtent)
}

// The viewer's file scan includes a skipped UTF-8 BOM in its byte count.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-text-statistics-bom-", ".txt")
    defer discard catch File.delete(fileName)
    let bytes = [0xEF'u8, 0xBB'u8, 0xBF'u8, 'a'u8, '\n'u8, 'b'u8]
    discard expect File.writeAllBytes(fileName, bytes)

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    var session = openTestViewer(PlainText.viewerPlugin(), &host.root, fileName)
    let view = assume cast(*PlainText.Panel, session.view)
    defer discard view.retire()
    completeTextReads(&host, view)
    completeTextStatistics(&host, view)

    Swag.require(view.encoding == .Utf8 and view.contentStart == 3)
    Swag.require(view.statistics.bytes == bytes.count and view.statistics.extent == .Exact)
}
