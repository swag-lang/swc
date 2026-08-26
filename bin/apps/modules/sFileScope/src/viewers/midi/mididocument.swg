#global internal

using Core, Core.Errors

private const MidiFileLimit = 32 * 1024 * 1024'u64
private const MidiNoteLimit = 1_000_000'u64

struct MidiNote
{
    startTick: u64
    endTick:   u64
    track:     u32
    channel:   u8
    key:       u8
    velocity:  u8
}

struct MidiTrack
{
    name:       String
    eventCount: u64
    noteCount:  u64
    lastTick:   u64
}

struct MidiTempo
{
    tick:             u64
    microsPerQuarter: u32
}

struct MidiTimeSignature
{
    tick:        u64
    numerator:   u8
    denominator: u32
}

struct MidiKeySignature
{
    tick:   u64
    sharps: s32
    minor:  bool
}

struct MidiDocument
{
    format:         u16
    division:       u16
    declaredTracks: u16
    tracks:         Array'MidiTrack
    notes:          Array'MidiNote
    tempos:         Array'MidiTempo
    timeSignatures: Array'MidiTimeSignature
    keySignatures:  Array'MidiKeySignature
    durationTicks:  u64
    durationSeconds: f64
    minKey:         u8 = 127
    maxKey:         u8
}

private struct MidiVlq
{
    value: u64
    next:  u64
    valid: bool
}

private func midiHas(bytes: const [..] u8, offset, count: u64)->bool
{
    return offset <= @countof(bytes) and count <= @countof(bytes) - offset
}

private func midiMatches(bytes: const [..] u8, offset: u64, value: string)->bool
{
    if !midiHas(bytes, offset, @countof(value)) do
        return false
    for index in @countof(value) where bytes[offset + index] != value[index] do
        return false
    return true
}

private func midiU16(bytes: const [..] u8, offset: u64)->u16
{
    return (cast(u16) bytes[offset] << 8) | cast(u16) bytes[offset + 1]
}

private func midiU32(bytes: const [..] u8, offset: u64)->u32
{
    return (cast(u32) bytes[offset] << 24) | (cast(u32) bytes[offset + 1] << 16) | (cast(u32) bytes[offset + 2] << 8) | cast(u32) bytes[offset + 3]
}

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
        if !(value & 0x80)
        {
            result.valid = true
            return result
        }
    }
    return result
}

private func midiText(bytes: const [..] u8, at, length: u64)->String
{
    if !length do
        return {}
    var text: Array'u8
    text.reserve(length)
    for index in length
    {
        let value = bytes[at + index]
        text.add(value < 32 or value == 127 ? '.'u8 : value)
    }
    if Utf8.isValid(text.toSlice()) do
        return String.from(@mkstring(text.buffer!, text.count))
    for &value in text where value[] >= 128 do
        value[] = '.'u8
    return String.from(@mkstring(text.buffer!, text.count))
}

private func closeMidiNote(document: *MidiDocument, active: *u64, tick: u64)
{
    if !active[] do
        return
    let note = &document.notes[active[] - 1]
    note.endTick = Math.max(tick, note.startTick + 1)
    active[] = 0
}

private func parseMidiTrack(document: *MidiDocument, bytes: const [..] u8, trackIndex: u32, at, end: u64) fail
{
    var track: MidiTrack
    var active: [16 * 128] u64
    var scan = at
    var tick: u64
    var running: u8

    while scan < end
    {
        let delta = midiVlq(bytes, scan, end)
        if !delta.valid do
            fail InvalidFormatError{Errors.mkString(midiStrings().err_Event)}
        tick += delta.value
        scan  = delta.next
        if scan >= end do
            fail InvalidFormatError{Errors.mkString(midiStrings().err_Event)}

        let first = bytes[scan]
        var status: u8
        if first & 0x80
        {
            status = first
            scan  += 1
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
            if !midiHas(bytes, scan, count) or scan + count > end do
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
                    active[index] = document.notes.count
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
            if !length.valid or length.value > end - length.next do
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
            if !length.valid or length.value > end - length.next do
                fail InvalidFormatError{Errors.mkString(midiStrings().err_Event)}
            scan = length.next + length.value
        }
        else do
            fail InvalidFormatError{Errors.mkString(midiStrings().err_Event)}

        track.eventCount += 1
    }

    track.lastTick = tick
    for channel in 16
    {
        for key in 128
        {
            let index = cast(u64) channel * 128 + key
            closeMidiNote(document, &active[index], tick)
        }
    }

    if track.name.isEmpty() do
        track.name = Format.toString(midiStrings().ui_TrackName, trackIndex + 1)
    document.durationTicks = Math.max(document.durationTicks, tick)
    document.tracks.add(#move track)
}

private func computeMidiDuration(document: *MidiDocument)
{
    if !document.durationTicks do
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
    if !quarter do
        return
    document.tempos.sort(func(a, b) { return a.tick <=> b.tick })
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

func loadMidiDocument(fileName: string)->MidiDocument fail
{
    let info = try File.info(fileName)
    if info.size > MidiFileLimit do
        fail UnsupportedFormatError{Errors.mkString(midiStrings().err_TooLarge)}
    let bytes = try File.readAllBytes(fileName)
    if !midiHas(bytes.toSlice(), 0, 14) or !midiMatches(bytes.toSlice(), 0, "MThd") do
        fail InvalidFormatError{Errors.mkString(midiStrings().err_Header)}

    let headerLength = cast(u64) midiU32(bytes.toSlice(), 4)
    if headerLength < 6 or !midiHas(bytes.toSlice(), 8, headerLength) do
        fail InvalidFormatError{Errors.mkString(midiStrings().err_Header)}

    var result: retval
    result.format         = midiU16(bytes.toSlice(), 8)
    result.declaredTracks = midiU16(bytes.toSlice(), 10)
    result.division       = midiU16(bytes.toSlice(), 12)
    if result.format > 2 or !result.declaredTracks or !result.division do
        fail InvalidFormatError{Errors.mkString(midiStrings().err_Header)}

    var scan = 8 + headerLength
    for trackIndex in result.declaredTracks
    {
        if !midiHas(bytes.toSlice(), scan, 8) or !midiMatches(bytes.toSlice(), scan, "MTrk") do
            fail InvalidFormatError{Errors.mkString(midiStrings().err_Track)}
        let length = cast(u64) midiU32(bytes.toSlice(), scan + 4)
        let body   = scan + 8
        if length > bytes.count - body do
            fail InvalidFormatError{Errors.mkString(midiStrings().err_Track)}
        try parseMidiTrack(&result, bytes.toSlice(), trackIndex, body, body + length)
        scan = body + length
    }

    if result.notes.isEmpty() do
        result.minKey = 48
        result.maxKey = 72
    result.notes.sort(func(a, b) { return a.startTick <=> b.startTick })
    computeMidiDuration(&result)
    return result
}
