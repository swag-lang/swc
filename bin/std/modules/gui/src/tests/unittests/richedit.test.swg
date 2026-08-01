#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// The default shortcut table contains one command per key/modifier pair.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)

    let ed = RichEditCtrl.create(&host.root, {0, 0, 300, 200})
    @assert(ed.commandForShortcut(Input.Key.Down, Input.KeyModifiers.Shift) == .SelectRuneDown)
    @assert(ed.commandForShortcut(Input.Key.Down, Input.KeyModifiers.Control) == .ScrollLineDown)

    let mappingCount = ed.mapping.count
    ed.setDefaultMapping()
    @assert(ed.mapping.count == mappingCount)

    for [i] in ed.mapping.count
    {
        for var j = i + 1; j < ed.mapping.count; j += 1
        {
            @assert(ed.mapping[i].key != ed.mapping[j].key or ed.mapping[i].modifiers != ed.mapping[j].modifiers)
        }
    }

    host.shutdown()
}

// setText/text round-trips; addText appends; clear empties.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)

    let ed = RichEditCtrl.create(&host.root, {0, 0, 300, 200})
    ed.setText("Hello")
    @assert(ed.text() == "Hello")

    ed.addText(" World")
    @assert(ed.text() == "Hello World")

    ed.clear()
    @assert(ed.text() == "")

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
    @assert(ed.selectedText() == "Selectable")

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
    @assert(ed.text() == "Xabc")

    ed.undo()
    @assert(ed.text() == "abc")

    ed.redo()
    @assert(ed.text() == "Xabc")

    host.shutdown()
}
