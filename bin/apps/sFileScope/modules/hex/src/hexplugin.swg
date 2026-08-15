#global public

using Core, Pixel, Gui

private const ViewerPluginApiVersion = 2'u32
private const HexPageSize = 64 * 1024'u64
private const HexLineSize = 16'u64

internal func formatHexPage(bytes: const [..] u8, baseOffset: u64)->String
{
    var result: retval
    result.reserve(@countof(bytes) * 4)
    var line = 0'u64
    while line < @countof(bytes)
    {
        result += Format.toString("%{X016}  ", baseOffset + line)
        for column in HexLineSize
        {
            let index = line + column
            if index < @countof(bytes) do
                result += Format.toString("%{X02} ", bytes[index])
            else do
                result += "   "
            if column == 7 do
                result += " "
        }

        result += " │"
        for column in HexLineSize
        {
            let index = line + column
            if index >= @countof(bytes) do
                break
            let value = bytes[index]
            result += value >= 32 and value < 127 ? value : '.'
        }

        result += "│\n"
        line   += HexLineSize
    }

    return result
}

internal struct HexPluginView
{
    using wnd: Wnd

    #[Swag.Late]
    {
        commands:       *Wnd
        previousButton: *IconButton
        nextButton:     *IconButton
        offsetLabel:    *Label
        editor:         *RichEditCtrl
    }

    fileName: String
    fileSize: u64
    offset:   u64
}

internal impl HexPluginView
{
    mtd updateCommands()
    {
        .previousButton.enable(.offset > 0)
        .nextButton.enable(.offset + HexPageSize < .fileSize)
        let end = Math.min(.offset + HexPageSize, .fileSize)
        .offsetLabel.setText(Format.toString("%{X}–%{X}", .offset, end).toString())
    }

    mtd loadPage()
    {
        var stream = catch File.openRead(.fileName.toString()) as openError
        if openError != null
        {
            .editor.setText("The file could not be read.")
            return
        }

        discard catch stream.seek(.Begin, .offset)

        let wanted = Math.min(HexPageSize, .fileSize - .offset)
        var bytes: Array'u8
        bytes.resize(wanted)
        let read = catch stream.read(bytes.buffer, wanted) as readError
        if readError != null
        {
            .editor.setText("The file could not be read.")
            return
        }

        bytes.resize(read)
        .editor.setText(formatHexPage(bytes.toSlice(), .offset).toString())
        .updateCommands()
    }

    mtd movePage(direction: s32)
    {
        if direction < 0
        {
            .offset = .offset >= HexPageSize ? .offset - HexPageSize : 0
        }
        elif .offset + HexPageSize < .fileSize do
            .offset += HexPageSize
        .loadPage()
    }
}

internal impl IWnd for HexPluginView
{
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind == .Pressed and evt.key == .PageUp do
            .movePage(-1)
        elif evt.kind == .Pressed and evt.key == .PageDown do
            .movePage(1)
        else do
            evt.accepted = false
    }
}

internal impl HexPluginView
{
    func create(contentParent, commandParent: *Wnd, fileName: string)->*HexPluginView
    {
        let result = Wnd.create'HexPluginView(contentParent, "sFileScope.hex")
        result.backgroundStyle = .View
        result.fileName        = fileName
        let info = catch File.info(fileName) as infoError
        if infoError == null do
            result.fileSize = info.size

        result.commands                 = Wnd.create'Wnd(commandParent, {0, 0, 224, 36})
        result.commands.backgroundStyle = .Window

        with result.previousButton = IconButton.create(result.commands, result.theme().icon(.ChevronLeft, 18), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .toolTip    = "Previous 64 KiB"
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.movePage(-1)
            }
        }

        with result.nextButton = IconButton.create(result.commands, result.theme().icon(.ChevronRight, 18), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .margin.x   = 8
            .toolTip    = "Next 64 KiB"
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.movePage(1)
            }
        }

        with result.offsetLabel = Label.create(result.commands, "", {0, 0, 144, 36}, null, .SecondaryText)
        {
            .dockStyle = .Right
            .style.setFont(result.theme().createDefaultFontFS(result.themeMetrics().defaultFixedFontSize), .Regular)
            .setTextAlignment(.Right, .Center)
        }

        result.editor           = RichEditCtrl.create(result)
        result.editor.dockStyle = .Center
        result.editor.setFlags(.ReadOnly)
        result.editor.marginLeft  = 12
        result.editor.marginRight = 12
        result.editor.style.setFont(result.theme().createDefaultFontFS(result.themeMetrics().defaultFixedFontSize), .Regular)
        result.loadPage()
        result.applyLayout()
        result.setInitialFocus(result.editor)
        return result
    }
}

// Creates the hexadecimal view exported through the sFileScope plugin ABI.
func sFileScopePluginCreate(contentParent, commandParent: *Wnd, fileName: string, apiVersion: u32, commands: *#null *Wnd)->#null *Wnd
{
    if apiVersion != ViewerPluginApiVersion do
        return null
    let view = HexPluginView.create(contentParent, commandParent, fileName)
    commands[] = view.commands
    return view
}
