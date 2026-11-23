#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// Writes readable content at exact offsets. A checked-in fixture would carry whatever line endings
// the checkout gave it, which moves every offset an assertion names.
internal func writeSampleFile()->String
{
    let fileName = Gui.Testing.tempFilePath("viewer-hex-sample-", ".bin")
    let content  = "Swag Scope hex fixture\nASCII text and symbols: 00 FF 42.\n"
    discard expect File.writeAllText(fileName, content)
    return fileName
}

// A generated station-telemetry capture reads from declared records through its later offsets.
#test
{
    let fileName = scopeTestDataPath("viewer.hex.telemetry.bin")
    var host: Testing.HeadlessHost
    host.setup(900, 600)

    let view = hexTestViewer(&host, fileName, 900, 560)
    let grid = view.grid
    Swag.require(grid.doc.fileSize == 656)
    Swag.require(grid.doc.byteAt(0) == 'N'u8 and grid.doc.byteAt(1) == 'B'u8)
    Swag.require(grid.doc.byteAt(4) == 1 and grid.doc.byteAt(6) == 0 and grid.doc.byteAt(7) == 20)
    Swag.require(grid.doc.byteAt(402) == 0x54 and grid.doc.byteAt(405) == 1)

    grid.setBytesPerRow(16, false)
    Swag.require(grid.goToTypedOffset("1A0") and grid.caret == 0x1A0)
    Swag.require(grid.topRow > 0)
    Swag.require(view.revealOffset(400, 32))
    Swag.require(grid.selectionStart() == 400 and grid.selectionLength() == 32)
}

// Selecting a decoded top-level structure is an explicit destination in the same history.
#test
{
    let fileName = scopeTestDataPath("viewer.field-station.elf")
    var host: Testing.HeadlessHost
    host.setup(900, 600)
    let view = hexTestViewer(&host, fileName, 900, 560)
    Swag.require(view.structure.tabs.count > 0)
    view.grid.moveCaret(32, false)
    view.selectStructure(0)
    Swag.require(view.grid.caret == view.structure.tabs[0].offset)
    Swag.require(view.navigateHistory(-1) and view.grid.caret == 32)
}

// A file-open error crosses the viewer boundary instead of appearing as an empty byte grid.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 420)

    var result = openTestViewer(Hex.viewerPlugin(), &host.root, "this-file-does-not-exist.bin", commandParent: &host.root, infoParent: &host.root)
    Swag.require(result.view != null and result.commands == null and result.info != null)
    let view = assume cast(*Hex.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)
    Swag.require(not view.failureReason.isEmpty())
}

// Replacing the document clears the old caret and selection state.
#test
{
    let fileName = writeStreamedFile(16)
    defer discard catch File.delete(fileName)
    let replacementName = writeStreamedFile(4)
    defer discard catch File.delete(replacementName)

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    let view = hexTestViewer(&host, fileName, 900, 560)
    view.grid.selectRange(7, 1)
    Swag.require(view.grid.hasSelection())

    var replacement: Hex.Document
    let opened = replacement.open(replacementName)
    Swag.require(opened)
    defer replacement.close()
    view.grid.exchangeDocument(&replacement)
    Swag.require(view.grid.caret == 0 and view.grid.selectionStart() == 0)
    Swag.require(not view.grid.hasSelection() and view.grid.selectionLength() == 1)
}

// Typed grouping changes scalar presentation without taking byte-exact movement and selection away.
#test
{
    let fileName = writeStreamedFile(4096)
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(900, 600)

    let view = hexTestViewer(&host, fileName, 900, 560)
    let grid = view.grid
    grid.setGrouping(.Unsigned32)
    Swag.require(grid.valueSize() == 4 and grid.displayGroupSize() == 4)
    Swag.require(grid.selectionStart() == 0 and grid.selectionLength() == 1)

    host.focus(grid)
    host.keyPress(.Right)
    Swag.require(grid.caret == 1 and grid.selectionStart() == 1 and grid.selectionLength() == 1)
    host.keyPress(.Right, .Shift)
    Swag.require(grid.caret == 2 and grid.selectionStart() == 1 and grid.selectionLength() == 2)

    grid.setGrouping(.Float64)
    Swag.require(grid.valueSize() == 8 and grid.selectionStart() == 1 and grid.selectionLength() == 2)
    grid.setGrouping(.Bytes)
    Swag.require(grid.selectionLength() == 2 and grid.hasSelection())

    // Width and spelling are independent controls. Float appears only where the selected width
    // has a corresponding representation.
    view.setValueWidth(1)
    view.setFormat(1)
    Swag.require(grid.grouping == .Unsigned16)
    view.setValueWidth(3)
    view.setFormat(3)
    Swag.require(grid.grouping == .Float64 and grid.valueSize() == 8)
    view.setValueWidth(0)
    Swag.require(view.formatCount() == 3 and view.formatIndex == 0 and grid.grouping == .Bytes)

    // The options reach the same choices, and offer float only where the width has one.
    host.activateOptionRowWhenShown(Hex.texts().ui_ValueWidth)
    host.thenActivateOptionRow(Hex.texts().ui_Width32)
    host.thenActivateOptionRow(Hex.texts().ui_Representation)
    host.thenActivateOptionRow(Hex.texts().ui_FormatFloat)
    view.showOptions()
    Swag.require(host.autoHandled and grid.grouping == .Float32)
    view.setValueWidth(0)
}

