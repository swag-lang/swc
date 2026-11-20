#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

private func putU32(bytes: *Array'u8, offset: u64, value: u32)
{
    bytes[offset]     = cast(u8, value >> 24)
    bytes[offset + 1] = cast(u8, value >> 16)
    bytes[offset + 2] = cast(u8, value >> 8)
    bytes[offset + 3] = cast(u8, value)
}

private func putAscii(bytes: *Array'u8, offset: u64, value: string)
{
    for character, index in value do
        bytes[offset + index] = cast(u8, character)
}

// Both image containers preserve their original metadata record, then expose a bounded set of
// namespace-qualified XMP values. The fixture is synthetic and generated beside its source.
#test
{
    for name in ["viewer.xmp.webp", "viewer.xmp.jpg"]
    {
        let image = expect Image.load(scopeTestDataPath(name))
        var packetFound = false
        for metadata in image.metadata where metadata.isTag("XMP") or
            cast(string, metadata.tag.toSlice()) == "http://ns.adobe.com/xap/1.0/"
            do packetFound = true
        Swag.require(packetFound, name)

        var data: MediaInfoData
        data.addImageMetadata(image.metadata.toSlice())
        var title = false
        var creator = false
        var subject = false
        var date = false
        for row in data.rows
        {
            if row.name == "XMP dc:title" and row.value == "Watershed field study" do title = true
            if row.name == "XMP dc:creator" and row.value == "Generated Field Team" do creator = true
            if row.name == "XMP dc:subject" and row.value == "watershed; field notes" do subject = true
            if row.name == "XMP xmp:CreateDate" and row.value == "2026-06-14T10:30:00Z" do date = true
        }
        Swag.require(title and creator and subject and date, name)
    }

    // Keep the original EXIF name/value and the qualified XMP property side by side on conflict.
    var exif: ImageMetadata
    exif.signature = 1
    exif.tag = "Exif"
    exif.value = "\0II\x2a\0\x08\0\0\0\x01\0\x0e\x01\x02\0\x06\0\0\0\x1a\0\0\0\0\0\0\0Legacy"
    var xmp: ImageMetadata
    xmp.tag = "XMP"
    xmp.value = "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"><rdf:Description xmlns:dc=\"http://purl.org/dc/elements/1.1/\" dc:title=\"Current\"/></rdf:RDF></x:xmpmeta>"
    var records: Array'ImageMetadata
    records.add(#move exif)
    records.add(#move xmp)
    var conflict: MediaInfoData
    conflict.addImageMetadata(records.toSlice())
    var exifValue = false
    var xmpValue = false
    for row in conflict.rows
    {
        if row.name == "ImageDescription" and row.value == "Legacy" do exifValue = true
        if row.name == "XMP dc:title" and row.value == "Current" do xmpValue = true
    }
    Swag.require(exifValue and xmpValue)

    var malformedRecord: ImageMetadata
    malformedRecord.tag = "XMP"
    malformedRecord.value = "<x:xmpmeta><rdf:RDF></x:xmpmeta>"
    var malformedRecords: Array'ImageMetadata
    malformedRecords.add(#move malformedRecord)
    var malformed: MediaInfoData
    malformed.addImageMetadata(malformedRecords.toSlice())
    Swag.require(malformed.rows.count == 2 and malformed.rows[1].field == .Unavailable and
                 Utf8.contains(malformed.rows[1].value, "XMP packet cannot be inspected"))

    var oversizedRecord: ImageMetadata
    oversizedRecord.tag = "XMP"
    oversizedRecord.value.resize(1024'u64 * 1024 + 1)
    var oversizedRecords: Array'ImageMetadata
    oversizedRecords.add(#move oversizedRecord)
    var oversized: MediaInfoData
    oversized.addImageMetadata(oversizedRecords.toSlice())
    Swag.require(oversized.rows.count == 2 and oversized.rows[1].field == .Unavailable and
                 Utf8.contains(oversized.rows[1].value, "1 MiB"))
}

// JPEG EXIF is interpreted from the preserved APP1 payload, while decodeMetadata remains optional.
#test
{
    let fileName = Testing.tempFilePath("scope-exif-", ".jpg")
    defer discard catch File.delete(fileName)
    var source = Image.create(8, 8, .RGB8)
    source.fill(Color.fromRgb(255, 255, 255))
    var record: ImageMetadata
    record.signature = 1
    record.tag       = "Exif"
    record.value     = "\0II\x2a\0\x08\0\0\0\x01\0\x0f\x01\x02\0\x06\0\0\0\x1a\0\0\0\0\0\0\0Camera"
    source.metadata.add(record)
    expect source.save(fileName)
    let decoded = expect Image.load(fileName)
    var data: MediaInfoData
    data.addImageMetadata(decoded.metadata.toSlice())
    var found = false
    for row in data.rows where row.name == "Make" and row.value == "Camera" do
        found = true
    Swag.require(found)

    var file       = expect File.MappedFile.open(fileName)
    let region     = expect file.mapAll()
    let pixelsOnly = expect Image.decode(fileName, region.bytes(), {decodeMetadata: false})
    Swag.require(pixelsOnly.isValid() and pixelsOnly.metadata.isEmpty())
    source.metadata[0].value = "\0II"
    var malformed: MediaInfoData
    malformed.addImageMetadata(source.metadata.toSlice())
    Swag.require(malformed.rows.count == 2 and malformed.rows[1].field == .Unavailable)
}

// WebP's ICC chunk keeps its profile bytes intact; the information sheet reads only the bounded
// ICC header and `desc` identity, with no claim that the displayed pixels were converted.
#test
{
    let description = "Swag generated sRGB"
    let descOffset = 144'u64
    let descLength = 12 + description.count + 1
    var profile: Array'u8
    profile.resize(descOffset + descLength)
    putU32(&profile, 0, cast(u32, profile.count))
    putAscii(&profile, 12, "mntr")
    putAscii(&profile, 16, "RGB ")
    putAscii(&profile, 20, "XYZ ")
    putAscii(&profile, 36, "acsp")
    putU32(&profile, 128, 1)
    putAscii(&profile, 132, "desc")
    putU32(&profile, 136, cast(u32, descOffset))
    putU32(&profile, 140, cast(u32, descLength))
    putAscii(&profile, descOffset, "desc")
    putU32(&profile, descOffset + 8, cast(u32, description.count + 1))
    putAscii(&profile, descOffset + 12, description)

    var record: ImageMetadata
    record.tag = "ICC"
    record.value = #move profile
    var records: Array'ImageMetadata
    records.add(#move record)

    var data: MediaInfoData
    data.addImageMetadata(records.toSlice())
    var found = false
    for row in data.rows where row.name == mediaInfoStrings().iccProfile and
        Utf8.contains(row.value, "RGB ") and Utf8.contains(row.value, "XYZ ") and
        Utf8.contains(row.value, "inspection only") and Utf8.contains(row.value, description)
        do found = true
    Swag.require(found)

    // The same identity survives the real decoder path from the generated WebP ICC chunk.
    let webp = expect Image.load(scopeTestDataPath("viewer.icc-profile.webp"))
    var decodedIcc = false
    for metadata in webp.metadata where metadata.isTag("ICC") do
        decodedIcc = true
    Swag.require(decodedIcc)
    var decodedInfo: MediaInfoData
    decodedInfo.addImageMetadata(webp.metadata.toSlice())
    var decodedName = false
    for row in decodedInfo.rows where row.name == mediaInfoStrings().iccProfile and
        Utf8.contains(row.value, "RGB ") and Utf8.contains(row.value, description)
        do decodedName = true
    Swag.require(decodedName)

    // JPEG uses sequenced APP2 records; the generated fixture reaches the same identity through
    // the ordinary decoder, including the marker's sequence/count bytes.
    let jpeg = expect Image.load(scopeTestDataPath("viewer.icc-profile.jpg"))
    var jpegChunks: Array'ImageMetadata
    for metadata in jpeg.metadata where metadata.signature == 2 and metadata.isTag("ICC_PROFILE") do
        jpegChunks.add(metadata)
    Swag.require(jpegChunks.count == 1 and jpegChunks[0].value.count > 2)
    var jpegInfo: MediaInfoData
    jpegInfo.addImageMetadata(jpeg.metadata.toSlice())
    var jpegName = false
    for row in jpegInfo.rows where row.name == mediaInfoStrings().iccProfile and
        Utf8.contains(row.value, "RGB ") and Utf8.contains(row.value, description)
        do jpegName = true
    Swag.require(jpegName)

    // A real generated WebP carries two `mluc` locales, with French first; the reader prefers
    // the English record and keeps the other locale out of the displayed identity.
    let mlucWebp = expect Image.load(scopeTestDataPath("viewer.icc-profile-mluc.webp"))
    var mlucInfo: MediaInfoData
    mlucInfo.addImageMetadata(mlucWebp.metadata.toSlice())
    var selectedEnglish = false
    for row in mlucInfo.rows where row.name == mediaInfoStrings().iccProfile and
        Utf8.contains(row.value, "Swag generated sRGB mluc") and
        not Utf8.contains(row.value, "Profil ICC français")
        do selectedEnglish = true
    Swag.require(selectedEnglish)

    // Exercise out-of-order multi-segment assembly independently of the encoder's one-segment
    // profile, then reject missing and duplicate sequence numbers.
    let jpegProfile = jpegChunks[0].value.toSlice()[2 to]
    let split = jpegProfile.count / 2
    var secondChunk: ImageMetadata
    secondChunk.signature = 2
    secondChunk.tag = "ICC_PROFILE"
    secondChunk.value.add(2)
    secondChunk.value.add(2)
    secondChunk.value.add(jpegProfile[split to])
    var firstChunk: ImageMetadata
    firstChunk.signature = 2
    firstChunk.tag = "ICC_PROFILE"
    firstChunk.value.add(1)
    firstChunk.value.add(2)
    firstChunk.value.add(jpegProfile[until split])
    var splitRecords: Array'ImageMetadata
    splitRecords.add(#move secondChunk)
    splitRecords.add(#move firstChunk)
    var splitInfo: MediaInfoData
    splitInfo.addImageMetadata(splitRecords.toSlice())
    var splitName = false
    for row in splitInfo.rows where row.name == mediaInfoStrings().iccProfile and
        Utf8.contains(row.value, description)
        do splitName = true
    Swag.require(splitName)

    var missingRecords: Array'ImageMetadata
    missingRecords.add(splitRecords[1])
    var missingInfo: MediaInfoData
    missingInfo.addImageMetadata(missingRecords.toSlice())
    Swag.require(missingInfo.rows.count == 2 and missingInfo.rows[1].field == .Unavailable and
                 Utf8.contains(missingInfo.rows[1].value, "missing one or more segments"))

    var duplicateRecords: Array'ImageMetadata
    duplicateRecords.add(splitRecords[1])
    duplicateRecords.add(splitRecords[1])
    var duplicateInfo: MediaInfoData
    duplicateInfo.addImageMetadata(duplicateRecords.toSlice())
    Swag.require(duplicateInfo.rows.count == 2 and duplicateInfo.rows[1].field == .Unavailable and
                 Utf8.contains(duplicateInfo.rows[1].value, "duplicate segment"))

    // Without English, the first valid locale is shown. Construct the same small ICC profile
    // shape with only one French `mluc` record to exercise the fallback choice.
    let fallbackName = "Profil ICC francais"
    let fallbackTextOffset = 172'u64
    let fallbackTextLength = fallbackName.count * 2
    var fallbackProfile: Array'u8
    fallbackProfile.resize(fallbackTextOffset + fallbackTextLength)
    putU32(&fallbackProfile, 0, cast(u32, fallbackProfile.count))
    putAscii(&fallbackProfile, 12, "mntr")
    putAscii(&fallbackProfile, 16, "RGB ")
    putAscii(&fallbackProfile, 20, "XYZ ")
    putAscii(&fallbackProfile, 36, "acsp")
    putU32(&fallbackProfile, 128, 1)
    putAscii(&fallbackProfile, 132, "desc")
    putU32(&fallbackProfile, 136, 144)
    putU32(&fallbackProfile, 140, cast(u32, fallbackProfile.count - 144))
    putAscii(&fallbackProfile, 144, "mluc")
    putU32(&fallbackProfile, 152, 1)
    putU32(&fallbackProfile, 156, 12)
    putAscii(&fallbackProfile, 160, "frFR")
    putU32(&fallbackProfile, 164, cast(u32, fallbackTextLength))
    putU32(&fallbackProfile, 168, cast(u32, fallbackTextOffset - 144))
    for character, index in fallbackName
    {
        fallbackProfile[fallbackTextOffset + 2 * index] = 0
        fallbackProfile[fallbackTextOffset + 2 * index + 1] = cast(u8, character)
    }
    var fallbackRecord: ImageMetadata
    fallbackRecord.tag = "ICC"
    fallbackRecord.value = #move fallbackProfile
    var fallbackRecords: Array'ImageMetadata
    fallbackRecords.add(#move fallbackRecord)
    var fallbackInfo: MediaInfoData
    fallbackInfo.addImageMetadata(fallbackRecords.toSlice())
    var selectedFallback = false
    for row in fallbackInfo.rows where row.name == mediaInfoStrings().iccProfile and
        Utf8.contains(row.value, fallbackName)
        do selectedFallback = true
    Swag.require(selectedFallback)

    var malformedMluc: ImageMetadata
    malformedMluc.tag = "ICC"
    var mlucProfileBytes: Array'u8
    for metadata in mlucWebp.metadata where metadata.isTag("ICC") do
        mlucProfileBytes = metadata.value
    Swag.require(mlucProfileBytes.count > 173)
    malformedMluc.value = #move mlucProfileBytes
    // The first UTF-16 code unit becomes an unpaired high surrogate.
    malformedMluc.value[184] = 0xD8
    malformedMluc.value[185] = 0x00
    var malformedMlucRecords: Array'ImageMetadata
    malformedMlucRecords.add(#move malformedMluc)
    var malformedMlucInfo: MediaInfoData
    malformedMlucInfo.addImageMetadata(malformedMlucRecords.toSlice())
    Swag.require(malformedMlucInfo.rows.count == 2 and malformedMlucInfo.rows[1].field == .Unavailable and
                 Utf8.contains(malformedMlucInfo.rows[1].value, "unpaired high surrogate"))

    var malformedMlucTable: ImageMetadata
    malformedMlucTable.tag = "ICC"
    for metadata in mlucWebp.metadata where metadata.isTag("ICC") do
        malformedMlucTable.value = metadata.value
    putU32(&malformedMlucTable.value, 152, 65) // More locale records than the inspection limit.
    var malformedMlucTableRecords: Array'ImageMetadata
    malformedMlucTableRecords.add(#move malformedMlucTable)
    var malformedMlucTableInfo: MediaInfoData
    malformedMlucTableInfo.addImageMetadata(malformedMlucTableRecords.toSlice())
    Swag.require(malformedMlucTableInfo.rows.count == 2 and malformedMlucTableInfo.rows[1].field == .Unavailable and
                 Utf8.contains(malformedMlucTableInfo.rows[1].value, "record table is invalid"))

    var damaged: ImageMetadata
    damaged.tag = "ICC"
    damaged.value = "invalid profile"
    var damagedRecords: Array'ImageMetadata
    damagedRecords.add(#move damaged)
    var malformed: MediaInfoData
    malformed.addImageMetadata(damagedRecords.toSlice())
    Swag.require(malformed.rows.count == 2 and malformed.rows[1].field == .Unavailable and
                 Utf8.contains(malformed.rows[1].value, "shorter than 128"))

    var badTableBytes: Array'u8
    badTableBytes.resize(132)
    putU32(&badTableBytes, 0, 132)
    putAscii(&badTableBytes, 36, "acsp")
    putU32(&badTableBytes, 128, 1) // The table claims an entry but has no 12-byte entry body.
    var badTableRecord: ImageMetadata
    badTableRecord.tag = "ICC"
    badTableRecord.value = #move badTableBytes
    var badTableRecords: Array'ImageMetadata
    badTableRecords.add(#move badTableRecord)
    var badTable: MediaInfoData
    badTable.addImageMetadata(badTableRecords.toSlice())
    Swag.require(badTable.rows.count == 2 and badTable.rows[1].field == .Unavailable and
                 Utf8.contains(badTable.rows[1].value, "tag table is truncated"))

    var oversizedRecord: ImageMetadata
    oversizedRecord.tag = "ICC"
    oversizedRecord.value.resize(1024'u64 * 1024 + 1)
    var oversizedRecords: Array'ImageMetadata
    oversizedRecords.add(#move oversizedRecord)
    var oversized: MediaInfoData
    oversized.addImageMetadata(oversizedRecords.toSlice())
    Swag.require(oversized.rows.count == 2 and oversized.rows[1].field == .Unavailable and
                 Utf8.contains(oversized.rows[1].value, "1 MiB"))
}
