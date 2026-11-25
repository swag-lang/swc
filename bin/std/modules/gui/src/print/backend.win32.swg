#global if #os == Swag.TargetOs.Windows
#global internal
#global namespace Print

using Core, Core.Math, Pixel, Win32

func printers()->Array'Printer
{
    var result:        #returntype
    let flags = PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS
    var needed, count: DWORD
    discard EnumPrintersW(flags, null, 4, null, 0, &needed, &count)
    if not needed do
        return result

    var storage: Array'u8
    storage.resize(needed)
    if not EnumPrintersW(flags, null, 4, storage.buffer, needed, &needed, &count) do
        return result

    var defaultLength: DWORD
    discard GetDefaultPrinterW(null, &defaultLength)
    var defaultName: String
    if defaultLength
    {
        var wide: Array'u16
        wide.resize(defaultLength)
        if GetDefaultPrinterW(wide.buffer, &defaultLength) do
            defaultName = printerName(wide.buffer)
    }

    let entries = assume cast([*] PRINTER_INFO_4W, storage.buffer)
    for i in count
    {
        let name = printerName(entries[i].pPrinterName)
        if not name.isEmpty() do
            result.add({name, id: name, isDefault: name == defaultName})
    }

    return result
}

private func printerName(wide: LPCWSTR)->String
{
    if not wide do
        return {}
    return Utf8.fromUtf16(Swag.makeSlice(wide, Utf16.lengthZeroTerminated(wide)))
}

private func paperId(paper: Paper)->SHORT
{
    switch paper
    {
    case .A4:     return DMPAPER_A4
    case .Letter: return DMPAPER_LETTER
    case .Legal:  return DMPAPER_LEGAL
    }
}

private func isUnattendedQueue(printer: HANDLE)->bool
{
    var needed: DWORD
    GetPrinterW(printer, 5, null, 0, &needed)
    if not needed do
        return false

    var storage: Array'u8
    storage.resize(needed)
    if not GetPrinterW(printer, 5, storage.buffer, needed, &needed) do
        return false

    let info = assume cast(const *PRINTER_INFO_5W, storage.buffer)
    if info.Attributes & PRINTER_ATTRIBUTE_FAX do
        return false

    // These ports ask the spooler to open a Windows file picker from StartDoc.
    var ports = printerName(info.pPortName)
    ports.makeUpper()
    for port in Tokenize.split(ports, ','u8) where port == "FILE:" or port == "PORTPROMPT:" do
        return false
    return not ports.isEmpty()
}

