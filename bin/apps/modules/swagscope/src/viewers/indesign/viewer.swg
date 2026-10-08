#global internal
#global namespace Viewers.InDesign

using Core, Core.Errors, Pixel, Gui

private
{
    // The Adobe InDesign document signature and the master-page fields that establish that the
    // following embedded XMP belongs to a native document rather than to arbitrary binary data.
    const Signature: [16] u8     = [0x06, 0x06, 0xED, 0xF5, 0xD8, 0x1D, 0x46, 0xE5, 0xBD, 0x31, 0xEF, 0xE7, 0xFE, 0x74, 0xB7, 0x1D]
    const HeaderType             = "DOCUMENT"
    const HeaderCopySize         = 4096'u64
    const ByteOrderOffset        = 24'u64
    const FormatVersionOffset    = 29'u64
    const SequenceOffset         = 264'u64
    const StoragePageCountOffset = 280'u64
    const HeaderMinimumSize      = StoragePageCountOffset + 4

    // A contiguous object stream starts with a header marker and ends with a matching trailer; only a
    // complete stream is searched for an attached XMP packet.
    const ContiguousMarkerSize       = 32'u64
    const ContiguousHeader:  [16] u8 = [0xDE, 0x39, 0x39, 0x79, 0x51, 0x88, 0x4B, 0x6C, 0x8E, 0x63, 0xEE, 0xF8, 0xAE, 0xE0, 0xDD, 0x38]
    const ContiguousTrailer: [16] u8 = [0xFD, 0xCE, 0xDB, 0x70, 0xF7, 0x86, 0x4B, 0x4F, 0xA4, 0xD3, 0xC7, 0x28, 0xB3, 0x41, 0x71, 0x06]

    // The XMP elements that list the saved page previews.
    const PreviewItemOpen   = "<rdf:li"
    const PreviewItemClose  = "</rdf:li>"
    const PreviewImageOpen  = "<xmpGImg:image>"
    const PreviewImageClose = "</xmpGImg:image>"
    const PreviewPageOpen   = "<xmpTPg:PageNumber>"
    const PreviewPageClose  = "</xmpTPg:PageNumber>"

    // Bounds on a saved preview: its base64 text, its decoded payload, its pixels, and the pixels the
    // cache of decoded pages may hold together.
    const PreviewBase64Limit     = 16 * 1024 * 1024'u64
    const PreviewPayloadLimit    = 20 * 1024 * 1024'u64
    const PreviewPixelLimit      = 16 * 1024 * 1024'u64
    const PreviewCachePixelLimit = 24 * 1024 * 1024'u64

    // Marks a page without a saved preview.
    const NoPreview = Swag.U64.Max

    // Width of the page selector in the command bar.
    const PageLabelWidth = 96.0
}

// One validated master-page header.
//
// InDesign retains two header copies and selects the newer sequence, so a partial overwrite of
// either first page does not make the document unreadable.
private struct Header
{
    offset:        u64
    bigEndian:     bool
    formatVersion: u32
    sequence:      u64
    storagePages:  u32
}

// One saved page preview, an actual document rendering supplied by InDesign.
//
// The index retains only its base64 range; the reader decodes its pixels on demand and never
// invents a layout that the document did not save.
struct Preview
{
    page:         u32
    payloadStart: u64
    payloadEnd:   u64
}

// One decoded page held in the bounded viewer cache.
private struct CachedPreview
{
    index:      u64
    pixelCount: u64
    lastUsed:   u64
    image:      Image
}

// The pixel size of one saved page preview.
private struct PreviewGeometry
{
    width:  u32
    height: u32
}

// A native InDesign document with an index of the XMP page pixels it saved.
struct Document
{
    header:           Header
    fileName:         String
    fileSize:         u64
    declaredBytes:    u64
    xmpObjectStreams: u64
    previews:         Array'Preview
}

// How an InDesign source is shown: through the page previews a native document saved, or as the
// page scenes of an IDML package rendered as markup.
private enum DocumentKind
{
    NativePreview
    Markup
}

// One opened InDesign source: the saved pixels of a native document or the page scenes of an IDML package.
//
// Both kinds load behind one asynchronous opening operation, and the source decides the rendering
// path before a window is attached.
private struct ViewerDocument
{
    kind:   DocumentKind
    native: Document
    markup: Idml.Document
}

private func hasBytes(bytes: const [..] u8, offset, count: u64)->bool => offset <= bytes.count and count <= bytes.count - offset

private func matchesAt(bytes: const [..] u8, offset: u64, text: string)->bool
{
    if not hasBytes(bytes, offset, text.count) do
        return false
    for index in text.count where bytes[offset + index] != text[index] do
        return false
    return true
}

private func matchesContiguousMarker(bytes: const [..] u8, offset: u64, trailer = false)->bool
{
    if not hasBytes(bytes, offset, ContiguousHeader.count) do
        return false
    for index in ContiguousHeader.count where bytes[offset + index] != (trailer ? ContiguousTrailer[index] : ContiguousHeader[index]) do
        return false
    return true
}

