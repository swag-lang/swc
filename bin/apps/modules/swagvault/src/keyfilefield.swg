using Core, Gui

// Visible list of the ordered key files that participate in one vault access.
struct KeyFileField
{
    using wnd: Wnd

    late
    {
        files:    *ListCtrl
        empty:    *Label
        actions:  *StackLayoutCtrl
        add:      *IconButton
        generate: *IconButton
        remove:   *IconButton
    }

    sigPathsChanged: SigArray'func||(*KeyFileField)

    paths: Array'String
}

// Writes 64 bytes from the system's secure random generator to a new file at `path`.
private func writeRandomKeyFile(path: string) fail
{
    var random: [64] u8
    try Core.Crypto.randomBytes(random)
    defer Core.Crypto.secureClear(random)

    var stream = try File.open(path, .CreateNew, .Write, .Zero)
    try stream.writeAll(random)
    try stream.flush()
}

impl IWnd for KeyFileField
{
    mtd impl measureContent(_: Math.Point)->Math.Point
    {
        let metrics    = .themeMetrics()
        let rows       = cast(f32, Math.max(1, Math.min(cast(u32, .paths.count), VisibleRows)))
        let listHeight = rows * .files.lineHeight() + metrics.list_Padding * 2
        let height     = listHeight + metrics.dialog_BtnPadding + .actions.measure({}).preferred.y
        return Math.Point{0, height}
    }

    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        if .remove == null do
            return
        let room     = .clientRect()
        let metrics  = .themeMetrics()
        let rows     = cast(f32, Math.max(1, Math.min(cast(u32, .paths.count), VisibleRows)))
        let gap      = metrics.dialog_BtnPadding
        let actionsH = .actions.measure({}).preferred.y
        let listH    = Math.min(.files.lineHeight() * rows + metrics.list_Padding * 2, Math.max(0, room.height - gap - actionsH))
        let actionsY = room.y + listH + gap

        let listRect = Math.Rectangle{room.x, room.y, room.width, listH}
        .files.arrange(listRect)
        .empty.arrange(listRect)
        .actions.arrange(Math.Rectangle{room.x, actionsY, room.width, actionsH})
    }
}

private impl KeyFileField
{
    mtd hasPath(path: string)->bool
    {
        for one in .paths where Path.equals(one.toString(), path) do
            return true
        return false
    }

