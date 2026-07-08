#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag, Core

// setText/getText round-trips; addText appends; clear empties.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)

    let ed = RichEditCtrl.create(&host.root, {0, 0, 300, 200})
    ed.setText("Hello")
    @assert(ed.getText() == "Hello")

    ed.addText(" World")
    @assert(ed.getText() == "Hello World")

    ed.clear()
    @assert(ed.getText() == "")

    host.shutdown()
}

// selectAll selects the whole content.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)

    let ed = RichEditCtrl.create(&host.root, {0, 0, 300, 200})
    ed.setText("Selectable")
    ed.selectAll()
    @assert(ed.getSelectedText() == "Selectable")

    host.shutdown()
}

// insertText at the cursor, with undo/redo.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)

    let ed = RichEditCtrl.create(&host.root, {0, 0, 300, 200})
    ed.setText("abc")

    // An undoable edit is bracketed by pushUndo()/popUndo().
    ed.pushUndo()
    ed.insertText("X")
    ed.popUndo()
    @assert(ed.getText() == "Xabc")

    ed.undo()
    @assert(ed.getText() == "abc")

    ed.redo()
    @assert(ed.getText() == "Xabc")

    host.shutdown()
}