private func matchesSignature(bytes: const [..] u8, offset: u64)->bool
{
    if not hasBytes(bytes, offset, Signature.count) do
        return false
    for index in Signature.count where bytes[offset + index] != Signature[index] do
        return false
    return true
}

private func findBytes(bytes: const [..] u8, text: string, start, end: u64)->u64
{
    if start > end or text.count > end - start do
        return Swag.U64.Max

    var index = start
    while index <= end - text.count
    {
        if matchesAt(bytes, index, text) do
            return index
        index += 1
    }

    return Swag.U64.Max
}

private func readU32(bytes: const [..] u8, offset: u64, bigEndian: bool)->u32
{
    var result = 0'u32
    for index in 4'u64
    {
        let position = bigEndian ? index : 3 - index
        result = (result << 8) | cast(u32, bytes[offset + position])
    }

    return result
}

private func readU64(bytes: const [..] u8, offset: u64)->u64
{
    var result = 0'u64
    for index in 8'u64 do
        result = (result << 8) | cast(u64, bytes[offset + 7 - index])
    return result
}

// Reports whether a valid master-page header starts at `offset`, and stores its fields in `result`.
//
// Object-stream byte order controls the version field, while the sequence and storage-page fields
// are the little-endian master-page values InDesign writes.
private func parseHeader(bytes: const [..] u8, offset: u64, result: *Header)->bool
{
    if not hasBytes(bytes, offset, HeaderMinimumSize) or not matchesSignature(bytes, offset) or not matchesAt(bytes, offset + Signature.count, HeaderType) do
        return false

    let byteOrder = bytes[offset + ByteOrderOffset]
    if byteOrder != 1 and byteOrder != 2 do
        return false

    let storagePages = readU32(bytes, offset + StoragePageCountOffset, false)
    if not storagePages do
        return false

    result.offset        = offset
    result.bigEndian     = byteOrder == 2
    result.formatVersion = readU32(bytes, offset + FormatVersionOffset, result.bigEndian)
    result.sequence      = readU64(bytes, offset + SequenceOffset)
    result.storagePages  = storagePages
    return true
}

private func base64Byte(value: u8)->bool => value >= 'A' and value <= 'Z' or value >= 'a' and value <= 'z' or value >= '0' and value <= '9' or value == '+' or value == '/' or value == '='

// Returns the base64 text of one saved preview, or an empty string when it breaks the preview limits.
//
// XMP serializes preview line breaks as character entities. The reader keeps the base64 alphabet
// and skips a whole entity rather than retaining its hexadecimal spelling as false image data.
private func previewBase64(bytes: const [..] u8, start, end: u64)->String
{
    if end < start or end - start > PreviewPayloadLimit do
        return {}

    var result: Array'u8
    result.reserve(Math.min(end - start, PreviewBase64Limit))

    var index = start
    while index < end
    {
        if bytes[index] == '&'
        {
            var entityEnd = index + 1
            while entityEnd < end and bytes[entityEnd] != ';' do
                entityEnd += 1
            if entityEnd < end
            {
                index = entityEnd + 1
                continue
            }
        }

        let value = bytes[index]
        if base64Byte(value)
        {
            if result.count == PreviewBase64Limit do
                return {}
            result.add(value)
        }

        index += 1
    }

    return result.isEmpty() ? {} : cast(string, result.toSlice())
}

private func previewPageNumber(bytes: const [..] u8, start, end: u64)->u32
{
    let valueStart = findBytes(bytes, PreviewPageOpen, start, end)
    if valueStart == Swag.U64.Max do
        return 0

    let numberStart = valueStart + PreviewPageOpen.count
    let numberEnd   = findBytes(bytes, PreviewPageClose, numberStart, end)
    if numberEnd == Swag.U64.Max or numberEnd == numberStart do
        return 0

    var result = 0'u32
    for index in numberStart until numberEnd
    {
        let value = bytes[index]
        if value < '0' or value > '9' or result > (Swag.U32.Max - cast(u32, value - '0')) / 10 do
            return 0
        result = result * 10 + cast(u32, value - '0')
    }

    return result == Swag.U32.Max ? 0 : result
}

// Whether `marker` starts a frame: the range C0 to CF, less the three codes it lends to the
// Huffman tables (C4), the JPEG extensions (C8), and the arithmetic conditioning (CC).
private func jpegStartOfFrame(marker: u8)->bool => marker >= 0xC0 and marker <= 0xCF and marker != 0xC4 and marker != 0xC8 and marker != 0xCC

// Reads JPEG dimensions before materializing pixels, and reports whether they fit the preview limit.
//
// A saved preview may be a valid JPEG whose declared geometry would nevertheless exceed the
// reader's bounded cache.
private func jpegGeometry(bytes: const [..] u8, result: *PreviewGeometry)->bool
{
    if bytes.count < 4 or bytes[0] != 0xFF or bytes[1] != 0xD8 do
        return false

    var index = 2'u64
    while index + 1 < bytes.count
    {
        while index < bytes.count and bytes[index] == 0xFF do
            index += 1
        if index >= bytes.count do
            return false

        let marker = bytes[index]
        index += 1
        if marker == 0xD9 do
            break
        if marker == 0x01 or marker >= 0xD0 and marker <= 0xD7 do
            continue
        if index + 1 >= bytes.count do
            return false

        let segmentSize = (cast(u64, bytes[index]) << 8) | cast(u64, bytes[index + 1])
        if segmentSize < 2 or segmentSize > bytes.count - index do
            return false
        if jpegStartOfFrame(marker)
        {
            if segmentSize < 8 do
                return false

            result.height = (cast(u32, bytes[index + 3]) << 8) | cast(u32, bytes[index + 4])
            result.width  = (cast(u32, bytes[index + 5]) << 8) | cast(u32, bytes[index + 6])
            let pixels = cast(u64, result.width) * cast(u64, result.height)
            return result.width != 0 and result.height != 0 and pixels <= PreviewPixelLimit
        }

        index += segmentSize
    }

    return false
}

