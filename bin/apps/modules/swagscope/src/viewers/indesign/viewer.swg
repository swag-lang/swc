#global internal

using Core, Core.Errors, Pixel, Gui

// The Adobe InDesign document signature and the master-page fields that establish that the
// following embedded XMP belongs to a native document rather than to arbitrary binary data.
private const IndesignSignature: [16] u8     = [0x06, 0x06, 0xED, 0xF5, 0xD8, 0x1D, 0x46, 0xE5, 0xBD, 0x31, 0xEF, 0xE7, 0xFE, 0x74, 0xB7, 0x1D]
private const IndesignHeaderType              = "DOCUMENT"
private const IndesignHeaderCopySize          = 4096'u64
private const IndesignByteOrderOffset         = 24'u64
private const IndesignFormatVersionOffset     = 29'u64
private const IndesignSequenceOffset          = 264'u64
private const IndesignStoragePageCountOffset  = 280'u64
private const IndesignHeaderMinimumSize       = IndesignStoragePageCountOffset + 4
private const IndesignPreviewItemOpen         = "<rdf:li"
private const IndesignPreviewItemClose        = "</rdf:li>"
private const IndesignPreviewImageOpen        = "<xmpGImg:image>"
private const IndesignPreviewImageClose       = "</xmpGImg:image>"
private const IndesignPreviewPageOpen         = "<xmpTPg:PageNumber>"
private const IndesignPreviewPageClose        = "</xmpTPg:PageNumber>"
private const IndesignPreviewBase64Limit      = 16 * 1024 * 1024'u64
private const IndesignPreviewPayloadLimit     = 20 * 1024 * 1024'u64
private const IndesignPreviewPixelLimit       = 16 * 1024 * 1024'u64
private const IndesignPreviewCachePixelLimit  = 24 * 1024 * 1024'u64
private const IndesignNoPreview               = Swag.U64.Max
private const IndesignPageLabelWidth           = 96.0

// One validated master-page header. InDesign retains two header copies and selects the newer
// sequence, so a partial overwrite of either first page does not make the document unreadable.
private struct IndesignHeader
{
    offset:        u64
    bigEndian:     bool
    formatVersion: u32
    sequence:      u64
    storagePages:  u32
}

// One saved page preview is an actual document rendering supplied by InDesign. The index retains
// only its base64 range; the reader decodes its pixels on demand and never invents a layout that
// the document did not save.
struct IndesignPreview
{
    page:         u32
    payloadStart: u64
    payloadEnd:   u64
}

// One decoded page held in the bounded viewer cache.
private struct IndesignCachedPreview
{
    index:     u64
    pixelCount: u64
    lastUsed:  u64
    image:     Image
}

private struct IndesignPreviewGeometry
{
    width:  u32
    height: u32
}

// A native InDesign document with an index of the XMP page pixels it saved.
struct IndesignDocument
{
    header:        IndesignHeader
    fileName:      String
    fileSize:      u64
    declaredBytes: u64
    previews:      Array'IndesignPreview
}

private func indesignHas(bytes: const [..] u8, offset, count: u64)->bool
{
    return offset <= bytes.count and count <= bytes.count - offset
}

private func indesignMatches(bytes: const [..] u8, offset: u64, text: string)->bool
{
    if !indesignHas(bytes, offset, text.count) do
        return false
    for index in text.count where bytes[offset + index] != text[index] do
        return false
    return true
}

private func indesignMatchesSignature(bytes: const [..] u8, offset: u64)->bool
{
    if !indesignHas(bytes, offset, IndesignSignature.count) do
        return false
    for index in IndesignSignature.count where bytes[offset + index] != IndesignSignature[index] do
        return false
    return true
}

private func indesignFind(bytes: const [..] u8, text: string, start, end: u64)->u64
{
    if start > end or text.count > end - start do
        return Swag.U64.Max

    var index = start
    while index <= end - text.count
    {
        if indesignMatches(bytes, index, text) do
            return index
        index += 1
    }

    return Swag.U64.Max
}

private func indesignU32(bytes: const [..] u8, offset: u64, bigEndian: bool)->u32
{
    var result = 0'u32
    for index in 4'u64
    {
        let position = bigEndian ? index : 3 - index
        result = (result << 8) | cast(u32) bytes[offset + position]
    }

    return result
}