// The dump copy is the view in text form: the offset, the grouped bytes, and the text column.
#test
{
    let text = Hex.formatDump([0'u8, 1'u8, 0x20'u8, 0x41'u8, 0xFF'u8], 0x20, 16, 16)
    Swag.require(Utf8.contains(text.toSlice(), "0000000000000020"))
    Swag.require(Utf8.contains(text.toSlice(), "00 01 20 41 FF"))
    Swag.require(Utf8.contains(text.toSlice(), ".. A."))

    let narrow = Hex.formatDump([0xAA'u8, 0xBB'u8, 0xCC'u8], 0, 2, 8)
    Swag.require(Utf8.contains(narrow.toSlice(), "00000000  AA BB"))
    Swag.require(Utf8.contains(narrow.toSlice(), "00000002  CC"))
}

// Go To keeps bare values hexadecimal, and accepts explicit decimal, percentage, named, and
// caret-relative positions.
#test
{
    Swag.require(parseFileOffset("1F", 0, 1000) == 0x1F)
    Swag.require(parseFileOffset("  0x1f  ", 0, 1000) == 0x1F)
    Swag.require(parseFileOffset("00 1F", 0, 1000) == 0x1F)
    Swag.require(parseFileOffset("0d31", 0, 1000) == 31)
    Swag.require(parseFileOffset("50%", 0, 1000) == 499)
    let caret = parseFileOffset("caret", 0x20, 1000)
    Swag.require(caret == 0x20, Format.toString("caret resolved as %", caret))
    Swag.require(parseFileOffset("FileSize", 0, 1000) == 999)
    Swag.require(parseFileOffset("+10", 0x20, 1000) == 0x30)
    Swag.require(parseFileOffset("-10", 0x20, 1000) == 0x10)
    Swag.require(parseFileOffset("-1000", 0x20, 1000) == 0)
    Swag.require(parseFileOffset("FFFFFF", 0, 1000) == 999)
    Swag.require(parseFileOffset("101%", 0, 1000) == Swag.U64.Max)
    Swag.require(parseFileOffset("0dG", 0, 1000) == Swag.U64.Max)
    Swag.require(parseFileOffset("zz", 0, 1000) == Swag.U64.Max)
    Swag.require(parseFileOffset("", 0, 1000) == Swag.U64.Max)
    Swag.require(parseFileOffset("10", 0, 0) == Swag.U64.Max)
}

// Address expressions honor arithmetic precedence, alignment and the selected file origins.
#test
{
    Swag.require(parseFileOffset("10 + 2 * 3", 0, 1000) == 0x16)
    Swag.require(parseFileOffset("(10 + 2) * 3", 0, 1000) == 0x36)
    Swag.require(parseFileOffset("align(17, 10)", 0, 1000) == 0x20)
    Swag.require(parseFileOffset("align(20, 10)", 0, 1000) == 0x20)
    Swag.require(parseFileOffset("base", 0, 1000) == Swag.U64.Max)
    Swag.require(parseFileOffset("bookmark", 0, 1000) == Swag.U64.Max)
    Swag.require(parseFileOffset("base + 10", 0, 1000, 0x400000, hasAddressContext: true) == 0x10)
    Swag.require(parseFileOffset("align(base + 11, 10)", 0, 1000, 0x400000, hasAddressContext: true) == 0x20)
    Swag.require(parseFileOffset("bookmark + 10", 0, 1000, bookmark: 0x40, hasAddressContext: true) == 0x50)
    Swag.require(parseFileOffset("bookmark", 0, 1000) == Swag.U64.Max)
    Swag.require(parseFileOffset("base - 1", 0, 1000, 0x400000, hasAddressContext: true) == Swag.U64.Max)
    Swag.require(parseFileOffset("1 / 0", 0, 1000) == Swag.U64.Max)
    Swag.require(parseFileOffset("align(10, 0)", 0, 1000) == Swag.U64.Max)
    Swag.require(parseFileOffset("FFFFFFFFFFFFFFFF * 2", 0, 1000) == Swag.U64.Max)
    Swag.require(parseFileOffset("10 +", 0, 1000) == Swag.U64.Max)
    Swag.require(parseFileOffset("(10", 0, 1000) == Swag.U64.Max)
}

// Binary queries preserve their exact byte span: pairs can carry nibble wildcards, text is UTF-8,
// and an active scalar follows both the selected representation and byte order.
#test
{
    let wildcard = Hex.parseSearch("hex: 4D 5? ?? A?", .Bytes, false)
    Swag.require(wildcard.state == .Valid and wildcard.pattern.length() == 4)
    Swag.require(wildcard.pattern.values[0] == 0x4D and wildcard.pattern.masks[0] == 0xFF)
    Swag.require(wildcard.pattern.values[1] == 0x50 and wildcard.pattern.masks[1] == 0xF0)
    Swag.require(wildcard.pattern.values[2] == 0 and wildcard.pattern.masks[2] == 0)
    Swag.require(wildcard.pattern.values[3] == 0xA0 and wildcard.pattern.masks[3] == 0xF0)

    let text = Hex.parseSearch("text: café", .Bytes, false)
    Swag.require(text.state == .Valid and text.pattern.length() == ("café").count)
    Swag.require(text.pattern.values[text.pattern.length() - 2] == 0xC3 and text.pattern.values[text.pattern.length() - 1] == 0xA9)

    let little = Hex.parseSearch("value: 305419896", .Unsigned32, false)
    let big    = Hex.parseSearch("value: 305419896", .Unsigned32, true)
    Swag.require(little.state == .Valid and little.pattern.values[0] == 0x78 and little.pattern.values[3] == 0x12)
    Swag.require(big.state == .Valid and big.pattern.values[0] == 0x12 and big.pattern.values[3] == 0x78)

    let signed = Hex.parseSearch("value: -2", .Signed16, false)
    Swag.require(signed.state == .Valid and signed.pattern.values[0] == 0xFE and signed.pattern.values[1] == 0xFF)
    let real = Hex.parseSearch("value: 1", .Float32, false)
    Swag.require(real.state == .Valid and
                 real.pattern.values[0] == 0 and
                 real.pattern.values[2] == 0x80 and
                 real.pattern.values[3] == 0x3F)

    Swag.require(Hex.parseSearch("4", .Bytes, false).state == .Incomplete)
    Swag.require(Hex.parseSearch("4G", .Bytes, false).error == .Pattern)
    Swag.require(Hex.parseSearch("value: 70000", .Unsigned16, false).error == .Value)
}

// The inspector decodes IEEE-754 binary16 in either byte order and only when two bytes remain.
#test
{
    Swag.require(Hex.float16ToFloat(0x3C00) == 1'f32)
    Swag.require(Hex.float16ToFloat(0x0001) == 5.960464477539063e-8'f32)
    Swag.require(cast #bit (u32, Hex.float16ToFloat(0x0400)) == 0x38800000)
    Swag.require(cast #bit (u32, Hex.float16ToFloat(0x7BFF)) == 0x477FE000)
    Swag.require(cast #bit (u32, Hex.float16ToFloat(0x0000)) == 0x00000000)
    Swag.require(cast #bit (u32, Hex.float16ToFloat(0x8000)) == 0x80000000)
    Swag.require(cast #bit (u32, Hex.float16ToFloat(0x7C00)) == 0x7F800000)
    Swag.require(cast #bit (u32, Hex.float16ToFloat(0xFC00)) == 0xFF800000)
    let nanBits = cast #bit (u32, Hex.float16ToFloat(0x7E00))
    Swag.require((nanBits & 0x7F800000) == 0x7F800000 and (nanBits & 0x007FFFFF) != 0)
    let bigEndianBytes: Array'u8 = [0x3C, 0x00]
    Swag.require(Hex.float16ToFloat(cast(u16, Hex.readScalar(bigEndianBytes.toSlice(), true))) == 1'f32)

    let fileName = Gui.Testing.tempFilePath("scope-hex-inspector-f16-", ".bin")
    defer discard catch File.delete(fileName)
    let halfValue: Array'u8 = [0x00, 0x3C]
    expect File.writeAllBytes(fileName, halfValue.toSlice())

    var host: Testing.HeadlessHost
    host.setup(1200, 680)
    let view = hexTestViewer(&host, fileName, 1200, 640)
    view.refreshInspector()
    var found = false
    for line in view.inspectorView.readings where line.label == Hex.texts().ui_InspectorFloat16
    {
        Swag.require(line.value == "1", line.value)
        found = true
    }
    Swag.require(found)

    view.grid.bigEndian = true
    view.refreshInspector()
    found = false
    for line in view.inspectorView.readings where line.label == Hex.texts().ui_InspectorFloat16
    {
        Swag.require(line.value != "1", line.value)
        found = true
    }
    Swag.require(found)

    view.grid.moveCaret(1, false)
    view.refreshInspector()
    for line in view.inspectorView.readings do
        Swag.require(line.label != Hex.texts().ui_InspectorFloat16)
}

// IPv4 preserves the four source bytes regardless of scalar byte order, and needs all four bytes.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-hex-inspector-ipv4-", ".bin")
    defer discard catch File.delete(fileName)
    let address: Array'u8 = [192, 168, 1, 1]
    expect File.writeAllBytes(fileName, address.toSlice())

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    let view = hexTestViewer(&host, fileName, 900, 560)
    for reading in view.inspectorView.readings where reading.label == Hex.texts().ui_InspectorIpv4 do
        Swag.require(reading.value == "192.168.1.1", reading.value)

    view.grid.setBigEndian(true)
    view.refreshInspector()
    var found = false
    for reading in view.inspectorView.readings where reading.label == Hex.texts().ui_InspectorIpv4
    {
        Swag.require(reading.value == "192.168.1.1", reading.value)
        found = true
    }
    Swag.require(found)

    view.grid.moveCaret(1, false)
    view.refreshInspector()
    for reading in view.inspectorView.readings do
        Swag.require(reading.label != Hex.texts().ui_InspectorIpv4)
}

// ULEB128 and SLEB128 stop at ten bytes, distinguish incomplete input from overflow, and sign-extend.
#test
{
    let positive: Array'u8 = [0xE5, 0x8E, 0x26]
    let unsigned = Hex.readUleb128(positive.toSlice())
    let signed   = Hex.readSleb128(positive.toSlice())
    Swag.require(unsigned.state == .Valid and unsigned.value == 624485)
    Swag.require(signed.state == .Valid and cast #bit (s64, signed.value) == 624485)

    let minusOne: Array'u8 = [0x7F]
    let negative = Hex.readSleb128(minusOne.toSlice())
    Swag.require(negative.state == .Valid and cast #bit (s64, negative.value) == -1)
    let incomplete: Array'u8 = [0x80]
    Swag.require(Hex.readUleb128(incomplete.toSlice()).state == .Incomplete)
    Swag.require(Hex.readSleb128(incomplete.toSlice()).state == .Incomplete)

    var unsignedMax: Array'u8
    unsignedMax.resize(10)
    for index in 9 do
        unsignedMax[index] = 0xFF
    unsignedMax[9] = 1
    Swag.require(Hex.readUleb128(unsignedMax.toSlice()).value == Swag.U64.Max)

    var signedMin: Array'u8
    signedMin.resize(10)
    for index in 9 do
        signedMin[index] = 0x80
    signedMin[9] = 0x7F
    let minValue = Hex.readSleb128(signedMin.toSlice())
    Swag.require(minValue.state == .Valid and minValue.value == 0x8000000000000000)

    unsignedMax[9] = 2
    Swag.require(Hex.readUleb128(unsignedMax.toSlice()).state == .Invalid)
    signedMin[9] = 1
    Swag.require(Hex.readSleb128(signedMin.toSlice()).state == .Invalid)

    let fileName = Gui.Testing.tempFilePath("scope-hex-inspector-varint-", ".bin")
    defer discard catch File.delete(fileName)
    let encoded: Array'u8 = [0xE5, 0x8E, 0x26, 0x00]
    expect File.writeAllBytes(fileName, encoded.toSlice())
    var host: Testing.HeadlessHost
    host.setup(900, 600)
    let view = hexTestViewer(&host, fileName, 900, 560)
    var ulebFound = false
    var slebFound = false
    for reading in view.inspectorView.readings
    {
        if reading.label == Hex.texts().ui_InspectorUleb128
        {
            Swag.require(reading.value == "624 485")
            ulebFound = true
        }
        if reading.label == Hex.texts().ui_InspectorSleb128
        {
            Swag.require(reading.value == "624 485")
            slebFound = true
        }
    }
    Swag.require(ulebFound and slebFound)
}

// The inspector provides the full ten-byte window used by terminal ULEB128 and SLEB128 values.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-hex-inspector-varint-ten-bytes-", ".bin")
    defer discard catch File.delete(fileName)
    var bytes: Array'u8
    bytes.resize(10)
    for index in 9 do
        bytes[index] = 0xFF
    bytes[9] = 1
    expect File.writeAllBytes(fileName, bytes.toSlice())
    var host: Testing.HeadlessHost
    host.setup(900, 600)
    let view = hexTestViewer(&host, fileName, 900, 560)
    var found = false
    for reading in view.inspectorView.readings
    {
        if reading.label == Hex.texts().ui_InspectorUleb128
        {
            Swag.require(reading.value == "18 446 744 073 709 551 615")
            found = true
        }
    }
    Swag.require(found)
}

// Address readings use their wire order and are unaffected by the scalar endian option.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-hex-inspector-addresses-", ".bin")
    defer discard catch File.delete(fileName)
    let bytes: Array'u8 = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
                           0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F]
    expect File.writeAllBytes(fileName, bytes.toSlice())
    var host: Testing.HeadlessHost
    host.setup(900, 600)
    let view = hexTestViewer(&host, fileName, 900, 560)
    for reading in view.inspectorView.readings
    {
        if reading.label == Hex.texts().ui_InspectorIpv6 do
            Swag.require(reading.value == "0001:0203:0405:0607:0809:0A0B:0C0D:0E0F")
        if reading.label == Hex.texts().ui_InspectorGuid do
            Swag.require(reading.value == "00010203-0405-0607-0809-0A0B0C0D0E0F")
    }

    view.setBigEndian(true)
    view.refreshInspector()
    var ipv6Found = false
    var guidFound = false
    var rgbaFound = false
    for reading in view.inspectorView.readings
    {
        if reading.label == Hex.texts().ui_InspectorRgba8
        {
            Swag.require(reading.value == "#00010203")
            rgbaFound = true
        }
        if reading.label == Hex.texts().ui_InspectorIpv6
        {
            Swag.require(reading.value == "0001:0203:0405:0607:0809:0A0B:0C0D:0E0F")
            ipv6Found = true
        }
        if reading.label == Hex.texts().ui_InspectorGuid
        {
            Swag.require(reading.value == "00010203-0405-0607-0809-0A0B0C0D0E0F")
            guidFound = true
        }
    }
    Swag.require(ipv6Found and guidFound and rgbaFound)
}

// Packed decimal uses explicit sign nibbles and rejects malformed digits.
#test
{
    let positive: Array'u8 = [0x12, 0x3C]
    let negative: Array'u8 = [0x12, 0x3D]
    let malformed: Array'u8 = [0x1A, 0x3C]
    Swag.require(Hex.readPackedBcd(positive.toSlice()) == "123")
    Swag.require(Hex.readPackedBcd(negative.toSlice()) == "-123")
    Swag.require(Hex.readPackedBcd(malformed.toSlice()) == Hex.texts().ui_ReadingInvalid)

    let fileName = Gui.Testing.tempFilePath("scope-hex-inspector-bcd-", ".bin")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, positive.toSlice())
    var host: Testing.HeadlessHost
    host.setup(900, 600)
    let view = hexTestViewer(&host, fileName, 900, 560)
    var found = false
    for reading in view.inspectorView.readings
    {
        if reading.label == Hex.texts().ui_InspectorBcd
        {
            Swag.require(reading.value == "123")
            found = true
        }
    }
    Swag.require(found)
}

// The lens copies exactly the inspector's current headline, and disables the action without a value.
#test
{
    if not Clipboard.isFake() do
        return

    let fileName = Gui.Testing.tempFilePath("scope-hex-copy-value-", ".bin")
    defer discard catch File.delete(fileName)
    let payload: Array'u8 = [42, 43]
    expect File.writeAllBytes(fileName, payload.toSlice())

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    let view = hexTestViewer(&host, fileName, 900, 560)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    expect host.app.setLanguage("fr")
    Swag.require(Hex.texts().ui_CopyValue == "Copier la valeur inspectée")
    Swag.require(Hex.texts().ui_CopyReading == "Copier la lecture %")

    var results: Lens.Results
    var entries = Viewer.LensEntries.create(&results, "Hexadecimal", host.theme)
    view.describeLens(&entries)
    var found = false
    for &entry in results.sections[0]!.entries where entry.title == Hex.texts().ui_CopyValue
    {
        Swag.require(not entry.disabled)
        entry.run!()
        found = true
    }
    Swag.require(found and Clipboard.getString() == view.inspectorView.headline and Clipboard.getString() == "42")

    var f16Value = String{}
    for reading in view.inspectorView.readings where reading.label == Hex.texts().ui_InspectorFloat16 do
        f16Value = reading.value
    found = false
    let copyF16 = Format.toString(Hex.texts().ui_CopyReading, Hex.texts().ui_InspectorFloat16)
    for &entry in results.sections[0]!.entries where entry.title == copyF16
    {
        Swag.require(not entry.disabled)
        entry.run!()
        found = true
    }
    Swag.require(found, Format.toString("f16 copy row missing among % rows", results.sections[0]!.entries.count))
    Swag.require(not f16Value.isEmpty(), "f16 inspector value missing")
    Swag.require(Clipboard.getString() == f16Value, Format.toString("copied %, expected %", Clipboard.getString(), f16Value))

    view.grid.moveCaret(1, false)
    view.refreshInspector()
    Swag.require(view.inspectorView.headline == "43")
    results = {}
    entries = Viewer.LensEntries.create(&results, "Hexadecimal", host.theme)
    view.describeLens(&entries)
    found = false
    for &entry in results.sections[0]!.entries where entry.title == Hex.texts().ui_CopyValue
    {
        Swag.require(not entry.disabled)
        entry.run!()
        found = true
    }
    Swag.require(found and Clipboard.getString() == view.inspectorView.headline and Clipboard.getString() == "43")

    let emptyName = Gui.Testing.tempFilePath("scope-hex-copy-value-empty-", ".bin")
    defer discard catch File.delete(emptyName)
    expect File.writeAllText(emptyName, "")
    let emptyView = hexTestViewer(&host, emptyName, 640, 420)
    results = {}
    entries = Viewer.LensEntries.create(&results, "Hexadecimal", host.theme)
    emptyView.describeLens(&entries)
    found = false
    for &entry in results.sections[0]!.entries where entry.title == Hex.texts().ui_CopyValue
    {
        Swag.require(entry.disabled)
        found = true
    }
    Swag.require(found)
}

// Range analysis streams fixed byte counts and keeps inferred strings tied to their source bytes.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-hex-analysis-", ".bin")
    defer discard catch File.delete(fileName)

    var payload: Array'u8
    payload.resize(256)
    let ascii = "HELLO-WORLD"
    for value, index in ascii do
        payload[16 + index] = value
    let little = "WideLE"
    for value, index in little
    {
        payload[64 + index * 2]     = value
        payload[64 + index * 2 + 1] = 0
    }

    let big = "WideBE"
    for value, index in big
    {
        payload[96 + index * 2]     = 0
        payload[96 + index * 2 + 1] = value
    }

    payload[200] = 0xFF
    expect File.writeAllBytes(fileName, payload.toSlice())

    var operation: Hex.AnalysisOperation
    operation.start(fileName, Viewers.Hex.AnalysisRange{0, payload.count})
    operation.task.wait()
    let result = operation.finish()
    Swag.require(result.failureReason.isEmpty() and not result.cancelled and result.scanned == payload.count)
    Swag.require(result.histogram[0xFF] == 1 and result.histogram[cast(u8, 'H')] == 1)
    Swag.require(result.zeroCount > 200 and result.printableCount == ascii.count + little.count + big.count)
    Swag.require(result.entropy > 0 and result.entropy < 8)

    var foundAscii:  bool
    var foundLittle: bool
    var foundBig:    bool
    for one in result.strings
    {
        if one.kind == .Ascii and one.offset == 16 and one.length == ascii.count do
            foundAscii = one.text == ascii
        if one.kind == .Utf16Little and one.offset == 64 and one.length == little.count * 2 do
            foundLittle = one.text == little
        if one.kind == .Utf16Big and one.offset == 96 and one.length == big.count * 2 do
            foundBig = one.text == big
    }

    Swag.require(foundAscii and foundLittle and foundBig)

    // A scan run by work that was asked to stop ends before reading anything.
    var stopper: Swag.Task'Hex.AnalysisResult
    let self  = &stopper
    let count = payload.count
    let path:    string = fileName
    stopper.submit(func|self, path, count|()->Hex.AnalysisResult
    {
        self.cancel()
        return Hex.analyzeRange(path, Viewers.Hex.AnalysisRange{0, count})
    })
    let stopped = expect stopper.take()
    Swag.require(stopped.cancelled and not stopped.scanned and not stopped.hasDigests)
}

// Entropy blocks stay bounded, retain exact byte ranges, and navigate from the findings list.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-hex-entropy-blocks-", ".bin")
    defer discard catch File.delete(fileName)

    const BlockSize = 64 * 1024'u64
    var payload: Array'u8
    payload.resize(BlockSize * 2 + 7)
    for index in BlockSize do
        payload[BlockSize + index] = cast(u8, index)
    expect File.writeAllBytes(fileName, payload.toSlice())

    var result = Hex.analyzeRange(fileName, Viewers.Hex.AnalysisRange{0, payload.count})
    Swag.require(result.failureReason.isEmpty() and result.entropyBlocks.count == 3)
    Swag.require(result.entropyBlocks[0].range.offset == 0 and result.entropyBlocks[0].range.length == BlockSize)
    Swag.require(result.entropyBlocks[0].entropy == 0)
    Swag.require(result.entropyBlocks[1].range.offset == BlockSize and result.entropyBlocks[1].range.length == BlockSize)
    Swag.require(result.entropyBlocks[1].entropy > 7.99)
    Swag.require(result.entropyBlocks[2].range.offset == BlockSize * 2 and result.entropyBlocks[2].range.length == 7)

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    let view = hexTestViewer(&host, fileName, 900, 560)
    view.analysisView.publish(&result)
    Swag.require(view.analysisView.entropyList.lineCount() == 3)
    view.analysisView.entropyList.selectLine(1)
    Swag.require(view.grid.caret == BlockSize and view.grid.selectionStart() == BlockSize and view.grid.selectionLength() == BlockSize)
}

// Repeated blocks are reported only after exact byte comparison, and both occurrences navigate
// to their aligned ranges inside a non-zero analysis selection.
#test
{
    const BlockSize = 64 * 1024'u64
    let fileName = Gui.Testing.tempFilePath("scope-hex-repeated-blocks-", ".bin")
    defer discard catch File.delete(fileName)

    let start = 37'u64
    let length = BlockSize * 4 + 19
    var payload: Array'u8
    payload.resize(start + length + 11)
    for index in BlockSize
    {
        let value = cast(u8, index % 251)
        payload[start + index] = value
        payload[start + BlockSize * 2 + index] = value
        payload[start + BlockSize + index] = 0x5A
        payload[start + BlockSize * 3 + index] = value
    }
    payload[start + BlockSize * 3 + 123] ^= 1
    expect File.writeAllBytes(fileName, payload.toSlice())

    var result = Hex.analyzeRange(fileName, Viewers.Hex.AnalysisRange{start, length})
    Swag.require(result.failureReason.isEmpty() and result.scanned == length)
    Swag.require(result.repeatedBlocks.count == 1)
    Swag.require(result.repeatedBlocks[0].firstOffset == start)
    Swag.require(result.repeatedBlocks[0].repeatedOffset == start + BlockSize * 2)
    Swag.require(result.repeatedBlocks[0].length == BlockSize)
    Swag.require(not result.repeatScanTruncated and not result.repeatHintsTruncated)

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    let view = hexTestViewer(&host, fileName, 900, 560)
    view.analysisView.publish(&result)
    Swag.require(view.analysisView.findingsList.virtualCount == view.analysisView.result.strings.count + 2)
    view.analysisView.findingsList.selectLine(0)
    Swag.require(view.grid.selectionStart() == start and view.grid.selectionLength() == BlockSize)
    view.analysisView.findingsList.selectLine(1)
    Swag.require(view.grid.selectionStart() == start + BlockSize * 2 and view.grid.selectionLength() == BlockSize)
}

// A complete analysis computes selectable checksums and copies each with its exact byte range.
#test
{
    let fileName = Testing.tempFilePath("scope-hex-digests-", ".bin")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "xabcx")

    var defaults: Hex.AnalysisAlgorithms
    Swag.require(defaults.crc32 and defaults.md5 and defaults.sha1 and defaults.sha256)
    Swag.require(not defaults.crc64 and not defaults.sha512 and not defaults.blake2s and not defaults.blake2b)

    var all: Hex.AnalysisAlgorithms
    all.crc64 = true
    all.sha512 = true
    all.blake2s = true
    all.blake2b = true
    let result = Hex.analyzeRange(fileName, Viewers.Hex.AnalysisRange{1, 3}, algorithms: all)
    Swag.require(result.hasDigests and result.scanned == 3)
    Swag.require(result.crc32Text() == "352441C2")
    Swag.require(result.sha256Text() == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    Swag.require(result.md5Text() == "900150983cd24fb0d6963f7d28e17f72", result.md5Text())
    Swag.require(result.sha1Text() == "a9993e364706816aba3e25717850c26c9cd0d89d", result.sha1Text())
    Swag.require(result.crc64Text() == "66501A349A0E0855", result.crc64Text())
    Swag.require(result.sha512Text() == "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f", result.sha512Text())
    Swag.require(result.blake2sText() == "508c5e8c327c14e2e1a72ba34eeb452f37458b209ed63a294d999b4c86675982", result.blake2sText())
    Swag.require(result.blake2bText() == "ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d17d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923", result.blake2bText())
    Swag.require(Utf8.contains(result.digestsText(), "MD5 900150983cd24fb0d6963f7d28e17f72\nSHA-1 a9993e36"))
    Swag.require(result.digestCopyText("SHA-256", result.sha256Text()) == "SHA-256 [0x0000000000000001, 0x0000000000000004) ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

    // Leaving two algorithms off leaves them out of the stream and the published copy actions.
    var algorithms = all
    algorithms.sha256 = false
    algorithms.blake2b = false
    let selected = Hex.analyzeRange(fileName, Viewers.Hex.AnalysisRange{1, 3}, algorithms: algorithms)
    Swag.require(selected.hasDigests and selected.algorithms.sha512 and not selected.algorithms.sha256 and not selected.algorithms.blake2b)
    Swag.require(not selected.sha256[0] and not selected.blake2b[0])
    Swag.require(not Utf8.contains(selected.digestsText(), "SHA-256") and not Utf8.contains(selected.digestsText(), "BLAKE2b"))

    var none: Hex.AnalysisAlgorithms
    none.crc32 = false
    none.crc64 = false
    none.md5 = false
    none.sha1 = false
    none.sha256 = false
    none.sha512 = false
    none.blake2s = false
    none.blake2b = false
    let noChecksums = Hex.analyzeRange(fileName, Viewers.Hex.AnalysisRange{1, 3}, algorithms: none)
    Swag.require(noChecksums.hasDigests and noChecksums.digestsText().isEmpty())

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    let view      = hexTestViewer(&host, fileName, 900, 560)
    var published = result
    view.analysisView.publish(&published)
    Swag.require(view.analysisView.digestsLabel.isLocallyVisible())
    Swag.require(view.analysisView.algorithmsButton.toolTip == Hex.texts().ui_AnalysisAlgorithms)

    var results: Lens.Results
    var entries = Viewer.LensEntries.create(&results, "Hexadecimal", host.theme)
    view.describeLens(&entries)
    var copied = 0
    for &entry in results.sections[0]!.entries where entry.title == Hex.texts().ui_AnalysisCopySha256
    {
        entry.run!()
        copied += 1
    }

    Swag.require(copied == 1 and Clipboard.getString() == "SHA-256 [0x0000000000000001, 0x0000000000000004) ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

    // The panel toggles remain open for multiple choices and control the next streamed run.
    host.activateOptionRowWhenShown(Hex.texts().ui_AnalysisSha256)
    host.thenActivateOptionRow(Hex.texts().ui_AnalysisBlake2b)
    host.thenActivateOptionRow(Hex.texts().ui_AnalysisSha512)
    view.analysisView.showAlgorithmOptions()
    Swag.require(host.autoHandled and not view.analysisView.algorithms.sha256 and view.analysisView.algorithms.blake2b and view.analysisView.algorithms.sha512)
    view.analysis.start(fileName, Viewers.Hex.AnalysisRange{1, 3}, algorithms: view.analysisView.algorithms)
    view.analysis.task.wait()
    var selectedResult = view.analysis.finish()
    Swag.require(selectedResult.hasDigests and selectedResult.algorithms.sha512 and not selectedResult.algorithms.sha256 and selectedResult.algorithms.blake2b)
    view.analysisView.publish(&selectedResult)
    results = {}
    entries = Viewer.LensEntries.create(&results, "Hexadecimal", host.theme)
    view.describeLens(&entries)
    var sha512Copied = false
    var sha256Available = false
    for &entry in results.sections[0]!.entries
    {
        if entry.title == Hex.texts().ui_AnalysisCopySha512
        {
            entry.run!()
            sha512Copied = true
        }
        if entry.title == Hex.texts().ui_AnalysisCopySha256 do sha256Available = true
    }

    Swag.require(sha512Copied and not sha256Available)
    Swag.require(Clipboard.getString() == "SHA-512 [0x0000000000000001, 0x0000000000000004) ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")
}

// Caret movement, selection, and the row width the window fits.
#test
{
    let fileName = writeStreamedFile(4096)
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(900, 600)

    let view = hexTestViewer(&host, fileName, 900, 560)
    let grid = view.grid
    let wide = grid.bytesPerRow
    Swag.require(wide >= Hex.MinBytesPerRow and wide % grid.valueSize() == 0)

    host.focus(grid)
    host.keyPress(.Right)
    host.keyPress(.Down)
    Swag.require(grid.caret == 1 + wide)
    Swag.require(not grid.hasSelection() and grid.selectionLength() == 1)

    host.keyPress(.Right, .Shift)
    host.keyPress(.Right, .Shift)
    Swag.require(grid.hasSelection())
    Swag.require(grid.selectionStart() == 1 + wide and grid.selectionLength() == 3)

    host.keyPress(.A, .Control)
    Swag.require(grid.selectionStart() == 0 and grid.selectionLength() == 4096)

    // A narrow window gives up columns rather than the readability of the ones it keeps.
    grid.setBytesPerRow(0, true)
    view.resize(560, 560)
    view.applyLayout()
    grid.refreshLayout()
    Swag.require(grid.bytesPerRow <= wide)
    Swag.require(grid.contentWidth() <= grid.clientRect().width or grid.bytesPerRow == Hex.MinBytesPerRow)

    grid.setBytesPerRow(32, false)
    Swag.require(grid.bytesPerRow == 32 and not grid.autoFitRow)
}

// A point lands on the byte it names, in either column, and on nothing above the first row.
#test
{
    let fileName = writeStreamedFile(4096)
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(900, 600)

    let view = hexTestViewer(&host, fileName, 900, 560)
    let grid = view.grid
    grid.setBytesPerRow(16, false)

    let row    = 3'u64
    let column = 5'u64
    Swag.require(grid.offsetAt(Math.Point{grid.hexCellX(column) + 1, grid.rowTop(row) + 2}) == row * 16 + column)
    Swag.require(grid.offsetAt(Math.Point{grid.textCellX(column) + 1, grid.rowTop(row) + 2}) == row * 16 + column)
    Swag.require(grid.offsetAt({4, 2}) == Swag.U64.Max)
}

// Byte order is an action-bar option and immediately changes multi-byte decoding.
#test
{
    let fileName = Gui.Testing.tempFilePath("viewer-hex-values-", ".bin")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllBytes(fileName, [0x78'u8, 0x56'u8, 0x34'u8, 0x12'u8, 0'u8, 0'u8, 0'u8, 0x80'u8, 0x41'u8])

    var host: Testing.HeadlessHost
    host.setup(900, 600)

    let view = hexTestViewer(&host, fileName, 900, 560)
    Swag.require(not view.bigEndian and not view.grid.bigEndian)

    // The combo changes the values drawn by the grid, not only the distance between bytes.
    view.grid.setGrouping(.Unsigned32)
    Swag.require(view.grid.doc.ensure(0, view.grid.doc.fileSize))
    view.grid.writeValueText(&view.grid.cellText, 0)
    Swag.require(view.grid.scalarAt(0) == 0x12345678)
    Swag.require(Hex.formatScalar(.Unsigned32, view.grid.scalarAt(0)) == "305419896")
    Swag.require(cast(string, view.grid.cellText.toSlice()) == "305419896")

    view.setBigEndian(true)
    Swag.require(view.grid.bigEndian)
    view.grid.writeValueText(&view.grid.cellText, 0)
    Swag.require(cast(string, view.grid.cellText.toSlice()) == "2018915346")
}

// What leaves through the clipboard is what the reader selected, in the form asked for.
#test
{
    if not Clipboard.isFake() do
        return

    let fileName = writeStreamedFile(4096)
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(900, 600)

    let view = hexTestViewer(&host, fileName, 900, 560)

    with let grid = view.grid
    {
        .setBytesPerRow(16, false)
        .moveCaret(0x41, false)
        .moveCaret(0x44, true)
    }

    // A copy replaces whatever the clipboard held, a picture included, so pasting gives the bytes.
    Clipboard.addImage(Image.create(4, 4, .RGB8))
    grid.copySelection(.Bytes)
    Swag.require(Clipboard.getString() == "41 42 43 44" and not Clipboard.hasImage())

    grid.copySelection(.Text)
    Swag.require(Clipboard.getString() == "ABCD", Clipboard.getString())

    grid.copySelection(.Dump)
    let dump = Clipboard.getString()
    Swag.require(Utf8.contains(dump.toSlice(), "00000041  41 42 43 44"))
    Swag.require(Utf8.contains(dump.toSlice(), "ABCD"))

    // Scalar presentation never widens an exact byte selection or its clipboard payload.
    grid.setGrouping(.Unsigned32)
    grid.moveCaret(1, false)
    grid.moveCaret(4, true)
    Swag.require(grid.selectionStart() == 1 and grid.selectionLength() == 4)
    grid.copySelection(.Bytes)
    Swag.require(Clipboard.getString() == "01 02 03 04")

    // A selection wider than the clipboard bound is copied up to it, and never materializes more.
    grid.selectAll()
    grid.copySelection(.Text)
    Swag.require(Clipboard.getString().length == 4096)
    Swag.require(grid.doc.window.count <= Hex.WindowSize)
}

// The context menu reaches the same commands the keyboard does, and the go-to box opens and closes
// from inside the viewer without leaving a modal behind.
#test
{
    let fileName = writeStreamedFile(4096)
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(900, 600)

    let view = hexTestViewer(&host, fileName, 900, 560)
    let grid = view.grid

    host.clickPopupMenuItemWhenShown(Hex.Action.SelectAll)
    grid.showContextMenu({120, 120})
    host.pump()
    Swag.require(grid.selectionStart() == 0 and grid.selectionLength() == 4096)

    view.setRowWidth(3)
    Swag.require(grid.bytesPerRow == 32 and not grid.autoFitRow)

    grid.moveCaret(0x123, false)
    host.clickModalButtonWhenShown(Dialog.BtnCancel)
    grid.promptGoToOffset()
    Swag.require(grid.caret == 0x123)

    // The offset a reader types is read the same way whatever opened the box.
    Swag.require(grid.goToTypedOffset("0x800"))
    Swag.require(grid.caret == 0x800)
    Swag.require(grid.topRow > 0 and grid.topRow < 0x800 / grid.bytesPerRow)
    Swag.require(grid.goToTypedOffset("50%"))
    Swag.require(grid.caret == (grid.doc.fileSize - 1) / 2)
    Swag.require(grid.goToTypedOffset("0d1024"))
    Swag.require(grid.caret == 1024)
    Swag.require(grid.goToTypedOffset("-100"))
    Swag.require(grid.caret == 0x300)
    Swag.require(not grid.goToTypedOffset("nowhere"))
    Swag.require(grid.caret == 0x300)

    view.setBaseAddress(0x400000)
    Swag.require(grid.baseAddress == 0x400000)
    Swag.require(grid.goToTypedOffset("base + 20") and grid.caret == 0x20)

    // The panel's bookmark action updates the same named origin the grid's dialog parses.
    grid.moveCaret(0x50, false)
    var results: Lens.Results
    var entries = Viewer.LensEntries.create(&results, "Hexadecimal", host.theme)
    view.describeLens(&entries)
    var hasBookmarkAction = false
    var hasBaseAction     = false
    for &entry in results.sections[0]!.entries
    {
        if entry.title == Hex.texts().ui_SetBookmark
        {
            hasBookmarkAction = true
            entry.run!()
        }
        if entry.title == Hex.texts().ui_SetBaseAddress do hasBaseAction = true
    }

    Swag.require(hasBookmarkAction and hasBaseAction)
    Swag.require(view.hasBookmark and view.grid.bookmarkOffset == 0x50)
    Swag.require(grid.goToTypedOffset("bookmark + 10") and grid.caret == 0x60)

    let defaultFontSize = grid.fontSize
    host.mouseWheel(grid.surfaceRect().center(), 120, .Control)
    Swag.require(grid.fontSize == defaultFontSize + 1)
    host.focus(grid)
    host.keyPress(.D0, .Control)
    Swag.require(grid.fontSize == defaultFontSize)

    // The size answers Ctrl alone, as the zoom of every other viewer does.
    host.mouseWheel(grid.surfaceRect().center(), 120, .Control | .Shift)
    host.mouseWheel(grid.surfaceRect().center(), 120, .Control | .Alt)
    host.keyPress(.OemPlus, .Control | .Shift)
    host.keyPress(.OemMinus, .Control | .Alt)
    Swag.require(grid.fontSize == defaultFontSize)
    host.keyPress(.OemPlus, .Control)
    host.keyPress(.D0, .Control | .Shift)
    Swag.require(grid.fontSize == defaultFontSize + 1)
    host.keyPress(.D0, .Control)
}

// The reading line spells the caret, inclusive selection, active value, and file position.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-hex-readout-", ".bin")
    defer discard catch File.delete(fileName)
    expect File.writeAllText(fileName, "0123456789")

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    let view = hexTestViewer(&host, fileName, 900, 560)
    let grid = view.grid

    Swag.require(view.details == "0.0% · value 48 · caret 0x0/0")

    grid.moveCaret(9, false)
    Swag.require(view.details == "100.0% · value 57 · caret 0x9/9")

    grid.moveCaret(1, false)
    grid.moveCaret(3, true)
    Swag.require(view.details == "33.3% · value 51 · sel 0x1–0x3 (1–3) · len 3/0x3 · caret 0x3/3")

    view.resize(640, 320)
    view.applyLayout()
    view.grid.refreshLayout()
    Testing.assertContentFits(view)
}

// A search hit is revealed at the offset the host found, and stays marked once the caret moves on.
#test
{
    let fileName = writeSampleFile()
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(900, 600)

    let view     = hexTestViewer(&host, fileName, 900, 560)
    var revealed = view.revealOffset(11, 5)
    Swag.require(revealed)
    Swag.require(view.grid.matchStart == 11 and view.grid.matchLength == 5)
    Swag.require(view.grid.selectionStart() == 11 and view.grid.selectionLength() == 5)
    discard host.render(view)
    Swag.require(view.grid.doc.byteAt(11) == 'h'u8)

    view.grid.moveCaret(0, false)
    Swag.require(view.grid.matchStart == 11 and view.grid.matchLength == 5)
    revealed = view.revealOffset(view.grid.doc.fileSize, 5)
    Swag.require(not revealed)
}

// Multi-gigabyte geometry is synthetic: the test needs the address domain, not a multi-gigabyte
// fixture. Every operation below stays outside painting, so no byte beyond the real fixture is read.
#test
{
    let fileName = writeSampleFile()
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(900, 600)

    let view = hexTestViewer(&host, fileName, 900, 560)

    with let grid = view.grid
    {
        .doc.fileSize = 0x1_0000_1234
        .refreshLayout()
    }

    Swag.require(grid.offsetDigits == 16)
    Swag.require(grid.doc.fileSize > Swag.U32.Max)
    Swag.require(grid.rowCount() == (grid.doc.fileSize + grid.bytesPerRow - 1) / grid.bytesPerRow)
    Swag.require(grid.scroll.scrollSize.y <= Hex.ScrollSpan)
    host.focus(grid)
    host.keyPress(.End, .Control)
    Swag.require(grid.caret == 0x1_0000_1233 and grid.topRow == grid.maxTopRow())

    let dump = Hex.formatDump([0xAB'u8], 0x1_0000_0000, 16, grid.offsetDigits)
    Swag.require(Utf8.contains(dump.toSlice(), "0000000100000000"))
}

// A stream that returns fewer bytes than the size snapshot stops the document with one stable
// explanation instead of exposing stale or zero-filled bytes as file content.
#test
{
    let fileName = writeSampleFile()
    defer discard catch File.delete(fileName)

    var doc: Hex.Document
    defer doc.close()
    let documentOpened = doc.open(fileName)
    Swag.require(documentOpened)
    doc.fileSize += 4096
    Swag.require(not doc.ensure(0, doc.fileSize))
    Swag.require(doc.readFailed and doc.window.isEmpty())
    Swag.require(doc.failureReason == Hex.texts().err_Truncated)
    Swag.require(not doc.ensure(0, 1) and doc.read(0, 1).isEmpty())
}

// A drag beyond the viewport autoscrolls on a timer, and losing focus ends it with no capture or
// timer left to receive a later gesture that belongs to another control.
#test
{
    let fileName = writeStreamedFile(4096)
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(900, 600)

    let view = hexTestViewer(&host, fileName, 900, 560)
    let grid = view.grid
    grid.setBytesPerRow(16, false)
    let point = grid.localToSurface(Math.Point{grid.hexCellX(2) + 1, grid.rowTop(0) + 2})
    host.mouseDown(point)
    Swag.require(grid.selecting and grid.mouseCapture() == grid)

    let outside = grid.localToSurface(Math.Point{grid.textCellX(4), grid.clientRect().bottom() + 20})
    host.moveMouse(outside)
    Swag.require(grid.selectionTimer != null and grid.topRow > 0)
    let firstTop = grid.topRow
    host.fireTimer(grid.selectionTimer)
    Swag.require(grid.topRow > firstTop and grid.selectionLength() > 1)

    with let other = Wnd.create'Wnd(&host.root, "hex.capture.other", {0, 0, 40, 20})
    {
        .focusPolicy = .Tab
        .setFocus()
    }

    Swag.require(not grid.selecting and grid.selectionTimer == null and grid.mouseCapture() == null)
}

// Snapped fixed-width metrics keep the hit geometry and fitted rows coherent at fractional DPI.
#test
{
    let fileName = writeStreamedFile(4096)
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(900, 600, dpiScale: 1.5)

    let view = hexTestViewer(&host, fileName, 900, 560)
    let grid = view.grid
    grid.setBytesPerRow(16, false)
    let row    = 2'u64
    let column = 13'u64
    Swag.require(grid.deviceScale() == 1.5)
    Swag.require(grid.offsetAt(Math.Point{grid.textCellX(column) + 1, grid.rowTop(row) + 2}) == row * 16 + column)
    Swag.require(grid.contentWidth() <= grid.clientRect().width)
    discard host.render(view)
}

// Every painted and interactive hexadecimal string follows the live application language.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-hex-empty-", ".bin")
    defer discard catch File.delete(fileName)
    expect File.writeAllText(fileName, "")

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer discard catch host.app.setLanguage(ReferenceLanguage)

    let view = hexTestViewer(&host, fileName, 900, 560)
    Swag.require(Hex.texts().ui_Empty == "This file is empty.")
    var options: OptionSheet.Page
    view.describeOptions(&options)
    Swag.require(options.rows[1].value == "8-bit" and options.rows[3].value == "Little Endian")
    discard host.render(view)

    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.require(Hex.texts().ui_Empty == "Ce fichier est vide.")
    Swag.require(Utf8.contains(Hex.texts().ui_DetailsCaret, "valeur %"))
    Swag.require(Hex.texts().ui_CopyFormats == "Autres formats de copie")
    var translated: OptionSheet.Page
    view.describeOptions(&translated)
    Swag.require(translated.rows[1].label == "Largeur des valeurs" and translated.rows[1].value == "8 bits")
    Swag.require(translated.rows[3].value == "Little Endian")
    Swag.require(view.optionsButton.toolTip == "Options")
    Swag.require(view.goToButton.toolTip == "Aller au décalage" and not view.goToButton.isEnabled())
    Swag.require(view.copyFormatsButton.toolTip == "Autres formats de copie" and not view.copyFormatsButton.isEnabled())
    Swag.require(Utf8.contains(view.details.toSlice(), "caret 0x0/0") and Utf8.contains(view.details.toSlice(), "0.0%"))
    Swag.require(view.analysisButton.toolTip == "Analyser la sélection, ou le fichier entier lorsqu’aucune sélection n’est active")
    Swag.require(view.analysisView.analyzeButton.toolTip == "Analyser la sélection actuelle, ou le fichier entier lorsqu’aucune sélection n’est active")
    Swag.require(view.analysisView.titleLabel.text() == "Analyse" and view.analysisView.findingsList.header.itemAt(1).name.text == "Type")
    discard host.render(view)
    Testing.assertContentFits(unwrap view.optionsButton.parent)
}

// Go To is a first-class action while a file is open, with its existing Ctrl+G shortcut retained.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-hex-goto-action-", ".bin")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllBytes(fileName, "0123456789")

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    let view = hexTestViewer(&host, fileName, 900, 560)
    Swag.require(view.goToButton.isEnabled())
    Swag.require(view.goToButton.toolTip == Hex.texts().ui_GoTo)
    Swag.require(view.copyBytesButton.toolTip == Hex.texts().ui_CopyBytes and not view.copyBytesButton.isEnabled())
    Swag.require(view.copyFormatsButton.toolTip == Hex.texts().ui_CopyFormats and not view.copyFormatsButton.isEnabled())
    view.grid.moveCaret(1, false)
    view.grid.moveCaret(3, true)
    Swag.require(view.copyBytesButton.isEnabled())
    Swag.require(view.copyFormatsButton.isEnabled())
    view.copyBytesButton.sigPressed.call(view.copyBytesButton)
    Swag.require(Clipboard.getString() == "31 32 33")
}

// Alternate copy formats are reachable from the toolbar and use the same selected bytes as the
// context commands, including the dump's offset, hex, and printable columns.
#test
{
    let fileName = Gui.Testing.tempFilePath("viewer-hex-copy-formats-", ".bin")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllBytes(fileName, "ABCD")

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    let view = hexTestViewer(&host, fileName, 900, 560)
    Swag.require(not view.copyFormatsButton.isEnabled())

    view.grid.moveCaret(0, false)
    view.grid.moveCaret(3, true)
    Swag.require(view.copyFormatsButton.isEnabled())

    view.grid.sendCommandEvent(Hex.Action.CopyText)
    Swag.require(Clipboard.getString() == "ABCD")

    view.grid.sendCommandEvent(Hex.Action.CopyDump)
    let dump = Clipboard.getString()
    Swag.require(dump.contains("41 42 43 44") and dump.contains("ABCD"), dump)
}

// A bounded session-local bookmark is reachable from the lens and returns to its exact byte.
#test
{
    let fileName = Gui.Testing.tempFilePath("viewer-hex-bookmark-", ".bin")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllBytes(fileName, "0123456789")

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    let view = hexTestViewer(&host, fileName, 900, 560)
    view.grid.moveCaret(2, false)

    var setResults: Lens.Results
    var setEntries = Viewer.LensEntries.create(&setResults, "Hexadecimal", host.theme)
    view.describeLens(&setEntries)
    var setBookmark: *Lens.Entry?
    for &entry in setResults.sections[0]!.entries where entry.title == Hex.texts().ui_SetBookmark do
        setBookmark = entry
    Swag.require(setBookmark != null and not setBookmark.disabled)
    setBookmark.run!()
    Swag.require(view.hasBookmark and view.bookmarkOffset == 2)

    view.grid.moveCaret(7, false)
    var goResults: Lens.Results
    var goEntries = Viewer.LensEntries.create(&goResults, "Hexadecimal", host.theme)
    view.describeLens(&goEntries)
    let destination = Format.toString(Hex.texts().ui_GoToBookmark, "0x00000002")
    var goBookmark: *Lens.Entry?
    for &entry in goResults.sections[0]!.entries where entry.title == destination do
        goBookmark = entry
    Swag.require(goBookmark != null and not goBookmark.disabled)
    goBookmark.run!()
    Swag.require(view.grid.caret == 2)
}

// Explicit Go To, search reveals and bookmark activation share a traversable history. A new
// destination after Back discards the old forward branch, and lens shortcuts expose both ends.
#test
{
    let fileName = Gui.Testing.tempFilePath("viewer-hex-history-", ".bin")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllBytes(fileName, "0123456789abcdef")

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    let view = hexTestViewer(&host, fileName, 900, 560)

    Swag.require(view.grid.goToTypedOffset("4") and view.grid.caret == 4)
    Swag.require(view.revealOffset(8, 2) and view.grid.caret == 8)
    view.bookmarkOffset = 12
    view.hasBookmark    = true

    var results: Lens.Results
    var entries = Viewer.LensEntries.create(&results, "Hexadecimal", host.theme)
    view.describeLens(&entries)
    var bookmark: *Lens.Entry?
    for &entry in results.sections[0]!.entries where entry.title == Format.toString(Hex.texts().ui_GoToBookmark, "0x0000000C") do
        bookmark = entry
    Swag.require(bookmark != null and not bookmark.disabled)
    bookmark.run!()
    Swag.require(view.grid.caret == 12)

    var backResults: Lens.Results
    var backEntries = Viewer.LensEntries.create(&backResults, "Hexadecimal", host.theme)
    view.describeLens(&backEntries)
    var back: *Lens.Entry?
    for &entry in backResults.sections[0]!.entries where entry.title == Hex.texts().ui_Back do
        back = entry
    Swag.require(back != null and not back.disabled and back.defaultKey.key == .Left)
    back.run!()
    Swag.require(view.grid.caret == 8)

    var forwardResults: Lens.Results
    var forwardEntries = Viewer.LensEntries.create(&forwardResults, "Hexadecimal", host.theme)
    view.describeLens(&forwardEntries)
    var forward: *Lens.Entry?
    for &entry in forwardResults.sections[0]!.entries where entry.title == Hex.texts().ui_Forward do
        forward = entry
    Swag.require(forward != null and not forward.disabled and forward.defaultKey.key == .Right)
    forward.run!()
    Swag.require(view.grid.caret == 12)

    Swag.require(view.navigateHistory(-1) and view.grid.caret == 8)
    Swag.require(view.grid.goToTypedOffset("2") and view.grid.caret == 2)
    Swag.require(not view.navigateHistory(1))
}

// Navigation history retains only its newest sixty-four destinations on long sessions.
#test
{
    let fileName = writeStreamedFile(256)
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    let view = hexTestViewer(&host, fileName, 900, 560)
    for offset in 1 until 101 do
        Swag.require(view.revealOffset(offset, 1))
    Swag.require(view.navigationHistory.count == 64)
    Swag.require(view.grid.caret == 100)
    var steps = 0
    while steps < 63
    {
        Swag.require(view.navigateHistory(-1))
        steps += 1
    }

    Swag.require(view.grid.caret == 37 and not view.navigateHistory(-1))
}

// The clipboard contract names and enforces its exact bound before a large selection is copied.
#test
{
    if not Clipboard.isFake() do
        return

    let fileName = writeStreamedFile(Hex.CopyLimit + 37)
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(900, 600)

    let view = hexTestViewer(&host, fileName, 900, 560)
    let grid = view.grid
    grid.selectAll()

    let state = grid.sendComputeCommandStateEvent(Hex.Action.CopyText)
    Swag.require(state.name == Format.toString(Hex.texts().ui_CopyTextMax, StrConv.toDisplaySize(Hex.CopyLimit)))
    grid.copySelection(.Text)
    Swag.require(Clipboard.getString().length == Hex.CopyLimit)
    Swag.require(grid.doc.window.count <= Hex.WindowSize)
}

// The lens offers the commands of the context menu, with their shortcuts, and they act on the
// bytes as the menu does.
#test
{
    let fileName = Gui.Testing.tempFilePath("viewer-hex-lens-", ".bin")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllBytes(fileName, "ABCD")

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    let view = hexTestViewer(&host, fileName, 900, 560)

    var results: Lens.Results
    var entries = Viewer.LensEntries.create(&results, "Hexadecimal", host.theme)
    view.describeLens(&entries)

    // Copy actions are unavailable without a range, while navigation and select-all remain usable.
    for title in [Hex.texts().ui_CopyBytes, Hex.texts().ui_CopyText, Hex.texts().ui_CopyDump]
    {
        var found:    bool
        var disabled: bool
        for &entry in results.sections[0]!.entries where entry.title == title
        {
            found    = true
            disabled = entry.disabled
        }

        Swag.require(found and disabled, title)
    }

    for title in [Hex.texts().ui_GoTo, Hex.texts().ui_SelectAll]
    {
        var found:    bool
        var disabled: bool
        for &entry in results.sections[0]!.entries where entry.title == title
        {
            found    = true
            disabled = entry.disabled
        }

        Swag.require(found and not disabled, title)
    }

    func run(results: *Lens.Results, title: string)
    {
        for &entry in results.sections[0]!.entries where entry.title == title
        {
            Swag.require(not entry.disabled)
            entry.run!()
            return
        }

        Swag.require(false, title)
    }

    var goTo = 0
    for &entry in results.sections[0]!.entries where entry.title == Hex.texts().ui_GoTo do
        goTo += entry.detail == Input.formatKeyShortcut(.Control, .G) ? 1 : 0
    Swag.require(goTo == 1)

    run(&results, Hex.texts().ui_SelectAll)
    Swag.require(view.grid.selectionStart() == 0 and view.grid.selectionLength() == 4)

    // Rebuild the lens entries after selection, as the live lens does on refresh.
    var selectedResults: Lens.Results
    var selectedEntries = Viewer.LensEntries.create(&selectedResults, "Hexadecimal", host.theme)
    view.describeLens(&selectedEntries)
    run(&selectedResults, Hex.texts().ui_CopyText)
    Swag.require(Clipboard.getString() == "ABCD")
    run(&selectedResults, Hex.texts().ui_CopyBytes)
    Swag.require(Clipboard.getString() == "41 42 43 44")
    run(&selectedResults, Hex.texts().ui_CopyDump)
    let dump = Clipboard.getString()
    Swag.require(dump.contains("41 42 43 44") and dump.contains("ABCD"), dump)

    // The zoom keys have their rows: one step larger, then back to the size of the theme.
    let size = view.grid.fontSize
    run(&selectedResults, appStrings().cmd_ZoomIn)
    Swag.require(view.grid.fontSize == size + 1)
    run(&selectedResults, appStrings().cmd_ZoomReset)
    Swag.require(view.grid.fontSize == size)
}

// A colon and an offset in the lens, in the grammar of Go to Offset, move the caret there.
#test
{
    let fileName = writeStreamedFile(4096)
    defer discard catch File.delete(fileName)
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, fileName, false)
    for choice, index in window.choices where choice.key == "hex" and index != window.activeChoiceIndex do
        window.selectViewer(cast(u32, index))
    completeQueuedViewerFile(&host, window)
    let view = assume cast(*Hex.Panel, window.currentView)

    window.lens.open(":1f0")
    host.finishAnimations()
    let section = unwrap window.lens.results.sections[0]
    Swag.require(Utf8.contains(section.entries[0].title.toString(), "000001F0"), section.entries[0].title.toString())
    section.entries[0].run!()
    window.lens.close()
    host.finishAnimations()
    Swag.require(view.grid.caret == 0x1F0)
}

// The lens copies the offset of the caret as a hexadecimal address.
#test
{
    Swag.require(Hex.offsetHex(26) == "0x0000001A" and Hex.offsetHex(0x1_0000_0000) == "0x0000000100000000", Hex.offsetHex(26))
}
