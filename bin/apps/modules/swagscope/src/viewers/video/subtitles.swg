#global internal
#global namespace Viewers.Film

using Core, Pixel, Gui, Video, Audio

// Where the subtitles shown come from: none, a track of the container, or a sidecar file.
enum SubtitleSource
{
    Off
    Embedded
    Sidecar
}

// The typeface subtitles are drawn in.
enum SubtitleFont
{
    Sans
    Monospace
}

// The size of subtitle text, one of the steps the subtitle menu offers.
enum SubtitleSize
{
    Small
    Normal
    Large
    VeryLarge
}

// What keeps subtitle text readable over the picture.
enum SubtitleEffect
{
    Outline
    Shadow
    Background
    None
}

// Where subtitles sit over the picture.
enum SubtitlePosition
{
    Bottom
    Center
    Top
}

// The color of subtitle text.
enum SubtitleColor
{
    White
    Yellow
}

// How subtitles look and how far they are shifted in time; shared by every video and saved
// with the window state.
struct SubtitleSettings
{
    font:     SubtitleFont
    size:     SubtitleSize = .Normal
    effect:   SubtitleEffect
    position: SubtitlePosition
    color:    SubtitleColor
    delay:    f64
}

impl SubtitleSettings
{
    // Brings preferences read back from a saved state into the ranges the menus offer.
    mtd sanitize()
    {
        .delay = Math.clamp(.delay, -60, 60)
    }
}

var g_SubtitleSettings: SubtitleSettings

// Replaces `result` with the cues showing at `seconds`, one per line, and returns the next time that text changes.
func subtitlePresentationAt(track: const *Subtitle.Track, seconds: f64, result: *String)->f64
{
    result.clear()
    var nextChange = Swag.F64.Inf
    for index in track.cueCount()
    {
        let start = track.cueStartTime(index)
        let end   = track.cueEndTime(index)
        if start > seconds
        {
            nextChange = Math.min(nextChange, start)
            break
        }

        if end <= seconds do
            continue
        if not result.isEmpty() do
            result.append('\n'rune)
        result[]   += track.cueContent(index)
        nextChange = Math.min(nextChange, end)
    }

    return nextChange
}

private func hasSubtitleExtension(fileName: string)->bool
{
    let extension = String.toLower(Path.extension(fileName))
    switch extension.toString()
    {
    case ".srt", ".vtt", ".ass", ".ssa", ".lrc", ".sub": return true
    default: return false
    }
}

private func addSidecar(fileName: string, result: *Array'*Subtitle.Track) fail
{
    result.add(try Subtitle.Track.loadOwned(fileName))
}

// Finds VLC-style sidecars: `movie.srt`, `movie.en.srt`, and other dotted qualifiers.
func loadSidecars(fileName: string, result: *Array'*Subtitle.Track)
{
    let folder = Path.directoryName(fileName)
    let stem   = Path.fileNameWithoutExtension(fileName)
    if not folder or not stem do
        return

    let files = catch Directory.enumerateFiles(folder) as listError
    if listError != null do
        return

    var candidates: Array'String
    for file in files where not file.isDirectory() and hasSubtitleExtension(file.fullName)
    {
        let candidate = Path.fileNameWithoutExtension(file.fullName)
        if not candidate or not Utf8.startsWith(candidate, stem, .Latin1NoCase) do
            continue
        let exactName = Latin1.compare(candidate, stem, ignoreCase: true) == 0
        if not exactName and (candidate.count <= stem.count or candidate[stem.count] != '.') do
            continue

        candidates.add(file.fullName)
    }

    // Sort paths before loading: subtitle tracks own their decoded cues and are moved only once.
    // The exact stem compares before every dotted qualifier, matching VLC's preferred sidecar
    // while keeping the language variants deterministic.
    candidates.sort(func(a, b) => Utf8.compare(a, b, .Latin1NoCase))
    for candidate in candidates do
        discard catch addSidecar(candidate.toString(), result)
}