private func indesignU64(bytes: const [..] u8, offset: u64)->u64
{
    var result = 0'u64
    for index in 8'u64 do
        result = (result << 8) | cast(u64) bytes[offset + 7 - index]
    return result
}

// Parses one master-page header. Object-stream byte order controls the version field, while the
// sequence and storage-page fields are the little-endian master-page values InDesign writes.
private func parseIndesignHeader(bytes: const [..] u8, offset: u64, result: *IndesignHeader)->bool
{
    if !indesignHas(bytes, offset, IndesignHeaderMinimumSize) or !indesignMatchesSignature(bytes, offset) or !indesignMatches(bytes, offset + IndesignSignature.count, IndesignHeaderType) do
        return false

    let byteOrder = bytes[offset + IndesignByteOrderOffset]
    if byteOrder != 1 and byteOrder != 2 do
        return false

    let storagePages = indesignU32(bytes, offset + IndesignStoragePageCountOffset, false)
    if !storagePages do
        return false

    result.offset        = offset
    result.bigEndian     = byteOrder == 2
    result.formatVersion = indesignU32(bytes, offset + IndesignFormatVersionOffset, result.bigEndian)
    result.sequence      = indesignU64(bytes, offset + IndesignSequenceOffset)
    result.storagePages  = storagePages
    return true
}

private func indesignBase64Byte(value: u8)->bool
{
    return value >= 'A' and value <= 'Z' or value >= 'a' and value <= 'z' or value >= '0' and value <= '9' or value == '+' or value == '/' or value == '='
}

// XMP serializes preview line breaks as character entities. Keep the base64 alphabet and skip a
// whole entity rather than retaining its hexadecimal spelling as false image data.
private func indesignPreviewBase64(bytes: const [..] u8, start, end: u64)->String
{
    if end < start or end - start > IndesignPreviewPayloadLimit do
        return {}

    var result: Array'u8
    result.reserve(Math.min(end - start, IndesignPreviewBase64Limit))

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
        if indesignBase64Byte(value)
        {
            if result.count == IndesignPreviewBase64Limit do
                return {}
            result.add(value)
        }
        index += 1
    }

    return result.isEmpty() ? {} : String.from(Swag.makeString(result.buffer!, result.count))
}

private func indesignPreviewPageNumber(bytes: const [..] u8, start, end: u64)->u32
{
    let valueStart = indesignFind(bytes, IndesignPreviewPageOpen, start, end)
    if valueStart == Swag.U64.Max do
        return 0

    let numberStart = valueStart + IndesignPreviewPageOpen.count
    let numberEnd   = indesignFind(bytes, IndesignPreviewPageClose, numberStart, end)
    if numberEnd == Swag.U64.Max or numberEnd == numberStart do
        return 0

    var result = 0'u32
    for index in numberStart until numberEnd
    {
        let value = bytes[index]
        if value < '0' or value > '9' or result > (Swag.U32.Max - cast(u32) (value - '0')) / 10 do
            return 0
        result = result * 10 + cast(u32) (value - '0')
    }

    return result == Swag.U32.Max ? 0 : result
}

private func indesignJpegStartOfFrame(marker: u8)->bool
{
    return marker == 0xC0 or marker == 0xC1 or marker == 0xC2 or marker == 0xC3 or marker == 0xC5 or marker == 0xC6 or marker == 0xC7 or marker == 0xC9 or marker == 0xCA or marker == 0xCB or marker == 0xCD or marker == 0xCE or marker == 0xCF
}

// Reads JPEG dimensions before materializing pixels. A saved preview may be a valid JPEG whose
// declared geometry would nevertheless exceed the reader's bounded cache.
private func indesignJpegGeometry(bytes: const [..] u8, result: *IndesignPreviewGeometry)->bool
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

        let segmentSize = (cast(u64) bytes[index] << 8) | cast(u64) bytes[index + 1]
        if segmentSize < 2 or segmentSize > bytes.count - index do
            return false
        if indesignJpegStartOfFrame(marker)
        {
            if segmentSize < 8 do
                return false

            result.height = (cast(u32) bytes[index + 3] << 8) | cast(u32) bytes[index + 4]
            result.width  = (cast(u32) bytes[index + 5] << 8) | cast(u32) bytes[index + 6]
            let pixels    = cast(u64) result.width * cast(u64) result.height
            return result.width != 0 and result.height != 0 and pixels <= IndesignPreviewPixelLimit
        }

        index += segmentSize
    }

    return false
}

