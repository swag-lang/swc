#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

var EditHeadlessEnterCount:  u32
var EditHeadlessEscapeCount: u32

func editHeadlessEnter(eb: *EditBox)
{
    discard eb;
    EditHeadlessEnterCount += 1
}

func editHeadlessEscape(eb: *EditBox)
{
    discard eb;
    EditHeadlessEscapeCount += 1
}

// setText/getText round-trips the content.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 60)

    let edit = EditBox.create(&host.root, "Hello", {20, 20, 200, 26})
    @assert(edit.getText() == "Hello")

    edit.setText("World")
    @assert(edit.getText() == "World")

    host.shutdown()
}

// Typing runes inserts text at the caret.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 60)

    let edit = EditBox.create(&host.root, null, {20, 20, 200, 26})
    host.focus(edit)

    host.sendRune(Input.Key.A, 'H')
    host.sendRune(Input.Key.A, 'i')
    @assert(edit.getText() == "Hi")

    host.shutdown()
}

// Backspace removes the rune before the caret.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 60)

    let edit = EditBox.create(&host.root, null, {20, 20, 200, 26})
    host.focus(edit)

    host.sendRune(Input.Key.A, 'A')
    host.sendRune(Input.Key.A, 'B')
    @assert(edit.getText() == "AB")

    host.keyPress(Input.Key.Back)
    @assert(edit.getText() == "A")

    host.shutdown()
}

// selectAll + deleteSelection clears the content.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 60)

    let edit = EditBox.create(&host.root, "Hello", {20, 20, 200, 26})
    edit.selectAll()
    edit.deleteSelection()
    @assert(edit.getText() == "")

    host.shutdown()
}

// A read-only editbox ignores typed runes.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 60)

    let edit = EditBox.create(&host.root, "lock", {20, 20, 200, 26}, null, EditBoxFlags.ReadOnly)
    host.focus(edit)

    host.sendRune(Input.Key.A, 'Z')
    @assert(edit.getText() == "lock")

    host.shutdown()
}

// maxLength caps the number of runes.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 60)

    let edit = EditBox.create(&host.root, null, {20, 20, 200, 26})
    edit.maxLength = 3
    host.focus(edit)

    host.sendRune(Input.Key.A, '1')
    host.sendRune(Input.Key.A, '2')
    host.sendRune(Input.Key.A, '3')
    host.sendRune(Input.Key.A, '4')
    @assert(edit.getText() == "123")

    host.shutdown()
}

// The cached caret/selection pixel offset must match the snapped position the
// text is actually drawn with. The glyph run is rendered with per-glyph pixel
// snapping, so a caret computed from the raw (unsnapped) advances drifts further
// from the real glyph edge the longer the text is.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 60)

    let longText = "The quick brown fox jumps over the lazy dog 0123456789"
    let edit = EditBox.create(&host.root, longText, {0, 0, 380, 26}, null, EditBoxFlags.Zero)
    host.focus(edit)

    let len = @countof(edit.getText())
    edit.setSelection(len, len)

    let fontR    = nnFont(edit.getFont().regular)
    let expected = Pixel.Painter.measureStringSnapped(edit.getText(), fontR)
    let drift    = Math.abs(edit.posSelEnd - expected)

    // Caret must land within a pixel of the drawn glyph edge regardless of length.
    @assert(drift <= 1.0)

    host.shutdown()
}

// Right-aligned caret offset must also track the snapped draw position (this path
// was already snapped; the test guards against a regression).
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 60)

    let longText = "The quick brown fox jumps over the lazy dog 0123456789"
    let edit = EditBox.create(&host.root, longText, {0, 0, 380, 26}, null, EditBoxFlags.RightAlign)
    host.focus(edit)

    let len = @countof(edit.getText())
    edit.setSelection(len, len)

    let fontR    = nnFont(edit.getFont().regular)
    let expected = Pixel.Painter.measureStringSnapped(edit.getText(), fontR)
    let drift    = Math.abs(edit.posSelEnd - expected)
    @assert(drift <= 1.0)

    host.shutdown()
}

