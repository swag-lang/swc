#global internal

using Core

// Returns whether the file is a Standard MIDI File.
func isMidiFile(image: *BinaryImage)->bool => image.matches(0, "MThd")

// One variable-length quantity and the first byte after it.
private struct MidiNumber
{
    value: u64
    next:  u64
    valid: bool
}

// Facts gathered while one track's events are walked.
private struct MidiTrackResult
{
    name:     String
    events:   u64
    lastTick: u64
    complete: bool
    ended:    bool
}

// Adds an SMF header and every track event stream.
func reportMidiFile(image: *BinaryImage, report: *BinaryReport)
{
    image.bigEndian = true

    let s            = binStrings()
    let headerLength = cast(u64) image.u32At(4)
    let format       = image.u16At(8)
    let trackCount   = image.u16At(10)
    let division     = image.u16At(12)
    let headerSize   = Math.min(8 + headerLength, image.bytes.count)
    let formatName   = midiFormatName(format)
    let divisionText = midiDivisionText(division)

    report.beginGroup(s.midi_File, formatName, "", offset: 0, length: headerSize, open: true)
    report.field(0, 4, "Chunk type", image.fixedTextAt(0, 4).toString())
    report.sizeField(4, 4, "Length", headerLength)
    report.numField(8, 2, "Format", cast(u64) format, formatName)
    report.numField(10, 2, "Tracks", cast(u64) trackCount)
    report.numField(12, 2, "Division", cast(u64) division, divisionText.toString())
    report.endGroup()

    var scan        = headerSize
    var tracks      = 0'u64
    var totalEvents = 0'u64
    var complete    = headerLength >= 6
    report.beginGroup(s.midi_Tracks, "", "", offset: scan, length: image.bytes.count - scan, open: true)

    while complete and tracks < cast(u64) trackCount
    {
        if !image.has(scan, 8) or !image.matches(scan, "MTrk")
        {
            complete = false
            break
        }

        let length = cast(u64) image.u32At(scan + 4)
        let bodyAt = scan + 8
        if length > image.bytes.count - bodyAt
        {
            complete = false
            break
        }

        let shown = tracks < BinaryListLimit
        var trackRow: u64
        if shown
        {
            let label = Format.toString(s.midi_Track, tracks + 1)
            trackRow = report.rows.count
            report.beginGroup(label.toString(), "", "", offset: bodyAt, length: length)
            report.field(scan, 4, "Chunk type", image.fixedTextAt(scan, 4).toString())
            report.sizeField(scan + 4, 4, "Length", length)
        }

        let track = reportMidiTrack(image, report, bodyAt, bodyAt + length, shown)
        if shown
        {
            let counted = countText(track.events, s.word_Event, s.word_Events)
            report.rows[trackRow].value  = #move counted
            report.rows[trackRow].detail = #move track.name
            report.endGroup()
        }

        totalEvents += track.events
        complete    = track.complete
        tracks      += 1
        scan        = bodyAt + length
    }

    if !complete do
        report.note(s.midi_Malformed)
    report.listCut(Math.min(tracks, BinaryListLimit), cast(u64) trackCount)
    report.endGroup()

    let countedTracks = countText(tracks, s.word_Track, s.word_Tracks)
    let countedEvents = countText(totalEvents, s.word_Event, s.word_Events)
    report.formatName = String.from(s.midi_File)
    report.summary    = Format.toString("% · % · %", s.midi_File, countedTracks, countedEvents)
}