// Finds every saved JPEG page preview without decoding their pixels. A document can retain several
// XMP generations, so the last usable reference for a physical page wins.
private func indexIndesignPreviews(bytes: const [..] u8)->Array'IndesignPreview fail
{
    var result: retval
    var fallbackPage = 1'u32
    var cursor       = 0'u64

    while cursor < bytes.count
    {
        let itemStart = indesignFind(bytes, IndesignPreviewItemOpen, cursor, bytes.count)
        if itemStart == Swag.U64.Max do
            break

        let itemContentStart = indesignFind(bytes, ">", itemStart, bytes.count)
        let itemEnd          = indesignFind(bytes, IndesignPreviewItemClose, itemStart, bytes.count)
        if itemContentStart == Swag.U64.Max or itemEnd == Swag.U64.Max or itemContentStart >= itemEnd do
            break

        let contentStart = itemContentStart + 1
        let imageStart   = indesignFind(bytes, IndesignPreviewImageOpen, contentStart, itemEnd)
        let imageEnd     = imageStart == Swag.U64.Max ? Swag.U64.Max : indesignFind(bytes, IndesignPreviewImageClose, imageStart + IndesignPreviewImageOpen.count, itemEnd)
        if imageEnd != Swag.U64.Max and imageEnd - imageStart <= IndesignPreviewPayloadLimit
        {
            let payloadStart = imageStart + IndesignPreviewImageOpen.count
            var page         = indesignPreviewPageNumber(bytes, contentStart, itemEnd)
            if !page
            {
                page = fallbackPage
                if fallbackPage != Swag.U32.Max do
                    fallbackPage += 1
            }
            elif page >= fallbackPage and page < Swag.U32.Max do
                fallbackPage = page + 1

            var existing = IndesignNoPreview
            for saved, index in result where saved.page == page
            {
                existing = index
                break
            }

            var saved: IndesignPreview
            saved.page         = page
            saved.payloadStart = payloadStart
            saved.payloadEnd   = imageEnd
            if existing != IndesignNoPreview do
                result[existing] = saved
            else do
                result.add(saved)
        }

        cursor = itemEnd + IndesignPreviewItemClose.count
    }

    if result.isEmpty() do
        fail InvalidFormatError{indesignStrings().err_Preview}
    return #move result
}

// Decodes one indexed JPEG preview on a worker. Encoded-payload and pixel bounds make opening a
// malformed document unable to retain the whole XMP payload or every document page at once.
private func loadIndesignPreview(fileName: string, preview: const *IndesignPreview)->Image fail
{
    var file  = try File.MappedFile.open(fileName)
    let region = try file.mapAll()
    let bytes  = region.bytes()
    if preview.payloadEnd < preview.payloadStart or !indesignHas(bytes, preview.payloadStart, preview.payloadEnd - preview.payloadStart) do
        fail InvalidFormatError{indesignStrings().err_Preview}

    let payload = indesignPreviewBase64(bytes, preview.payloadStart, preview.payloadEnd)
    if payload.isEmpty() do
        fail InvalidFormatError{indesignStrings().err_Preview}

    var previewBytes: Array'u8
    previewBytes = catch Base64.decode(payload.toString()) as base64Error
    if base64Error != null or previewBytes.count < 4 or previewBytes[0] != 0xFF or previewBytes[1] != 0xD8 or previewBytes[previewBytes.count - 2] != 0xFF or previewBytes[previewBytes.count - 1] != 0xD9 do
        fail InvalidFormatError{indesignStrings().err_Preview}

    var geometry: IndesignPreviewGeometry
    if !indesignJpegGeometry(previewBytes.toSlice(), &geometry) do
        fail InvalidFormatError{indesignStrings().err_Preview}

    var result: retval
    result = catch Image.decode("indesign-preview.jpg", previewBytes.toSlice()) as decodeError
    if decodeError != null or !result.isValid() or result.width != cast(s32) geometry.width or result.height != cast(s32) geometry.height do
        fail InvalidFormatError{indesignStrings().err_Preview}
    return #move result
}

