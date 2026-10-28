#global internal
#global namespace Viewers.Film

using Core, Gui, Audio

// Visible strings of the video viewer.
struct Texts
{
    ui_TipPlay:                string = "Play"                                                    // Tooltip while playback is stopped or paused.
    ui_TipPause:               string = "Pause"                                                   // Tooltip while playback is running.
    ui_TipStop:                string = "Stop"                                                    // Tooltip of the stop button.
    ui_TipBackward:            string = "Back 10 Seconds (Left) · Ctrl+Left: previous frame"      // Tooltip of the backward seek button.
    ui_TipForward:             string = "Forward 10 Seconds (Right) · Ctrl+Right: next frame"     // Tooltip of the forward seek button.
    ui_TipSeek:                string = "Seek"                                                    // Tooltip of the playback timeline.
    ui_TipMute:                string = "Mute or Unmute (M)"                                      // Tooltip of the mute switch.
    ui_TipVolume:              string = "Volume"                                                  // Tooltip of the volume slider.
    ui_TipFullScreen:          string = "Full Screen (F)"                                         // Tooltip of the full-screen button.
    ui_SubtitleChip:           string = "Subtitles %"                                             // Chip of the subtitles in force: their language, or off.
    ui_OptionSpeed:            string = "Speed"                                                   // Option choosing the playback rate.
    ui_OptionAudio:            string = "Audio track"                                             // Option choosing the sound track.
    ui_OptionSubtitles:        string = "Subtitles"                                               // Option choosing and styling the subtitles.
    ui_PlayerSpeedNormal:      string = "Normal"                                                  // The source playback rate.
    ui_AudioTrackNumber:       string = "Audio %"                                                 // Fallback name for an unnamed sound track.
    ui_AudioTrackLang:         string = "<p2> (%)</p>"                                            // A sound-track language suffix.
    ui_AudioDetails:           string = "% · % ch · %{f1} kHz"                                    // Encoding, channel count, and sample rate in the host summary.
    ui_SubtitleOff:            string = "Off"                                                     // Disables subtitle presentation.
    ui_SubtitleTrackNumber:    string = "Subtitle %"                                              // Fallback name for an unnamed subtitle track.
    ui_SubtitleTrackLang:      string = "<p2> (%)</p>"                                            // A subtitle-track language suffix.
    ui_SubtitleEmbedded:       string = "Embedded"                                                // Where a subtitle track comes from: the film itself.
    ui_SubtitleSidecar:        string = "External file"                                           // Where a subtitle track comes from: a file beside the film.
    ui_SubtitleTrack:          string = "Track"                                                   // Heading of the subtitle tracks.
    ui_SubtitleAppearance:     string = "Appearance"                                              // Heading of the subtitle style options.
    ui_SubtitleFont:           string = "Font"                                                    // Subtitle font option.
    ui_SubtitleFontSans:       string = "System sans serif"                                       // Proportional subtitle font.
    ui_SubtitleFontMono:       string = "Monospace"                                               // Fixed-width subtitle font.
    ui_SubtitleSize:           string = "Text size"                                               // Subtitle size submenu.
    ui_SubtitleSizeSmall:      string = "Small"
    ui_SubtitleSizeNormal:     string = "Normal"
    ui_SubtitleSizeLarge:      string = "Large"
    ui_SubtitleSizeVeryLarge:  string = "Very large"
    ui_SubtitleEffect:         string = "Readability"     // Subtitle readability-effect submenu.
    ui_SubtitleEffectOutline:  string = "Outline"
    ui_SubtitleEffectShadow:   string = "Shadow"
    ui_SubtitleEffectBackdrop: string = "Background"
    ui_SubtitleEffectNone:     string = "None"
    ui_SubtitlePosition:       string = "Position"
    ui_SubtitlePositionBottom: string = "Bottom"
    ui_SubtitlePositionCenter: string = "Center"
    ui_SubtitlePositionTop:    string = "Top"
    ui_SubtitleColor:          string = "Text color"
    ui_SubtitleColorWhite:     string = "White"
    ui_SubtitleColorYellow:    string = "Yellow"
    ui_SubtitleDelay:          string = "Synchronization"
    ui_SubtitleDelayReset:     string = "Reset Delay"
    word_Frame:                string = "frame"      // One video frame.
    word_Frames:               string = "frames"     // Several video frames.

    // Summary the host shows beside the file size: geometry, frame count, frame rate, and duration.
    ui_Details:      string = "% × % px · % · %{f2} fps · % · Swag CPU"
    err_AudioTrack:  string = "video audio-track index exceeds the track count"     // Diagnostics of a video that cannot play.
    err_AudioEngine: string = "cannot create the audio engine for video playback"
}

private const FrenchStringsName = "lang/fr/scope.video.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.video.tweak")

private var g_Texts: Texts

// Returns the visible strings of the video viewer in the active language.
func texts()->const *Texts => &g_Texts

// Returns `count` followed by the frame noun in the form that count calls for.
func frameCountText(count: u64)->String => Format.toString("% %", count, count == 1 ? texts().word_Frame : texts().word_Frames)

