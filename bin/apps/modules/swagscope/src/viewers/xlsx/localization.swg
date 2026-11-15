#global internal
#global namespace Viewers.Xlsx

using Core, Gui

struct Texts
{
    ui_Grid:               string = "Show Worksheet Grid"
    ui_ReadText:           string = "Read Worksheet as Text"
    ui_CopyCell:           string = "Copy Cell Value"
    ui_HiddenRanges:       string = "Show Hidden Rows and Columns"
    ui_Name:               string = "Workbook"
    ui_Previous:           string = "Previous Sheet"
    ui_Next:               string = "Next Sheet"
    ui_ShowHidden:         string = "Show Hidden Sheets"
    ui_Hidden:             string = "% (hidden)"
    ui_AllHidden:          string = "All sheets in this workbook are hidden."
    ui_Cell:               string = "% · % cell"
    ui_Cells:              string = "% · % cells"
    ui_Preparing:          string = "Preparing workbook…"
    ui_Details:            string = "Workbook · % sheets · % cells"
    ui_FormatsOmitted:     string = " · % number formats not shown"
    ui_FormatNotice:       string = "Some cells use number formats this viewer cannot show; their stored values are displayed."
    ui_True:               string = "TRUE"
    ui_False:              string = "FALSE"
    ui_FormulaUnavailable: string = "[Formula result unavailable]"
    err_Invalid:           string = "This workbook has a damaged structure."
    err_TooLarge:          string = "This workbook is too large to open safely."
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
