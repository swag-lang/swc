#global internal

using Core, Gui

// Visible strings of the image viewer.
//
// Units keep their symbol in every language — `px`, `%` and the `×` between two dimensions are
// read the same way everywhere — so only the words around them are translated.
struct ImageStrings
{
    ui_TipPrevious:            string = "Previous image"                         // Tooltip of the previous-file button.
    ui_TipNext:                string = "Next image"                             // Tooltip of the next-file button.
    ui_TipZoomOut:             string = "Zoom out"                               // Tooltip of the zoom-out button.
    ui_TipZoomIn:              string = "Zoom in"                                // Tooltip of the zoom-in button.
    ui_TipFit:                 string = "Fit image"                              // Tooltip of the fit-to-window button.
    ui_TipActual:              string = "Actual size"                            // Tooltip of the actual-size button.
    ui_TipTransform:           string = "Image orientation"                      // Tooltip of the orientation menu button.
    ui_TipPlay:                string = "Play or pause"                          // Tooltip of the animation transport button.
    ui_RotateClockwise:        string = "Rotate clockwise"           // Clockwise menu action.
    ui_RotateCounterClockwise: string = "Rotate counter-clockwise"   // Counter-clockwise menu action.
    ui_MirrorHorizontal:       string = "Mirror horizontally"        // Horizontal reflection menu action.
    ui_MirrorVertical:         string = "Mirror vertically"          // Vertical reflection menu action.
    ui_ResetTransform:         string = "Reset orientation"          // Restores source orientation.
    word_Mirrored:             string = "mirrored"                               // Status of reflected image content.
    word_Frame:                string = "frame"                                  // One animation frame.
    word_Frames:               string = "frames"                                 // Several animation frames.

    // Summaries the host shows beside the file size. `%` takes the pixel size, then the frame
    // count with its noun, or the number of bits one pixel is stored on.
    ui_DetailsMovie: string = "% × % px · %"
    ui_DetailsStill: string = "% × % px · % bit"
}

private const FrenchStringsName = "lang/fr/filescope.image.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/filescope.image.tweak")

private var g_ImageStrings: ImageStrings

// Returns the visible strings of the image viewer in the active language.
func imageStrings()->const *ImageStrings => &g_ImageStrings

// Returns `count` followed by the noun in the form that count calls for.
func frameCountText(count: s32)->String
{
    return Format.toString("% %", count, count == 1 ? imageStrings().word_Frame : imageStrings().word_Frames)
}

// Registers this viewer's string table with the application.
//
// The embedded translation is published before the table is registered, so the viewer follows
// the language of the application around it. Calling this again is a no-op.
func registerImageStrings(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'ImageStrings(&g_ImageStrings, "filescope.image")
}

#run
{
    expect Gui.validateStrings'ImageStrings(cast(string) FrenchStrings)
}
