#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

func packageWithRelationships(source: string)->String
{
    var entries: [1] ZipFixtureEntry
    entries[0].name = "word/_rels/document.xml.rels"
    entries[0].plain.add(source)
    entries[0].packed = entries[0].plain
    let path = Gui.Testing.tempFilePath("scope-relationships-", ".docx")
    discard expect File.writeAllBytes(path, buildZipEntries(entries[0 until entries.count]).toSlice())
    return path
}

#test
{
    var scan = Package.Scanner.create("<?xml version='1.0'?><root><!-- note --><x:item id='a&amp;b' href=\"a&gt;b\"/><x:text>One &#xE9; &lt; two</x:text></root>")
    var token: Package.Token
    Swag.require(scan.next(&token) and token.isElement("root") and token.kind == .Start)
    Swag.require(scan.next(&token) and token.isElement("item") and token.empty)
    Swag.require(token.attribute("id") == "a&b" and token.attribute("href") == "a>b")
    Swag.require(scan.next(&token) and token.isElement("text") and token.kind == .Start)
    Swag.require(scan.next(&token) and token.kind == .Text and token.text == "One é < two")
    Swag.require(scan.next(&token) and token.isElement("text") and token.kind == .End)
    Swag.require(scan.next(&token) and token.isElement("root") and token.kind == .End)
    Swag.require(not scan.next(&token) and not scan.damaged)
}

#test
{
    var scan = Package.Scanner.create("<p:sldId id='256' r:id='rId2'/>")
    var token: Package.Token
    Swag.require(scan.next(&token) and token.isElement("sldId"))
    Swag.require(token.attribute("id") == "256")
    Swag.require(token.attribute("r:id") == "rId2")
}

#test
{
    var scan = Package.Scanner.create("<!DOCTYPE root [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><root/>")
    var token: Package.Token
    Swag.require(not scan.next(&token) and scan.damaged)
}

#test
{
    Swag.require(Package.resolvePath("OEBPS/Text", "../Images/cover.png") == "OEBPS/Images/cover.png")
    Swag.require(Package.resolvePath("", "../outside.txt").isEmpty())
    Swag.require(Package.resolvePath("", "https://elsewhere/image.png").isEmpty())
    Swag.require(Package.resolveRelationshipTarget("xl", "/xl/worksheets/sheet1.xml") == "xl/worksheets/sheet1.xml")
    Swag.require(Package.resolveRelationshipTarget("ppt", "slides/slide1.xml") == "ppt/slides/slide1.xml")
    Swag.require(Package.resolveRelationshipTarget("ppt", "/../escape.xml").isEmpty())
}

// External relationships preserve web targets while local relationships keep their path contract.
#test
{
    let fileName = scopeTestDataPath("viewer.image.docx")
    let archive = expect Archive.Zip.load(fileName)
    let reader = Package.PartReader{fileName, &archive, "Invalid XML", "XML too large"}
    let external = expect reader.externalRelationships("word/document.xml")
    let local = expect reader.relationships("word/document.xml")
    Swag.require(external.count == 1 and local.count == 1)
    Swag.require(external[0].id == "rIdRemote")
    Swag.require(external[0].target == "https://example.invalid/never.jpg")
    Swag.require(Utf8.endsWith(external[0].kind, "/image"))
    Swag.require(local[0].id == "rIdPhoto" and local[0].path == "word/media/photo.jpg")
}

// A package with no relationship part has no external relationships.
#test
{
    let fileName = scopeTestDataPath("viewer.docx")
    let archive = expect Archive.Zip.load(fileName)
    let reader = Package.PartReader{fileName, &archive, "Invalid XML", "XML too large"}
    let external = expect reader.externalRelationships("word/document.xml")
    Swag.require(external.isEmpty())
}

// Safe HTTP(S) links and one-recipient mail links are returned; unsafe targets are omitted.
#test
{
    let source = """<Relationships>
        <Relationship Id="web" Type="hyperlink" Target="https://example.invalid/page" TargetMode="External"/>
        <Relationship Id="mail" Type="hyperlink" Target="mailto:help@example.invalid" TargetMode="External"/>
        <Relationship Id="upperScheme" Type="hyperlink" Target="HTTPS://example.invalid/case" TargetMode="External"/>
        <Relationship Id="script" Type="hyperlink" Target="javascript:alert(1)" TargetMode="External"/>
        <Relationship Id="relative" Type="hyperlink" Target="../../outside" TargetMode="External"/>
        <Relationship Id="credentials" Type="hyperlink" Target="https://user@example.invalid/" TargetMode="External"/>
        <Relationship Id="markup" Type="hyperlink" Target="https://example.invalid/&lt;bad&gt;" TargetMode="External"/>
        <Relationship Id="injection" Type="hyperlink" Target="mailto:help@example.invalid%0d%0aBcc:other@example.invalid" TargetMode="External"/>
        <Relationship Id="multiple" Type="hyperlink" Target="mailto:first@example.invalid,second@example.invalid" TargetMode="External"/>
        <Relationship Id="query" Type="hyperlink" Target="mailto:help@example.invalid?subject=Hello" TargetMode="External"/>
        <Relationship Id="missingAt" Type="hyperlink" Target="mailto:help.example.invalid" TargetMode="External"/>
        <Relationship Id="emptyRecipient" Type="hyperlink" Target="mailto:@example.invalid" TargetMode="External"/>
    </Relationships>"""
    let fileName = packageWithRelationships(source)
    defer discard catch File.delete(fileName)
    let archive = expect Archive.Zip.load(fileName)
    let reader = Package.PartReader{fileName, &archive, "Invalid XML", "XML too large"}
    let external = expect reader.externalRelationships("word/document.xml")
    Swag.require(external.count == 3)
    Swag.require(external[0].id == "web" and external[0].target == "https://example.invalid/page")
    Swag.require(external[1].id == "mail" and external[1].target == "mailto:help@example.invalid")
    Swag.require(external[2].id == "upperScheme" and external[2].target == "HTTPS://example.invalid/case")
}

// Present but malformed or ambiguous relationship XML is rejected; a missing part above is empty.
#test
{
    const Invalid: [2] string = [
        "<Relationships><Relationship Id='r' Target='https://example.invalid' Type='hyperlink'></Relationships>",
        "<Relationships><Relationship Id='same' Target='https://example.invalid' Type='hyperlink' TargetMode='External'/><Relationship Id='same' Target='https://other.invalid' Type='hyperlink' TargetMode='External'/></Relationships>"]
    for source in Invalid
    {
        let fileName = packageWithRelationships(source)
        defer discard catch File.delete(fileName)
        let archive = expect Archive.Zip.load(fileName)
        let reader = Package.PartReader{fileName, &archive, "Invalid XML", "XML too large"}
        var error: Swag.Error
        discard catch reader.externalRelationships("word/document.xml") as error
        Swag.require(error.value() is Errors.InvalidFormatError)
    }
}
