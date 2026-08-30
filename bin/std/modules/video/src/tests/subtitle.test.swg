#global if #command == Swag.CompilerCommand.Test

using Core, Video

private func subtitleFixturePath()->String
{
    return Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/subtitle-sample.srt")
}

// SubRip keeps explicit lines, strips presentation markup, and represents overlapping cues.
#test
{
    let track = expect Subtitle.Track.load(subtitleFixturePath().toString())
    Swag.assert(track.format == .SubRip and track.cues.count == 3)
    Swag.assert(track.cueContent(0) == "First caption.")
    Swag.assert(Math.isEqualEpsilon(track.cues[2].startSeconds, 62.25, 0.0001))

    let overlap = track.presentationAt(1.75)
    Swag.assert(overlap.text == "First caption.\nOverlapping caption.")
    Swag.assert(Math.isEqualEpsilon(overlap.nextChangeSeconds, 2, 0.0001))
    Swag.assert(track.presentationAt(4).text.isEmpty())
}

// Module-owned tracks expose their text through caller-owned output storage.
#test
{
    let track = expect Subtitle.Track.loadOwned(subtitleFixturePath().toString())
    Swag.assert(track != null)
    defer Subtitle.Track.destroy(track!)
    var text: String
    track!.copyCueContent(0, &text)
    Swag.assert(text == "First caption.")
}

// WebVTT accepts cue identifiers and settings while exposing only readable text.
#test
{
    const Source = "WEBVTT\n\nintro\n00:00.100 --> 00:02.500 align:start position:10%\n<v Narrator>Hello &amp; <b>welcome</b></v>\n"
    let track = expect Subtitle.Track.decode("sample.vtt", Source)
    Swag.assert(track.format == .WebVtt and track.cues.count == 1)
    Swag.assert(track.cueContent(0) == "Hello & welcome")
}

// ASS reads the declared event-field order and removes override commands without losing lines.
#test
{
    const Source = "[Script Info]\nTitle: Sample\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:01.00,0:00:03.50,Default,,0,0,0,,{\\i1}Hello{\\i0}\\Nworld\n"
    let track = expect Subtitle.Track.decode("sample.ass", Source)
    Swag.assert(track.format == .SubStationAlpha and track.cues.count == 1)
    Swag.assert(track.cueContent(0) == "Hello\nworld")
}

// LRC closes an open lyric at the next timestamp and MicroDVD honors its declared frame rate.
#test
{
    let lyric = expect Subtitle.Track.decode("sample.lrc", "[00:01.00]One\n[00:03.50]Two\n")
    Swag.assert(lyric.cues.count == 2)
    Swag.assert(Math.isEqualEpsilon(lyric.cues[0].endSeconds, 3.5, 0.0001))

    let micro = expect Subtitle.Track.decode("sample.sub", "{1}{1}20.0\n{20}{60}First|second\n")
    Swag.assert(micro.cues.count == 1 and micro.cueContent(0) == "First\nsecond")
    Swag.assert(Math.isEqualEpsilon(micro.cues[0].startSeconds, 1, 0.0001))
    Swag.assert(Math.isEqualEpsilon(micro.cues[0].endSeconds, 3, 0.0001))
}