// Adds one track's events and returns its name, extent, and completeness.
private func reportMidiTrack(image: *BinaryImage, report: *BinaryReport, at, end: u64, show: bool)->MidiTrackResult
{
    var result: retval
    result.complete = true
    var scan = at
    var running: u8

    while scan < end
    {
        let delta = midiNumber(image, scan, end)
        if !delta.valid
        {
            result.complete = false
            break
        }

        result.lastTick += delta.value
        let eventAt = delta.next
        if eventAt >= end
        {
            result.complete = false
            break
        }

        let first = image.u8At(eventAt)
        var status: u8
        var dataAt: u64
        if first & 0x80
        {
            status = first
            dataAt = eventAt + 1
        }
        else
        {
            status = running
            dataAt = eventAt
        }

        if status < 0x80
        {
            result.complete = false
            break
        }

        let shown = show and result.events < BinaryListLimit
        if status < 0xF0
        {
            running = status
            let kind  = status >> 4
            let count = kind == 0xC or kind == 0xD ? 1'u64 : 2'u64
            if !image.has(dataAt, count) or dataAt + count > end or image.u8At(dataAt) & 0x80 or (count == 2 and image.u8At(dataAt + 1) & 0x80)
            {
                result.complete = false
                break
            }

            let next = dataAt + count
            if shown do
                reportMidiChannelEvent(image, report, scan, next, status, dataAt, result.lastTick)
            scan = next
        }
        elif status == 0xFF
        {
            running = 0
            if dataAt >= end
            {
                result.complete = false
                break
            }

            let kind   = image.u8At(dataAt)
            let length = midiNumber(image, dataAt + 1, end)
            if !length.valid or length.value > end - length.next
            {
                result.complete = false
                break
            }

            let next = length.next + length.value
            if kind == 0x2F do
                result.ended = true
            if shown do
                reportMidiMetaEvent(image, report, &result, scan, next, kind, length.next, length.value, result.lastTick)
            elif kind == 0x03 and result.name.isEmpty() do
                result.name = image.fixedTextAt(length.next, length.value)
            scan = next
        }
        elif status == 0xF0 or status == 0xF7
        {
            running = 0
            let length = midiNumber(image, dataAt, end)
            if !length.valid or length.value > end - length.next
            {
                result.complete = false
                break
            }

            let next = length.next + length.value
            if shown
            {
                let value  = StrConv.toDisplaySize(length.value)
                let detail = Format.toString(binStrings().midi_At, result.lastTick)
                report.field(scan, next - scan, status == 0xF0 ? "System Exclusive" : "System Exclusive continuation", value.toString(), detail.toString())
            }

            scan = next
        }
        else
        {
            result.complete = false
            break
        }

        result.events += 1
    }

    if show
    {
        report.listCut(Math.min(result.events, BinaryListLimit), result.events)
        if result.complete and !result.ended do
            report.note(binStrings().midi_NoEnd)
    }

    return result
}

// Adds one channel event, preserving its MIDI name and the channel it addresses.
private func reportMidiChannelEvent(image: *BinaryImage, report: *BinaryReport, at, next: u64, status: u8, dataAt, tick: u64)
{
    let kind    = status >> 4
    let channel = cast(u64) (status & 0x0F) + 1
    let first   = cast(u64) image.u8At(dataAt)
    let second  = next - dataAt == 2 ? cast(u64) image.u8At(dataAt + 1) : 0
    let detail  = Format.toString(binStrings().midi_AtChannel, tick, channel)

    var value: String
    switch kind
    {
    case 0x8, 0x9, 0xA: value = Format.toString("% · velocity %", first, second)
    case 0xB:           value = Format.toString("% = %", first, second)
    case 0xC:           value = Format.toString("%", first)
    case 0xD:           value = Format.toString("%", first)
    case 0xE:           value = Format.toString("%", first | second << 7)
    }

    report.field(at, next - at, midiChannelEventName(kind), value.toString(), detail.toString())
}

