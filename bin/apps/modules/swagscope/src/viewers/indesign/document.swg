#global internal
#global namespace Viewers.InDesign

using Core, Core.Errors, Pixel

// Marks a page without a saved preview.
const NoPreview = Swag.U64.Max

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

    // Bounds on a saved preview: its base64 text, its decoded payload, and its pixels.
    const PreviewBase64Limit  = 16 * 1024 * 1024'u64
    const PreviewPayloadLimit = 20 * 1024 * 1024'u64
    const PreviewPixelLimit   = 16 * 1024 * 1024'u64
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
struct CachedPreview
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
    if not hasBytes(bytes, offset, HeaderMinimumSize) or
       not matchesSignature(bytes, offset) or
       not matchesAt(bytes, offset + Signature.count, HeaderType) do
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

// Reads the page number of the preview record between `start` and `end`. Returns zero when the
// number is missing or malformed.
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

// Merges `source` into `result`; a preview for a page already present replaces the earlier one.
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
    if base64Error != null or
       previewBytes.count < 4 or
       previewBytes[0] != 0xFF or
       previewBytes[1] != 0xD8 or
       previewBytes[previewBytes.count - 2] != 0xFF or
       previewBytes[previewBytes.count - 1] != 0xD9 do
        fail InvalidFormatError{texts().err_Preview}

    var geometry: PreviewGeometry
    if not jpegGeometry(previewBytes.toSlice(), &geometry) do
        fail InvalidFormatError{texts().err_Preview}

    var result: retval
    result = catch Image.decode("indesign-preview.jpg", previewBytes.toSlice()) as decodeError
    if decodeError != null or
       not result.isValid() or
       result.width != cast(s32, geometry.width) or
       result.height != cast(s32, geometry.height) do
        fail InvalidFormatError{texts().err_Preview}
    return #move result
}

// Owns one selected page decode.
//
// The shared viewer background loader takes only a filename, while this operation also needs the
// immutable preview range selected by the reader.
struct PreviewLoad
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