// Finds every saved JPEG page preview without decoding their pixels.
//
// A document can retain several XMP generations, so the last usable reference for a physical page
// wins.
private func indexPreviews(bytes: const [..] u8, start, end: u64)->Array'Preview
{
    var result: retval
    var fallbackPage = 1'u32
    var cursor       = start

    while cursor < end
    {
        let itemStart = findBytes(bytes, PreviewItemOpen, cursor, end)
        if itemStart == Swag.U64.Max do
            break

        let itemContentStart = findBytes(bytes, ">", itemStart, end)
        let itemEnd = findBytes(bytes, PreviewItemClose, itemStart, end)
        if itemContentStart == Swag.U64.Max or itemEnd == Swag.U64.Max or itemContentStart >= itemEnd do
            break

        let contentStart = itemContentStart + 1
        let imageStart   = findBytes(bytes, PreviewImageOpen, contentStart, itemEnd)
        let imageEnd     = imageStart == Swag.U64.Max ? Swag.U64.Max : findBytes(bytes, PreviewImageClose, imageStart + PreviewImageOpen.count, itemEnd)
        if imageEnd != Swag.U64.Max and imageEnd - imageStart <= PreviewPayloadLimit
        {
            let payloadStart = imageStart + PreviewImageOpen.count
            var page         = previewPageNumber(bytes, contentStart, itemEnd)
            if not page
            {
                page = fallbackPage
                if fallbackPage != Swag.U32.Max do
                    fallbackPage += 1
            }
            elif page >= fallbackPage and page < Swag.U32.Max
            {
                fallbackPage = page + 1
            }

            var existing = NoPreview
            for saved, index in result where saved.page == page
            {
                existing = index
                break
            }

            var saved: Preview
            saved.page         = page
            saved.payloadStart = payloadStart
            saved.payloadEnd   = imageEnd
            if existing != NoPreview do
                result[existing] = saved
            else do
                result.add(saved)
        }

        cursor = itemEnd + PreviewItemClose.count
    }

    return #move result
}

private func appendPreviews(result: *Array'Preview, source: const *Array'Preview)
{
    for preview in source
    {
        var existing = NoPreview
        for saved, index in result where saved.page == preview.page
        {
            existing = index
            break
        }

        if existing == NoPreview do
            result.add(preview[])
        else do
            result[existing] = preview[]
    }
}

// Indexes the saved previews of the continuous object streams that follow the declared database pages.
//
// XMP is located only inside complete streams: the matching trailer makes a byte sequence inside
// arbitrary document data unable to impersonate an attached XMP packet.
private func indexObjectPreviews(bytes: const [..] u8, start, end: u64, streamCount: *u64)->Array'Preview
{
    var result: retval
    var cursor = start
    while cursor + ContiguousMarkerSize <= end
    {
        if not matchesContiguousMarker(bytes, cursor)
        {
            cursor += 1
            continue
        }

        let payloadStart = cursor + ContiguousMarkerSize
        let length       = cast(u64, readU32(bytes, cursor + 24, false))
        if length > end - payloadStart - ContiguousMarkerSize
        {
            cursor += 1
            continue
        }

        let trailer = payloadStart + length
        if not matchesContiguousMarker(bytes, trailer, true)
        {
            cursor += 1
            continue
        }

        var sameMarker = true
        for index in 16'u64 until ContiguousMarkerSize where bytes[cursor + index] != bytes[trailer + index]
        {
            sameMarker = false
            break
        }

        if not sameMarker
        {
            cursor += 1
            continue
        }

        let previews = indexPreviews(bytes, payloadStart, trailer)
        if not previews.isEmpty()
        {
            appendPreviews(&result, &previews)
            streamCount[] += 1
        }

        cursor = trailer + ContiguousMarkerSize
    }

    return result
}

