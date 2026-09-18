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

        with let bar = Wnd.create'Wnd(result, {0, 0, 0, 36})
        {
            .dockStyle = .Top
            .margin    = {0, 0, 0, 8}
        }

        with result.resetButton = IconButton.create(bar, result.theme().icon(.Undo, 18), {0, 0, 36, 36})
        {
            .dockStyle = .Right
            .margin    = {8, 0, 0, 0}
            .setIconSize(18, 18)
            .sigPressed += func|options = result|(button)
            {
                discard button
                options.reset()
            }
        }

        // The entries follow the order of `Pipeline.BuildPreset`, and name the compiler's build
        // configurations, which are never translated.
        with result.presetCombo = ComboBox.create(bar)
        {
            .dockStyle = .Center
            .addItem("release")
            .addItem("devmode")
            .setSelectedIndex(0, notify: false)
            .sigChanged += func|options = result|(combo, index)
            {
                discard combo
                discard index
                options.sigChanged.call(options)
            }
        }

        with result.editor = RichEditCtrl.create(result)
        {
            .dockStyle = .Center
            .setLexer(&result.lexer)
            .setText(Pipeline.BuildSettings.DefaultConfiguration)
            .sigChanged += func|options = result|(editor)
            {
                discard editor
                options.sigChanged.call(options)
            }
        }

        result.retranslate()
        return result
    }

    mtd settings(level: Swag.BuildCfgBackendOptimLevel)->Pipeline.BuildSettings => {preset: cast(Pipeline.BuildPreset) .presetCombo.selectedIndex, optimization: level, configuration: .editor.text()}

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
