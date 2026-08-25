using Core, Gui

// Compact selector for the ordered key files that participate in one vault access.
//
// The combo box exposes the complete list without making the form as tall as it. The three
// adjacent icon actions add existing files, create a random one, and remove the selected entry;
// their tooltips carry the wording so the row stays one line high in every language.
struct KeyFileField
{
    using wnd: Wnd

    #[Swag.Late]
    {
        files:    *ComboBox
        add:      *IconButton
        generate: *IconButton
        remove:   *IconButton
    }

    paths: Array'String
}

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
    mtd impl measureContent(available: Math.Point)->Math.Point
    {
        discard available
        return {0, .themeMetrics().comboBox_Height}
    }

    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        discard evt
        if !@isset(.remove) do
            return
        let room = .clientRect()
        let gap  = .themeMetrics().dialog_BtnPadding
        let cell = room.height

        var right = room.right()
        for button in [cast(*Wnd) .remove, cast(*Wnd) .generate, cast(*Wnd) .add]
        {
            right -= cell
            button.arrange({right, room.y, cell, cell})
            right -= gap
        }

        .files.arrange({room.x, room.y, Math.max(0, right - room.x), room.height})
    }
}

private impl KeyFileField
{
    mtd hasPath(path: string)->bool
    {
        for &one in .paths where Path.equals(one.toString(), path) do
            return true
        return false
    }

    mtd rebuild(selected = 0'u32)
    {
        .files.clear()
        if .paths.isEmpty()
        {
            .files.addItem(appStrings().ui_NoKeyFiles)
            .files.setSelectedIndex(0, notify: false)
            .files.enable(false)
            .remove.enable(false)
            return
        }

        for &path in .paths do
            .files.addItem(path.toString())
        .files.enable(true)
        .files.setSelectedIndex(Math.min(selected, cast(u32) (.paths.count - 1)), notify: false)
        .remove.enable(true)
    }

    mtd addPaths(paths: Array'String)
    {
        var firstAdded = Swag.U32.Max
        for &path in paths
        {
            if .hasPath(path.toString()) do
                continue
            if firstAdded == Swag.U32.Max do
                firstAdded = cast(u32) .paths.count
            .paths.add(String.from(path.toString()))
        }

        if firstAdded != Swag.U32.Max do
            .rebuild(firstAdded)
    }

    mtd chooseExisting()
    {
        var options: FileDlgOptions
        options.mode              = .SelectFiles
        options.title             = appStrings().dlg_TitleKeyFiles
        options.confirmButtonText = appStrings().dlg_BtnAdd
        options.shortcuts.add({Env.SpecialDirectory.Desktop, appStrings().ui_Desktop})
        options.shortcuts.add({Env.SpecialDirectory.UserDocuments, "Documents"})

        let dialog = FileDlg.create(.surface!, options)
        if dialog.doModal() == Dialog.BtnOk do
            .addPaths(dialog.selectedPaths())
    }

    mtd generateRandom()
    {
        var options: FileDlgOptions
        options.mode              = .CreateFile
        options.title             = appStrings().dlg_TitleGenerateKey
        options.confirmButtonText = appStrings().dlg_BtnCreate
        options.initialName       = "vault.key"
        options.shortcuts.add({Env.SpecialDirectory.Desktop, appStrings().ui_Desktop})
        options.shortcuts.add({Env.SpecialDirectory.UserDocuments, "Documents"})

        let dialog = FileDlg.create(.surface!, options)
        if dialog.doModal() != Dialog.BtnOk do
            return

        var path = dialog.selectedPath()
        discard catch writeRandomKeyFile(path.toString()) as generationError
        if generationError != null
        {
            MessageDlg.error(.surface!, appStrings().msg_KeyFileCreateFailed, generationError)
            return
        }

        var generated: Array'String
        generated.add(#move path)
        .addPaths(#move generated)
    }

    mtd removeSelected()
    {
        if .paths.isEmpty() or .files.selectedIndex >= .paths.count do
            return

        let selected = .files.selectedIndex
        .paths.removeAtOrdered(selected)
        .rebuild(selected)
    }
}

impl KeyFileField
{
    func create(parent: *Wnd)->*KeyFileField
    {
        let result = Wnd.create'KeyFileField(parent)
        result.backgroundStyle = .Transparent

        result.files = ComboBox.create(result)
        setMachineFont(result.files)

        with result.add = IconButton.create(result, result.theme().icon(.OpenFile, 16), flags: .IconOnly)
        {
            .sigPressed += func|field = result|(button)
            {
                discard button
                field.chooseExisting()
            }
        }

        with result.generate = IconButton.create(result, result.theme().icon(.SaveAs, 16), flags: .IconOnly)
        {
            .sigPressed += func|field = result|(button)
            {
                discard button
                field.generateRandom()
            }
        }

        with result.remove = IconButton.create(result, result.theme().icon(.Remove, 16), flags: .IconOnly)
        {
            .sigPressed += func|field = result|(button)
            {
                discard button
                field.removeSelected()
            }
        }

        result.retranslate()
        result.rebuild()
        return result
    }

    mtd retranslate()
    {
        let texts = appStrings()
        .add.toolTip      = texts.ui_AddKeyFiles
        .generate.toolTip = texts.ui_GenerateKeyFile
        .remove.toolTip   = texts.ui_RemoveKeyFile
        if .paths.isEmpty() do
            .rebuild()
    }

    mtd setPaths(paths: const [..] String)
    {
        .paths.clear()
        for &path in paths do
            .paths.add(String.from(path.toString()))
        .rebuild()
    }

    mtd copyPaths(destination: *Array'String)
    {
        destination.clear()
        for &path in .paths do
            destination.add(String.from(path.toString()))
    }

    mtd samePaths(paths: const [..] String)->bool
    {
        if .paths.count != @countof(paths) do
            return false
        for &path, index in .paths where path.toString() != paths[index].toString() do
            return false
        return true
    }
}