// Decodes one indexed JPEG preview on a worker.
//
// Encoded-payload and pixel bounds make opening a malformed document unable to retain the whole
// XMP payload or every document page at once.
private func loadPreview(fileName: string, preview: const *Preview)->Image fail
{
    var file   = try File.MappedFile.open(fileName)
    let region = try file.mapAll()
    let bytes  = region.bytes()
    if preview.payloadEnd < preview.payloadStart or not hasBytes(bytes, preview.payloadStart, preview.payloadEnd - preview.payloadStart) do
        fail InvalidFormatError{texts().err_Preview}

    let payload = previewBase64(bytes, preview.payloadStart, preview.payloadEnd)
    if payload.isEmpty() do
        fail InvalidFormatError{texts().err_Preview}

    let previewBytes = catch Base64.decode(payload) as base64Error
    if base64Error != null or previewBytes.count < 4 or previewBytes[0] != 0xFF or previewBytes[1] != 0xD8 or previewBytes[previewBytes.count - 2] != 0xFF or previewBytes[previewBytes.count - 1] != 0xD9 do
        fail InvalidFormatError{texts().err_Preview}

    var geometry: PreviewGeometry
    if not jpegGeometry(previewBytes.toSlice(), &geometry) do
        fail InvalidFormatError{texts().err_Preview}

    var result: retval
    result = catch Image.decode("indesign-preview.jpg", previewBytes.toSlice()) as decodeError
    if decodeError != null or not result.isValid() or result.width != cast(s32, geometry.width) or result.height != cast(s32, geometry.height) do
        fail InvalidFormatError{texts().err_Preview}
    return #move result
}

// Owns one selected page decode.
//
// The shared viewer background loader takes only a filename, while this operation also needs the
// immutable preview range selected by the reader.
private struct PreviewLoad
{
    using operation: Viewer.BackgroundOperation
    fileName:        String
    preview:         Preview
    value:           Image
    error:           String
}

private impl PreviewLoad
{
    mtd start(fileName: string, preview: const *Preview)
    {
        Swag.assert(not .started)
        .fileName = fileName
        .preview  = preview[]
        .started  = true

        let operation = me
        .task.submit(func|operation|()
        {
            operation.value = catch loadPreview(operation.fileName, &operation.preview) as loadError
            operation.error = Errors.message(loadError)
        })
    }

    mtd finish(value: *Image)->String
    {
        Swag.assert(.isDone())
        .wait()
        value[] = #move .value
        return #move .error
    }

    mtd retire()->bool
    {
        if not .started do
            return true
        if not .isDone() do
            return false
        .wait()
        .stopPolling()
        return true
    }

    mtd opDrop()
    {
        .wait()
    }
}

// Reads the master-page headers and indexes previews from validated continuous XMP object streams.
//
// Legacy documents that retained XMP inside their declared pages keep a bounded compatibility path.
func loadDocument(fileName: string)->Document fail
{
    var stream      = try File.openReadLive(fileName)
    let fileSize    = try stream.size()
    let headerBytes = Math.min(fileSize, 2 * HeaderCopySize)
    var headerData: Array'u8
    headerData.resize(headerBytes)
    if not try stream.readExact(headerData.toSlice()) do
        fail InvalidFormatError{texts().err_Header}

    var first, second: Header
    let hasFirst  = parseHeader(headerData.toSlice(), 0, &first)
    let hasSecond = parseHeader(headerData.toSlice(), HeaderCopySize, &second)
    if not hasFirst and not hasSecond do
        fail InvalidFormatError{texts().err_Header}

    var file          = try File.MappedFile.open(fileName)
    let region        = try file.mapAll()
    let header        = hasSecond and (not hasFirst or second.sequence > first.sequence) ? second : first
    let declaredBytes = cast(u64, header.storagePages) * HeaderCopySize
    if declaredBytes > fileSize do
        fail InvalidFormatError{texts().err_Header}
    let bytes    = region.bytes()
    var xmpObjectStreams: u64
    var previews = indexObjectPreviews(bytes, declaredBytes, bytes.count, &xmpObjectStreams)
    if previews.isEmpty() do
        previews = indexPreviews(bytes, 0, declaredBytes)
    if previews.isEmpty() do
        fail InvalidFormatError{texts().err_Preview}

    return {header, fileName, fileSize, declaredBytes, xmpObjectStreams, #move previews}
}

private func loadViewerDocument(fileName: string)->ViewerDocument fail
{
    var result: retval
    let extension = Path.extension(fileName) orelse ""
    if Utf8.compare(extension, ".idml", .Latin1NoCase) == 0
    {
        result.kind   = .Markup
        result.markup = try Idml.load(fileName)
    }
    else
    {
        result.kind   = .NativePreview
        result.native = try loadDocument(fileName)
    }

    return result
}

// Describes the InDesign document reader, for native documents and IDML packages, to the host.
func viewerPlugin()->Viewer.Plugin
{
    with var result: retval
    {
        .key          = "indesign"
        .resolveName  = func()->string => texts().ui_Name
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Indesign)
        .create       = &createViewer
        .smokeFixture = "uni-halle-52a.idml"
        .addSelectors(".indd;.idml")
    }

    return result
}

private func commandWidth(metrics: const *ThemeMetrics)->f32 => 2 * themeActionButtonSize(metrics) + PageLabelWidth + 16

// Shows an InDesign document page by page: saved previews of a native file, composed pages of an IDML package.
//
// For saved previews, ImageView provides wheel zoom, pointer-centred panning, and a double-click
// actual-size toggle, all on the pixels the document saved.
struct Panel
{
    using wnd: Wnd

