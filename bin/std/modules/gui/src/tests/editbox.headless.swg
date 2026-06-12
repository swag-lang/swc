#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag, Core

var EditHeadlessEnterCount:  u32
var EditHeadlessEscapeCount: u32

func editHeadlessEnter(eb: *EditBox)  { discard eb; EditHeadlessEnterCount += 1 }
func editHeadlessEscape(eb: *EditBox) { discard eb; EditHeadlessEscapeCount += 1 }

// setText/getText round-trips the content.
#test
{
    var host: GuiHeadlessHost
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
    var host: GuiHeadlessHost
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
    var host: GuiHeadlessHost
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
    var host: GuiHeadlessHost
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
    var host: GuiHeadlessHost
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
    var host: GuiHeadlessHost
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

// Enter and Escape emit their dedicated signals.
// (EditBoxFlags.Zero avoids AutoLoseFocus, which would re-focus the top view.)
#test
{
    var host: GuiHeadlessHost
    host.setup(240, 60)
    EditHeadlessEnterCount  = 0
    EditHeadlessEscapeCount = 0

    let edit = EditBox.create(&host.root, "x", {20, 20, 200, 26}, null, EditBoxFlags.Zero)
    edit.sigEnterPressed += &editHeadlessEnter
    edit.sigEscapePressed += &editHeadlessEscape

    host.focus(edit)
    host.keyPress(Input.Key.Return)
    @assert(EditHeadlessEnterCount == 1)

    host.keyPress(Input.Key.Escape)
    @assert(EditHeadlessEscapeCount == 1)

    host.shutdown()
}
