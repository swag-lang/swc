#global internal
#global namespace Viewers.Sound

using Core

// Keeps the origin of a time marker explicit: a tag reader, a sidecar, or this listening session.
enum LandmarkSource
{
    Embedded
    Sidecar
    Session
}

struct Landmark
{
    seconds: f32
    label:   String
    source:  LandmarkSource
}

func landmarkSourceText(source: LandmarkSource)->string
{
    switch source
    {
    case .Sidecar: return texts().ui_Sidecar
    case .Session: return texts().ui_Session
    default:       return texts().ui_Embedded
    }
}

// Reads the standard single-file sidecar beside a recording. The source file remains untouched;
// session markers live only in the panel and are never folded into this list.
func readCueSidecar(fileName: string)->{markers: Array'Landmark, invalid: bool}
{
    var result: #returntype
    let folder = Path.directoryName(fileName) orelse ""
    let stem   = Path.fileNameWithoutExtension(fileName) orelse ""
    if not stem.count do
        return result

    let cuePath = Path.combine(folder, Format.toString("%.cue", stem))
    let info    = catch File.info(cuePath) { return result }
    if info.size > 1 * 1024 * 1024
    {
        result.invalid = true
        return result
    }

    let text          = catch File.readAllText(cuePath) { return result }
    var sourceMatches = true
    var isAudio       = false
    var trackLabel: String
    let mediaName     = Path.fileName(fileName) orelse fileName

    for line in Tokenize.splitLines(text)
    {
        let value = Latin1.trim(line)
        if Utf8.startsWith(value, "FILE ", .Latin1NoCase)
        {
            let cueName = cueFirstValue(value[5 to])
            let cueBase = Path.fileName(cueName) orelse cueName
            sourceMatches = Latin1.compare(cueBase, mediaName, ignoreCase: true) == 0
            isAudio       = false
        }
        elif Utf8.startsWith(value, "TRACK ", .Latin1NoCase)
        {
            let parts = Tokenize.split(value, ' 'u8)
            isAudio = parts.count >= 3 and Latin1.compare(parts[2], "AUDIO", ignoreCase: true) == 0
            let number = parts.count >= 2 ? parts[1] : "?"
            trackLabel = Format.toString(texts().word_Track, number)
        }
        elif Utf8.startsWith(value, "TITLE ", .Latin1NoCase) and isAudio
        {
            trackLabel = cueFirstValue(value[6 to])
        }
        elif Utf8.startsWith(value, "INDEX 01 ", .Latin1NoCase) and isAudio and sourceMatches
        {
            let parts   = Tokenize.split(value, ' 'u8)
            var cueTime = parseCueTime("")
            if parts.count == 3 do
                cueTime = parseCueTime(parts[2])
            if cueTime.valid do
                result.markers.add(Landmark{cast(f32, cueTime.seconds), trackLabel, .Sidecar})
            else do
                result.invalid = true
        }
    }

    return result
}

private func cueFirstValue(value: string)->String
{
    let trimmed = Latin1.trim(value)
    if not trimmed.count do
        return ""
    if trimmed[0] == '"'
    {
        for index in 1 until trimmed.count where trimmed[index] == '"' do
            return String.from(trimmed[1 until index])
        return ""
    }

    for index in trimmed.count where Latin1.isSpace(trimmed[index]) do
        return String.from(trimmed[until index])
    return String.from(trimmed)
}

// CUE INDEX timestamps are minute:second:frame addresses at 75 frames per second.
private func parseCueTime(value: string)->{seconds: f64, valid: bool}
{
    var result: #returntype
    let parts = Tokenize.split(value, ':'u8, removeEmpty: false)
    if parts.count != 3 do
        return result
    let minutes = catch StrConv.toU64(parts[0]) { return result }
    let seconds = catch StrConv.toU64(parts[1]) { return result }
    let frames  = catch StrConv.toU64(parts[2]) { return result }
    if seconds >= 60 or frames >= 75 do
        return result
    result.seconds = cast(f64, minutes * 60 + seconds) + cast(f64, frames) / 75
    result.valid   = true
    return result
}
