using Core, Pixel, Gui

const ViewerBarHeight = 52.0
const ViewerInfoHeight = 44.0
const ViewerGlyphSize = 20.0

struct ViewerInstance
{
    view:     #null *Wnd
    commands: #null *Wnd
    details:  String
}

struct ViewerWindow
{
    using wnd: Wnd

    #[Swag.Late]
    {
        commandBar:     *Wnd
        previousButton: *IconButton
        nextButton:     *IconButton
        openButton:     *IconButton
        viewerCombo:    *ComboBox
        infoBar:        *Wnd
        infoTypeLabel:  *Label
        infoNameLabel:  *Label
        infoStatsLabel: *Label
        emptyLabel:     *Label
    }

    index:           ViewerPluginIndex
    plugins:         ViewerPluginManager
    currentView:     #null *Wnd
    currentCommands: #null *Wnd
    choices:         Array'ViewerChoice
    instances:       Array'ViewerInstance
    activeChoiceIndex = Swag.U32.Max
    startupTimer:    #null *Timer
    pendingFile:     String
    currentFile:     String
    siblings:        Array'String
    siblingIndex:    u64
    siblingsDirty     = true
    fileDlgState:    FileDlgState
}

impl IWnd for ViewerWindow
{
    mtd impl onDragDropEvent(evt: *DragDropEvent)
    {
        let fileName = evt.data.singleFile()
        if !fileName
        {
            evt.accepted = false
            return
        }

        if evt.kind == .Drop do
            .openFile(fileName)
        evt.effect = pickDropEffect(evt.allowed & (DropEffect.Copy | DropEffect.Link), evt.modifiers)
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed
        {
            evt.accepted = false
            return
        }

        if evt.key == .O and evt.modifiers.has(.Control) do
            .chooseFile()
        elif evt.key == .Left and evt.modifiers == .None do
            .navigate(-1)
        elif evt.key == .Right and evt.modifiers == .None do
            .navigate(1)
        elif evt.key == .F5 and !.currentFile.isEmpty() do
            .openFile(.currentFile.toString())
        else do
            evt.accepted = false
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .startupTimer
        {
            evt.accepted = false
            return
        }

        .removeTimer(.startupTimer!)
        .startupTimer = null
        if !.pendingFile.isEmpty()
        {
            let fileName = #move .pendingFile
            .openFile(fileName.toString())
        }
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        if .startupTimer
        {
            .removeTimer(.startupTimer!)
            .startupTimer = null
        }
    }
}

impl ViewerWindow
{
    func create(parent: *Wnd, index: ViewerPluginIndex)->*ViewerWindow
    {
        let result = Wnd.create'ViewerWindow(parent, "sFileScope.main")
        result.surface!.setView(result)
        result.surface!.minSize = {640, 420}
        result.backgroundStyle  = .View
        result.index            = #move index

        Separator.create(result, .Top, .Accent)

        with result.commandBar = Wnd.create'Wnd(result, {0, 0, 0, ViewerBarHeight})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Window
            .padding         = {16, 8, 16, 8}
        }

