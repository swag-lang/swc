#global internal
#global namespace Viewers.Picture

using Core, Gui

// Visible strings of the image viewer.
//
// Units keep their symbol in every language — `px`, `%` and the `×` between two dimensions are
// read the same way everywhere — so only the words around them are translated.
struct Texts
{
    ui_TipPrevious:            string = "Previous Image"               // Tooltip of the previous-file button.
    ui_TipNext:                string = "Next Image"                   // Tooltip of the next-file button.
    ui_TipFit:                 string = "Fit Image"                    // Zoom-menu entry fitting the picture to the window.
    ui_ZoomMenu:               string = "Zoom…"                        // Tooltip of the zoom value menu.
    ui_TipTransform:           string = "Image Orientation"            // Tooltip of the orientation menu button.
    ui_TipPlay:                string = "Play or Pause"                // Tooltip of the animation transport button.
    ui_ItemSelector:           string = "Choose an image in this set"   // Tooltip of the independent image-set selector.
    ui_RotateClockwise:        string = "Rotate Clockwise"             // Clockwise menu action.
    ui_RotateCounterClockwise: string = "Rotate Counter-Clockwise"     // Counter-clockwise menu action.
    ui_MirrorHorizontal:       string = "Mirror Horizontally"          // Horizontal reflection menu action.
    ui_MirrorVertical:         string = "Mirror Vertically"            // Vertical reflection menu action.
    ui_ResetTransform:         string = "Reset Orientation"            // Restores source orientation.
    ui_CopyImage:              string = "Copy Image"                   // Puts the picture on the clipboard.
    ui_CopyColor:              string = "Copy Color % at %"            // Puts the color of the pixel last under the pointer on the clipboard; its code, then where it is.
    word_Mirrored:             string = "mirrored"                     // Status of reflected image content.
    word_Frame:                string = "frame"                        // One animation frame.
    word_Frames:               string = "frames"                       // Several animation frames.

    // Summaries the host shows beside the file size. `%` takes the pixel size, then the frame
    // count with its noun, or the number of bits one pixel is stored on. A vector document
    // states the extent of its view box instead, which is a coordinate space, not pixels.
    ui_DetailsMovie:  string = "% × % px · %"
    ui_DetailsStill:  string = "% × % px · % bit"
    ui_DetailsVector: string = "% × % · vector"

    // Reading of the point under the pointer, after the summary: its pixel, counted from the
    // top-left corner of the picture as stored, then its color and its opacity.
    ui_ProbePixel:  string = "x %, y %"
    ui_ItemLevel:   string = "level %"           // Mipmap level of the texture item in view.
    ui_ItemLayer:   string = "layer %"           // Array layer of the texture item in view.
    ui_ItemFace:    string = "face %"            // Cube face of the texture item in view.
    ui_ItemPage:    string = "page"               // Independent image page.
    ui_ItemVariant: string = "variant"            // Alternative image variant, such as an icon size.
    ui_FrameDelay:  string = "delay % ms"        // How long the frame of a paused animation stays on screen.
    ui_ProbeAlpha:  string = "opacity %"         // The share of opacity, its percent sign included.
    ui_Opaque:      string = "none, every pixel is opaque"     // Transparency reading of a picture whose alpha hides nothing.
    ui_Transparent: string = "% transparent"     // Share of pixels the alpha hides wholly.
    ui_Translucent: string = "% translucent"     // Share of pixels the alpha lets show through.
}

private const FrenchStringsName = "lang/fr/scope.image.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.image.tweak")

private var g_Texts: Texts

// Returns the visible strings of the image viewer in the active language.
func texts()->const *Texts => &g_Texts

// Returns `count` followed by the noun in the form that count calls for.
func frameCountText(count: s32)->String => Format.toString("% %", count, count == 1 ? texts().word_Frame : texts().word_Frames)

// Registers this viewer's string table with the application.
//
// The embedded translation is published before the table is registered, so the viewer follows
// the language of the application around it. Calling this again is a no-op.
func registerTexts(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'Texts(&g_Texts, "scope.image")
}

#run
{
    expect Gui.validateStrings'Texts(cast(string, FrenchStrings))
}
