#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Math, Pixel, Gui.Print

#test
{
    let size  = paperSize(.Letter)
    let setup = PageSetup{paper: .Letter, landscape: true, margin: 18}
    let sheet = pdfSheet(setup)
    Swag.require(sheet.size == Point{size.y, size.x})

    var document: Document
    document.image    = Image.create(100, 400, .RGB8)
    document.imageDpi = 72
    document.image.fill(Color.fromArgb(Argb.Red))

    let printable = Sheet{size: {220, 300}, imageable: {24, 6, 190, 288}}
    var layout    = expect prepare(&document, printable, setup)
    Swag.require(layout.content == Rectangle{24, 18, 178, 264})
    Swag.require(layout.fitsPrinter({{220.1, 300}, printable.imageable}))
    Swag.require(not layout.fitsPrinter({printable.size, {30, 6, 184, 288}}))
    Swag.require(not layout.fitsPrinter({{230, 300}, printable.imageable}))

    let sizeInPoints = expect layout.sourceSize(0)
    let fitted       = layout.pagePlacement(sizeInPoints)
    Swag.require(Math.isEqualEpsilon(fitted.width, 66, 0.001))
    Swag.require(Math.isEqualEpsilon(fitted.height, 264, 0.001))
    Swag.require(not expect layout.clips(0, 1))
    var image = expect layout.render(0, 72)
    Swag.require(image.isValid() and image.width == 220 and image.height == 300)
    Swag.require(image.pixelColor(110, 150).r == 255 and image.pixelColor(110, 150).g == 0)
    Swag.require(image.pixelColor(28, 150).g == 255)

    layout.placement = .Actual
    Swag.require(expect layout.clips(0, 1))
    Swag.require(layout.pagePlacement(sizeInPoints).height == 400)
    image = expect layout.render(0, 72)
    Swag.require(image.pixelColor(110, 0).g == 255 and image.pixelColor(110, 150).g == 0)
}

// A default printer may be asleep or offline. Showing the preview needs only the paper settings.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 760)
    defer host.shutdown()

    var previewed = false
    host.app.sigFrame += func|host = &host, &previewed|(app)
    {
        if app.modalSurfaces.isEmpty() do
            return
        if app.modalSurfaces.back().view() is Dialog as dlg
        {
            let tr    = strings()
            let title = dlg.title.text.toString()
            switch
            {
            case title == tr.print_Title:
                Swag.require(host.clickModalButton(PrintDlg.PreviewButton))

            case title == tr.print_Preparing:
                break

            case title == tr.print_Preview:
                previewed = true
                Swag.require(host.clickModalButton(Dialog.BtnCancel))

            default:
                Swag.require(false, title)
            }
        }
    }

    var document: Document
    document.name  = "Capture"
    document.image = Image.create(36, 20, .RGB8)
    let devices: [1] Printer = [{name: "Offline Printer", id: "swag-testing-nonexistent-printer", isDefault: true}]
    PrintDlg.showDocument(&host.surface, &document, "", devices)
    Swag.require(previewed)
}

// A task that returns a value after the Cancel button was pressed cannot expose that value.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 760)
    defer host.shutdown()

    var clicked = false
    host.app.sigFrame += func|host = &host, &clicked|(app)
    {
        if not clicked and not app.modalSurfaces.isEmpty()
        {
            clicked = true
            let cancel = unwrap app.modalSurfaces.back().view().childById(Dialog.BtnCancel)
            host.clickWnd(cancel)
        }
    }

    var failure: Swag.Error
    discard catch PrintDlg.runWork(&host.surface, strings().print_Preparing, func()->bool fail
    {
        for 2000
        {
            if Swag.isCancelled() do
                return true
            Threading.Thread.sleep(1'ms)
        }

        return false
    }) as failure
    Swag.require(clicked)
    if failure.value() is PrintError as reason do
        Swag.require(reason.kind == .Cancelled)
    else do
        Swag.require(false)
}