// Owns one selected page decode. The shared viewer background loader takes only a filename, while
// this operation also needs the immutable preview range selected by the reader.
private struct IndesignPreviewLoad
{
    using operation: Viewer.BackgroundOperation
    fileName: String
    preview:  IndesignPreview
    value:    Image
    error:    #null any
}

private impl IndesignPreviewLoad
{
    mtd start(fileName: string, preview: const *IndesignPreview)
    {
        Debug.assert(!.started)
        .fileName   = fileName
        .preview    = preview[]
        .job.lambda = func(data: #null *void)
        {
            let operation = cast(*IndesignPreviewLoad) data!
            operation.value = catch loadIndesignPreview(operation.fileName.toString(), &operation.preview) as loadError
            operation.error = loadError
        }
        .job.data = me
        .started  = true
        Jobs.schedule(&.job)
    }

    mtd finish(value: *Image)->String
    {
        Debug.assert(.isDone())
        .wait()
        value[] = #move .value
        let result = Errors.message(.error)
        .error = null
        return result
    }

    mtd retire()->bool
    {
        if !.started do
            return true
        if !.isDone() do
            return false
        .wait()
        return true
    }

    mtd opDrop()
    {
        .wait()
    }
}

// Reads the master-page headers and indexes the saved page previews. The preview loader decodes
// pixels only after the user selects a page, while the header prevents arbitrary XMP from claiming
// the `.indd` viewer.
func loadIndesignDocument(fileName: string)->IndesignDocument fail
{
    var stream = try File.open(fileName, .Open, .Read, .ReadWrite | .Delete)
    let fileSize = try stream.size()
    let headerBytes = Math.min(fileSize, 2 * IndesignHeaderCopySize)
    var bytes: Array'u8
    bytes.resize(headerBytes)
    if !try stream.readExact(bytes.toSlice()) do
        fail InvalidFormatError{indesignStrings().err_Header}

    var first, second: IndesignHeader
    let hasFirst  = parseIndesignHeader(bytes.toSlice(), 0, &first)
    let hasSecond = parseIndesignHeader(bytes.toSlice(), IndesignHeaderCopySize, &second)
    if !hasFirst and !hasSecond do
        fail InvalidFormatError{indesignStrings().err_Header}

    var file    = try File.MappedFile.open(fileName)
    let region  = try file.mapAll()
    var previews = try indexIndesignPreviews(region.bytes())

    var result: retval
    result.header        = hasSecond and (!hasFirst or second.sequence > first.sequence) ? second : first
    result.fileName      = fileName
    result.fileSize      = fileSize
    result.declaredBytes = cast(u64) result.header.storagePages * IndesignHeaderCopySize
    result.previews      = #move previews
    return #move result
}

// Describes the visual InDesign preview reader to the host.
func indesignViewerPlugin()->Viewer.Plugin
{
    var result: retval
    result.key          = "indesign"
    result.resolveName  = &indesignViewerName
    result.attach       = &registerIndesignStrings
    result.iconAtlas    = viewerIcons()
    result.iconIndex    = cast(s32) ViewerIcons.Indesign
    result.create       = &createIndesignViewer
    result.smokeFixture = "viewer.indd"
    result.addSelectors(".indd")
    return result
}

private func indesignViewerName()->string => indesignStrings().ui_Name

private func indesignCommandWidth(metrics: const *ThemeMetrics)->f32
{
    return 2 * themeActionButtonSize(metrics) + IndesignPageLabelWidth + 16
}

// Shows the saved page previews as a document surface. ImageView provides wheel zoom,
// pointer-centred panning, and a double-click actual-size toggle, all on the pixels the document saved.
internal struct IndesignViewer
{
    using wnd: Wnd

    details:              String
    fileName:             String
    previews:             Array'IndesignPreview
    cachedPreviews:       Array'IndesignCachedPreview
    cachedPixels:         u64
    previewUseSerial      = 1'u64
    hasPreviewContent:    bool
    previewIndex:         u64
    requestedPreviewIndex = IndesignNoPreview
    loadingPreviewIndex   = IndesignNoPreview
    load:                 Viewer.BackgroundLoad'IndesignDocument
    loadTimer:            #null *Timer
    previewLoad:          IndesignPreviewLoad
    previewLoadTimer:     #null *Timer
    previewLoadPending:   bool
    reportFailure:        #null Viewer.ReportFailure
    reportDetails:        #null Viewer.ReportDetails
    reportChromeChanged:  #null Viewer.ReportChromeChanged
    reportLoadingChanged: #null Viewer.ReportLoadingChanged
    failureReason:        String

