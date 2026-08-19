#global internal

using Core, Gui

// Visible strings of the video viewer.
struct VideoStrings
{
    ui_TipPlay:  string = "Play"       // Tooltip while playback is stopped or paused.
    ui_TipPause: string = "Pause"      // Tooltip while playback is running.
    ui_TipStop:  string = "Stop"       // Tooltip of the stop button.
    ui_TipSeek:  string = "Seek"       // Tooltip of the frame timeline.
    word_Frame:  string = "frame"      // One video frame.
    word_Frames: string = "frames"     // Several video frames.

    // Summary the host shows beside the file size: geometry, frame count, frame rate, and duration.
    ui_Details: string = "% × % · % · %{f2} fps · %{f2} s"
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
