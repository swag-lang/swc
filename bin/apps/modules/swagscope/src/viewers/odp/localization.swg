#global internal
#global namespace Viewers.Odp

using Core, Gui

struct Texts
{
    ui_Name:          string = "OpenDocument Presentation"
    ui_Hidden:        string = "% (hidden)"
    ui_ObjectOmitted: string = "[Drawing or embedded content not shown]"
    err_Invalid:      string = "This OpenDocument presentation has a damaged structure."
    err_TooLarge:     string = "This presentation is too large to open safely."
    err_Encrypted:    string = "This presentation is password-protected."
}

private const FrenchStringsName = "lang/fr/scope.odp.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.odp.tweak")
private var g_Texts: Texts
func texts()->const *Texts => &g_Texts

func registerTexts(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'Texts(&g_Texts, "scope.odp")
}

#run { expect Gui.validateStrings'Texts(cast(string, FrenchStrings)) }