    #[Swag.Late]
    {
        commands:       *Wnd
        info:           *Wnd
        previousButton: *IconButton
        nextButton:     *IconButton
        pageLabel:      *IconButton
        zoomLabel:      *IconButton
        imageView:      *ImageView
    }
}

private impl IndesignViewer
{
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
        .previousButton.enable(.previewIndex != 0)
        .nextButton.enable(.previewIndex + 1 < .previews.count)
        .pageLabel.setText(Format.toString(indesignStrings().ui_Page, .previewIndex + 1, .previews.count).toString())
    }

    mtd refreshZoom()
    {
        .zoomLabel.setText(Format.toString("% %", cast(u32) Math.round(.imageView.effectiveZoom() * 100), "%"))
        if .reportChromeChanged do
            .reportChromeChanged!(me)
    }

    mtd showZoomMenu()
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        menu.addItem("50%", "scope.indesign.zoom50")
        menu.addItem(indesignStrings().ui_Actual, "scope.indesign.zoomActual", .theme().icon(.ActualSize, themeRowIconSize(.themeMetrics())))
        menu.addItem("125%", "scope.indesign.zoom125")
        menu.addItem("150%", "scope.indesign.zoom150")
        menu.addItem("200%", "scope.indesign.zoom200")
        menu.addSeparator()
        menu.addItem(indesignStrings().ui_Fit, "scope.indesign.zoomFit", .theme().icon(.FitView, themeRowIconSize(.themeMetrics())), rightName: "F")
        switch menu.doModal(.zoomLabel, autoDestroy: true) orelse ""
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
        if .reportDetails do
            .reportDetails!(me, .details.toString())
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
            .details = Format.toString(indesignStrings().ui_Details, index + 1, .previews.count, preview.image.width, preview.image.height)
            .refreshZoom()
            .reportCurrentDetails()
            return true
        }

        return false
    }

    mtd cachePreview(index: u64, image: *Image)
    {
        let pixelCount = cast(u64) image.width * cast(u64) image.height
        for &cached in .cachedPreviews
        {
            if cached.index == index
            {
                .cachedPixels -= cached.pixelCount
                cached.pixelCount = pixelCount
                cached.lastUsed   = .nextPreviewUse()
                cached.image = #move image[]
                .cachedPixels += pixelCount
                return
            }
        }

        while !.cachedPreviews.isEmpty() and .cachedPixels > IndesignPreviewCachePixelLimit - pixelCount
        {
            var oldestIndex = 0'u64
            for cached, cachedIndex in .cachedPreviews where cached.lastUsed < .cachedPreviews[oldestIndex].lastUsed do
                oldestIndex = cachedIndex
            .cachedPixels -= .cachedPreviews[oldestIndex].pixelCount
            .cachedPreviews.removeAt(oldestIndex)
        }

        var cached: IndesignCachedPreview
        cached.index      = index
        cached.pixelCount = pixelCount
        cached.lastUsed   = .nextPreviewUse()
        cached.image      = #move image[]
        .cachedPreviews.add(#move cached)
        .cachedPixels += pixelCount
    }

    mtd startRequestedPreview()
    {
        if .previewLoadPending or .requestedPreviewIndex == IndesignNoPreview do
            return

        .loadingPreviewIndex   = .requestedPreviewIndex
        .requestedPreviewIndex = IndesignNoPreview
        .previewLoad.start(.fileName.toString(), &.previews[.loadingPreviewIndex])
        .previewLoadPending = true
        .previewLoadTimer   = .addTimer(Viewer.BackgroundPollInterval)
        if .reportLoadingChanged do
            .reportLoadingChanged!(me)
    }

    mtd selectPreview(index: u64)
    {
        Debug.assert(index < .previews.count)
        .previewIndex = index
        .refreshPageCommands()
        if .showCachedPreview(index)
        {
            .requestedPreviewIndex = IndesignNoPreview
            return
        }

        .details = Format.toString(indesignStrings().ui_LoadingDetails, index + 1, .previews.count)
        .reportCurrentDetails()
        .requestedPreviewIndex = index
        .startRequestedPreview()
    }

    mtd publishDocument(document: *IndesignDocument)
    {
        .fileName = #move document.fileName
        .previews = #move document.previews
        .selectPreview(0)
        .applyLayout()
        .setInitialFocus(.imageView)
    }

    mtd retranslate()
    {
        .previousButton.toolTip = indesignStrings().ui_PreviousPage
        .nextButton.toolTip     = indesignStrings().ui_NextPage
        .pageLabel.toolTip      = indesignStrings().ui_ChoosePage
        .zoomLabel.toolTip      = indesignStrings().ui_ZoomMenu
        .refreshZoom()
        if !.loadTimer and !.previews.isEmpty()
        {
            .refreshPageCommands()
            if !.showCachedPreview(.previewIndex)
            {
                .details = Format.toString(indesignStrings().ui_LoadingDetails, .previewIndex + 1, .previews.count)
                .reportCurrentDetails()
            }
            .applyLayout()
        }
    }

    mtd showPageMenu()
    {
        let strings = indesignStrings()
        let menu    = MenuCtrl.createPopup(me, owner: me)
        var commands: Array'String
        commands.reserve(.previews.count)
        for preview, index in .previews
        {
            commands.add(Format.toString("scope.indesign.page.%", index))
            menu.addItem(Format.toString(strings.ui_PageMenuEntry, preview.page).toString(), commands[index].toString(), checked: index == .previewIndex)
        }

        let chosen = menu.doModal(.pageLabel, autoDestroy: true)
        if !chosen do
            return
        for command, index in commands where chosen! == command.toString()
        {
            .selectPreview(index)
            return
        }
    }

    mtd retire()->bool
    {
        if !.load.retire() do
            return false
        if !.previewLoad.retire() do
            return false
        if .loadTimer
        {
            .removeTimer(.loadTimer!)
            .loadTimer = null
        }
        if .previewLoadTimer
        {
            .removeTimer(.previewLoadTimer!)
            .previewLoadTimer = null
        }

        return true
    }
}

