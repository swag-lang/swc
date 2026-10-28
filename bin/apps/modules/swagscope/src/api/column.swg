#global public
#global namespace Viewer

using Core, Gui, Pixel

// The measures of reading: prose in a column of 680 in a face of 16 on lines 29 apart, code in a
// numbered column of 900 in the fixed face on lines twice its size apart. The column grows with
// the zoom, so a line holds the same words at every size.
const ProseColumn   = 680.0
const ProseFontSize = 16'u32
const ProsePitch    = 29.0 / 16.0
const CodeColumn    = 900.0
const CodePitch     = 2.0

// Air a reading column keeps from the edges of a window narrower than it.
const ColumnInset = 24.0

// Keeps the text of `editor` in a column of `width` centred in its view, the margins taking the
// rest of the width and never less than [[Viewer.ColumnInset]]. Call it whenever the view or the
// zoom changes; a margin that moved lays the lines out again.
func centerColumn(editor: *RichEditCtrl, width: f32)
{
    let view   = editor.clientRect().width
    let margin = Math.round(Math.max(ColumnInset, (view - width) * 0.5))
    if margin == editor.marginLeft and margin == editor.marginRight do
        return
    editor.marginLeft  = margin
    editor.marginRight = margin
    editor.setFlags(editor.flags)
}

// Sets the lines of `editor` `pitch` times the size of `font` apart, from baseline to baseline.
func setLinePitch(editor: *RichEditCtrl, font: *Font, size: u32, pitch: f32)
{
    editor.lineSpacing = Math.max(Math.round(cast(f32, size) * pitch) - font.height, 0)
    editor.setFlags(editor.flags)
}
