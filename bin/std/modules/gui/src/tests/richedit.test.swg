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
    Swag.assert(not line.setLexerState(12))
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

// Editing keys stay in a multiline editor, while an unbound Escape reaches the modal action.
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 260)
    defer host.shutdown()

    let dlg = Dialog.create(&host.surface, 320, 230, title: "Edit")
    let ed  = RichEditCtrl.create(dlg.view(), {16, 16, 280, 120})
    dlg.addButton("Ok", Dialog.BtnOk, true)
    dlg.addButton("Cancel", Dialog.BtnCancel)
    dlg.applyLayout()

    var checked: bool
    host.app.sigFrame += func|host = &host, ed, checked = &checked|(app)
    {
        discard app
        if checked[] do
            return
        checked[] = true
        ed.setFocus()

        host.keyPress(Input.Key.Return)
        host.sendRune(Input.Key.Return, '\n')
        Swag.assert(ed.text() == "\n")
        host.keyPress(Input.Key.Tab)
        Swag.assert(ed.text().count > 1)
        Swag.assert(ed.focusTarget().hasFocus())
        host.keyPress(Input.Key.Escape)
    }

    let modalResult = dlg.doModal()
    Swag.assert(modalResult == Dialog.BtnCancel)
    Swag.assert(checked)
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

// Wrapping uses the viewport left by the vertical scrollbar, and bounds even a long token.
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 220)
    defer host.shutdown()
    let ed = RichEditCtrl.create(&host.root, {0, 0, 340, 200})
    ed.marginLeft  = 12
    ed.marginRight = 12
    ed.setFlags(.ReadOnly | .WordWrap)
    var text: Core.String
    for 16_384 do
        text += "x"
    ed.setText(text.toString())
    ed.setVirtualDocumentRange(0, 100_000)
    host.root.applyLayout()
    discard host.render(ed)
    discard host.render(ed)
    Swag.assert(ed.scrollWnd.paddingZ > 0)
    Swag.assert(ed.lines.count > 1)
    let right = ed.scrollWnd.paddedClientRect().width - ed.scrollWnd.paddingZ - ed.marginRight
    for line, index in ed.lines
    {
        let position = ed.cursorDisplayPosition({index, line!.length()})
        Swag.assert(position.x <= right + 1)
    }

    Swag.assert(ed.text() == text)
    ed.addText(" tail")
    text += " tail"
    discard host.render(ed)
    Swag.assert(ed.text() == text)
    ed.setFlags(.ReadOnly)
    discard host.render(ed)
    Swag.assert(ed.lines.count == 1 and ed.text() == text)
}

// A document with no line answers the origin for any point instead of reading a missing line.
#test
{
    var host: Testing.HeadlessHost
    host.setup(420, 220)
    defer host.shutdown()

    let ed = RichEditCtrl.create(&host.root, {0, 0, 400, 200})
    ed.clear()
    let cursor = ed.cursorAt({20, 20})
    Swag.assert(cursor.lineIndex == 0 and cursor.charPosInLine == 0)
}

// Counts the lines a paint asks to be lexed.
struct CountingLexer
{
    lexed: u32
}

impl IRichEditLexer for CountingLexer
{
    mtd impl setup(ed: *RichEditCtrl) {}
    mtd impl setupTheme(ed: *RichEditCtrl) {}
    mtd impl insertRune(ed: *RichEditCtrl, ch: rune)->bool => false
    mtd impl compute(linePrev: *RichEditLine?, line: *RichEditLine, lineNext: *RichEditLine?) { .lexed += 1 }
}

// A viewport change must not re-lex the document. Lexing reads the text, not the rectangle it is
// shown in, and running it over every line of a large file on each frame of a border drag is what
// made the window stop following the pointer.
#test
{
    var host: Testing.HeadlessHost
    host.setup(420, 260)
    defer host.shutdown()

    let ed = RichEditCtrl.create(&host.root, {0, 0, 400, 240})
    var lexer: CountingLexer
    ed.setLexer(&lexer)

    var text: Core.String
    for 200 do
        text += "let value = 1\n"
    ed.setText(text.toString())
    host.root.applyLayout()
    discard host.render(ed)
    Swag.assert(lexer.lexed > 0, "the first paint lexes the document it was given")

    lexer.lexed = 0
    ed.setPosition({0, 0, 300, 240})
    host.root.applyLayout()
    discard host.render(ed)
    Swag.assert(lexer.lexed == 0, "a resize must not lex a single line")
}

// A wrapped document reflows once, when the border drag ends, instead of at every size the
// pointer passes through. Re-wrapping a whole file cannot run at pointer cadence, and the text is
// clipped to the viewport for as long as the gesture lasts anyway.
#test
{
    var host: Testing.HeadlessHost
    host.setup(420, 260)
    defer host.shutdown()

    let ed = RichEditCtrl.create(&host.root, {0, 0, 400, 240})
    ed.setFlags(.WordWrap)

    var text: Core.String
    for 400 do
        text += "word "
    ed.setText(text.toString())
    host.root.applyLayout()
    discard host.render(ed)

    let wrapped = ed.lines.count
    Swag.assert(wrapped > 1)

    host.surface.setSizing(true)
    ed.setPosition({0, 0, 200, 240})
    host.root.applyLayout()
    discard host.render(ed)
    Swag.assert(ed.lines.count == wrapped, "a live border drag must not reflow the document")

    host.surface.setSizing(false)
    discard host.render(ed)
    Swag.assert(ed.lines.count > wrapped, "the narrower viewport must reflow once the drag ends")
}
