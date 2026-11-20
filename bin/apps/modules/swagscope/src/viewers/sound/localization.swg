#global internal
#global namespace Viewers.Sound

using Core, Gui

// Visible strings of the sound viewer.
//
// Units keep their symbol in every language — `Hz`, `ms`, `s` and `bit` are read the same way
// everywhere — so only the words around them are translated.
struct Texts
{
    ui_TipPlay:     string = "Play"                           // Tooltip of the transport button while stopped or paused.
    ui_TipPause:    string = "Pause"                          // Tooltip of the transport button while playing.
    ui_TipStop:     string = "Stop"                           // Tooltip of the stop button.
    ui_TipBackward: string = "Back 10 Seconds (Left)"         // Tooltip of the backward seek button.
    ui_TipForward:  string = "Forward 10 Seconds (Right)"     // Tooltip of the forward seek button.
    ui_TipSeek:     string = "Seek"                           // Tooltip of the playback timeline.
    ui_TipMute:     string = "Mute or Unmute (M)"             // Tooltip of the mute switch.
    ui_TipVolume:   string = "Volume"                         // Tooltip of the volume slider.
    cmd_GoToTime:   string = "Go to Time…"                    // Lens command opening the numeric time prompt.
    ui_Go:          string = "Go"                             // Primary action accepting a valid time.
    ui_TimeHelp:    string = "Enter mm:ss or hh:mm:ss, or +30 / -10 seconds."
    ui_TimeError:   string = "Enter a time within this recording: mm:ss, hh:mm:ss, or a signed number of seconds."
    cmd_Faster:     string = "Play Faster"                    // Lens command moving playback one rate up; the pitch rises with it.
    cmd_Slower:     string = "Play Slower"                    // Lens command moving playback one rate down.
    cmd_LoopStart:  string = "Start Loop Here"                // Lens command marking where the looped passage starts.
    cmd_LoopEnd:    string = "End Loop Here"                  // Lens command marking where it ends, playback then repeating it.
    cmd_LoopClear:  string = "Stop Looping"                   // Lens command removing the looped passage.
    ui_Loop:        string = "loop %–%"                       // Looped passage in the summary: its start and end times.
    cmd_AddMarker:  string = "Add Session Marker"             // Adds a temporary marker at the current position.
    cmd_PreviousLandmark: string = "Previous Marker"          // Seeks to the previous sidecar or session marker.
    cmd_NextLandmark: string = "Next Marker"                  // Seeks to the next sidecar or session marker.
    cmd_NavigationBack: string = "Back in Listening History"   // Returns to a recent seek position.
    cmd_NavigationForward: string = "Forward in Listening History" // Replays a position left by Back.
    ui_Landmarks:   string = "% markers"                      // Summary count of available markers.
    ui_InvalidCues: string = "invalid cue timing ignored"      // Warns that at least one sidecar cue was rejected.
    ui_Sidecar:     string = "sidecar"                         // Origin of a marker read from a .cue file.
    ui_Session:     string = "session"                         // Origin of a temporary marker made while listening.
    ui_Embedded:    string = "embedded"                        // Origin of a marker stored in the media.
    word_Track:     string = "Track %"                         // Default label for an unnamed CUE track.
    word_Marker:    string = "Marker %"                       // Label for a temporary session marker.
    ui_NoEngine:    string = "Playback unavailable"           // Tooltip when no audio engine could be acquired.
    word_Channel:   string = "channel"                        // One audio channel.
    word_Channels:  string = "channels"                       // Several audio channels.

    // Summary the host shows beside the file size: sample rate, channel count with its noun,
    // sample width, then the duration.
    ui_Details: string = "% Hz · % · % bit · %"
}

private const FrenchStringsName = "lang/fr/scope.sound.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.sound.tweak")

private var g_Texts: Texts

// Returns the visible strings of the sound viewer in the active language.
func texts()->const *Texts => &g_Texts

// Returns `count` followed by the noun in the form that count calls for.
func channelCountText(count: u32)->String => Format.toString("% %", count, count == 1 ? texts().word_Channel : texts().word_Channels)

// Registers this viewer's string table with the application.
//
// The embedded translation is published before the table is registered, so the viewer follows
// the language of the application around it. Calling this again is a no-op.
func registerTexts(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'Texts(&g_Texts, "scope.sound")
}

#run
{
    expect Gui.validateStrings'Texts(cast(string, FrenchStrings))
}
