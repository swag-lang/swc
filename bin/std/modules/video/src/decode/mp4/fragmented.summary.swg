//! Format: ISO Base Media File Format (MP4) fragmented recording summary.
//! Supported: Bounded H.264 and AAC-LC fragments, including a partially written final box.
//! Not supported: Classic sample tables and files changing during the scan.
//! Role: This file reports track durations and recovery boundaries without a packet table.
//
#global namespace Mp4
#global export

using Core

// Counts one fragmented MP4 track on its own integer clock.
//
// An empty track has zero packets and zero start and end times. `endDecodeTime` is the end of its
// last complete packet, so a gap before the first packet does not change its count.
struct FragmentedTrackSummary
{
    public timescale:       u32     // Decode-time ticks per second.
    public packetCount:     u64     // Number of complete compressed packets.
    public firstDecodeTime: u64     // Decode time of the first complete packet.
    public endDecodeTime:   u64     // Decode time just after the last complete packet.
}

// Describes the complete portion of a fragmented H.264 recording.
//
// Audio tracks keep their movie order, including empty tracks. A complete final `mfra` index is
// outside `completeMediaByteCount`. An interrupted tail may be removed and indexed through
// [[Video.Mp4.rebuildFragmentedIndex]].
struct FragmentedRecordingSummary
{
    public width:                  s32                              // Video width in pixels.
    public height:                 s32                              // Video height in pixels.
    public video:                  FragmentedTrackSummary           // Complete video packets.
    public audioTracks:            Array'FragmentedTrackSummary     // Complete AAC-LC packets by track.
    public completeMediaByteCount: u64                              // Byte offset after the last complete media-data box.
    public hasIncompleteTail:      bool                             // Whether an incomplete final box stopped the scan.
}

// Scans fragment headers and returns recording lengths without reading encoded payloads.
//
// Opening reads the initialization movie; the scan keeps at most one 1024-sample fragment and
// four audio track summaries. Its memory use is independent of the recording duration. A file
// with no media packets has zero counts and no complete media boundary. The file must stay
// unchanged during the scan.
func summarizeFragmentedRecording(fileName: string)->FragmentedRecordingSummary fail
{
    var cursor = try FragmentedPacketCursor.open(fileName)
    var result: #returntype
    result.width  = cursor.width()
    result.height = cursor.height()
    result.video.timescale = cursor.timescale()
    result.audioTracks.resize(cursor.audioTrackCount())
    for index in result.audioTracks.count do
        result.audioTracks[index].timescale = (try cursor.audioTrack(index)).sampleRate

    var packet: FragmentedCursorPacket
    while try cursor.nextPacket(&packet)
    {
        if packet.isVideo do
            addFragmentedSummaryPacket(&result.video, packet.info)
        else do
            addFragmentedSummaryPacket(&result.audioTracks[packet.trackIndex], packet.info)
    }

    result.completeMediaByteCount = cursor.completeMediaByteCount()
    result.hasIncompleteTail      = cursor.endedWithIncompleteTail()
    return result
}

private func addFragmentedSummaryPacket(track: *FragmentedTrackSummary, packet: FragmentedPacketInfo)
{
    if not track.packetCount do
        track.firstDecodeTime = packet.decodeTime
    track.packetCount   += 1
    track.endDecodeTime = packet.decodeTime + packet.duration
}
