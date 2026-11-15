#global if #command == Swag.CompilerCommand.Test
#global internal

using Core, Gui

func odsTestPackage(body: string, styles: string = "", settings: string = "", manifest: string = "")->String
{
    let content = Format.toString("""<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"><office:body><office:spreadsheet>%</office:spreadsheet></office:body></office:document-content>""", body)
    let names   = ["mimetype", "content.xml", "styles.xml", "settings.xml", "META-INF/manifest.xml"]
    let values  = ["application/vnd.oasis.opendocument.spreadsheet", content.toString(), styles, settings, manifest]
    var entries: Array'ZipFixtureEntry
    for name, index in names
    {
        if not values[index].count and index >= 2 do
            continue
        var entry: ZipFixtureEntry
        entry.name = name
        entry.plain.add(values[index])
        entry.packed = entry.plain
        entries.add(entry)
    }

    let path = Testing.tempFilePath("scope-ods-", ".ods")
    discard expect File.writeAllBytes(path, buildZipEntries(entries.toSlice()).toSlice())
    return path
}
