#global internal
#global namespace Viewers.Xlsx

using Core, Gui

struct Texts
{
    ui_Name:       string = "Workbook"
    ui_Preparing:  string = "Preparing workbook…"
    ui_Details:    string = "Workbook · % sheets · % cells"
    ui_True:       string = "TRUE"
    ui_False:      string = "FALSE"
    err_Invalid:   string = "This workbook has a damaged structure."
    err_TooLarge:  string = "This workbook is too large to open safely."
}

private const FrenchStringsName = "lang/fr/scope.xlsx.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.xlsx.tweak")

private var g_Texts: Texts

func texts()->const *Texts => &g_Texts

func registerTexts(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'Texts(&g_Texts, "scope.xlsx")
}

#run
{
    expect Gui.validateStrings'Texts(cast(string, FrenchStrings))
}