    details:             String
    fileName:            String
    kind:                DocumentKind
    previews:            Array'Preview
    markupPages:         Array'Idml.Page
    cachedPreviews:      Array'CachedPreview
    cachedPixels:        u64
    previewUseSerial          = 1'u64
    hasPreviewContent:   bool
    previewIndex:        u64
    markupZoom:          f32  = 1
    markupFit:           bool = true
    markupFitWidth:      bool
    markupRenderedScale: f32  = 1
    requestedPreviewIndex     = NoPreview
    loadingPreviewIndex       = NoPreview
    load:                Viewer.BackgroundLoad'ViewerDocument
    previewLoad:         PreviewLoad
    services:            Viewer.HostServices
    failureReason:       String

    late
    {
        commands:       *Wnd
        info:           *Wnd
        previousButton: *IconButton
        nextButton:     *IconButton
        pageLabel:      *IconButton
        zoomLabel:      *IconButton
        imageView:      *ImageView
    }

    htmlView: *HtmlView?
}

private impl Panel
{
    mtd pageCount()->u64 => .kind == .Markup ? .markupPages.count : .previews.count
    mtd isMarkup()->bool => .kind == .Markup

    mtd pageName(index: u64)->String
    {
        if .kind == .Markup do
            return .markupPages[index].name
        return Format.toString("%", .previews[index].page)
    }

    mtd markupDetails(index: u64)->String
    {
        let page = &.markupPages[index]
        return Format.toString(texts().ui_MarkupDetails, index + 1, .markupPages.count, page.textFrameCount, page.missingImageCount())
    }

    mtd nextPreviewUse()->u64
    {
        if .previewUseSerial == Swag.U64.Max
        {
            .previewUseSerial = 1
            for &preview in .cachedPreviews do
                preview.lastUsed = 0
        }

        let result = .previewUseSerial
        .previewUseSerial += 1
        return result
    }

    mtd refreshPageCommands()
    {
        let pageCount = .pageCount()
        .previousButton.enable(.previewIndex != 0)
        .nextButton.enable(.previewIndex + 1 < pageCount)
        .pageLabel.setText(Format.toString(texts().ui_Page, .previewIndex + 1, pageCount))
    }

    mtd refreshZoom()
    {
        if .isMarkup()
        {
            .zoomLabel.setText(.markupFit ? (.markupFitWidth ? texts().ui_FitWidth : texts().ui_Fit) : Format.toString("% %", cast(u32, Math.round(.markupPageScale(.previewIndex) * 100)), "%"))
            .services.chromeChanged(me)
            return
        }

        .zoomLabel.setText(Format.toString("% %", cast(u32, Math.round(.imageView.effectiveZoom() * 100)), "%"))
        .services.chromeChanged(me)
    }

    mtd markupFitScale(index: u64)->f32
    {
        let page   = &.markupPages[index]
        let client = .clientRect()
        if client.width <= 0 or client.height <= 0 do
            return 1
        let width  = Math.max(client.width - 48, 1)
        let height = Math.max(client.height - 48, 1)
        let scale  = .markupFitWidth ? width / page.bounds.width : Math.min(width / page.bounds.width, height / page.bounds.height)
        return Math.clamp(scale, 0.25, 3)
    }

    mtd markupPageScale(index: u64)->f32 => .markupFit ? .markupFitScale(index) : .markupZoom

    mtd setMarkupZoom(percent: u32)
    {
        .markupFit      = false
        .markupFitWidth = false
        .markupZoom     = cast(f32, Math.clamp(percent, 25'u32, 300'u32)) / 100
        .selectMarkupPage(.previewIndex)
    }

    mtd fitMarkupPage()
    {
        .markupFit      = true
        .markupFitWidth = false
        .selectMarkupPage(.previewIndex)
    }

    mtd fitMarkupWidth()
    {
        .markupFit      = true
        .markupFitWidth = true
        .selectMarkupPage(.previewIndex)
    }

    mtd showZoomMenu()
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        menu.addItem("50%", "scope.indesign.zoom50")
        if not .isMarkup() do
            menu.addItem(texts().ui_Actual, "scope.indesign.zoomActual", .theme().icon(.ActualSize, themeRowIconSize(.themeMetrics())))
        menu.addItem("125%", "scope.indesign.zoom125")
        menu.addItem("150%", "scope.indesign.zoom150")
        menu.addItem("200%", "scope.indesign.zoom200")
        menu.addSeparator()
        menu.addItem(texts().ui_Fit, "scope.indesign.zoomFit", .theme().icon(.FitView, themeRowIconSize(.themeMetrics())), rightName: "F")
        if .isMarkup() do
            menu.addItem(texts().ui_FitWidth, "scope.indesign.zoomFitWidth", .theme().icon(.FitView, themeRowIconSize(.themeMetrics())), rightName: "W")
        let chosen = menu.doModal(.zoomLabel, autoDestroy: true) orelse ""
        if .isMarkup()
        {
            switch chosen
            {
            case "scope.indesign.zoom50":       .setMarkupZoom(50)
            case "scope.indesign.zoom125":      .setMarkupZoom(125)
            case "scope.indesign.zoom150":      .setMarkupZoom(150)
            case "scope.indesign.zoom200":      .setMarkupZoom(200)
            case "scope.indesign.zoomFit":      .fitMarkupPage()
            case "scope.indesign.zoomFitWidth": .fitMarkupWidth()
            }

            return
        }

