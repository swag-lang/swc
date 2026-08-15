#global public

using Core, Gui

// Visible strings of sViewer.
struct AppStrings
{
    ui_WindowTitle: string = "sViewer — Universal viewer"
    ui_Open:        string = "Open"
    ui_Previous:    string = "Previous file"
    ui_Next:        string = "Next file"
    ui_Viewer:      string = "Viewer"
    ui_DropTitle:   string = "Drop a file to view it"
    ui_DropHelp:    string = "Text, Markdown, HTML, images, WAV audio, and hexadecimal bytes."
    ui_Ready:       string = "Ready"
    ui_Unsupported: string = "No installed plugin can show this file."
    ui_OpenStopped: string = "The file could not be shown."
    dlg_TitleOpen:  string = "Open a file"
    dlg_ButtonOpen: string = "Open"
    dlg_AllFiles:   string = "All files"
}

private const FrenchStringsName = "lang/fr/sviewer.tweak"
private const FrenchStrings = #include("../datas/lang/fr/sviewer.tweak")

private var g_AppStrings: AppStrings

// Returns the visible strings of sViewer in the active language.
func appStrings()->const *AppStrings => &g_AppStrings

// Registers the sViewer string table and its embedded translations.
func registerAppStrings(bundle: *Core.Resources.Bundle)
{
    Gui.registerStrings'AppStrings(&g_AppStrings, "sviewer")
    bundle.addEmbedded(FrenchStringsName, FrenchStrings)
}

#run
{
    expect Gui.validateStrings'AppStrings(cast(string) FrenchStrings)
}
