#global internal

using Core, Core.Errors

private const MidiFileLimit = 32 * 1024 * 1024'u64
private const MidiNoteLimit = 1_000_000'u64

// One sounding note, from its note-on tick to its note-off tick.
struct MidiNote
{
    startTick: u64
    endTick:   u64
    track:     u32
    channel:   u8
    key:       u8
    velocity:  u8
}

// Name and event counts of one track chunk.
struct MidiTrack
{
    name:       String
    eventCount: u64
    noteCount:  u64
    lastTick:   u64
}

// A tempo change, in microseconds per quarter note from `tick` on.
struct MidiTempo
{
    tick: u64
    microsPerQuarter: u32
}

// A meter change, such as 3/4, from `tick` on.
struct MidiTimeSignature
{
    tick:        u64
    numerator:   u8
    denominator: u32
}

// A key change from `tick` on: sharps are positive and flats negative.
struct MidiKeySignature
{
    tick:   u64
    sharps: s32
    minor:  bool
}

// A Standard MIDI File reduced to what the piano roll shows: its notes, tracks, and timing.
struct MidiDocument
{
    format:          u16
    division:        u16
    declaredTracks:  u16
    tracks:          Array'MidiTrack
    notes:           Array'MidiNote
    tempos:          Array'MidiTempo
    timeSignatures:  Array'MidiTimeSignature
    keySignatures:   Array'MidiKeySignature
    durationTicks:   u64
    durationSeconds: f64
    minKey:          u8 = 127
    maxKey:          u8
}

