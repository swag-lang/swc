#global internal
#global namespace Viewers.Hex

using Core

// Tabs the structure strip names at most. A format with more top-level structures than a window
// is wide keeps the first ones; the rest stay reachable from the caret.
const TabLimit = 24'u64

// Strings a structure is read in, copied from the active language when the read starts. A reader
// names what it finds in that language, whatever the interface switches to while it runs.
tls private var g_ReadTexts: Binary.Texts

// One tab over the grid: a structure of the file, or a run of neighbouring structures of one name,
// such as the image data chunks of a PNG.
struct StructureTab
{
    label:  String     // The structure's name, followed by "× n" for a run.
    offset: u64        // First byte the tab covers.
    length: u64        // Bytes the tab covers.
}

// What the binary reader recognized in the file, as the byte view shows it: the format's name, its
// byte order, its structures as tabs, and every decoded field for the inspector.
struct Structure
{
    formatName: String
    bigEndian:  bool
    report:     Binary.Report
    tabs:       Array'StructureTab
}

impl Structure
{
    // Reads the structure of `fileName` with the binary viewer's readers.
    //
    // A file no reader takes apart gives a structure with no tabs: the bytes are all there is.
    func read(fileName: string)->Structure
    {
        var result: #returntype

        g_ReadTexts = Binary.texts()[]
        Binary.setTextsOverride(&g_ReadTexts)
        defer Binary.setTextsOverride(null)

        var document: Binary.Document
        if not document.open(fileName) or document.kind == .Unknown do
            return result

        result.formatName = #move document.report.formatName
        result.bigEndian  = document.image.bigEndian
        result.report     = #move document.report
        result.collectTabs()
        return result
    }

    // Returns the row of the top-level structure that holds `offset`, the narrowest when several
    // do, or `Swag.U64.Max`.
    //
    // The summary of the file opens the report and covers every byte, so it is never the answer.
    mtd groupAt(offset: u64)->u64
    {
        var result = Swag.U64.Max
        var span   = Swag.U64.Max
        for row, index in .report.rows where index and .isStructure(row)
        {
            if offset < row.offset or offset - row.offset >= row.length or row.length >= span do
                continue
            result = index
            span   = row.length
        }

        return result
    }

    // Returns the index of the tab that holds `offset`, or `Swag.U64.Max`.
    mtd tabAt(offset: u64)->u64
    {
        for tab, index in .tabs where offset >= tab.offset and offset - tab.offset < tab.length do
            return index
        return Swag.U64.Max
    }

    // Returns the row of the decoded value that holds `offset` and is read as one scalar, or
    // `Swag.U64.Max`.
    mtd fieldAt(offset: u64)->u64
    {
        for row, index in .report.rows where row.kind == .Field and row.offset != Swag.U64.Max
        {
            if offset < row.offset or offset - row.offset >= row.length do
                continue
            if row.length == 1 or row.length == 2 or row.length == 4 or row.length == 8 do
                return index
        }

        return Swag.U64.Max
    }

    // Returns the rows of the values decoded directly under the group at row `group`.
    mtd fieldsOf(group: u64)->Array'u64
    {
        var result: #returntype
        let level = .report.rows[group].level
        for index in group + 1 until .report.rows.count
        {
            let row = &.report.rows[index]
            if row.level <= level do
                break
            if row.kind == .Field and row.level == level + 1 do
                result.add(index)
        }

        return result
    }

    // Reports whether `row` is a top-level structure with a byte range a tab can stand for.
    private mtd isStructure(row: const *Binary.Row)->bool => row.kind == .Group and row.level == 0 and row.offset != Swag.U64.Max and row.length

    // Builds one tab per top-level structure, in file order, folding a run of neighbours that share
    // a name into one tab.
    private mtd collectTabs()
    {
        var groups: Array'u64
        for row, index in .report.rows where index and .isStructure(row) do
            groups.add(index)

        let rows = &.report.rows
        groups.sort(func|rows|(a, b: u64)->s32
        {
            let left  = rows[a].offset
            let right = rows[b].offset
            return left < right ? -1 : (left > right ? 1 : 0)
        })

        var counts: Array'u64
        for group in groups
        {
            let row = &.report.rows[group]
            if not .tabs.isEmpty() and .tabs[.tabs.count - 1].label == row.label
            {
                let tab = &.tabs[.tabs.count - 1]
                tab.length = Math.max(tab.offset + tab.length, row.offset + row.length) - tab.offset
                counts[counts.count - 1] += 1
                continue
            }

            if .tabs.count == TabLimit do
                break
            .tabs.add({row.label, row.offset, row.length})
            counts.add(1)
        }

        for index in .tabs.count where counts[index] > 1 do
            .tabs[index].label = Format.toString("% × %", .tabs[index].label, counts[index])
    }
}
