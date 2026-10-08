#global internal
#global namespace Viewers.Film

using Core, Gui, Audio

// Visible strings of the video viewer.
struct Texts
{
    ui_TipPlay:                string = "Play"                                         // Tooltip while playback is stopped or paused.
    ui_TipPause:               string = "Pause"                                        // Tooltip while playback is running.
    ui_TipStop:                string = "Stop"                                         // Tooltip of the stop button.
    ui_TipBackward:            string = "Back 10 seconds (Left)"                       // Tooltip of the backward seek button.
    ui_TipForward:             string = "Forward 10 seconds (Right)"                   // Tooltip of the forward seek button.
    ui_TipSeek:                string = "Seek"                                         // Tooltip of the playback timeline.
    ui_TipMute:                string = "Mute or unmute (M)"                           // Tooltip of the mute switch.
    ui_TipVolume:              string = "Volume"                                       // Tooltip of the volume slider.
    ui_TipAudio:               string = "Audio track"                                  // Tooltip of the sound-track selector.
    ui_TipSubtitles:           string = "Subtitles"                                    // Tooltip of the subtitle selector.
    ui_TipPlaybackSpeed:       string = "Playback speed"                               // Tooltip of the playback-speed menu button.
    ui_PlayerSpeedNormal:      string = "Normal"                                       // The source playback rate.
    ui_AudioTrack:             string = "<b>%</b>% · <p3>% · % ch · %{f1} kHz</p>"     // One sound-track selector entry.
    ui_AudioTrackNumber:       string = "Audio %"                                      // Fallback name for an unnamed sound track.
    ui_AudioTrackLang:         string = "<p2> (%)</p>"                                 // A sound-track language suffix.
    ui_AudioDetails:           string = "% · % ch · %{f1} kHz"                         // Encoding, channel count, and sample rate in the host summary.
    ui_SubtitleOff:            string = "Off"                                          // Disables subtitle presentation.
    ui_SubtitleTrackNumber:    string = "Subtitle %"                                   // Fallback name for an unnamed subtitle track.
    ui_SubtitleTrackLang:      string = "<p2> (%)</p>"                                 // A subtitle-track language suffix.
    ui_SubtitleEmbedded:       string = "<b>%</b>% · <p3>Embedded</p>"                 // Embedded subtitle-track entry.
    ui_SubtitleSidecar:        string = "<b>%</b>% · <p3>External file</p>"            // Sidecar subtitle-track entry.
    ui_SubtitleFont:           string = "Font"                                         // Subtitle font submenu.
    ui_SubtitleFontSans:       string = "System sans serif"                            // Proportional subtitle font.
    ui_SubtitleFontMono:       string = "Monospace"                                    // Fixed-width subtitle font.
    ui_SubtitleSize:           string = "Text size"                                    // Subtitle size submenu.
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
    ui_SubtitleDelayReset:     string = "Reset delay"
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

// Formats one sound-track selector entry from the properties its decoder validated.
func audioTrackText(index: u32, sound: const *Audio.SoundFile)->String
{
    let strings = texts()
    let name    = sound.displayName().count ? String.from(sound.displayName()) : Format.toString(strings.ui_AudioTrackNumber, index + 1)
    var language: String
    if sound.language().count and sound.language() != "und" do
        language = Format.toString(strings.ui_AudioTrackLang, sound.language())
    return Format.toString(strings.ui_AudioTrack, name, language, audioEncodingText(sound.sampleEncoding()), sound.numChannels(), cast(f64, sound.sampleRateHz()) / 1_000.0)
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

// Formats the active sound track for the information bar.
func audioDetailsText(sound: const *Audio.SoundFile)->String => Format.toString(texts().ui_AudioDetails, audioEncodingText(sound.sampleEncoding()), sound.numChannels(), cast(f64, sound.sampleRateHz()) / 1_000.0)

// Formats one embedded or sidecar subtitle-track entry.
func subtitleTrackText(index: u32, track: const *Video.Subtitle.Track, sidecar: bool)->String
{
    let strings     = texts()
    let displayName = track.displayName()
    let language    = track.languageTag()
    let name        = displayName.count ? String.from(displayName) : Format.toString(strings.ui_SubtitleTrackNumber, index + 1)
    var languageSuffix: String
    if language.count and language != "und" do
        languageSuffix = Format.toString(strings.ui_SubtitleTrackLang, language)
    return Format.toString(sidecar ? strings.ui_SubtitleSidecar : strings.ui_SubtitleEmbedded, name, languageSuffix)
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
