#global public
#global namespace Viewer

using Core, Gui

// The editor holds a bounded window of text and looks ahead by six viewport heights.
const ResidentWindowSize = 256 * 1024'u64
const StreamLookAhead    = 6.0

// Reports when a streamed editor is near the end of its resident text.
func needsMoreText(editor: *RichEditCtrl, loaded: u64, offsetY: f32)->bool
{
    if loaded >= ResidentWindowSize do
        return false
    let height = editor.loadedDocumentHeight()
    return height <= 0 or editor.scrollPosition().y + editor.paddedClientRect().height * StreamLookAhead >= offsetY + height
}

// Prevents caret and wrapping corrections during paint from reloading the lines being drawn.
func paintResidentText(evt: *PaintEvent, repositioning: *bool)
{
    let previous = repositioning[]
    repositioning[] = true
    defer repositioning[] = previous
    evt.target!.processEvent(evt)
}
