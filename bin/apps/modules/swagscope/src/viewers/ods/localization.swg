#global internal
#global namespace Viewers.Ods

using Core, Gui

struct Texts
{
    ui_Name:       string = "OpenDocument Spreadsheet"
    err_Invalid:   string = "This OpenDocument spreadsheet has a damaged structure."
    err_TooLarge:  string = "This workbook is too large to open safely."
    err_Encrypted: string = "This workbook is password-protected."
}

private const FrenchStringsName = "lang/fr/scope.ods.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.ods.tweak")
private var g_Texts: Texts
func texts()->const *Texts => &g_Texts

func registerTexts(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'Texts(&g_Texts, "scope.ods")
}

#run { expect Gui.validateStrings'Texts(cast(string, FrenchStrings)) }
