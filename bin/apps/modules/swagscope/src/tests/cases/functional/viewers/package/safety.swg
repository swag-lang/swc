#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Viewers

func escaped(source: string)->String
{
    var result: String
    Package.appendHtmlEscaped(&result, source)
    return result
}

// Returns the text of the first text token of `source`, and whether the scanner refused the input.
func firstText(source: string)->{ text: String, damaged: bool }
{
    var scan = Package.Scanner.create(source)
    var token:  Package.Token
    var result: #returntype
    while scan.next(&token)
    {
        if token.kind == .Text
        {
            result.text = token.text
            break
        }
    }

    result.damaged = scan.damaged
    return result
}

// Document text cannot introduce markup or leave a double-quoted attribute, whatever it contains.
#test
{
    Swag.require(escaped("plain text") == "plain text")
    Swag.require(escaped("<script>alert(1)</script>") == "&lt;script&gt;alert(1)&lt;/script&gt;")
    Swag.require(escaped("\" onload=\"run()") == "&quot; onload=&quot;run()")
    Swag.require(escaped("a & b &amp; c") == "a &amp; b &amp;amp; c")
    Swag.require(escaped("café — 日本") == "café — 日本")
    Swag.require(escaped("").isEmpty())

    // Appending keeps what the caller already wrote.
    var result: String = "<p>"
    Package.appendHtmlEscaped(&result, "1 < 2")
    Swag.require(result == "<p>1 &lt; 2")
}

// A package reference resolves inside the package or not at all.
#test
{
    const Inside: [7] { base: string, reference: string, path: string } = [
        {"OEBPS",         "chapter.xhtml",             "OEBPS/chapter.xhtml"},
        {"OEBPS",         "./text/../chapter.xhtml",   "OEBPS/chapter.xhtml"},
        {"OEBPS/Text",    "../Styles/book.css",        "OEBPS/Styles/book.css"},
        {"OEBPS",         "chapter.xhtml#section-2",   "OEBPS/chapter.xhtml"},
        {"OEBPS",         "chapter.xhtml?print=1#top", "OEBPS/chapter.xhtml"},
        {"",              "mimetype",                  "mimetype"},
        {"/OEBPS//Text/", "page.xhtml",                "OEBPS/Text/page.xhtml"}]
    for row in Inside do
        Swag.require(Package.resolvePath(row.base, row.reference) == row.path, row.reference)

    const Refused: [8] { base: string, reference: string } = [
        {"OEBPS", ""},
        {"OEBPS", "/etc/passwd"},
        {"OEBPS", "..\\outside.txt"},
        {"OEBPS", "file:///etc/passwd"},
        {"OEBPS", "https://example.invalid/a.png"},
        {"OEBPS", "../../outside.txt"},
        {"",      ".."},
        {"",      "#fragment-only"}]
    for row in Refused do
        Swag.require(Package.resolvePath(row.base, row.reference).isEmpty(), row.reference)

    // A relationship target may name the package root; it still cannot leave it.
    Swag.require(Package.resolveRelationshipTarget("word", "/word/media/image1.png") == "word/media/image1.png")
    Swag.require(Package.resolveRelationshipTarget("word", "media/image1.png") == "word/media/image1.png")
    Swag.require(Package.resolveRelationshipTarget("word", "//server/share/image1.png").isEmpty())
    Swag.require(Package.resolveRelationshipTarget("word", "/").isEmpty())
    Swag.require(Package.resolveRelationshipTarget("word", "../../image1.png").isEmpty())

    Swag.require(Package.parentPath("ppt/slides/slide1.xml") == "ppt/slides")
    Swag.require(Package.parentPath("ppt/slide1.xml") == "ppt")
    Swag.require(Package.parentPath("content.xml").isEmpty() and Package.parentPath("").isEmpty())
}

// Character references decode to their characters; anything else stops the document rather
// than being guessed.
#test
{
    Swag.require(firstText("<a>&lt;&gt;&amp;&quot;&apos;</a>").text == "<>&\"'")
    Swag.require(firstText("<a>&#233;&#xE9;&#Xe9;</a>").text == "ééé")
    Swag.require(firstText("<a>&#x1F600;</a>").text == "😀")
    Swag.require(firstText("<a>&#x10FFFF;</a>").text.length == 4)

    const Damaged: [10] string = [
        "<a>&nbsp;</a>",
        "<a>&unterminated</a>",
        "<a>&;</a>",
        "<a>&#;</a>",
        "<a>&#x;</a>",
        "<a>&#0;</a>",
        "<a>&#xD800;</a>",
        "<a>&#x110000;</a>",
        "<a>&#99999999999999;</a>",
        "<a>&#12a;</a>"]
    for source in Damaged
    {
        let read = firstText(source)
        Swag.require(read.damaged and read.text.isEmpty(), source)
    }
}

