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
        var images = try Package.ImageCatalog.load(fileName, &archive, "word", "word/_rels/document.xml.rels",
                                                   texts().err_Invalid, texts().err_TooLarge)
        var reader = Reader{document: Document{html: "<html><body>"}, images: #move images}

        while scan.next(&token)
        {
            if token.kind == .Start do
                reader.start(&token)
            elif token.kind == .End do
                reader.end(&token)
            elif reader.inBody and reader.inText
            {
                if reader.inRun do
                    Package.appendHtmlEscaped(&reader.run, token.text)
                else do
                    Package.appendHtmlEscaped(&reader.paragraph, token.text)
            }
            if reader.document.html.count + reader.paragraph.count + reader.run.count > 32 * 1024 * 1024 do
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        }
        if scan.damaged or reader.inBody or reader.inParagraph or
           not reader.document.paragraphs and not reader.document.tables do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        reader.document.html += "</body></html>"
        return #move reader.document
    }
}
