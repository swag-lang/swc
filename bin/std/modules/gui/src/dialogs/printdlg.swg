#global namespace PrintDlg

using Core, Pixel

// Opens the standard print workflow for a still image.
//
// The image is borrowed for the duration of the modal call. `dpi` defines its physical
// size at 100%. The caller supplies the proposed job and PDF file name in `name`.
public func printImage(from: *Surface, image: Image, name: string, dpi = 96.0'f32)
{
    var document: Print.Document
    document.kind     = .Image
    document.name     = name
    document.image    = image
    document.imageDpi = dpi
    show(from, &document, "")
}

// Opens the standard print workflow for a PDF file.
//
// The preview uses the document's page boxes and rotation. The modal call reads the source
// file as needed, so it must remain available until the workflow ends.
public func printPdf(from: *Surface, fileName: string)
{
    let name = Path.fileName(fileName) orelse ""
    var document: Print.Document
    document.kind = .Pdf
    document.name = name
    document.pdf  = #move catch runWork(from, strings().print_Preparing, func|fileName|()->Pdf.Reader fail
    {
        return try Pdf.Reader.open(fileName)
    })
    {
        reportError(from, Swag.err)
        return
    }

    show(from, &document, fileName)
}

// Opens the standard print workflow for a plain text file.
//
// `encoding` is the file's encoding. Output uses a fixed-pitch font, with `tabWidth` measured
// in spaces and lines wrapped within the printable width.
public func printText(from: *Surface, fileName: string, encoding: Text.Encoding = .Utf8, tabWidth = 4'u32)
{
    let name = Path.fileName(fileName) orelse ""
    var document: Print.Document
    document.kind     = .Text
    document.name     = name
    document.tabWidth = Math.max(tabWidth, 1)
    document.text     = #move catch runWork(from, strings().print_Preparing, func|fileName, encoding|()->String fail
    {
        return try File.readAllText(fileName, encoding)
    })
    {
        reportError(from, Swag.err)
        return
    }

    show(from, &document, fileName)
}