        switch chosen
        {
        case "scope.indesign.zoom50":     .imageView.setZoom(0.5)
        case "scope.indesign.zoomActual": .imageView.actualSize()
        case "scope.indesign.zoom125":    .imageView.setZoom(1.25)
        case "scope.indesign.zoom150":    .imageView.setZoom(1.5)
        case "scope.indesign.zoom200":    .imageView.setZoom(2)
        case "scope.indesign.zoomFit":    .imageView.zoomToFit()
        }
    }

    mtd reportCurrentDetails()
    {
        .services.showDetails(me, .details)
    }

    mtd showCachedPreview(index: u64)->bool
    {
        for &preview in .cachedPreviews
        {
            if preview.index != index do
                continue

            preview.lastUsed = .nextPreviewUse()
            .imageView.setImage(preview.image)
            .hasPreviewContent = true
            .details = Format.toString(texts().ui_Details, index + 1, .previews.count, preview.image.width, preview.image.height)
            .refreshZoom()
            .reportCurrentDetails()
            return true
        }

        return false
    }

    mtd cachePreview(index: u64, image: *Image)
    {
        let pixelCount = cast(u64, image.width) * cast(u64, image.height)
        for &cached in .cachedPreviews
        {
            if cached.index == index
            {
                .cachedPixels     -= cached.pixelCount
                cached.pixelCount = pixelCount
                cached.lastUsed   = .nextPreviewUse()
                cached.image      = #move image[]
                .cachedPixels     += pixelCount
                return
            }
        }

        while not .cachedPreviews.isEmpty() and .cachedPixels > PreviewCachePixelLimit - pixelCount
        {
            var oldestIndex = 0'u64
            for cached, cachedIndex in .cachedPreviews where cached.lastUsed < .cachedPreviews[oldestIndex].lastUsed do
                oldestIndex = cachedIndex
            .cachedPixels -= .cachedPreviews[oldestIndex].pixelCount
            .cachedPreviews.removeAt(oldestIndex)
        }

        var cached: CachedPreview
        cached.index      = index
        cached.pixelCount = pixelCount
        cached.lastUsed   = .nextPreviewUse()
        cached.image      = #move image[]
        .cachedPreviews.add(#move cached)
        .cachedPixels += pixelCount
    }

    mtd startRequestedPreview()
    {
        if .previewLoad.isPending() or .requestedPreviewIndex == NoPreview do
            return

        .loadingPreviewIndex   = .requestedPreviewIndex
        .requestedPreviewIndex = NoPreview
        .previewLoad.start(.fileName, &.previews[.loadingPreviewIndex])
        .previewLoad.pollFrom(me)
        .services.loadingChanged(me)
    }

    mtd selectPreview(index: u64)
    {
        Swag.assert(index < .pageCount())
        if .isMarkup()
        {
            .selectMarkupPage(index)
            return
        }

        .previewIndex = index
        .refreshPageCommands()
        if .showCachedPreview(index)
        {
            .requestedPreviewIndex = NoPreview
            return
        }

        .details = Format.toString(texts().ui_LoadingDetails, index + 1, .previews.count)
        .reportCurrentDetails()
        .requestedPreviewIndex = index
        .startRequestedPreview()
    }

    mtd selectMarkupPage(index: u64)
    {
        Swag.assert(index < .markupPages.count)
        .previewIndex = index
        .htmlView?.destroy()
        .markupRenderedScale      = .markupPageScale(index)
        .htmlView = HtmlView.createText(me, .markupPages[index].html(.markupRenderedScale))
        .htmlView.dockStyle       = .Center
        .htmlView.backgroundStyle = .View
        .imageView.hide()
        .hasPreviewContent = true
        .details = .markupDetails(index)
        .refreshPageCommands()
        .refreshZoom()
        .reportCurrentDetails()
        .applyLayout()
        .setInitialFocus(.htmlView)
    }

    mtd publishDocument(document: *ViewerDocument)
    {
        .kind = document.kind
        if .isMarkup()
        {
            .fileName       = #move document.markup.fileName
            .markupPages    = #move document.markup.pages
            .markupFit      = true
            .markupFitWidth = false
            .zoomLabel.show()
            .selectMarkupPage(0)
        }
        else
        {
            .fileName = #move document.native.fileName
            .previews = #move document.native.previews
            .selectPreview(0)
            .applyLayout()
            .setInitialFocus(.imageView)
        }

        .retranslate()
    }

    mtd retranslate()
    {
        .previousButton.toolTip = .isMarkup() ? texts().ui_PreviousDocumentPage : texts().ui_PreviousPage
        .nextButton.toolTip     = .isMarkup() ? texts().ui_NextDocumentPage : texts().ui_NextPage
        .pageLabel.toolTip      = .isMarkup() ? texts().ui_ChooseDocumentPage : texts().ui_ChoosePage
        .zoomLabel.toolTip      = texts().ui_ZoomMenu
        .refreshZoom()
        if not .load.isPending() and .pageCount()
        {
            .refreshPageCommands()
            if .isMarkup()
            {
                .details = .markupDetails(.previewIndex)
                .reportCurrentDetails()
            }
            elif not .showCachedPreview(.previewIndex)
            {
                .details = Format.toString(texts().ui_LoadingDetails, .previewIndex + 1, .previews.count)
                .reportCurrentDetails()
            }

            .applyLayout()
        }
    }

    mtd goToTypedPage(text: string)->bool
    {
        let parsed = catch StrConv.parseU64(text) as parseError
        if parseError != null or parsed.eat != text.count or parsed.ovf or not parsed.value or parsed.value > .pageCount() do
            return false
        .selectPreview(parsed.value - 1)
        return true
    }

    mtd promptGoToPage()
    {
        if not .surface or not .pageCount() do
            return
        var options: EditDlgOptions
        options.title   = texts().ui_GoToPage
        options.message = Format.toString(texts().ui_PageRange, .pageCount()).toString()
        options.text    = Format.toString("%", .previewIndex + 1).toString()
        let dialog = EditDlg.createSingleLine(.surface, options)
        if dialog.doModal() != Dialog.BtnOk do
            return
        discard .goToTypedPage(dialog.text())
    }

    mtd showPageMenu()
    {
        let strings = texts()

        with let menu = MenuCtrl.createPopup(me, owner: me)
        {
            .addItem(strings.ui_GoToPage, "scope.indesign.goToPage", rightName: "Ctrl+G")
            .addSeparator()
        }

        var commands: Array'String
        commands.reserve(.pageCount())
        for index in .pageCount()
        {
            commands.add(Format.toString("scope.indesign.page.%", index))
            menu.addRadioItem(Format.toString(strings.ui_PageMenuEntry, .pageName(index)), commands[index], checked: index == .previewIndex)
        }

        let chosen = menu.doModal(.pageLabel, autoDestroy: true)
        if not chosen do
            return
        if chosen == "scope.indesign.goToPage"
        {
            .promptGoToPage()
            return
        }

        for command, index in commands where chosen == command.toString()
        {
            .selectPreview(index)
            return
        }
    }

    // Collects the matches of each generated HTML page source, tagged with its page index for revealFileOffset.
    //
    // Source matches may include markup; rendered text ranges belong to the HTML view.
    mtd collectMatches(text: string, options: Viewer.SearchOptions, result: *Array'Viewer.SearchMatch)
    {
        if not .isMarkup() do
            return
        for page, index in .markupPages do
            Viewer.collectTextMatches(page.html(1), text, options, index, 0, 0, result)
    }

    mtd revealMatch(match: Viewer.SearchMatch, text: string)->bool
    {
        if not .isMarkup() or match.major >= .markupPages.count do
            return false
        .selectMarkupPage(match.major)
        return .htmlView!.revealFileOffset(match.offset, text)
    }

    mtd searchBounds(result: *Math.Rectangle)->bool => .isMarkup() and .htmlView and .htmlView.searchMatchRect(result)

    mtd clearSearch()
    {
        if .isMarkup() and .htmlView do
            .htmlView.clearSearch()
    }

    mtd retire()->bool
    {
        return .load.retire() and .previewLoad.retire()
    }
}

private impl IWnd for Panel
{
    mtd impl onResizeEvent(?: *ResizeEvent)
    {
        if .isMarkup() and .markupFit and .htmlView
        {
            let scale = .markupFitScale(.previewIndex)
            if Math.abs(scale - .markupRenderedScale) >= 0.01 do
                .selectMarkupPage(.previewIndex)
        }
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer == .load.timer
        {
            if not .load.poll() do
                return

            var document: ViewerDocument
            .failureReason = .load.finish(&document)
            if not .failureReason.isEmpty()
            {
                .services.failed(me, .failureReason)
                return
            }

            .publishDocument(&document)
            .services.loadingChanged(me)
            return
        }

        if evt.timer != .previewLoad.timer
        {
            evt.accepted = false
            return
        }

        if not .previewLoad.poll() do
            return

        let completedIndex = .loadingPreviewIndex
        .loadingPreviewIndex = NoPreview
        var image: Image
        let failure = .previewLoad.finish(&image)
        if .requestedPreviewIndex == completedIndex do
            .requestedPreviewIndex = NoPreview

        if failure.isEmpty()
        {
            .cachePreview(completedIndex, &image)
            if completedIndex == .previewIndex do
                discard .showCachedPreview(completedIndex)
        }
        elif completedIndex == .previewIndex
        {
            .failureReason = failure
            .services.failed(me, .failureReason)
        }

        .startRequestedPreview()

        .services.loadingChanged(me)
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed
        {
            evt.accepted = false
            return
        }

        if not .pageCount()
        {
            evt.accepted = false
            return
        }

        switch evt.key
        {
        case .G where evt.modifiers == .Control:
            .promptGoToPage()

        case .Add, .OemPlus:
            if .isMarkup() do
                .setMarkupZoom(cast(u32, Math.round(.markupPageScale(.previewIndex) * 100)) + 25)
            else do
                .imageView.zoomIn()

        case .Subtract, .OemMinus:
            if .isMarkup() do
                .setMarkupZoom(Math.max(cast(u32, Math.round(.markupPageScale(.previewIndex) * 100)), 50) - 25)
            else do
                .imageView.zoomOut()

        case .D0 where not .isMarkup() and evt.modifiers.has(.Control):
            .imageView.actualSize()

        case .F where evt.modifiers == .None:
            if .isMarkup() do
                .fitMarkupPage()
            else do
                .imageView.zoomToFit()

        case .W where .isMarkup() and evt.modifiers == .None:
            .fitMarkupWidth()

        case .Left, .PageUp where evt.modifiers == .None:
            if .previewIndex do
                .selectPreview(.previewIndex - 1)
            else do
                evt.accepted = false

        case .Right, .PageDown where evt.modifiers == .None:
            if .previewIndex + 1 < .pageCount() do
                .selectPreview(.previewIndex + 1)
            else do
                evt.accepted = false

        case .Home where evt.modifiers == .None:
            .selectPreview(0)

        case .End where evt.modifiers == .None:
            .selectPreview(.pageCount() - 1)

        default:
            evt.accepted = false
        }
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        else do
            evt.accepted = false
    }
}

impl Panel
{
    func create(host: Viewer.Host)->*Panel
    {
        let services = host.services()

        with let result = Wnd.create'Panel(host.contentParent(), "scope.indesign")
        {
            .backgroundStyle = .View
            .services        = services
        }

        result.createPageCommands(host)
        result.createZoomButton(host)
        with result.imageView = ImageView.create(result)
        {
            .backgroundStyle = .View
            .dockStyle       = .Center
            .sigZoomChanged  += func|view = result|(?) { view.refreshZoom() }
        }

        result.hookOnChildEvent = func|view = result|(?, evt)
        {
            switch evt
            {
            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and keyEvt.key == .G and keyEvt.modifiers == .Control:
                view.promptGoToPage()
                return true

            case KeyEvent as keyEvt where view.isMarkup() and keyEvt.kind == .Pressed and keyEvt.modifiers == .None:
                switch keyEvt.key
                {
                case .Left, .PageUp:
                    if view.previewIndex
                    {
                        view.selectPreview(view.previewIndex - 1)
                        return true
                    }

                case .Right, .PageDown:
                    if view.previewIndex + 1 < view.pageCount()
                    {
                        view.selectPreview(view.previewIndex + 1)
                        return true
                    }

                case .Home:
                    view.selectPreview(0)
                    return true

                case .End:
                    view.selectPreview(view.pageCount() - 1)
                    return true
                }

            default:
                break
            }

            return false
        }

        result.applyLayout()
        result.refreshZoom()
        result.load.startPolled(result, host.fileName(), &loadViewerDocument)
        return result
    }

    // Creates the page commands: previous page, next page, and the page selector.
    private mtd createPageCommands(host: Viewer.Host)
    {
        let metrics    = .themeMetrics()
        let buttonSize = themeActionButtonSize(metrics)
        .commands = host.createCommandGroup(commandWidth(metrics))
        with .previousButton = Viewer.createActionButton(me.commands, .ChevronLeft)
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = texts().ui_PreviousPage
            .enable(false)
            .sigPressed += func|view = me|(?)
            {
                if view.previewIndex do
                    view.selectPreview(view.previewIndex - 1)
            }
        }

        with .nextButton = Viewer.createActionButton(me.commands, .ChevronRight)
        {
            .dockStyle = .Left
            .toolTip   = texts().ui_NextPage
            .enable(false)
            .sigPressed += func|view = me|(?)
            {
                if view.previewIndex + 1 < view.pageCount() do
                    view.selectPreview(view.previewIndex + 1)
            }
        }

        with .pageLabel = IconButton.create(me.commands, {}, {0, 0, PageLabelWidth, buttonSize}, "scope.indesign.page", .CenterContent)
        {
            .dockStyle = .Left
            .margin.x  = 8
            .setArrowPosition(.RightDownward)
            .setForm(.Rectangle)
            .style.setFont(me.theme().createDefaultFontFs(11), .Regular)
            .toolTip    = texts().ui_ChoosePage
            .sigPressed += func|view = me|(?) { view.showPageMenu() }
        }
    }

    // Creates the zoom button of the information band.
    private mtd createZoomButton(host: Viewer.Host)
    {
        .info      = host.createInfoGroup(Viewer.ZoomSlotWidth)
        .zoomLabel = Viewer.createZoomButton(me.info, "scope.indesign.zoom", texts().ui_ZoomMenu)
        .zoomLabel.sigPressed += func|view = me|(?) { view.showZoomMenu() }
    }
}

// Creates the integrated InDesign document view and connects its search and lifecycle to the host.
func createViewer(host: Viewer.Host)
{
    let view = Panel.create(host)
    host.attachView(view)

    host.setSearch(Viewer.searchApi(view))

    with var lifecycle: Viewer.LifecycleApi
    {
        .isLoading = func|view|()->bool => view.load.isPending() or view.previewLoad.isPending()
        .needsLoadingOverlay = func|view|()->bool => view.load.isPending() or (view.previewLoad.isPending() and not view.hasPreviewContent)
        .retire    = func|view|()->bool => view.retire()
    }

    host.setLifecycle(lifecycle)
}
