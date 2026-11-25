#global if #os == Swag.TargetOs.Linux
#global internal
#global namespace Print

using Core, Core.Math, Linux.Cups

func printers()->Array'Printer
{
    var result: #returntype
    var library = #move catch NativeLibrary.load("libcups.so.2") orelse NativeLibrary{}
    if not library.isOpen() do
        return result

    let getDests  = cast(cupsGetDestsFunc?, library.symbol("cupsGetDests"))
    let freeDests = cast(cupsFreeDestsFunc?, library.symbol("cupsFreeDests"))
    if not getDests or not freeDests do
        return result

    var dests: [*] cups_dest_t?
    let count = getDests(&dests)
    if count <= 0 or not dests do
        return result
    defer freeDests!(count, dests)

    for i in count
    {
        let dest = &dests[i]
        let id   = nativeString(dest.name)
        if id.isEmpty() do
            continue
        let instance = nativeString(dest.instance)
        let name     = instance.isEmpty() ? id : Format.toString("%/%", id, instance)
        result.add({name, id, instance, dest.is_default != 0})
    }

    return result
}

private func nativeString(value: const [*] u8?)->String
{
    if not value do
        return {}
    var length = 0'u64
    while value[length] != 0 do
        length += 1
    return String.from(Swag.makeString(value, length))
}

private func mediaName(paper: Paper)->string
{
    switch paper
    {
    case .A4:     return "iso_a4_210x297mm"
    case .Letter: return "na_letter_8.5x11in"
    case .Legal:  return "na_legal_8.5x14in"
    }
}

func printerSheet(printer: const *Printer, setup: PageSetup)->Sheet fail
{
    var library = #move catch NativeLibrary.load("libcups.so.2") orelse NativeLibrary{}
    if not library.isOpen() do
        fail PrintError{.PrinterUnavailable}

    let getDest  = cast(cupsGetNamedDestFunc?, library.symbol("cupsGetNamedDest"))
    let freeDest = cast(cupsFreeDestsFunc?, library.symbol("cupsFreeDests"))
    let getInfo  = cast(cupsCopyDestInfoFunc?, library.symbol("cupsCopyDestInfo"))
    let freeInfo = cast(cupsFreeDestInfoFunc?, library.symbol("cupsFreeDestInfo"))
    let getMedia = cast(cupsGetDestMediaByNameFunc?, library.symbol("cupsGetDestMediaByName"))
    if not getDest or not freeDest or not getInfo or not freeInfo or not getMedia do
        fail PrintError{.PrinterUnavailable}

    let dest = getDest(null, printer.id.storage(), printer.instance.isEmpty() ? null : printer.instance.storage())
    if not dest do
        fail PrintError{.PrinterUnavailable}
    defer freeDest!(1, dest)

    let info = getInfo(null, &dest[0])
    if not info do
        fail PrintError{.PrinterUnavailable}
    defer freeInfo!(unwrap info)

    var media: cups_size_t
    if not getMedia(null, &dest[0], info, mediaName(setup.paper).buffer, CUPS_MEDIA_FLAGS_DEFAULT, &media) do
        fail PrintError{.UnsupportedPaper}

    let scale = PointsPerInch / (100 * MillimetersPerInch)
    var size  = Point{media.width * scale, media.length * scale}
    var rect  = Rectangle{media.left * scale, media.top * scale,
                          (media.width - media.left - media.right) * scale,
                          (media.length - media.top - media.bottom) * scale}
    if setup.landscape
    {
        rect = {rect.y, size.x - rect.right(), rect.height, rect.width}
        size = {size.y, size.x}
    }

    return {size, rect}
}

func printNative(printer: const *Printer, layout: const *Layout, options: JobOptions) fail
{
    var library = #move catch NativeLibrary.load("libcups.so.2") orelse NativeLibrary{}
    if not library.isOpen() do
        fail PrintError{.PrinterUnavailable}

    let send   = cast(cupsPrintFileFunc?, library.symbol("cupsPrintFile"))
    let cancel = cast(cupsCancelJobFunc?, library.symbol("cupsCancelJob"))
    if not send or not cancel do
        fail PrintError{.PrinterUnavailable}

    let temporary = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("swag-print-%.pdf", Guid128.random()))
    defer discard catch File.delete(temporary)
    try writePdf(layout, options, temporary)
    try checkCancelled()

    let copies = Format.toString("%", options.copies)
    let fields: [4] cups_option_t = [
        {"media".buffer,                 mediaName(options.setup.paper).buffer},
        {"copies".buffer,                copies.storage()},
        {"orientation-requested".buffer, (options.setup.landscape ? "4" : "3").buffer},
        {"print-scaling".buffer,         "none".buffer}]
    let title = layout.document.name.isEmpty() ? "Swag".buffer : layout.document.name.storage()
    let job   = send(printer.id.storage(), temporary.storage(), title, 4, &fields[0])
    if job <= 0 do
        fail PrintError{.PrinterFailed}
    if Swag.isCancelled()
    {
        if not cancel(printer.id.storage(), job) do
            fail PrintError{.PrinterFailed}
        fail PrintError{.Cancelled}
    }
}
