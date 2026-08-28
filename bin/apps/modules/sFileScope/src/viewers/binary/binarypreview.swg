#global internal

using Core, Pixel, Serialization

private const BinaryPreviewLimit = 8'u64

private func writePreviewU32(bytes: *Array'u8, offset: u64, value: u32)
{
    bytes[offset]     = cast(u8) value
    bytes[offset + 1] = cast(u8) (value >> 8)
    bytes[offset + 2] = cast(u8) (value >> 16)
    bytes[offset + 3] = cast(u8) (value >> 24)
}

func isIconContainer(image: *BinaryImage)->bool
{
    if !image.has(0, 6) or image.u16At(0) != 0 or !image.u16At(4) do
        return false
    let kind = image.u16At(2)
    return kind == 1 or kind == 2
}

// Rebuilds each directory entry as a one-image ICO so the existing decoder can expose every size,
// rather than selecting only the largest image from the original container.
func reportIconContainer(image: *BinaryImage, report: *BinaryReport, previews: *Array'BinaryPreview)
{
    image.bigEndian = false
    let count      = cast(u64) image.u16At(4)
    let kind       = image.u16At(2)
    let formatName = kind == 1 ? "Windows icon" : "Windows cursor"
    report.formatName = formatName
    report.summary    = Format.toString("% · % image%", formatName, count, count == 1 ? "" : "s")
    report.beginGroup("ICONDIR", "", "", offset: 0, length: 6 + count * 16, open: true)
    report.numField(0, 2, "Reserved", 0)
    report.numField(2, 2, "Type", cast(u64) kind, kind == 1 ? "Icon" : "Cursor")
    report.numField(4, 2, "ImageCount", count)

    let shown = Math.min(count, BinaryPreviewLimit)
    for index in shown
    {
        let at = 6 + index * 16
        if !image.has(at, 16) do
            break
        let width  = image.u8At(at) ? cast(u32) image.u8At(at) : 256
        let height = image.u8At(at + 1) ? cast(u32) image.u8At(at + 1) : 256
        let bits   = image.u16At(at + 6)
        let size   = cast(u64) image.u32At(at + 8)
        let offset = cast(u64) image.u32At(at + 12)
        let label  = Format.toString("%×% · %b", width, height, bits)

        report.beginGroup(Format.toString("Image %", index + 1).toString(), label.toString(), "", offset: offset, length: size)
        report.sizeField(at + 8, 4, "StoredSize", size)
        report.hexField(at + 12, 4, "Offset", offset)
        report.endGroup()

        if !size or !image.has(offset, size) do
            continue
        var one: Array'u8
        one.resize(22 + size)
        one[2] = cast(u8) kind
        one[4] = 1
        Memory.copy(one.buffer + 6, image.bytes.buffer + at, 16)
        writePreviewU32(&one, 18, 22)
        Memory.copy(one.buffer + 22, image.bytes.buffer + offset, size)
        let decoded = catch Image.decode(kind == 1 ? "entry.ico" : "entry.cur", one.toSlice()) as decodeError
        if decodeError != null do
            continue
        var preview: BinaryPreview
        preview.image = #move decoded
        preview.label = #move label
        previews.add(#move preview)
    }

    report.endGroup()
}

private func previewGuid(text: string)->Guid128
{
    var result: Guid128
    discard Guid128.tryParse(text, &result)
    return result
}

private func captureContainerKind()->Guid128  => previewGuid("7355af24-cf65-447b-918c-18ac74e6dc66")
private func capturePreviewRole()->Guid128    => previewGuid("f53e06c1-05a7-4537-9c6a-d85609209874")
private func captureBackgroundRole()->Guid128 => previewGuid("04267f4e-d659-4d32-9296-cc68be5bdb9d")
private func captureOriginalRole()->Guid128   => previewGuid("11d1a796-38d8-46ca-a4e6-5e2271ebd321")

private func addTagBinImage(bytes: const [..] u8, label: string, previews: *Array'BinaryPreview)
{
    var decoder: Decoder'Read.TagBin
    let image = catch decoder.readAll'Image(bytes) as decodeError
    if decodeError != null or image == null do
        return
    var preview: BinaryPreview
    preview.image = #move image![]
    preview.label = label
    Memory.delete(image)
    previews.add(#move preview)
}

// sSnapForge declares the role of every picture. Reader.readChunk performs the registered deflate
// step first, so compressed background and original images reach the same decoder as stored ones.
func loadSccImagePreviews(fileName: string, previews: *Array'BinaryPreview)
{
    var reader: Scc.Reader
    catch reader.initialize(fileName) as openError
    if openError != null or reader.kind() != captureContainerKind() do
        return

    for chunk in reader.chunks() where previews.count < BinaryPreviewLimit
    {
        if chunk.roleId != capturePreviewRole() and chunk.roleId != captureBackgroundRole() and chunk.roleId != captureOriginalRole() do
            continue
        let bytes = catch reader.readChunk(chunk.id) as readError
        if readError != null do
            continue

        if chunk.roleId == capturePreviewRole()
        {
            let image = catch Image.decode("preview.png", bytes.toSlice()) as decodeError
            if decodeError != null do
                continue
            var preview: BinaryPreview
            preview.image = #move image
            preview.label = "Preview"
            previews.add(#move preview)
        }
        elif chunk.roleId == captureBackgroundRole() do
            addTagBinImage(bytes.toSlice(), "Background", previews)
        else do
            addTagBinImage(bytes.toSlice(), "Original", previews)
    }
}