// Clicking maps the X position to a byte index using the same snapped advances the
// glyphs are drawn with: indices are non-decreasing as the click moves right, the
// far left lands on 0 and the far right lands on the last index.
#test
{
    var host: Testing.HeadlessHost
    host.setup(420, 60)

    let edit = EditBox.create(&host.root, "Hello world example text", {0, 0, 400, 26}, null, EditBoxFlags.Zero)
    host.focus(edit)

    let rect = edit.getSurfaceRect()
    let yc   = rect.vertCenter()

    // Far left clamps to the first byte.
    host.click({rect.x + 1, yc})
    @assert(edit.selEnd == 0)

    // Sweeping rightwards yields monotonically non-decreasing caret indices.
    var prev = 0'u64
    var x    = rect.x + 2
    while x < rect.right() - 2
    {
        host.click({x, yc})
        @assert(edit.selEnd >= prev)
        prev = edit.selEnd
        x    += 8
    }

    // Far right clamps to the end of the text.
    host.click({rect.right() - 1, yc})
    @assert(edit.selEnd == @countof(edit.getText()))

    host.shutdown()
}

// Clicking on a glyph then reading back its caret pixel offset round-trips: the
// caret sits within half an average glyph of where the click landed.
#test
{
    var host: Testing.HeadlessHost
    host.setup(420, 60)

    let edit = EditBox.create(&host.root, "Monotonic caret round trip", {0, 0, 400, 26}, null, EditBoxFlags.Zero)
    host.focus(edit)

    let fontR = nnFont(edit.getFont().regular)
    let len   = @countof(edit.getText())

    // For every caret index, the cached offset must equal the snapped advance to that
    // byte (what the renderer would place the glyph edge at).
    for idx in 0 to len
    {
        edit.setSelection(idx, idx)
        let expected = Pixel.Painter.measureStringSnapped(edit.getText(), fontR, idx)
        @assert(Math.abs(edit.posSelEnd - expected) <= 0.5)
    }

    host.shutdown()
}

// Home / End / arrow navigation moves the caret to the expected byte positions.
#test
{
    var host: Testing.HeadlessHost
    host.setup(300, 60)

    let edit = EditBox.create(&host.root, "abcdef", {0, 0, 260, 26}, null, EditBoxFlags.Zero)
    host.focus(edit)

    host.keyPress(Input.Key.End)
    @assert(edit.selBeg == 6 and edit.selEnd == 6)

    host.keyPress(Input.Key.Home)
    @assert(edit.selBeg == 0 and edit.selEnd == 0)

    host.keyPress(Input.Key.Right)
    @assert(edit.selEnd == 1)

    host.keyPress(Input.Key.Right)
    @assert(edit.selEnd == 2)

    host.keyPress(Input.Key.Left)
    @assert(edit.selEnd == 1)

    host.shutdown()
}

// Shift+arrow extends a selection while keeping its anchor; posSelBeg/posSelEnd stay
// in sync with the snapped advances of both ends.
#test
{
    var host: Testing.HeadlessHost
    host.setup(300, 60)

    let edit = EditBox.create(&host.root, "selection", {0, 0, 260, 26}, null, EditBoxFlags.Zero)
    host.focus(edit)

    host.keyPress(Input.Key.Home)
    host.keyPress(Input.Key.Right, Input.KeyModifiers.Shift)
    host.keyPress(Input.Key.Right, Input.KeyModifiers.Shift)
    host.keyPress(Input.Key.Right, Input.KeyModifiers.Shift)
    @assert(edit.selBeg == 0 and edit.selEnd == 3)

    let fontR = nnFont(edit.getFont().regular)
    @assert(Math.abs(edit.posSelBeg - Pixel.Painter.measureStringSnapped(edit.getText(), fontR, 0)) <= 0.5)
    @assert(Math.abs(edit.posSelEnd - Pixel.Painter.measureStringSnapped(edit.getText(), fontR, 3)) <= 0.5)

    host.shutdown()
}