    // Lists the key files again and selects the one at `selected`.
    mtd rebuild(selected = 0'u32)
    {
        .files.clear()
        let size = themeRowIconSize(.themeMetrics())
        for path in .paths do
            discard .files.createLine(path.toString(), .theme().fileGlyph(path.toString(), false, size))
        let empty = .paths.isEmpty()
        .empty.show(empty)
        .files.show(not empty)
        if not empty do
            .files.selectLine(Math.min(selected, cast(u32, .paths.count - 1)))
        .remove.enable(.files.selectedLine() != null)
    }

    // Adds the key files not listed yet, and selects the first one added.
    mtd addPaths(paths: Array'String)
    {
        var firstAdded = Swag.U32.Max
        for path in paths where not .hasPath(path.toString())
        {
            if firstAdded == Swag.U32.Max do
                firstAdded = cast(u32, .paths.count)
            .paths.add(path[])
        }

        if firstAdded != Swag.U32.Max
        {
            .rebuild(firstAdded)
            .sigPathsChanged.call(me)
        }
    }

    mtd chooseExisting()
    {
        with var options: FileDlgOptions
        {
            .mode  = .SelectFiles
            .title = appStrings().dlg_TitleKeyFiles
            .confirmButtonText = appStrings().dlg_BtnAdd
            .shortcuts.add({type: Env.SpecialDirectory.Desktop, name: appStrings().ui_Desktop})
            .shortcuts.add({type: Env.SpecialDirectory.UserDocuments, name: "Documents"})
        }

        let dialog = FileDlg.create(unwrap .surface, options)
        if dialog.doModal() == Dialog.BtnOk do
            .addPaths(dialog.selectedPaths())
    }

    // Writes a new random key file where the user chooses, and adds it.
    mtd generateRandom()
    {
        with var options: FileDlgOptions
        {
            .mode              = .CreateFile
            .title             = appStrings().dlg_TitleGenerateKey
            .confirmButtonText = appStrings().dlg_BtnCreate
            .initialName       = "vault.key"
            .shortcuts.add({type: Env.SpecialDirectory.Desktop, name: appStrings().ui_Desktop})
            .shortcuts.add({type: Env.SpecialDirectory.UserDocuments, name: "Documents"})
        }

        let dialog = FileDlg.create(unwrap .surface, options)
        if dialog.doModal() != Dialog.BtnOk do
            return

        var path = dialog.selectedPath()
        discard catch writeRandomKeyFile(path)
        {
            let failure = describeFailure(Swag.err)
            MessageDlg.error(.surface, failure.reason, options: {title: appStrings().msg_KeyFileCreateFailed, detail: failure.code})
            return
        }

        var generated: Array'String
        generated.add(#move path)
        .addPaths(#move generated)
    }

    // Removes the selected key file from the list; the file itself stays on disk.
    mtd removeSelected()
    {
        if .paths.isEmpty() do
            return

        let selectedLine = .files.selectedLine()
        if not selectedLine do
            return
        var selected = Swag.U32.Max
        for index in .paths.count
        {
            if .files.lineAt(cast(u32, index)) == selectedLine
            {
                selected = cast(u32, index)
                break
            }
        }

        if selected == Swag.U32.Max do
            return
        .paths.removeAtOrdered(selected)
        .rebuild(selected)
        .sigPathsChanged.call(me)
    }

}

impl KeyFileField
{
    const VisibleRows = 5

    // Creates an empty selector in `parent`. `canGenerate` offers the action that creates a random
    // key file, which only makes sense where a new access is being chosen.
    func create(parent: *Wnd, canGenerate = true)->*KeyFileField
    {
        with let result = Wnd.create'KeyFileField(parent)
        {
            .backgroundStyle = .Transparent
        }

        result.files = ListCtrl.createSimple(result)
        result.files.updateFlags(.StretchFirstColumn | .Ellipsis)
        result.empty = Label.create(result, appStrings().ui_NoKeyFiles, flags: .SecondaryText)
        result.empty.setTextAlignment(.Left, .OpticalCenter)

        with result.actions = StackLayoutCtrl.create(result, .Left)
        {
            .backgroundStyle = .Transparent
            .spacing         = result.themeMetrics().dialog_BtnPadding
        }

        with result.add = IconButton.createQuiet(result.actions, menu: false)
        {
            .setIcon(result.theme().icon(.Plus, themeRowIconSize(result.themeMetrics())))
            .sigPressed += func|field = result|(_) { field.chooseExisting() }
        }

        with result.generate = IconButton.createQuiet(result.actions, menu: false)
        {
            .show(canGenerate)
            .setIcon(result.theme().icon(.SaveAs, themeRowIconSize(result.themeMetrics())))
            .sigPressed += func|field = result|(_) { field.generateRandom() }
        }

        with result.remove = IconButton.createQuiet(result.actions, menu: false)
        {
            .setIcon(result.theme().icon(.WndClose, themeRowIconSize(result.themeMetrics())))
            .sigPressed += func|field = result|(_) { field.removeSelected() }
        }
        result.files.sigSelectionChanged += func|field = result|(list)
        {
            field.remove.enable(list.selectedLine() != null)
        }

        result.retranslate()
        return result
    }

    // Writes the action labels and empty-list sentence in the active language.
    mtd retranslate()
    {
        let texts = appStrings()
        .empty.setText(texts.ui_NoKeyFiles)
        .add.setQuietText(texts.ui_AddKeyFiles)
        .generate.setQuietText(texts.ui_GenerateKeyFile)
        .remove.setQuietText(texts.ui_RemoveKeyFile)
        .rebuild()
    }

    // Replaces the selection with a copy of `paths`, in order.
    mtd setPaths(paths: const [..] String)
    {
        .paths.clear()
        for path in paths do
            .paths.add(path[])
        .rebuild()
    }

    // Replaces `destination` with a copy of the selected paths, in order.
    mtd copyPaths(destination: *Array'String)
    {
        destination.clear()
        for path in .paths do
            destination.add(path[])
    }

    // Returns whether the selection is exactly `paths`, in the same order.
    mtd samePaths(paths: const [..] String)->bool
    {
        if .paths.count != paths.count do
            return false
        for path, index in .paths where path[] != paths[index] do
            return false
        return true
    }
}