#test
{
    var document: Document
    document.kind = .Text
    document.text = "First\trow\r\n\rSecond row\n"
    for 40 do
        document.text += "Long ligne accentuée qui traverse la zone imprimable.\n"

    let size   = Point{180, 110}
    let layout = expect prepare(&document, {size, {0, 0, size.x, size.y}}, {margin: 12})
    Swag.require(layout.pageCount > 3)
    Swag.require(layout.rows[0] == TextRow{0, 9})
    Swag.require(layout.rows[1] == TextRow{11, 11})
    let range = expect PrintDlg.parseRange(" 2 - 3 ", layout.pageCount)
    Swag.require(range.first == 1 and range.end == 3)
    var rejected: Swag.Error
    discard catch PrintDlg.parseRange("3-2", layout.pageCount) as rejected
    Swag.require(rejected.value() is PrintError)

    let folder = Testing.tempFilePath("gui-print-range-", "")
    expect Directory.create(folder)
    defer discard catch Directory.delete(folder, recurse: true)
    var fileName = String.from("printed")

    // On Linux the target itself is valid. The old temporary name exceeded NAME_MAX.
    for #os == Swag.TargetOs.Linux ? 232 : 0 do
        fileName += "x"
    fileName += ".pdf"
    let target = Path.combine(folder, fileName)
    expect savePdf(&layout, {first: range.first, end: range.end}, target)
    var reader = expect Pdf.Reader.open(target)
    Swag.require(reader.pageCount() == 2)
    Swag.require((expect reader.pageSize(0)) == size)
    let page   = expect reader.loadPage(0)
    let image  = expect page.render()
    var hasInk = false
    for y in image.height
    {
        for x in image.width where image.pixelColor(x, y).r < 100 do
            hasInk = true
    }

    Swag.require(hasInk)
}

// The primary action exports directly. A failed write keeps the destination available for retry.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 760)
    defer host.shutdown()

    let root = Testing.tempFilePath("gui-print-dialog-", "")
    expect Directory.create(root)
    defer discard catch Directory.delete(root, recurse: true)
    let target = Path.combine(root, "printed.pdf")

    host.clickModalButtonWhenShown(Dialog.BtnOk, maxFrames: 600)
    host.withModalEdit(strings().print_Range, "2")
    host.thenClickModalButton(Dialog.BtnOk)
    let save = host.autoStages.backPtr()
    save.folder = root
    save.file   = "printed.pdf"
    if #os == Swag.TargetOs.Linux
    {
        // The editor accepts this name, but the filesystem rejects the rename.
        for 252 do
            save.file += "x"
        host.thenClickModalButton(Dialog.BtnOk)     // Dismiss the write error.
        host.thenClickModalButton(Dialog.BtnOk)
        host.autoStages.backPtr().file = "printed.pdf"
    }

    var document: Document
    document.kind = .Text
    document.name = "Report"
    for i in 75 do
        document.text.appendFormat("Report entry %.\n", i + 1)
    let devices: Array'Printer
    PrintDlg.showDocument(&host.surface, &document, "", devices.toSlice())
    host.pump()
    Swag.require(host.autoHandled, host.autoFailure)
    var reader = expect Pdf.Reader.open(target)
    Swag.require(reader.pageCount() == 1)
}

#test
{
    let source = Testing.tempFilePath("gui-print-source-", ".pdf")
    let target = Testing.tempFilePath("gui-print-output-", ".pdf")
    defer
    {
        discard catch File.delete(source)
        discard catch File.delete(target)
    }

    var pdf = Pdf.Document.create()
    for color in [Argb.Red, Argb.Green, Argb.Blue]
    {
        var image = Image.create(3, 2, .RGB8)
        image.fill(Color.fromArgb(color))
        var page = Pdf.Page.create(150, 100)
        page.addImage(image, 0, 0, 150, 100)
        pdf.addPage(#move page)
    }

    expect pdf.save(source)

    var document: Document
    document.kind = .Pdf
    document.pdf  = #move expect Pdf.Reader.open(source)
    let size   = Point{160, 140}
    let layout = expect prepare(&document, {size, {0, 0, size.x, size.y}}, {margin: 12})
    Swag.require(layout.pageCount == 3)

    let preview = expect layout.render(1, 72)
    Swag.require(preview.pixelColor(80, 70).g == 128)

    expect savePdf(&layout, {first: 1, end: 3}, target)
    var reader = expect Pdf.Reader.open(target)
    Swag.require(reader.pageCount() == 2)

    let first       = expect reader.loadPage(0)
    let firstPixels = expect first.render()
    Swag.require(firstPixels.pixelColor(80, 70).g == 128 and firstPixels.pixelColor(80, 70).b == 0)
    let last       = expect reader.loadPage(1)
    let lastPixels = expect last.render()
    Swag.require(lastPixels.pixelColor(80, 70).b == 255 and lastPixels.pixelColor(80, 70).r == 0)

    var failure: Swag.Error
    discard catch {try savePdf(&layout, {first: 3, end: 4}, target)} as failure
    Swag.require(failure.value() is PrintError)
    let preserved = expect Pdf.Reader.open(target)
    Swag.require(preserved.pageCount() == 2)
}