// Ctrl+Left / Ctrl+Right jump by words.
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 60)

    let edit = EditBox.create(&host.root, "one two three", {0, 0, 320, 26}, null, EditBoxFlags.Zero)
    host.focus(edit)

    host.keyPress(Input.Key.Home)
    host.keyPress(Input.Key.Right, Input.KeyModifiers.Control)
    @assert(edit.selEnd == 3)     // end of "one"

    host.keyPress(Input.Key.Right, Input.KeyModifiers.Control)
    @assert(edit.selEnd == 4)     // crosses the space to the start of "two"

    host.keyPress(Input.Key.Right, Input.KeyModifiers.Control)
    @assert(edit.selEnd == 7)     // end of "two"

    host.keyPress(Input.Key.Left, Input.KeyModifiers.Control)
    @assert(edit.selEnd == 4)     // back to the start of "two"

    host.shutdown()
}

// A scrolled (overflowing) left-aligned box keeps the caret at the end aligned with
// the snapped text width after the scroll offset is applied.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 60)

    // Narrow box, long text -> horizontal scroll kicks in.
    let edit = EditBox.create(&host.root, "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ", {0, 0, 120, 26}, null, EditBoxFlags.Zero)
    host.focus(edit)

    let len = @countof(edit.getText())
    edit.setSelection(len, len)

    let fontR    = nnFont(edit.getFont().regular)
    let expected = Pixel.Painter.measureStringSnapped(edit.getText(), fontR, len)
    @assert(Math.abs(edit.posSelEnd - expected) <= 0.5)

    host.shutdown()
}

// A caret placed after the last character of an overflowing (scrolled) box must
// stay inside the visible edit rectangle — the scroll has to leave room for it,
// otherwise it is clipped at the right edge and appears to vanish.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 60)

    let edit = EditBox.create(&host.root, "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ", {0, 0, 120, 26}, null, EditBoxFlags.Zero)
    host.focus(edit)

    let len = @countof(edit.getText())
    edit.setSelection(len, len)
    edit.updateScroll()

    // The box must actually be scrolled, otherwise the test proves nothing.
    @assert(edit.scrollPosX > 0)

    let cc = edit.caretClip()
    @assert(cc.caret.x >= cc.view.x - 0.5)                 // not clipped left
    @assert(cc.caret.right() <= cc.view.right() + 0.5)     // not clipped right (the bug)

    host.shutdown()
}

// As the caret sweeps an overflowing box (home -> each rune -> end), it must stay
// visible at every position once the scroll is updated.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 60)

    let edit = EditBox.create(&host.root, "abcdefghijklmnopqrstuvwxyz0123456789", {0, 0, 120, 26}, null, EditBoxFlags.Zero)
    host.focus(edit)

    let len = @countof(edit.getText())
    for idx in 0 to len
    {
        edit.setSelection(idx, idx)
        edit.updateScroll()
        let cc = edit.caretClip()
        @assert(cc.caret.x >= cc.view.x - 0.5)
        @assert(cc.caret.right() <= cc.view.right() + 0.5)
    }

    host.shutdown()
}

// Enter and Escape emit their dedicated signals.
// (EditBoxFlags.Zero avoids AutoLoseFocus, which would re-focus the top view.)
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 60)
    EditHeadlessEnterCount  = 0
    EditHeadlessEscapeCount = 0

    let edit = EditBox.create(&host.root, "x", {20, 20, 200, 26}, null, EditBoxFlags.Zero)
    edit.sigEnterPressed  += &editHeadlessEnter
    edit.sigEscapePressed += &editHeadlessEscape

    host.focus(edit)
    host.keyPress(Input.Key.Return)
    @assert(EditHeadlessEnterCount == 1)

    host.keyPress(Input.Key.Escape)
    @assert(EditHeadlessEscapeCount == 1)

    host.shutdown()
}