// Names the major key of a signature with `sharps` sharps, or flats when negative.
private func midiKeySignatureName(sharps: s32)->string
{
    switch sharps
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

impl MidiDocument
{
    // Returns the first time signature as numerator/denominator, or 4/4 when the file declares none.
    mtd const meterText()->String
    {
        if .timeSignatures.isEmpty() do
            return String.from("4/4")
        let meter = &.timeSignatures[0]
        return Format.toString("%/%", meter.numerator, meter.denominator)
    }

    // Returns the first key signature in words, or C major when the file declares none.
    mtd const keyText()->String
    {
        if .keySignatures.isEmpty() do
            return Format.toString("C %", midiStrings().ui_Major)
        let key = &.keySignatures[0]
        return Format.toString("% %", midiKeySignatureName(key.sharps), key.minor ? midiStrings().ui_Minor : midiStrings().ui_Major)
    }

    // Returns the first tempo in beats per minute, or 120 when the file declares none.
    mtd const bpm()->u32
    {
        if .tempos.isEmpty() or not .tempos[0].microsPerQuarter do
            return 120
        return 60_000_000'u32 / .tempos[0].microsPerQuarter
    }
}

private struct MidiVlq
{
    value: u64
    next:  u64
    valid: bool
}

private func midiHas(bytes: const [..] u8, offset, count: u64)->bool => offset <= bytes.count and count <= bytes.count - offset

private func midiMatches(bytes: const [..] u8, offset: u64, value: string)->bool => midiHas(bytes, offset, value.count) and Slice.equals(bytes[offset until offset + value.count], cast(const [..] u8) value)

private func midiU16(bytes: const [..] u8, offset: u64)->u16 => (cast(u16) bytes[offset] << 8) | cast(u16) bytes[offset + 1]

private func midiU32(bytes: const [..] u8, offset: u64)->u32 => (cast(u32) bytes[offset] << 24) | (cast(u32) bytes[offset + 1] << 16) | (cast(u32) bytes[offset + 2] << 8) | cast(u32) bytes[offset + 3]

private func midiVlq(bytes: const [..] u8, at, end: u64)->MidiVlq
{
    var result: retval
    result.next = at
    for 4
    {
        if result.next >= end do
            return result
        let value = bytes[result.next]
        result.next  += 1
        result.value = (result.value << 7) | cast(u64) (value & 0x7F)
        if not (value & 0x80)
        {
            result.valid = true
            return result
        }
    }

    return result
}

private func midiText(bytes: const [..] u8, at, length: u64)->String
{
    if not length do
        return {}
    var text: Array'u8
    text.reserve(length)
    for index in length
    {
        let value = bytes[at + index]
        text.add(value < 32 or value == 127 ? '.'u8 : value)
    }

    if Utf8.isValid(text.toSlice()) do
        return String.from(cast(string) text.toSlice())
    for &value in text where value[] >= 128 do
        value[] = '.'u8
    return String.from(cast(string) text.toSlice())
}

// Ends the note an `active` slot holds, as a one-based index into the notes, and frees the slot.
private func closeMidiNote(document: *MidiDocument, active: *u64, tick: u64)
{
    if not active[] do
        return
    let note = &document.notes[active[] - 1]
    note.endTick = Math.max(tick, note.startTick + 1)
    active[]     = 0
}

private func parseMidiTrack(document: *MidiDocument, bytes: const [..] u8, trackIndex: u32, at, end: u64) fail
{
    var track:   MidiTrack
    var active:  [16 * 128] u64
    var scan = at
    var tick:    u64
    var running: u8

    while scan < end
    {
        let delta = midiVlq(bytes, scan, end)
        if not delta.valid do
            fail InvalidFormatError{Errors.mkString(midiStrings().err_Event)}
        tick += delta.value
        scan = delta.next
        if scan >= end do
            fail InvalidFormatError{Errors.mkString(midiStrings().err_Event)}

        let first = bytes[scan]
        var status: u8
        if first & 0x80
        {
            status = first
            scan   += 1
        }
        else do
            status = running

        if status < 0x80 do
            fail InvalidFormatError{Errors.mkString(midiStrings().err_Event)}

        if status < 0xF0
        {
            running = status
            let kind  = status >> 4
            let count = kind == 0xC or kind == 0xD ? 1'u64 : 2'u64
            if not midiHas(bytes, scan, count) or scan + count > end do
                fail InvalidFormatError{Errors.mkString(midiStrings().err_Event)}
            let data1 = bytes[scan]
            let data2 = count == 2 ? bytes[scan + 1] : 0
            if data1 & 0x80 or data2 & 0x80 do
                fail InvalidFormatError{Errors.mkString(midiStrings().err_Event)}
            scan += count

            if kind == 0x8 or kind == 0x9
            {
                let channel = status & 0x0F
                let key     = data1
                let index   = cast(u64) channel * 128 + key
                if kind == 0x8 or data2 == 0 do
                    closeMidiNote(document, &active[index], tick)
                else
                {
                    closeMidiNote(document, &active[index], tick)
                    if document.notes.count >= MidiNoteLimit do
                        fail UnsupportedFormatError{Errors.mkString(midiStrings().err_TooManyNotes)}
                    document.notes.add({tick, Swag.U64.Max, trackIndex, channel, key, data2})
                    active[index]   = document.notes.count
                    track.noteCount += 1
                    document.minKey = Math.min(document.minKey, key)
                    document.maxKey = Math.max(document.maxKey, key)
                }
            }
        }
        elif status == 0xFF
        {
            running = 0
            if scan >= end do
                fail InvalidFormatError{Errors.mkString(midiStrings().err_Event)}
            let kind   = bytes[scan]
            let length = midiVlq(bytes, scan + 1, end)
            if not length.valid or length.value > end - length.next do
                fail InvalidFormatError{Errors.mkString(midiStrings().err_Event)}
            let body = length.next

            switch kind
            {
            case 0x03 where track.name.isEmpty():
                track.name = midiText(bytes, body, length.value)

            case 0x51 where length.value == 3:
                let micros = (cast(u32) bytes[body] << 16) | (cast(u32) bytes[body + 1] << 8) | cast(u32) bytes[body + 2]
                if micros do
                    document.tempos.add({tick, micros})

            case 0x58 where length.value == 4 and bytes[body + 1] < 16:
                document.timeSignatures.add({tick, bytes[body], 1'u32 << bytes[body + 1]})

            case 0x59 where length.value == 2:
                let encoded = cast(s32) bytes[body]
                document.keySignatures.add({tick, encoded >= 128 ? encoded - 256 : encoded, bytes[body + 1] != 0})
            }

            scan = body + length.value
        }
        elif status == 0xF0 or status == 0xF7
        {
            running = 0
            let length = midiVlq(bytes, scan, end)
            if not length.valid or length.value > end - length.next do
                fail InvalidFormatError{Errors.mkString(midiStrings().err_Event)}
            scan = length.next + length.value
        }
        else do
            fail InvalidFormatError{Errors.mkString(midiStrings().err_Event)}

        track.eventCount += 1
    }

    track.lastTick = tick
    for &slot in active do
        closeMidiNote(document, slot, tick)

    if track.name.isEmpty() do
        track.name = Format.toString(midiStrings().ui_TrackName, trackIndex + 1)
    document.durationTicks = Math.max(document.durationTicks, tick)
    document.tracks.add(#move track)
}

private func computeMidiDuration(document: *MidiDocument)
{
    if not document.durationTicks do
        return

    if document.division & 0x8000
    {
        let encoded = cast(u8) (document.division >> 8)
        let frames  = encoded == 0xE3 ? 29.97 : cast(f64) (256'u32 - encoded)
        let ticks   = cast(f64) (document.division & 0xFF)
        if frames > 0 and ticks > 0 do
            document.durationSeconds = cast(f64) document.durationTicks / (frames * ticks)
        return
    }

    let quarter = cast(u64) document.division
    if not quarter do
        return
    document.tempos.sort(func(a, b) => a.tick <=> b.tick)
    var previous: u64
    var micros = 500_000'u64
    for tempo in document.tempos where tempo.tick <= document.durationTicks
    {
        document.durationSeconds += cast(f64) (tempo.tick - previous) * cast(f64) micros / (cast(f64) quarter * 1_000_000)
        previous = tempo.tick
        micros   = tempo.microsPerQuarter
    }

    document.durationSeconds += cast(f64) (document.durationTicks - previous) * cast(f64) micros / (cast(f64) quarter * 1_000_000)
}

// Loads and parses a Standard MIDI File.
//
// Fails when the file cannot be read, is over 32 MiB, has a malformed header, track chain, or
// event, or holds more notes than the viewer can display safely.
func loadMidiDocument(fileName: string)->MidiDocument fail
{
    let info = try File.info(fileName)
    if info.size > MidiFileLimit do
        fail UnsupportedFormatError{Errors.mkString(midiStrings().err_TooLarge)}
    let content = try File.readAllBytes(fileName)
    let bytes   = content.toSlice()
    if not midiHas(bytes, 0, 14) or not midiMatches(bytes, 0, "MThd") do
        fail InvalidFormatError{Errors.mkString(midiStrings().err_Header)}

    let headerLength = cast(u64) midiU32(bytes, 4)
    if headerLength < 6 or not midiHas(bytes, 8, headerLength) do
        fail InvalidFormatError{Errors.mkString(midiStrings().err_Header)}

    with var result: retval
    {
        .format         = midiU16(bytes, 8)
        .declaredTracks = midiU16(bytes, 10)
        .division       = midiU16(bytes, 12)
    }

    if result.format > 2 or not result.declaredTracks or not result.division do
        fail InvalidFormatError{Errors.mkString(midiStrings().err_Header)}

    var scan = 8 + headerLength
    for trackIndex in result.declaredTracks
    {
        if not midiHas(bytes, scan, 8) or not midiMatches(bytes, scan, "MTrk") do
            fail InvalidFormatError{Errors.mkString(midiStrings().err_Track)}
        let length = cast(u64) midiU32(bytes, scan + 4)
        let body   = scan + 8
        if length > bytes.count - body do
            fail InvalidFormatError{Errors.mkString(midiStrings().err_Track)}
        try parseMidiTrack(&result, bytes, trackIndex, body, body + length)
        scan = body + length
    }

    if result.notes.isEmpty()
    {
        result.minKey = 48
        result.maxKey = 72
    }

    result.notes.sort(func(a, b) => a.startTick <=> b.startTick)
    computeMidiDuration(&result)
    return result
}
