#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

#test
{
    var line: RichEditLine
    line.chars.add('x')
    line.styles.add(0)
    @assert(line.runeAt(0) == 'x')
    line.setStyleAt(0, 7)
    @assert(line.styleAt(0) == 7)
    @assert(line.setLexerState(12))
    @assert(!line.setLexerState(12))
    @assert(line.lexerState() == 12)
    line.dirtyStyle = false
    line.markStyleDirty()
    @assert(line.dirtyStyle)
}

// The default shortcut table contains one command per key/modifier pair.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)
    defer host.shutdown()
    let ed = RichEditCtrl.create(&host.root, {0, 0, 300, 200})
    @assert(ed.commandForShortcut(Input.Key.Down, Input.KeyModifiers.Shift) == .SelectRuneDown)
    @assert(ed.commandForShortcut(Input.Key.Down, Input.KeyModifiers.Control) == .ScrollLineDown)

    let mappingCount = ed.mapping.count
    ed.setDefaultMapping()
    @assert(ed.mapping.count == mappingCount)

    for i in ed.mapping.count
    {
        for j in i + 1 until ed.mapping.count
        {
            @assert(ed.mapping[i].key != ed.mapping[j].key or ed.mapping[i].modifiers != ed.mapping[j].modifiers)
        }
    }
}

// setText/text round-trips; addText appends; clear empties.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)
    defer host.shutdown()
    let ed = RichEditCtrl.create(&host.root, {0, 0, 300, 200})
    ed.setText("Hello")
    @assert(ed.text() == "Hello")

    ed.addText(" World")
    @assert(ed.text() == "Hello World")

    ed.clear()
    @assert(ed.text() == "")
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 120)
    defer host.shutdown()

    let ed = RichEditCtrl.create(&host.root, {0, 0, 300, 100})
    var notified: bool
    ed.sigScrollPositionChanged += func|&notified|(ctrl, oldPosition, newPosition)
    {
        discard ctrl
        discard oldPosition
        notified = newPosition.y > 0
    }

    for 80 do
        ed.addText("one line\n")
    host.settleAnimations(ed)
    @assert(ed.scrollableClientRect().height > ed.paddedClientRect().height)

    ed.scrollWnd.setScrollPos(0, 40)
    @assert(ed.scrollPosition().y > 0)
    @assert(notified)
}

// A streaming document can expose its eventual height before all text is resident, and appending
// another chunk does not move a viewport already positioned in that virtual range.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 120)
    defer host.shutdown()

    let ed = RichEditCtrl.create(&host.root, {0, 0, 300, 100})
    for 20 do
        ed.addText("one line\n")
    host.settleAnimations(ed)

    let loadedHeight = ed.loadedDocumentHeight()
    @assert(loadedHeight > 0)
    ed.setEstimatedDocumentHeight(loadedHeight * 4)
    ed.setScrollPosition({0, loadedHeight * 2})
    let position = ed.scrollPosition()
    @assert(position.y > loadedHeight)

    // Rendering the not-yet-resident gap must stay safe and blank while the owner fetches more.
    host.settleAnimations(ed)
    for 10 do
        ed.addText("another line\n")
    host.settleAnimations(ed)
    @assert(ed.scrollPosition() == position)
    @assert(ed.scrollableClientRect().height >= loadedHeight * 4)

    ed.setEstimatedDocumentHeight(0)
    host.settleAnimations(ed)
    @assert(ed.scrollableClientRect().height == ed.loadedDocumentHeight())
}

// selectAll selects the whole content.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)
    defer host.shutdown()
    let ed = RichEditCtrl.create(&host.root, {0, 0, 300, 200})
    ed.setText("Selectable")
    ed.selectAll()
    @assert(ed.selectedText() == "Selectable")
}

// insertText at the cursor, with undo/redo.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)
    defer host.shutdown()
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
}
