#global internal

using Core, Gui, Audio

// Visible strings of the video viewer.
struct VideoStrings
{
    ui_TipPlay:     string = "Play"                           // Tooltip while playback is stopped or paused.
    ui_TipPause:    string = "Pause"                          // Tooltip while playback is running.
    ui_TipStop:     string = "Stop"                           // Tooltip of the stop button.
    ui_TipBackward: string = "Back 10 seconds (Left)"         // Tooltip of the backward seek button.
    ui_TipForward:  string = "Forward 10 seconds (Right)"     // Tooltip of the forward seek button.
    ui_TipSeek:     string = "Seek"                           // Tooltip of the time timeline.
    ui_TipMute:     string = "Mute or unmute (M)"             // Tooltip of the mute switch.
    ui_TipVolume:   string = "Volume"                         // Tooltip of the volume slider.
    ui_TipAudio:    string = "Audio track"                    // Tooltip of the sound-track selector.
    ui_AudioTrack:  string = "Audio % · % ch · %{f1} kHz"     // One sound-track selector entry.
    word_Frame:     string = "frame"                          // One video frame.
    word_Frames:    string = "frames"                         // Several video frames.

    // Summary the host shows beside the file size: geometry, frame count, frame rate, and duration.
    ui_Details: string = "% × % px · % · %{f2} fps · % · Swag CPU"
}

private const FrenchStringsName = "lang/fr/filescope.video.tweak"
private const FrenchStrings = #include("../../../datas/lang/fr/filescope.video.tweak")

private var g_VideoStrings: VideoStrings

// Returns the visible strings of the video viewer in the active language.
func videoStrings()->const *VideoStrings => &g_VideoStrings

// Returns `count` followed by the frame noun in the form that count calls for.
func videoFrameCountText(count: u64)->String
{
    return Format.toString("% %", count, count == 1 ? videoStrings().word_Frame : videoStrings().word_Frames)
}

// Formats one sound-track selector entry from the properties its decoder validated.
func videoAudioTrackText(index: u32, sound: const *Audio.SoundFile)->String
{
    return Format.toString(videoStrings().ui_AudioTrack, index + 1, sound.numChannels(), cast(f64) sound.sampleRateHz() / 1_000.0)
}

// Registers this viewer's string table with the application.
func registerVideoStrings(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'VideoStrings(&g_VideoStrings, "filescope.video")
}

#run
{
    expect Gui.validateStrings'VideoStrings(cast(string) FrenchStrings)
}