// Names one sound track, with its language when the file declares one.
func audioTrackName(index: u32, sound: const *Audio.SoundFile)->String
{
    let strings = texts()
    var result: #returntype = sound.displayName().count ? String.from(sound.displayName()) : Format.toString(strings.ui_AudioTrackNumber, index + 1)
    if sound.language().count and sound.language() != "und" do
        result += Format.toString(strings.ui_AudioTrackLang, sound.language())
    return result
}

// Returns the established technical name of an audio payload encoding.
func audioEncodingText(encoding: Audio.SoundFileEncoding)->string
{
    switch encoding
    {
    case .Pcm8:     return "PCM 8-bit"
    case .Pcm16:    return "PCM 16-bit"
    case .Pcm24:    return "PCM 24-bit"
    case .Pcm32:    return "PCM 32-bit"
    case .Float32:  return "PCM float32"
    case .AacLc:    return "AAC-LC"
    case .Ac3:      return "AC-3"
    case .Eac3:     return "E-AC-3"
    case .Dts:      return "DTS"
    case .Flac:     return "FLAC"
    case .Mp3:      return "MP3"
    case .Vorbis:   return "Vorbis"
    case .Opus:     return "Opus"
    case .AdpcmMs:  return "ADPCM"
    case .AdpcmIma: return "IMA ADPCM"
    default:        return "Audio"
    }
}

// Names a subtitle syntax the way its specification spells it.
func subtitleFormatText(format: Video.Subtitle.Format)->string
{
    switch #complete format
    {
    case .SubRip:          return "SubRip"
    case .WebVtt:          return "WebVTT"
    case .SubStationAlpha: return "SubStation Alpha"
    case .Lyric:           return "LRC"
    case .MicroDvd:        return "MicroDVD"
    case .MatroskaText:    return "Matroska"
    }
}

// Formats the active sound track for the information bar.
func audioDetailsText(sound: const *Audio.SoundFile)->String => Format.toString(texts().ui_AudioDetails, audioEncodingText(sound.sampleEncoding()), sound.numChannels(), cast(f64, sound.sampleRateHz()) / 1_000.0)

// Names one embedded or sidecar subtitle track, with its language when it declares one.
func subtitleTrackName(index: u32, track: const *Video.Subtitle.Track)->String
{
    let strings  = texts()
    let language = track.languageTag()
    var result: #returntype = track.displayName().count ? String.from(track.displayName()) : Format.toString(strings.ui_SubtitleTrackNumber, index + 1)
    if language.count and language != "und" do
        result += Format.toString(strings.ui_SubtitleTrackLang, language)
    return result
}

// Names the subtitles in force on their chip: their language, their name, or their number.
func subtitleChipName(track: const *Video.Subtitle.Track)->String
{
    let language = track.languageTag()
    if language.count and language != "und" do
        return String.toUpper(language, .Unicode)
    if track.displayName().count do
        return String.from(track.displayName())
    return String.from("1")
}

// Names a sound track on its chip: its language and the layout of its channels, as "EN 5.1".
func audioChipName(index: u32, sound: const *Audio.SoundFile)->String
{
    let channels = sound.numChannels()
    let layout   = channels > 2 ? Format.toString("%.1", channels - 1) : Format.toString("%.0", channels)
    if sound.language().count and sound.language() != "und" do
        return Format.toString("% %", String.toUpper(sound.language(), .Unicode), layout)
    if sound.displayName().count do
        return Format.toString("% %", sound.displayName(), layout)
    return Format.toString("% %", Format.toString(texts().ui_AudioTrackNumber, index + 1), layout)
}

// Names each subtitle style in the language of the interface.
func subtitleFontText(font: SubtitleFont)->string
{
    switch #complete font
    {
    case .Sans:      return texts().ui_SubtitleFontSans
    case .Monospace: return texts().ui_SubtitleFontMono
    }
}

func subtitleSizeText(size: SubtitleSize)->string
{
    switch #complete size
    {
    case .Small:     return texts().ui_SubtitleSizeSmall
    case .Normal:    return texts().ui_SubtitleSizeNormal
    case .Large:     return texts().ui_SubtitleSizeLarge
    case .VeryLarge: return texts().ui_SubtitleSizeVeryLarge
    }
}

func subtitleEffectText(effect: SubtitleEffect)->string
{
    switch #complete effect
    {
    case .Outline:    return texts().ui_SubtitleEffectOutline
    case .Shadow:     return texts().ui_SubtitleEffectShadow
    case .Background: return texts().ui_SubtitleEffectBackdrop
    case .None:       return texts().ui_SubtitleEffectNone
    }
}

func subtitlePositionText(position: SubtitlePosition)->string
{
    switch #complete position
    {
    case .Bottom: return texts().ui_SubtitlePositionBottom
    case .Center: return texts().ui_SubtitlePositionCenter
    case .Top:    return texts().ui_SubtitlePositionTop
    }
}

func subtitleColorText(color: SubtitleColor)->string
{
    switch #complete color
    {
    case .White:  return texts().ui_SubtitleColorWhite
    case .Yellow: return texts().ui_SubtitleColorYellow
    }
}

// Registers this viewer's string table with the application.
func registerTexts(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'Texts(&g_Texts, "scope.video")
}

#run
{
    expect Gui.validateStrings'Texts(cast(string, FrenchStrings))
}
