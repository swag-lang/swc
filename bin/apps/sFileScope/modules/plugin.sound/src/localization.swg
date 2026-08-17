#global public

using Core, Gui

// Visible strings of the sound viewer.
//
// Units keep their symbol in every language — `Hz`, `ms`, `s` and `bit` are read the same way
// everywhere — so only the words around them are translated.
struct SoundStrings
{
    ui_TipPlay:      string = "Play"                                    // Tooltip of the transport button while stopped or paused.
    ui_TipPause:     string = "Pause"                                   // Tooltip of the transport button while playing.
    ui_TipStop:      string = "Stop"                                    // Tooltip of the stop button.
    ui_NoEngine:     string = "Playback unavailable"                    // Tooltip when no audio engine could be acquired.
    ui_ErrDecode:    string = "This WAV file could not be decoded."     // Shown when the file is not readable PCM or float WAV.
    ui_DetailsError: string = "WAV · decode failed"                     // Summary the host shows for a file that would not decode.

    word_Channel:  string = "channel"      // One audio channel.
    word_Channels: string = "channels"     // Several audio channels.

    // Summary the host shows beside the file size: sample rate, channel count with its noun,
    // sample width, then the duration.
    ui_Details: string = "% Hz · % · % bit · %"
}

private const FrenchStringsName = "lang/fr/filescope.sound.tweak"
private const FrenchStrings = #include("../datas/lang/fr/filescope.sound.tweak")

private var g_SoundStrings: SoundStrings

// Returns the visible strings of the sound viewer in the active language.
func soundStrings()->const *SoundStrings => &g_SoundStrings

// Returns `count` followed by the noun in the form that count calls for.
func channelCountText(count: u32)->String
{
    return Format.toString("% %", count, count == 1 ? soundStrings().word_Channel : soundStrings().word_Channels)
}

// Registers this plugin's string table with the host that loaded it.
//
// A plugin enters the process long after the host chose a language, so its translations are
// published into the host's bundle before the table is registered: [[Gui.registerStrings]] then
// finds them and the viewer opens in the language of the window around it. Calling this again
// is a no-op, so the first view of this format pays for it and no other does.
func registerSoundStrings(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'SoundStrings(&g_SoundStrings, "filescope.sound")
}

#run
{
    expect Gui.validateStrings'SoundStrings(cast(string) FrenchStrings)
}
