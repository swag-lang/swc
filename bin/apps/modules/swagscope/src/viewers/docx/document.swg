#global internal
#global namespace Viewers.Docx

using Core

// The readable body of one WordprocessingML document.
struct Document
{
    html:          String
    paragraphs:    u64
    tables:        u64
    omittedImages: u64
}

impl Document
{
    // Reads paragraphs and tables from the main document part without executing embedded content.
    func load(fileName: string)->Document fail
    {
        let archive = try Archive.Zip.load(fileName)
        let entry = archive.tryFindEntry("word/document.xml")
        if not entry do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        if entry.uncompressedSize > 16 * 1024 * 1024 do
            fail Errors.UnsupportedFormatError{texts().err_TooLarge}

        let bytes = try Archive.Zip.loadEntry(fileName, entry)
        var scan = Package.Scanner.create(cast(string, bytes.toSlice()))
        var token: Package.Token
        var result: #returntype
        result.html = "<html><body>"
        var inText = false
        var inBody = false

        while scan.next(&token)
        {
            if token.kind == .Start
            {
                if token.isElement("body") do
                    inBody = true
                if not inBody do
                    continue
                if token.isElement("tbl")
                {
                    result.tables += 1
                    result.html += "<table>"
                }
                elif token.isElement("tr") do
                    result.html += "<tr>"
                elif token.isElement("tc") do
                    result.html += "<td>"
                elif token.isElement("p")
                {
                    result.paragraphs += 1
                    result.html += "<p>"
                }
                elif token.isElement("t") do
                    inText = true
                elif token.isElement("br") do
                    result.html += "<br>"
                elif token.isElement("tab") do
                    result.html += "&emsp;"
                elif token.isElement("drawing") or token.isElement("pict")
                {
                    result.omittedImages += 1
                    result.html += "<span>"
                    Package.appendHtmlEscaped(&result.html, texts().ui_ImageOmitted)
                    result.html += "</span>"
                }

                if token.empty and token.isElement("t") do
                    inText = false
            }
            elif token.kind == .End
            {
                if token.isElement("body") do
                    inBody = false
                if not inBody and not token.isElement("body") do
                    continue
                if token.isElement("t") do
                    inText = false
                elif token.isElement("p") do
                    result.html += "</p>"
                elif token.isElement("tc") do
                    result.html += "</td>"
                elif token.isElement("tr") do
                    result.html += "</tr>"
                elif token.isElement("tbl") do
                    result.html += "</table>"
            }
            elif inBody and inText do
                Package.appendHtmlEscaped(&result.html, token.text)
            if result.html.count > 32 * 1024 * 1024 do
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        }
        if scan.damaged or not result.paragraphs and not result.tables do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        result.html += "</body></html>"
        return result
    }
}
