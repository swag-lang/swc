using Core, Pixel, Gui

private const TextStreamChunkSize = 16 * 1024'u64
private const TextStreamLookAhead = 2.0

// Host-owned text view available for every file without loading a plugin.
struct BasicTextView
{
    using wnd: Wnd

    #[Swag.Late]
    {
        commands:   *Wnd
        editor:     *RichEditCtrl
        wrapButton: *PushButton
    }

    stream:    File.FileStream
    fileSize:  u64
    loadTimer: #null *Timer
    hasText:   bool
    wrapping = true
}

impl BasicTextView
{
    mtd hasMore()->bool
    {
        if !.stream.isOpen() do
            return false
        let position = catch .stream.position() as positionError
        return positionError == null and position < .fileSize
    }

    mtd needsMore()->bool
    {
        if !.hasMore() do
            return false
        let viewport = .editor.paddedClientRect()
        let document = .editor.scrollableClientRect()
        return .editor.scrollPosition().y + viewport.height * TextStreamLookAhead >= document.height
    }

    mtd scheduleMore()
    {
        if .loadTimer or !.needsMore() do
            return
        .loadTimer = .addTimer(8'ms)
    }

    mtd stopLoading()
    {
        if .loadTimer
        {
            .removeTimer(.loadTimer!)
            .loadTimer = null
        }

        .stream.close()
    }

    mtd showReadError()
    {
        .stopLoading()
        let message = "This file does not contain supported UTF-8 text. Select Hexadecimal to inspect its bytes."
        if !.hasText do
            .editor.setText(message)
        else do
            .editor.addText(Format.toString("\n\n%", message).toString())
    }

    mtd loadNextChunk()
    {
        if !.hasMore() do
            return

        let chunk = catch .stream.readUtf8Chunk(TextStreamChunkSize) as readError
        if readError != null or Utf8.indexOf(chunk.toSlice(), 0'rune) != Swag.U64.Max
        {
            .showReadError()
            return
        }

        if chunk.isEmpty()
        {
            .stopLoading()
            return
        }

        .editor.addText(chunk.toString())
        .hasText = true
        if !.hasMore() do
            .stream.close()
    }

    mtd updateWrap()
    {
        .editor.setFlags(.ReadOnly | (.wrapping ? RichEditFlags.WordWrap : .None))
        .wrapButton.setText(.wrapping ? "Wrap on" : "Wrap off")
        .scheduleMore()
    }

    mtd toggleWrap()
    {
        .wrapping = !.wrapping
        .updateWrap()
    }
}

impl IWnd for BasicTextView
{
    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        .stopLoading()
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .loadTimer
        {
            evt.accepted = false
            return
        }

        .removeTimer(evt.timer)
        .loadTimer = null
        .loadNextChunk()
        .scheduleMore()
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind == .Pressed and evt.key == .W and evt.modifiers.has(.Control) do
            .toggleWrap()
        else do
            evt.accepted = false
    }
}

impl BasicTextView
{
    func create(contentParent, commandParent: *Wnd, fileName: string)->*BasicTextView
    {
        let result = Wnd.create'BasicTextView(contentParent, "sFileScope.basicText")
        result.backgroundStyle = .View

        result.commands                 = Wnd.create'Wnd(commandParent, {0, 0, 104, 36})
        result.commands.backgroundStyle = .Window

        with result.wrapButton = PushButton.create(result.commands, "Wrap on", {0, 0, 96, 36})
        {
            .dockStyle  = .Left
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.toggleWrap()
            }
        }

        result.editor             = RichEditCtrl.create(result)
        result.editor.dockStyle   = .Center
        result.editor.marginLeft  = 12
        result.editor.marginRight = 12
        result.editor.style.setFont(result.theme().createDefaultFontFS(result.themeMetrics().defaultFixedFontSize), .Regular)
        result.editor.sigScrollPositionChanged += func|view = result|(editor, oldPosition, newPosition)
        {
            discard editor
            discard oldPosition
            discard newPosition
            view.scheduleMore()
        }
        result.hookOnEvent = func|view = result|(wnd, evt)
        {
            discard wnd
            if evt is ResizeEvent do
                view.scheduleMore()
            return false
        }

        result.stream = catch File.openRead(fileName) as openError
        if openError != null do
            result.showReadError()
        else
        {
            let size = catch result.stream.size() as sizeError
            if sizeError != null do
                result.showReadError()
            else
            {
                result.fileSize = size
                if !size do
                    result.stream.close()
                else do
                    result.loadNextChunk()
            }
        }

        result.updateWrap()
        result.applyLayout()
        result.scheduleMore()
        result.setInitialFocus(result.editor)
        return result
    }
}
