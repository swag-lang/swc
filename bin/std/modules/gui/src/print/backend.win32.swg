#global if #os == Swag.TargetOs.Windows
#global internal
#global namespace Print

using Core, Core.Math, Pixel, Win32

func printers()->Array!{Printer}
{
    var result:  #returntype
    var storage: Array!{u8}
    let count = enumerateQueues(PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS, 4, &storage)
    if not count
    {
        return result
    }

    let interactive = interactiveQueues()
    var defaultLength: DWORD
    discard GetDefaultPrinterW(null, &defaultLength)
    var defaultName: String
    if defaultLength
    {
        var wide: Array!{u16}
        wide.resize(defaultLength)
        if GetDefaultPrinterW(wide.buffer, &defaultLength)
        {
            defaultName = printerName(wide.buffer)
        }
    }

    let entries = assume cast([*] PRINTER_INFO_4W, storage.buffer)
    for i in count
    {
        let name = printerName(entries[i].pPrinterName)
        if not name.isEmpty() and not interactive.contains(name)
        {
            result.add({name, id: name, isDefault: name == defaultName})
        }
    }

    return result
}

private func enumerateQueues(flags, level: DWORD, storage: *Array!{u8})->DWORD
{
    var needed, count: DWORD
    discard EnumPrintersW(flags, null, level, null, 0, &needed, &count)
    if not needed
    {
        return 0
    }

    storage.resize(needed)
    if not EnumPrintersW(flags, null, level, storage.buffer, needed, &needed, &count)
    {
        return 0
    }

    return count
}

// Read local port names without opening each queue or asking remote drivers for their settings.
private func interactiveQueues()->HashSet!{String}
{
    var result:  #returntype
    var storage: Array!{u8}
    let count = enumerateQueues(PRINTER_ENUM_LOCAL, 5, &storage)
    if not count
    {
        return result
    }

    let entries = assume cast([*] PRINTER_INFO_5W, storage.buffer)
    for i in count where needsDriverDialog(entries[i])
    {
        discard result.add(printerName(entries[i].pPrinterName))
    }

    return result
}

private func printerName(wide: LPCWSTR)->String
{
    if not wide
    {
        return {}
    }

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
    if not needed
    {
        return false
    }

    var storage: Array!{u8}
    storage.resize(needed)
    if not GetPrinterW(printer, 5, storage.buffer, needed, &needed)
    {
        return false
    }

    let info = assume cast(const *PRINTER_INFO_5W, storage.buffer)
    return not needsDriverDialog(info[]) and not printerName(info.pPortName).isEmpty()
}

private func needsDriverDialog(info: PRINTER_INFO_5W)->bool
{
    if info.Attributes & PRINTER_ATTRIBUTE_FAX
    {
        return true
    }

    // These ports ask the spooler to open a Windows file picker from StartDoc.
    var ports = printerName(info.pPortName)
    ports.makeUpper()
    for port in Tokenize.split(ports, ','_u8)
    {
        let name = Latin1.trim(port)
        if name == "FILE:" or name == "PORTPROMPT:"
        {
            return true
        }
    }

    return false
}

private func device(printer: const *Printer, setup: PageSetup)->HDC fail
{
    var name = Utf16.toZeroTerminated(printer.id)
    var handle: HANDLE
    if not OpenPrinterW(name.buffer, &handle, null)
    {
        fail PrintError{.PrinterUnavailable}
    }

    defer ClosePrinter(handle)
    if not isUnattendedQueue(handle)
    {
        fail PrintError{.PrinterUnavailable}
    }

    let bytes = DocumentPropertiesW(null, handle, name.buffer, null, null, 0)
    if bytes < cast(s32, #sizeof(DEVMODEW))
    {
        fail PrintError{.PrinterFailed}
    }

    var storage: Array!{u8}
    storage.resize(cast(u64, bytes))
    let mode = assume cast(*DEVMODEW, storage.buffer)
    if DocumentPropertiesW(null, handle, name.buffer, mode, null, DM_OUT_BUFFER) != IDOK
    {
        fail PrintError{.PrinterFailed}
    }

    let orientation = setup.landscape ? DMORIENT_LANDSCAPE : DMORIENT_PORTRAIT
    let paper       = paperId(setup.paper)
    mode.dmFields      = (mode.dmFields & ~(DM_PAPERWIDTH | DM_PAPERLENGTH)) | DM_ORIENTATION | DM_PAPERSIZE | DM_COPIES
    mode.dmPaperSize   = paper
    mode.dmOrientation = orientation
    mode.dmCopies      = 1
    if DocumentPropertiesW(null, handle, name.buffer, mode, mode, DM_IN_BUFFER | DM_OUT_BUFFER) != IDOK or
       mode.dmPaperSize != paper or
       mode.dmOrientation != orientation
    {
        fail PrintError{.UnsupportedPaper}
    }

    let driver = Utf16.toZeroTerminated("WINSPOOL")
    let dc     = Gdi32.CreateDCW(driver.buffer, name.buffer, null, mode)
    if not dc
    {
        fail PrintError{.PrinterUnavailable}
    }

    return dc
}

private func sheetForDevice(dc: HDC)->Sheet fail
{
    let dpi = Point{Gdi32.GetDeviceCaps(dc, Gdi32.LOGPIXELSX), Gdi32.GetDeviceCaps(dc, Gdi32.LOGPIXELSY)}
    if dpi.x <= 0 or dpi.y <= 0
    {
        fail PrintError{.PrinterFailed}
    }

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
    try checkCancelled()
    let dc = try device(printer, setup)
    defer discard catch Gdi32.DeleteDC(dc)
    try checkCancelled()
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
    if lines == 0 or lines == -1
    {
        fail PrintError{.PrinterFailed}
    }
}

// An unsubmitted result carries the geometry the caller needs to preview.
func printNative(printer: const *Printer, layout: const *Layout, options: JobOptions)->Submission fail
{
    try checkCancelled()
    let dc = try device(printer, options.setup)
    defer discard catch Gdi32.DeleteDC(dc)
    try checkCancelled()
    let sheet = try sheetForDevice(dc)
    if not layout.fitsPrinter(sheet)
    {
        return {sheet: sheet}
    }

    let title = Utf16.toZeroTerminated(layout.document.name)
    let info  = Gdi32.DOCINFOW{cbSize: cast(s32, #sizeof(Gdi32.DOCINFOW)), lpszDocName: title.buffer}
    try checkCancelled()
    if Gdi32.StartDocW(dc, &info) <= 0
    {
        fail PrintError{.PrinterFailed}
    }

    var complete = false
    defer
    {
        if not complete
        {
            Gdi32.AbortDoc(dc)
        }
    }

    for options.copies
    {
        for index in options.first until options.end
        {
            var page = #move try layout.render(index, OutputDpi)
            try checkCancelled()
            if Gdi32.StartPage(dc) <= 0
            {
                fail PrintError{.PrinterFailed}
            }

            try sendPage(dc, &page)
            if Gdi32.EndPage(dc) <= 0
            {
                fail PrintError{.PrinterFailed}
            }
        }
    }

    try checkCancelled()
    if Gdi32.EndDoc(dc) <= 0
    {
        fail PrintError{.PrinterFailed}
    }

    complete = true
    return {submitted: true}
}
