#global internal

using Core, Gui

// Each panel edits a real module-configuration fragment independently of the shared program.
struct BuildOptions
{
    using wnd: Wnd

    late
    {
        presetCombo: *ComboBox
        resetButton: *IconButton
        editor:      *RichEditCtrl
    }

    lexer:      RichEditLexerSwag
    sigChanged: SigArray'func||(*BuildOptions)
    sigReset:   SigArray'func||(*BuildOptions)
}

impl BuildOptions
{
    func create(parent: *Wnd)->*BuildOptions
    {
        let result = Wnd.create'BuildOptions(parent)
        result.backgroundStyle = .Transparent
        let bar = Wnd.create'Wnd(result, {0, 0, 0, 36})
        bar.dockStyle                = .Top
        bar.margin                   = {0, 0, 0, 8}
        result.resetButton           = IconButton.create(bar, result.theme().icon(.Undo, 18), {0, 0, 36, 36})
        result.resetButton.dockStyle = .Right
        result.resetButton.margin    = {8, 0, 0, 0}
        result.resetButton.setIconSize(18, 18)
        result.presetCombo = ComboBox.create(bar)
        result.presetCombo.dockStyle = .Center
        result.presetCombo.addItem("release")
        result.presetCombo.addItem("devmode")
        result.presetCombo.setSelectedIndex(0, notify: false)
        result.editor = RichEditCtrl.create(result)
        result.editor.dockStyle = .Center
        result.editor.setLexer(&result.lexer)
        result.editor.setText(Pipeline.BuildSettings.DefaultConfiguration)
        result.editor.sigChanged += func|options = result|(editor)
        {
            discard editor
            options.sigChanged.call(options)
        }

        result.presetCombo.sigChanged += func|options = result|(combo, index)
        {
            discard combo
            discard index
            options.sigChanged.call(options)
        }

        result.resetButton.sigPressed += func|options = result|(button)
        {
            discard button
            options.reset()
        }

        result.retranslate()
        return result
    }

    mtd settings(level: Swag.BuildCfgBackendOptimLevel)->Pipeline.BuildSettings
    {
        return {preset: cast(Pipeline.BuildPreset) .presetCombo.selectedIndex, optimization: level, configuration: .editor.text()}
    }

    mtd reset()
    {
        .presetCombo.setSelectedIndex(0, notify: false)
        .editor.setText(Pipeline.BuildSettings.DefaultConfiguration)
        .sigReset.call(me)
    }

    mtd retranslate()
    {
        .presetCombo.toolTip = appStrings().ui_BuildPreset
        .resetButton.toolTip = appStrings().ui_ResetBuild
    }
}

impl IWnd for BuildOptions
{
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        elif evt.kind == .ThemeChanged do
            .resetButton.setIcon(.theme().icon(.Undo, 18))
        .wnd.IWnd.onNotifyEvent(evt)
    }
}
