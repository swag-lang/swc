#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Gui.Testing, Viewers

// Font, color, highlight and paragraph metrics survive the RTF-to-reading projection.
#test
{
    let document = expect Rtf.Document.load(scopeTestDataPath("viewer.styles.rtf"))
    Swag.require(document.paper and not document.simplifiedStyles and document.paragraphs == 7)
    for style in ["font-family:'Segoe UI'", "font-family:'Courier New'", "font-size:24pt", "color:#196051", "background-color:#FFEDAE", "margin-bottom:14pt", "margin-left:18pt", "line-height:1.25"] do
        Swag.require(Utf8.contains(document.html, style), style)
    Swag.require(Utf8.contains(document.html, "<i>Keep the useful things close.") and Utf8.contains(document.html, "Read at your own pace."))
    Swag.require(not Utf8.contains(document.html, "FIELD NOTES;") and not Utf8.contains(document.html, "fonttbl"))
}

// Group restoration and plain reset remove local character colors and sizes without losing prose.
#test
{
    let source = "{\\rtf1\\ansi{\\colortbl;\\red255\\green0\\blue0;} A {\\fs36\\cf1 red} normal \\fs30 big \\plain reset.\\par}"
    let path   = writeTempFile("group-styles.rtf", cast(const [..] u8, source))
    defer discard catch File.delete(path)
    let document = expect Rtf.Document.load(path)
    Swag.require(Utf8.contains(document.html, "<span style=\"font-size:18pt;color:#FF0000;\">red</span> normal "))
    Swag.require(Utf8.contains(document.html, "<span style=\"font-size:15pt;\">big </span>reset."))
}

// Font metadata is bounded, escaped and separated from alternate names and embedded binary bytes.
#test
{
    let source  = "{\\f0 Segoe UI{\\*\\falt Secret};}{\\f7 Caf\\'e9;}{\\f8 Evil'\\{font;}}}"
    let catalog = expect Rtf.Catalog.parse(cast(const [..] u8, source), 0, 2, true)
    Swag.require(catalog.fonts.count == 2 and
                 catalog.fonts[0].family == "Segoe UI" and
                 catalog.fonts[1].family == "Café")
    Swag.require(catalog.limited)
    let binary = "\\bin4 {}\\x;\\red1\\green2\\blue3;}"
    let colors = expect Rtf.Catalog.parse(cast(const [..] u8, binary), 0, 2, false)
    Swag.require(colors.colors.count == 2 and colors.colors[0].isEmpty() and colors.colors[1] == "010203")
}

// Damaged tables fail safely; unknown style references keep readable text and a limitation notice.
#test
{
    for table in ["{\\colortbl;\\red999;}", "{\\colortbl;\\red-1;}", "{\\fonttbl{\\f0 Unclosed;"]
    {
        let source = Format.toString("{\\rtf1\\ansi % Readable.\\par}", table)
        let path   = writeTempFile("bad-style-table.rtf", cast(const [..] u8, source.toString()))
        defer discard catch File.delete(path)
        var error: Swag.Error
        discard catch Rtf.Document.load(path) as error
        Swag.require(error.value() is Errors.InvalidFormatError)
    }

    let source = "{\\rtf1\\ansi \\f999\\cf999\\fs9999 Readable.\\par}"
    let path   = writeTempFile("unknown-style.rtf", cast(const [..] u8, source))
    defer discard catch File.delete(path)
    let document = expect Rtf.Document.load(path)
    Swag.require(document.simplifiedStyles and Utf8.contains(document.html, "Readable."))
    Swag.require(Utf8.contains(document.details(), Rtf.texts().ui_StylesSimplified))
}

// Paragraph properties restore at group boundaries; explicit zero margins remain explicit.
#test
{
    let source = "{\\rtf1\\ansi \\pard\\sb0\\sa0\\fi240 First.\\par {\\qc\\li360\\sb120 Centered.\\par}Left again.}"
    let path   = writeTempFile("paragraph-styles.rtf", cast(const [..] u8, source))
    defer discard catch File.delete(path)
    let document = expect Rtf.Document.load(path)
    Swag.require(Utf8.contains(document.html, "margin-top:0pt;margin-bottom:0pt;text-indent:12pt"))
    Swag.require(Utf8.contains(document.html, "text-align:center;margin-top:6pt;margin-bottom:0pt;margin-left:18pt;text-indent:12pt"))
    Swag.require(Utf8.contains(document.html, "<p style=\"margin-top:0pt;margin-bottom:0pt;text-indent:12pt\">Left again.</p>"))
}