        with result.openButton = IconButton.create(result.commandBar, result.theme().icon(.OpenFile, ViewerGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle = .Left
            .margin.z  = 16
            .toolTip   = appStrings().ui_Open
            .sigPressed += func|window = result|(button)
            {
                discard button
                window.chooseFile()
            }
        }

        with result.previousButton = IconButton.create(result.commandBar, result.theme().icon(.ChevronLeft, ViewerGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle = .Left
            .toolTip   = appStrings().ui_Previous
            .enable(false)
            .sigPressed += func|window = result|(button)
            {
                discard button
                window.navigate(-1)
            }
        }

        with result.nextButton = IconButton.create(result.commandBar, result.theme().icon(.ChevronRight, ViewerGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle = .Left
            .toolTip   = appStrings().ui_Next
            .enable(false)
            .sigPressed += func|window = result|(button)
            {
                discard button
                window.navigate(1)
            }
        }

        with result.viewerCombo = ComboBox.create(result.commandBar, {0, 0, 172, 36})
        {
            .dockStyle = .Right
            .margin.x  = 16
            .toolTip   = appStrings().ui_Viewer
            .hide()
            .sigChanged += func|window = result|(combo, index)
            {
                discard combo
                window.selectViewer(index)
            }
        }

        // File identity belongs to a quieter, persistent band of its own. Keeping it outside the
        // action bar prevents metadata from competing visually with navigation and plugin tools.
        with result.infoBar = Wnd.create'Wnd(result, {0, 0, 0, ViewerInfoHeight})
        {
            .dockStyle       = .Bottom
            .backgroundStyle = .Window
            .padding         = {18, 6, 18, 6}
        }

        with result.infoTypeLabel = Label.create(result.infoBar, "NO FILE", {0, 0, 116, 32}, null, .SecondaryText)
        {
            .dockStyle = .Left
            .style.setFont(result.theme().createDefaultFontFS(12), .Regular)
            .setTextAlignment(.Left, .Center)
        }

        with result.infoStatsLabel = Label.create(result.infoBar, appStrings().ui_Ready, {0, 0, 320, 32}, null, .SecondaryText)
        {
            .dockStyle = .Right
            .style.setFont(result.theme().createDefaultFontFS(12), .Regular)
            .setTextAlignment(.Right, .Center)
        }

        with result.infoNameLabel = Label.create(result.infoBar, "")
        {
            .dockStyle = .Center
            .style.setFont(result.theme().createDefaultFontFS(result.themeMetrics().defaultFixedFontSize), .Regular)
            .setTextAlignment(.Left, .Center)
        }

        with result.emptyLabel = Label.create(result, Format.toString("<b>%</b>\n%", appStrings().ui_DropTitle, appStrings().ui_DropHelp), {}, null, .WordWrap)
        {
            .dockStyle = .Center
            .padding   = {48, 48, 48, 48}
            .setTextAlignment(.Center, .Center)
        }

        result.applyLayout()
        return result
    }

    // Opens `fileName` after the surface has had a chance to paint its first frame.
    mtd queueFile(fileName: string)
    {
        .pendingFile = fileName
        if !.startupTimer do
            .startupTimer = .addTimer(1'ms)
    }

    mtd chooseFile()
    {
        var options: FileDlgOptions
        options.state             = &.fileDlgState
        options.mode              = .SelectFile
        options.title             = appStrings().dlg_TitleOpen
        options.confirmButtonText = appStrings().dlg_ButtonOpen
        options.filters.add({appStrings().dlg_AllFiles, "*"})

        let dialog = FileDlg.create(.surface!, options)
        if dialog.doModal() == Dialog.BtnOk do
            .openFile(dialog.selectedPath())
    }

    mtd showEmpty(message: string)
    {
        .destroyInstances()

        .emptyLabel.setText(message)
        .emptyLabel.show()
        .currentFile.clear()
        .choices.clear()
        .viewerCombo.clear()
        .viewerCombo.hide()
        .activeChoiceIndex = Swag.U32.Max
        .siblings.clear()
        .siblingsDirty = true
        .infoTypeLabel.setText("NO FILE")
        .infoNameLabel.setText("")
        .infoNameLabel.toolTip = ""
        .infoStatsLabel.setText(appStrings().ui_Ready)
        .surface!.setTitle(appStrings().ui_WindowTitle)
        .previousButton.enable(false)
        .nextButton.enable(false)
        .applyLayout()
    }

    mtd destroyInstances()
    {
        for &instance in .instances
        {
            instance.commands?.destroy()
            instance.view?.destroy()
        }

        .instances.clear()
        .currentCommands = null
        .currentView     = null
    }

    mtd activateChoice(index: u32)->bool
    {
        if index >= .choices.count do
            return false

        let choice   = &.choices[index]
        let instance = &.instances[index]
        if instance.view
        {
            .currentCommands?.hide()
            .currentView?.hide()
            .currentView     = instance.view
            .currentCommands = instance.commands
            .currentView!.show()
            .currentCommands?.show()
            .activeChoiceIndex = index
            .viewerCombo.setSelectedIndex(index, notify: false)
            .updateFileInfo(choice.name.toString(), instance.details.toString())
            .applyLayout()
            .invalidate()
            return true
        }

        var nextCommands: #null *Wnd
        var nextView:     #null *Wnd
        var nextDetails:  String
        if choice.kind == .BasicText
        {
            let basic = BasicTextView.create(me, .commandBar, .currentFile.toString())
            nextView     = basic
            nextCommands = basic.commands
            nextDetails  = "UTF-8 · streamed"
        }
        else
        {
            let spec = &.index.specs[choice.specIndex]
            nextView = catch .plugins.createView(me, .commandBar, .currentFile.toString(), spec, .index.directory.toString(), &nextCommands, &nextDetails) as pluginError
            if pluginError != null or !nextView
            {
                if nextCommands do
                    nextCommands!.destroy()
                return false
            }
        }

        .currentCommands?.hide()
        .currentView?.hide()
        .currentView            = nextView
        .currentCommands        = nextCommands
        .activeChoiceIndex      = index
        .currentView!.dockStyle = .Center
        if .currentCommands do
            .currentCommands!.dockStyle = .Right
        instance.view     = .currentView
        instance.commands = .currentCommands
        instance.details  = #move nextDetails
        .viewerCombo.setSelectedIndex(index, notify: false)
        .updateFileInfo(choice.name.toString(), instance.details.toString())
        .applyLayout()
        .invalidate()
        return true
    }

    mtd updateFileInfo(viewerName: string, details: string)
    {
        let baseName = Path.fileName(.currentFile.toString()) orelse .currentFile.toString()
        var stats    = String.from(details)
        let fileInfo = catch File.info(.currentFile.toString()) as infoError
        if infoError == null
        {
            let size = StrConv.toDisplaySize(fileInfo.size)
            stats = stats.isEmpty() ? String.from(size) : Format.toString("%  ·  %", stats, size)
        }

        .infoTypeLabel.setText(viewerName)
        .infoNameLabel.setText(baseName)
        .infoNameLabel.toolTip = .currentFile
        .infoStatsLabel.setText(stats)
        .infoStatsLabel.toolTip = stats
    }

    mtd selectViewer(index: u32)
    {
        if index == .activeChoiceIndex do
            return
        if !.activateChoice(index) and .activeChoiceIndex != Swag.U32.Max do
            .viewerCombo.setSelectedIndex(.activeChoiceIndex, notify: false)
    }

    mtd openFile(fileName: string)
    {
        if !File.exists(fileName)
        {
            .showEmpty(appStrings().ui_OpenStopped)
            return
        }

        .destroyInstances()
        var absolute = catch Path.absolute(fileName) as pathError
        if pathError != null do
            absolute = fileName
        .currentFile = #move absolute
        .choices     = .index.choices(.currentFile.toString())
        .instances.resize(.choices.count)
        .viewerCombo.clear()
        for choice in .choices do
            .viewerCombo.addItem(choice.name.toString())
        .viewerCombo.show()

        var selected = 0'u32
        if !.activateChoice(selected)
        {
            for choice, index in .choices where choice.kind == .BasicText
            {
                discard choice
                selected = cast(u32) index
                break
            }

            if !.activateChoice(selected)
            {
                .showEmpty(appStrings().ui_Unsupported)
                return
            }
        }

        .emptyLabel.hide()

        .siblingsDirty = true

        .previousButton.enable(true)
        .nextButton.enable(true)
        .applyLayout()
        .invalidate()
    }

    mtd rebuildSiblings()
    {
        .siblings.clear()
        .siblingIndex = 0
        let folder = Path.directoryName(.currentFile.toString())
        if !folder do
            return

        let files = catch Directory.enumerateFiles(folder) as listError
        if listError != null do
            return
        for file in files where !file.isDirectory() do
            .siblings.add(file.fullname)
        .siblings.sort(func(a, b) { return Utf8.compare(a.toSlice(), b.toSlice(), .Latin1NoCase) })

        for i in @countof(.siblings) where .siblings[i] == .currentFile
        {
            .siblingIndex = i
            break
        }

        .siblingsDirty = false
    }

    mtd navigate(delta: s32)
    {
        if .currentFile.isEmpty() do
            return
        if .siblingsDirty do
            .rebuildSiblings()
        if .siblings.count <= 1 do
            return

        var index = cast(s64) .siblingIndex + delta
        if index < 0 do
            index = cast(s64) .siblings.count - 1
        elif index >= cast(s64) .siblings.count do
            index = 0
        .openFile(.siblings[cast(u64) index].toString())
    }
}
