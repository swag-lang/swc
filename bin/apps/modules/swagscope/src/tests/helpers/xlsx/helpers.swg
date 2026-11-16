#global if #command == Swag.CompilerCommand.Test
#global internal

using Core, Gui

// Repackages a producer-style workbook with one controlled XML change.
func formattedWorkbookVariant(part: string, before, after: string, replacePart = false)->String
{
    let source  = scopeTestDataPath("viewer.formats.xlsx")
    let archive = expect Archive.Zip.load(source)
    var entries: Array'ZipFixtureEntry
    for item in archive.entries
    {
        var entry: ZipFixtureEntry
        entry.name  = item.path
        entry.plain = expect Archive.Zip.loadEntry(source, item)
        if item.path == part
        {
            var text = String.from(cast(string, entry.plain.toSlice()))
            if replacePart do
                text = after
            else do
                text.replace(before, after)
            entry.plain.clear()
            entry.plain.add(text.toSlice())
        }

        entry.packed = entry.plain
        entries.add(entry)
    }

    let path = Gui.Testing.tempFilePath("scope-xlsx-formats-", ".xlsx")
    discard expect File.writeAllBytes(path, buildZipEntries(entries.toSlice()).toSlice())
    return path
}