// Comments and processing instructions are skipped, a CDATA section is literal text, and an
// unterminated construct or a declaration other than the leading document type is refused.
#test
{
    Swag.require(firstText("<?xml version='1.0'?><!-- <b>not text</b> --><a>kept</a>").text == "kept")
    Swag.require(firstText("<a><![CDATA[<b>&amp;</b>]]></a>").text == "<b>&amp;</b>")

    const Damaged: [5] string = [
        "<a><!-- never closed",
        "<a><![CDATA[never closed",
        "<?xml never closed",
        "<a><!ELEMENT b ANY></a>",
        "<a><!ENTITY x 'y'></a>"]
    for source in Damaged do
        Swag.require(firstText(source).damaged, source)

    // A document type without an internal subset is allowed once, and only where asked for.
    var allowed = Package.Scanner.create("<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.1//EN\" \"a>b.dtd\"><html/>")
    allowed.allowDocumentType = true
    var token: Package.Token
    Swag.require(allowed.next(&token) and token.isElement("html") and not allowed.damaged)

    var twice = Package.Scanner.create("<!DOCTYPE html><!DOCTYPE html><html/>")
    twice.allowDocumentType = true
    Swag.require(not twice.next(&token) and twice.damaged)

    // Bytes that are not UTF-8 are refused before any token is read.
    var bytes: Array'u8
    bytes.add("<a>caf")
    bytes.add(0xE9'u8)
    bytes.add("</a>")
    var invalid = Package.Scanner.create(cast(string, bytes.toSlice()))
    Swag.require(invalid.damaged and not invalid.next(&token))
}

// A theme overrides the default scheme colors and typefaces it names with valid values only.
#test
{
    Swag.require(Package.isRgbHex("4F81BD") and Package.isRgbHex("ffffff"))
    Swag.require(not Package.isRgbHex("FFF") and
                 not Package.isRgbHex("GGGGGG") and
                 not Package.isRgbHex("#4F81BD"))
    Swag.require(not Package.isRgbHex("4F81BD00") and not Package.isRgbHex(""))

    var theme = Package.OfficeTheme.defaults()
    Swag.require(not theme.defined and theme.color("dk1") == "000000" and theme.color("accent1") == "4F81BD")
    Swag.require(theme.color("unknown").isEmpty() and theme.majorFont.isEmpty())

    var longName: String
    for 300 do
        longName += "x"
    let source = Format.toString("""<a:theme><a:themeElements>
        <a:clrScheme name="Test">
            <a:dk1><a:sysClr val="windowText" lastClr="112233"/></a:dk1>
            <a:lt1><a:srgbClr val="FEFEFE"/></a:lt1>
            <a:accent1><a:srgbClr val="not-a-color"/></a:accent1>
            <a:accent2><a:srgbClr val="ABCDEF"/></a:accent2>
        </a:clrScheme>
        <a:fontScheme>
            <a:majorFont><a:latin typeface="Aptos Display"/></a:majorFont>
            <a:minorFont><a:latin typeface="%"/><a:ea typeface="Ignored"/></a:minorFont>
        </a:fontScheme>
        <a:srgbClr val="999999"/>
        </a:themeElements></a:theme>""", longName)
    theme.read(source)
    Swag.require(theme.defined)
    Swag.require(theme.color("dk1") == "112233" and theme.color("lt1") == "FEFEFE")
    Swag.require(theme.color("accent1") == "4F81BD" and theme.color("accent2") == "ABCDEF")
    Swag.require(theme.color("hlink") == "0000FF")
    Swag.require(theme.majorFont == "Aptos Display" and theme.minorFont.isEmpty())
}

// An embedded picture becomes markup only when its bytes decode as the type it claims, and its
// description cannot leave the attribute it is written in.
#test
{
    let png = expect File.readAllBytes(scopeTestDataPath("viewer.png"))
    let jpg = expect File.readAllBytes(scopeTestDataPath("viewer.jpg"))

    let sized = Package.embeddedImageHtml(png.toSlice(), "image/png", 120, 80, "A \"quoted\" <figure>")
    Swag.require(Utf8.startsWith(sized, "<img width=\"120\" height=\"80\""))
    Swag.require(Utf8.contains(sized, "alt=\"A &quot;quoted&quot; &lt;figure&gt;\""))
    Swag.require(Utf8.contains(sized, "src=\"data:image/png;base64,") and Utf8.endsWith(sized, "\">"))
    Swag.require(not Utf8.contains(sized, "<figure>"))

    let unsized = Package.embeddedImageHtml(jpg.toSlice(), "image/jpeg", 0, 0, "")
    Swag.require(Utf8.startsWith(unsized, "<img style=\"max-width:100%;height:auto\" alt=\"\" src=\"data:image/jpeg;base64,"))
    let halfSized = Package.embeddedImageHtml(jpg.toSlice(), "image/jpeg", 120, 0, "")
    Swag.require(not Utf8.contains(halfSized, "width=\"120\""))

    // Bytes of another type, damaged bytes and unsupported types publish nothing.
    Swag.require(Package.embeddedImageHtml(png.toSlice(), "image/jpeg", 10, 10, "").isEmpty())
    Swag.require(Package.embeddedImageHtml("not an image", "image/png", 10, 10, "").isEmpty())
    Swag.require(Package.embeddedImageHtml(png.toSlice(), "image/svg+xml", 10, 10, "").isEmpty())
    Swag.require(Package.embeddedImageHtml(png.toSlice(), "text/html", 10, 10, "").isEmpty())
    Swag.require(Package.embeddedImageHtml("", "image/png", 10, 10, "").isEmpty())
}
