#global internal
#global namespace Viewers.Notebook

using Core, Gui

struct Texts
{
    ui_Search:    string = "Search cells and outputs"
    ui_SearchTip: string = "Search visible cell source and plain-text outputs. Prefix with source: or output: to choose one."
}

private const FrenchStringsName = "lang/fr/scope.notebook.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.notebook.tweak")
private var g_Texts: Texts

#run
{
    expect Gui.validateStrings'Texts(cast(string, FrenchStrings))
}

func texts()->const *Texts => &g_Texts

func registerTexts(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'Texts(&g_Texts, "scope.notebook")
}
