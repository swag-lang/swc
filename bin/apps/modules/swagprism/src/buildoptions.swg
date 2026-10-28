#global internal

using Core, Gui

/*
The build configuration of one panel: the preset it starts from and a real module-configuration
fragment the reader edits, independently of the shared program.

The page takes the place of the panel's viewer; the panel's header names it and carries its preset
menu and its actions.
*/
struct BuildOptions
{
    using wnd: Wnd

    late editor: *RichEditCtrl

    preset:     Pipeline.BuildPreset
    lexer:      RichEditLexerSwag
    sigChanged: SigArray'func||(*Wnd)
    sigReset:   SigArray'func||(*Wnd)
}

impl BuildOptions
{
    // The names of the presets, in the order of `Pipeline.BuildPreset`. They name the compiler's
    // build configurations, which are never translated.
    const PresetNames = ["release", "devmode"]

    // Builds the editor of the build configuration.
    func create(parent: *Wnd)->*BuildOptions
    {
        let result = Wnd.create'BuildOptions(parent)
        result.backgroundStyle = .Transparent
        with result.editor = RichEditCtrl.create(result)
        {
            .dockStyle   = .Center
            .lineSpacing = ListingView.LineSpacing
            .setFlags(.LineNumbers)
            .setLexer(&result.lexer)
            .setText(Pipeline.BuildSettings.DefaultConfiguration)
            .sigChanged += func|options = result|(_) { options.sigChanged.call(options) }
        }

        return result
    }

    mtd settings(level: Swag.Build.BackendOptimLevel)->Pipeline.BuildSettings =>
    {
        preset: .preset,
        optimization: level,
        configuration: .editor.text()}

    // Starts from `preset`, telling the panel when `notify` asks.
    mtd setPreset(preset: Pipeline.BuildPreset, notify = true)
    {
        .preset = preset
        if notify do
            .sigChanged.call(me)
    }

    // Restores the first preset and the default configuration.
    mtd reset()
    {
        .preset = .Release
        .editor.setText(Pipeline.BuildSettings.DefaultConfiguration)
        .sigReset.call(me)
    }
}
