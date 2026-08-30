#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

#test
{
    var line: RichEditLine
    line.chars.add('x')
    line.styles.add(0)
    Swag.assert(line.runeAt(0) == 'x')
    line.setStyleAt(0, 7)
    Swag.assert(line.styleAt(0) == 7)
    Swag.assert(line.setLexerState(12))
    Swag.assert(!line.setLexerState(12))
    Swag.assert(line.lexerState() == 12)
    line.dirtyStyle = false
    line.markStyleDirty()
    Swag.assert(line.dirtyStyle)
}

// The built-in namespace keeps its own style while its member retains the semantic style.
#test
{
    var host: Testing.HeadlessHost
    host.setup(420, 220)
    defer host.shutdown()

    let ed = RichEditCtrl.create(&host.root, {0, 0, 400, 200})
    var lexer: RichEditLexerSwag
    ed.setLexer(&lexer)
    ed.setText("Swag.assert(value)\nSwag.vecsplat(value)\nSwag.CompilerCommand.Test\nSwag.custom(value)\nUserSwag.assert(value)\n#[Swag.Inline]")
    ed.lexAll()

    Swag.assert(ed.runeAt({0, 0}).style == RichEditLexerSwag.Style.Namespace)
    Swag.assert(ed.runeAt({0, 4}).style == RichEditLexerSwag.Style.Default)
    Swag.assert(ed.runeAt({0, 5}).style == RichEditLexerSwag.Style.Intrinsic)
    Swag.assert(ed.runeAt({1, 0}).style == RichEditLexerSwag.Style.Namespace)
    Swag.assert(ed.runeAt({1, 5}).style == RichEditLexerSwag.Style.Builtin)
    Swag.assert(ed.runeAt({2, 0}).style == RichEditLexerSwag.Style.Namespace)
    Swag.assert(ed.runeAt({2, 5}).style == RichEditLexerSwag.Style.Class)
    Swag.assert(ed.runeAt({3, 0}).style == RichEditLexerSwag.Style.Namespace)
    Swag.assert(ed.runeAt({3, 5}).style == RichEditLexerSwag.Style.Function)
    Swag.assert(ed.runeAt({4, 0}).style == RichEditLexerSwag.Style.Class)
    Swag.assert(ed.runeAt({5, 0}).style == RichEditLexerSwag.Style.Preprocessor)
    Swag.assert(ed.runeAt({5, 2}).style == RichEditLexerSwag.Style.Namespace)
    Swag.assert(ed.runeAt({5, 6}).style == RichEditLexerSwag.Style.Default)
    Swag.assert(ed.runeAt({5, 7}).style == RichEditLexerSwag.Style.Preprocessor)
}

// The default shortcut table contains one command per key/modifier pair.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)
    defer host.shutdown()
    let ed = RichEditCtrl.create(&host.root, {0, 0, 300, 200})
    Swag.assert(ed.commandForShortcut(Input.Key.Down, Input.KeyModifiers.Shift) == .SelectRuneDown)
    Swag.assert(ed.commandForShortcut(Input.Key.Down, Input.KeyModifiers.Control) == .ScrollLineDown)

    let mappingCount = ed.mapping.count
    ed.setDefaultMapping()
    Swag.assert(ed.mapping.count == mappingCount)

    for i in ed.mapping.count
    {
        for j in i + 1 until ed.mapping.count
        {
            Swag.assert(ed.mapping[i].key != ed.mapping[j].key or ed.mapping[i].modifiers != ed.mapping[j].modifiers)
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
    Swag.assert(ed.text() == "Hello")

    ed.addText(" World")
    Swag.assert(ed.text() == "Hello World")

    ed.clear()
    Swag.assert(ed.text() == "")
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
    Swag.assert(ed.scrollableClientRect().height > ed.paddedClientRect().height)

    ed.scrollWnd.setScrollPos(0, 40)
    Swag.assert(ed.scrollPosition().y > 0)
    Swag.assert(notified)
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
    Swag.assert(loadedHeight > 0)
    ed.setEstimatedDocumentHeight(loadedHeight * 4)
    ed.setScrollPosition({0, loadedHeight * 2})
    let position = ed.scrollPosition()
    Swag.assert(position.y > loadedHeight)

    // Rendering the not-yet-resident gap must stay safe and blank while the owner fetches more.
    host.settleAnimations(ed)
    for 10 do
        ed.addText("another line\n")
    host.settleAnimations(ed)
    Swag.assert(ed.scrollPosition() == position)
    Swag.assert(ed.scrollableClientRect().height >= loadedHeight * 4)

    ed.setEstimatedDocumentHeight(0)
    host.settleAnimations(ed)
    Swag.assert(ed.scrollableClientRect().height == ed.loadedDocumentHeight())
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
    Swag.assert(ed.selectedText() == "Selectable")
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
    Swag.assert(ed.text() == "Xabc")

    ed.undo()
    Swag.assert(ed.text() == "abc")

    ed.redo()
    Swag.assert(ed.text() == "Xabc")
}

// The context menu reaches the same clipboard commands the keyboard does, and a read-only
// editor only offers the reading half of the vocabulary.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)
    defer host.shutdown()
    let ed = RichEditCtrl.create(&host.root, {0, 0, 300, 200})
    ed.setText("First line")

    host.clickPopupMenuItemWhenShown(RichEditCtrl.CtxSelectAll)
    ed.showContextMenu({60, 60})
    host.pump()
    Swag.assert(ed.selectedText() == "First line")

    host.clickPopupMenuItemWhenShown(RichEditCtrl.CtxCopy)
    ed.showContextMenu({60, 60})
    host.pump()
    Swag.assert(Clipboard.getString() == "First line")

    // Cut through the menu edits the document, which a read-only editor must refuse to offer.
    host.clickPopupMenuItemWhenShown(RichEditCtrl.CtxCut)
    ed.showContextMenu({60, 60})
    host.pump()
    Swag.assert(ed.text() == "")

    ed.setText("Frozen")
    ed.setFlags(.ReadOnly)
    ed.selectAll()
    host.clickPopupMenuItemWhenShown(RichEditCtrl.CtxCopy)
    ed.showContextMenu({60, 60})
    host.pump()
    Swag.assert(Clipboard.getString() == "Frozen")
    Swag.assert(ed.text() == "Frozen")
}