private impl IWnd for IndesignViewer
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer == .loadTimer
        {
            if !.load.isDone() do
                return

            .removeTimer(evt.timer)
            .loadTimer = null
            var document: IndesignDocument
            .failureReason = .load.finish(&document)
            if !.failureReason.isEmpty()
            {
                if .reportFailure do
                    .reportFailure!(me, .failureReason.toString())
                return
            }

            .publishDocument(&document)
            if .reportLoadingChanged do
                .reportLoadingChanged!(me)
            return
        }

        if evt.timer != .previewLoadTimer
        {
            evt.accepted = false
            return
        }

        if !.previewLoad.isDone() do
            return

        .removeTimer(evt.timer)
        .previewLoadTimer   = null
        .previewLoadPending = false
        let completedIndex  = .loadingPreviewIndex
        .loadingPreviewIndex = IndesignNoPreview
        var image: Image
        let failure = .previewLoad.finish(&image)
        if .requestedPreviewIndex == completedIndex do
            .requestedPreviewIndex = IndesignNoPreview

        if failure.isEmpty()
        {
            .cachePreview(completedIndex, &image)
            if completedIndex == .previewIndex do
                discard .showCachedPreview(completedIndex)
        }
        elif completedIndex == .previewIndex
        {
            .failureReason = failure
            if .reportFailure do
                .reportFailure!(me, .failureReason.toString())
        }

        .startRequestedPreview()

        if .reportLoadingChanged do
            .reportLoadingChanged!(me)
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed
        {
            evt.accepted = false
            return
        }
        if .previews.isEmpty()
        {
            evt.accepted = false
            return
        }

        switch evt.key
        {
        case .Add, .OemPlus:
            .imageView.zoomIn()

        case .Subtract, .OemMinus:
            .imageView.zoomOut()

        case .D0 where evt.modifiers.has(.Control):
            .imageView.actualSize()

        case .F where evt.modifiers == .None:
            .imageView.zoomToFit()

        case .Left, .PageUp where evt.modifiers == .None:
            if .previewIndex do
                .selectPreview(.previewIndex - 1)
            else do
                evt.accepted = false

        case .Right, .PageDown where evt.modifiers == .None:
            if .previewIndex + 1 < .previews.count do
                .selectPreview(.previewIndex + 1)
            else do
                evt.accepted = false

        case .Home where evt.modifiers == .None:
            .selectPreview(0)

        case .End where evt.modifiers == .None:
            .selectPreview(.previews.count - 1)

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

internal impl IndesignViewer
{
    func create(host: Viewer.Host)->*IndesignViewer
    {
        let services = host.services()
        let result   = Wnd.create'IndesignViewer(host.contentParent(), "scope.indesign")
        result.backgroundStyle      = .View
        result.reportFailure        = services.reportFailure
        result.reportDetails        = services.reportDetails
        result.reportChromeChanged  = services.reportChromeChanged
        result.reportLoadingChanged = services.reportLoadingChanged

        result.commands = host.createCommandGroup(indesignCommandWidth(result.themeMetrics()))
        result.info     = host.createInfoGroup(ViewerZoomSlotWidth)
        with result.previousButton = IconButton.create(result.commands, result.theme().icon(.ChevronLeft, themeActionIconSize(result.themeMetrics())), {0, 0, themeActionButtonSize(result.themeMetrics()), themeActionButtonSize(result.themeMetrics())})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = indesignStrings().ui_PreviousPage
            .enable(false)
            .sigPressed += func|view = result|(button)
            {
                discard button
                if view.previewIndex do
                    view.selectPreview(view.previewIndex - 1)
            }
        }

        with result.nextButton = IconButton.create(result.commands, result.theme().icon(.ChevronRight, themeActionIconSize(result.themeMetrics())), {0, 0, themeActionButtonSize(result.themeMetrics()), themeActionButtonSize(result.themeMetrics())})
        {
            .dockStyle = .Left
            .toolTip   = indesignStrings().ui_NextPage
            .enable(false)
            .sigPressed += func|view = result|(button)
            {
                discard button
                if view.previewIndex + 1 < view.previews.count do
                    view.selectPreview(view.previewIndex + 1)
            }
        }

        with result.pageLabel = IconButton.create(result.commands, {}, {0, 0, IndesignPageLabelWidth, themeActionButtonSize(result.themeMetrics())}, "scope.indesign.page", .CenterContent)
        {
            .dockStyle = .Left
            .margin.x  = 8
            .setArrowPosition(.RightDownward)
            .setForm(.Rectangle)
            .style.setFont(result.theme().createDefaultFontFS(11), .Regular)
            .toolTip    = indesignStrings().ui_ChoosePage
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.showPageMenu()
            }
        }

        with result.zoomLabel = IconButton.create(result.info, {}, {0, 0, ViewerZoomButtonWidth, 32}, "scope.indesign.zoom", .CenterContent)
        {
            .dockStyle = .Center
            .margin    = {ViewerInfoControlInset, 0, ViewerInfoControlInset, 0}
            .setText("100%")
            .setArrowPosition(.RightDownward)
            .setForm(.Rectangle)
            .style.setFont(result.theme().createDefaultFontFS(11), .Regular)
            .toolTip    = indesignStrings().ui_ZoomMenu
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.showZoomMenu()
            }
        }

        result.imageView                 = ImageView.create(result)
        result.imageView.backgroundStyle = .View
        result.imageView.dockStyle       = .Center
        result.imageView.sigZoomChanged += func|view = result|(imageView)
        {
            discard imageView
            view.refreshZoom()
        }

        result.applyLayout()
        result.refreshZoom()
        result.load.start(host.fileName(), &loadIndesignDocument)
        result.loadTimer = result.addTimer(Viewer.BackgroundPollInterval)
        return result
    }
}

// Creates the integrated InDesign page-preview view.
func createIndesignViewer(host: Viewer.Host)
{
    let view = IndesignViewer.create(host)
    host.attachView(view)
    host.setLifecycle({
        isLoading: func(wnd)->bool { let view = cast(*IndesignViewer) wnd; return view.loadTimer != null or view.previewLoadTimer != null },
        needsLoadingOverlay: func(wnd)->bool { let view = cast(*IndesignViewer) wnd; return view.loadTimer != null or (view.previewLoadTimer != null and !view.hasPreviewContent) },
        retire: func(wnd)->bool { return (cast(*IndesignViewer) wnd).retire() }})
}
