#global internal

using Core, Gui

// Visible strings of the sound viewer.
//
// Units keep their symbol in every language — `Hz`, `ms`, `s` and `bit` are read the same way
// everywhere — so only the words around them are translated.
struct SoundStrings
{
    ui_TipPlay:     string = "Play"                           // Tooltip of the transport button while stopped or paused.
    ui_TipPause:    string = "Pause"                          // Tooltip of the transport button while playing.
    ui_TipStop:     string = "Stop"                           // Tooltip of the stop button.
    ui_TipBackward: string = "Back 10 seconds (Left)"         // Tooltip of the backward seek button.
    ui_TipForward:  string = "Forward 10 seconds (Right)"     // Tooltip of the forward seek button.
    ui_TipSeek:     string = "Seek"                           // Tooltip of the playback timeline.
    ui_TipMute:     string = "Mute or unmute (M)"             // Tooltip of the mute switch.
    ui_TipVolume:   string = "Volume"                         // Tooltip of the volume slider.
    ui_NoEngine:    string = "Playback unavailable"           // Tooltip when no audio engine could be acquired.
    word_Channel:   string = "channel"                        // One audio channel.
    word_Channels:  string = "channels"                       // Several audio channels.

    // Summary the host shows beside the file size: sample rate, channel count with its noun,
    // sample width, then the duration.
    ui_Details: string = "% Hz · % · % bit · %"
}

private const FrenchStringsName = "lang/fr/filescope.sound.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/filescope.sound.tweak")

private var g_SoundStrings: SoundStrings

// Returns the visible strings of the sound viewer in the active language.
func soundStrings()->const *SoundStrings => &g_SoundStrings

// Returns `count` followed by the noun in the form that count calls for.
func channelCountText(count: u32)->String
{
    return Format.toString("% %", count, count == 1 ? soundStrings().word_Channel : soundStrings().word_Channels)
}

// Registers this viewer's string table with the application.
//
// The embedded translation is published before the table is registered, so the viewer follows
// the language of the application around it. Calling this again is a no-op.
func registerSoundStrings(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'SoundStrings(&g_SoundStrings, "filescope.sound")
}

#run
{
    expect Gui.validateStrings'SoundStrings(cast(string) FrenchStrings)
}
