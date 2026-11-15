#global if #command == Swag.CompilerCommand.Test
#global internal

using Core, Gui

func odpTestPackage(body: string, styles: string = "", manifest: string = "")->String
{
    let content = Format.toString("""<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0" xmlns:presentation="urn:oasis:names:tc:opendocument:xmlns:presentation:1.0" xmlns:xlink="http://www.w3.org/1999/xlink"><office:body><office:presentation>%</office:presentation></office:body></office:document-content>""", body)
    let names   = ["mimetype", "content.xml", "styles.xml", "META-INF/manifest.xml"]
    let values  = ["application/vnd.oasis.opendocument.presentation", content.toString(), styles, manifest]
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

    let path = Testing.tempFilePath("scope-odp-", ".odp")
    discard expect File.writeAllBytes(path, buildZipEntries(entries.toSlice()).toSlice())
    return path
}
