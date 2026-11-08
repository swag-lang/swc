//! Format: ISO Base Media File Format (MP4) interrupted fragmented recording recovery.
//! Supported: Completed H.264 and AAC-LC fragments with an incomplete final box or index.
//! Not supported: Classic sample tables, encrypted tracks, and files changing during recovery.
//! Role: This file rebuilds the final random-access index without copying a long recording.
//
#global namespace Mp4
#global export

using Core, Core.Errors

// Rebuilds the final key-frame index of a stopped fragmented H.264 recording in place.
//
// Every complete video or AAC fragment is retained. An incomplete final fragment, an incomplete
// index, or an existing final index is removed before a new `mfra`/`tfra` is appended. The file
// must be unchanged while recovery runs. Index entries and the new trailer use temporary disk
// files, so memory does not grow with the recording duration. Returns the indexed key-frame count.
// If there is no complete video fragment, the source is left untouched. A write failure after
// truncation can leave the complete media prefix playable but without a final index.
func rebuildFragmentedIndex(fileName: string)->u32 fail
{
    let originalSize = (try File.info(fileName)).size
    let entriesPath  = Path.combine(Env.getSpecialDirectory(.Temp),
                                    Format.toString("swag-mp4-recover-entries-%.tmp", Guid128.random()))
    let trailerPath = Path.combine(Env.getSpecialDirectory(.Temp),
                                   Format.toString("swag-mp4-recover-trailer-%.tmp", Guid128.random()))
    defer
    {
        discard catch File.delete(entriesPath.toString())
        discard catch File.delete(trailerPath.toString())
    }

    var cursor = try FragmentedPacketCursor.open(fileName)
    defer cursor.close()
    var entries = try File.open(entriesPath.toString(), .CreateNew, .ReadWrite, .Zero)
    defer entries.close()
    var point: FragmentedCursorPacket
    var count    = 0'u32
    var hasVideo = false
    while try cursor.nextPacket(&point)
    {
        if not point.isVideo do
            continue
        hasVideo = true
        if not point.info.isKeyFrame do
            continue
        if count >= (Swag.U32.Max - 48) / 20 do
            fail OverflowError{"fragmented MP4 recovery has too many key frames for its final index"}
        let entry = RandomAccessEntry{point.info.decodeTime, point.fragmentOffset, point.sampleNumber}
        try entries.writeAll(Swag.makeSlice(cast(const [*] u8, &entry), #sizeof(RandomAccessEntry)))
        count += 1
    }

    let mediaEnd = cursor.completeMediaByteCount()
    cursor.close()
    if not hasVideo or not count or not mediaEnd do
        fail InvalidFormatError{"fragmented MP4 recovery found no complete video fragment"}

    scope
    {
        var trailer = try ByteSink.createFile(trailerPath.toString())
        try writeFragmentRandomAccessIndex(&trailer, &entries, count)
        try trailer.close()
    }

    entries.close()

    var trailer = try File.open(trailerPath.toString(), .Open, .Read, .Read)
    defer trailer.close()
    var media = try File.open(fileName, .Open, .ReadWrite, .Zero)
    defer media.close()
    if try media.size() != originalSize or mediaEnd > originalSize do
        fail InvalidFormatError{"fragmented MP4 changed during index recovery"}
    try media.resize(mediaEnd)
    try media.seek(.Begin, mediaEnd)
    var bytes: Array'u8
    bytes.resize(64 * 1024)
    while true
    {
        let read = try trailer.read(bytes.toSlice())
        if not read do
            break
        try media.writeAll(bytes.toSlice()[until read])
    }

    try media.flush()
    media.close()
    trailer.close()
    return count
}
