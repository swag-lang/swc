#global public

using Core, Gui

// Visible strings of the image viewer.
//
// Units keep their symbol in every language — `px`, `%` and the `×` between two dimensions are
// read the same way everywhere — so only the words around them are translated.
struct ImageStrings
{
    ui_TipZoomOut: string = "Zoom out"             // Tooltip of the zoom-out button.
    ui_TipZoomIn:  string = "Zoom in"              // Tooltip of the zoom-in button.
    ui_Fit:        string = "Fit"                  // Label of the fit-to-window button.
    ui_TipFit:     string = "Fit image"            // Tooltip of the fit-to-window button.
    ui_TipActual:  string = "Actual size"          // Tooltip of the actual-size button.
    ui_TipRotate:  string = "Rotate clockwise"     // Tooltip of the rotation button.
    ui_TipPlay:    string = "Play or pause"        // Tooltip of the animation transport button.
    word_Frame:    string = "frame"                // One animation frame.
    word_Frames:   string = "frames"               // Several animation frames.

    // Summaries the host shows beside the file size. `%` takes the pixel size, then the frame
    // count with its noun, or the number of bits one pixel is stored on.
    ui_DetailsMovie: string = "% × % px · %"
    ui_DetailsStill: string = "% × % px · % bit"
}

private const FrenchStringsName = "lang/fr/filescope.image.tweak"
private const FrenchStrings = #include("../datas/lang/fr/filescope.image.tweak")

private var g_ImageStrings: ImageStrings

// Returns the visible strings of the image viewer in the active language.
func imageStrings()->const *ImageStrings => &g_ImageStrings

// Returns `count` followed by the noun in the form that count calls for.
func frameCountText(count: s32)->String
{
    return Format.toString("% %", count, count == 1 ? imageStrings().word_Frame : imageStrings().word_Frames)
}

// Registers this plugin's string table with the host that loaded it.
//
// A plugin enters the process long after the host chose a language, so its translations are
// published into the host's bundle before the table is registered: [[Gui.registerStrings]] then
// finds them and the viewer opens in the language of the window around it. Calling this again
// is a no-op, so the first view of this format pays for it and no other does.
func registerImageStrings(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'ImageStrings(&g_ImageStrings, "filescope.image")
}

#run
{
    expect Gui.validateStrings'ImageStrings(cast(string) FrenchStrings)
}