// Adds one meta event, decoding the musical metadata readers look for first.
private func reportMidiMetaEvent(image: *BinaryImage, report: *BinaryReport, track: *MidiTrackResult, at, next: u64, kind: u8, bodyAt, length, tick: u64)
{
    let label  = midiMetaEventName(kind)
    let detail = Format.toString(binStrings().midi_At, tick)
    var value: String

    switch kind
    {
    case 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07:
        value = image.fixedTextAt(bodyAt, length)
        if kind == 0x03 and track.name.isEmpty() do
            track.name = String.from(value.toString())

    case 0x20, 0x21:
        if length do
            value = Format.toString("%", image.u8At(bodyAt))

    case 0x51:
        if length == 3
        {
            let micros = image.scalarAt(bodyAt, 3)
            if micros do
                value = Format.toString("% BPM", 60_000_000'u64 / micros)
        }

    case 0x54:
        if length == 5 do
            value = Format.toString("%:%:%:%.%", image.u8At(bodyAt), image.u8At(bodyAt + 1), image.u8At(bodyAt + 2), image.u8At(bodyAt + 3), image.u8At(bodyAt + 4))

    case 0x58:
        if length == 4
        {
            let power = image.u8At(bodyAt + 1)
            if power < 64
            {
                let denominator = 1'u64 << power
                value = Format.toString("%/%", image.u8At(bodyAt), denominator)
            }
        }

    case 0x59:
        if length == 2
        {
            let encoded   = cast(s32) image.u8At(bodyAt)
            let signature = midiKeyName(encoded >= 128 ? encoded - 256 : encoded)
            let mode      = image.u8At(bodyAt + 1) ? binStrings().midi_Minor : binStrings().midi_Major
            value = Format.toString("% %", signature, mode)
        }

    default:
        if length
        {
            let size = StrConv.toDisplaySize(length)
            value = #move size
        }
    }

    report.field(at, next - at, label, value.toString(), detail.toString())
}

// Reads the big-endian, seven-bits-per-byte integer used for delta times and payload lengths.
private func midiNumber(image: *BinaryImage, at, end: u64)->MidiNumber
{
    var result: retval
    result.next = at

    for 4
    {
        if result.next >= end do
            return result
        let value = image.u8At(result.next)
        result.next  += 1
        result.value = (result.value << 7) | cast(u64) (value & 0x7F)
        if !(value & 0x80)
        {
            result.valid = true
            return result
        }
    }

    return result
}

private func midiFormatName(value: u16)->string
{
    switch value
    {
    case 0: return "format 0"
    case 1: return "format 1"
    case 2: return "format 2"
    }

    return "?"
}

private func midiDivisionText(value: u16)->String
{
    if !(value & 0x8000) do
        return Format.toString(binStrings().midi_TicksQuarter, value)

    let frames = 256'u64 - cast(u64) (value >> 8)
    let ticks  = cast(u64) (value & 0xFF)
    return Format.toString(binStrings().midi_Smpte, frames, ticks)
}

private func midiChannelEventName(kind: u8)->string
{
    switch kind
    {
    case 0x8: return "Note Off"
    case 0x9: return "Note On"
    case 0xA: return "Polyphonic Key Pressure"
    case 0xB: return "Control Change"
    case 0xC: return "Program Change"
    case 0xD: return "Channel Pressure"
    case 0xE: return "Pitch Bend Change"
    }

    return "?"
}

private func midiMetaEventName(kind: u8)->string
{
    switch kind
    {
    case 0x00: return "Sequence Number"
    case 0x01: return "Text Event"
    case 0x02: return "Copyright Notice"
    case 0x03: return "Sequence/Track Name"
    case 0x04: return "Instrument Name"
    case 0x05: return "Lyric"
    case 0x06: return "Marker"
    case 0x07: return "Cue Point"
    case 0x20: return "MIDI Channel Prefix"
    case 0x21: return "MIDI Port"
    case 0x2F: return "End of Track"
    case 0x51: return "Set Tempo"
    case 0x54: return "SMPTE Offset"
    case 0x58: return "Time Signature"
    case 0x59: return "Key Signature"
    case 0x7F: return "Sequencer-Specific Meta-Event"
    }

    return "Meta-Event"
}

private func midiKeyName(value: s32)->string
{
    switch value
    {
    case -7: return "C-flat"
    case -6: return "G-flat"
    case -5: return "D-flat"
    case -4: return "A-flat"
    case -3: return "E-flat"
    case -2: return "B-flat"
    case -1: return "F"
    case 0:  return "C"
    case 1:  return "G"
    case 2:  return "D"
    case 3:  return "A"
    case 4:  return "E"
    case 5:  return "B"
    case 6:  return "F-sharp"
    case 7:  return "C-sharp"
    }

    return "?"
}