private func device(printer: const *Printer, setup: PageSetup)->HDC fail
{
    var name = Utf16.toZeroTerminated(printer.id)
    var handle: HANDLE
    if not OpenPrinterW(name.buffer, &handle, null) do
        fail PrintError{.PrinterUnavailable}
    defer ClosePrinter(handle)
    if not isUnattendedQueue(handle) do
        fail PrintError{.PrinterUnavailable}

    let bytes = DocumentPropertiesW(null, handle, name.buffer, null, null, 0)
    if bytes < cast(s32, #sizeof(DEVMODEW)) do
        fail PrintError{.PrinterFailed}

    var storage: Array'u8
    storage.resize(cast(u64, bytes))
    let mode = assume cast(*DEVMODEW, storage.buffer)
    if DocumentPropertiesW(null, handle, name.buffer, mode, null, DM_OUT_BUFFER) != IDOK do
        fail PrintError{.PrinterFailed}

    let orientation = setup.landscape ? DMORIENT_LANDSCAPE : DMORIENT_PORTRAIT
    let paper       = paperId(setup.paper)
    mode.dmFields      = (mode.dmFields & ~(DM_PAPERWIDTH | DM_PAPERLENGTH)) | DM_ORIENTATION | DM_PAPERSIZE | DM_COPIES
    mode.dmPaperSize   = paper
    mode.dmOrientation = orientation
    mode.dmCopies      = 1
    if DocumentPropertiesW(null, handle, name.buffer, mode, mode, DM_IN_BUFFER | DM_OUT_BUFFER) != IDOK or
       mode.dmPaperSize != paper or
       mode.dmOrientation != orientation do
        fail PrintError{.UnsupportedPaper}

    let driver = Utf16.toZeroTerminated("WINSPOOL")
    let dc     = Gdi32.CreateDCW(driver.buffer, name.buffer, null, mode)
    if not dc do
        fail PrintError{.PrinterUnavailable}
    return dc
}

private func sheetForDevice(dc: HDC)->Sheet fail
{
    let dpi = Point{Gdi32.GetDeviceCaps(dc, Gdi32.LOGPIXELSX), Gdi32.GetDeviceCaps(dc, Gdi32.LOGPIXELSY)}
    if dpi.x <= 0 or dpi.y <= 0 do
        fail PrintError{.PrinterFailed}

    let x    = PointsPerInch / dpi.x
    let y    = PointsPerInch / dpi.y
    let size = Point{Gdi32.GetDeviceCaps(dc, Gdi32.PHYSICALWIDTH) * x,
                     Gdi32.GetDeviceCaps(dc, Gdi32.PHYSICALHEIGHT) * y}
    let imageable = Rectangle{Gdi32.GetDeviceCaps(dc, Gdi32.PHYSICALOFFSETX) * x,
                              Gdi32.GetDeviceCaps(dc, Gdi32.PHYSICALOFFSETY) * y,
                              Gdi32.GetDeviceCaps(dc, Gdi32.HORZRES) * x,
                              Gdi32.GetDeviceCaps(dc, Gdi32.VERTRES) * y}
    return {size, imageable}
}

func printerSheet(printer: const *Printer, setup: PageSetup)->Sheet fail
{
    let dc = try device(printer, setup)
    defer discard catch Gdi32.DeleteDC(dc)
    return try sheetForDevice(dc)
}

private func sendPage(dc: HDC, image: *Image) fail
{
    image.convertTo(.BGRA8)
    var info: Gdi32.BITMAPINFO
    info.bmiHeader.biSize        = #sizeof(Gdi32.BITMAPINFOHEADER)
    info.bmiHeader.biWidth       = image.width
    info.bmiHeader.biHeight      = image.height
    info.bmiHeader.biPlanes      = 1
    info.bmiHeader.biBitCount    = 32
    info.bmiHeader.biCompression = Gdi32.BI_RGB

    let x      = -Gdi32.GetDeviceCaps(dc, Gdi32.PHYSICALOFFSETX)
    let y      = -Gdi32.GetDeviceCaps(dc, Gdi32.PHYSICALOFFSETY)
    let width  = Gdi32.GetDeviceCaps(dc, Gdi32.PHYSICALWIDTH)
    let height = Gdi32.GetDeviceCaps(dc, Gdi32.PHYSICALHEIGHT)
    let lines  = Gdi32.StretchDIBits(dc, x, y, width, height, 0, 0, image.width, image.height, cast(LPCVOID, image.pixels.storage()), &info, Gdi32.DIB_RGB_COLORS, Gdi32.SRCCOPY)
    if lines == 0 or lines == -1 do
        fail PrintError{.PrinterFailed}
}

func printNative(printer: const *Printer, layout: const *Layout, options: JobOptions) fail
{
    let dc = try device(printer, options.setup)
    defer discard catch Gdi32.DeleteDC(dc)
    let sheet = try sheetForDevice(dc)
    if sheet.size != layout.sheet.size or sheet.imageable != layout.sheet.imageable do
        fail PrintError{.UnsupportedPaper}

    let title = Utf16.toZeroTerminated(layout.document.name)
    let info  = Gdi32.DOCINFOW{cbSize: cast(s32, #sizeof(Gdi32.DOCINFOW)), lpszDocName: title.buffer}
    try checkCancelled()
    if Gdi32.StartDocW(dc, &info) <= 0 do
        fail PrintError{.PrinterFailed}
    var complete = false
    defer
    {
        if not complete do
            Gdi32.AbortDoc(dc)
    }

    for options.copies
    {
        for index in options.first until options.end
        {
            var page = #move try layout.render(index, OutputDpi)
            try checkCancelled()
            if Gdi32.StartPage(dc) <= 0 do
                fail PrintError{.PrinterFailed}
            try sendPage(dc, &page)
            if Gdi32.EndPage(dc) <= 0 do
                fail PrintError{.PrinterFailed}
        }
    }

    try checkCancelled()
    if Gdi32.EndDoc(dc) <= 0 do
        fail PrintError{.PrinterFailed}
    complete = true
}
