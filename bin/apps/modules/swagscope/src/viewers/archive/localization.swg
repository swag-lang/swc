#global internal

using Core, Gui

struct ArchiveStrings
{
    ui_Name:              string = "Archive"
    ui_ColName:           string = "Name"
    ui_ColSize:           string = "Size"
    ui_Empty:             string = "This archive contains no files."
    ui_Select:            string = "Select a file to preview it."
    ui_Previewing:        string = "Preparing preview…"
    ui_PreviewError:      string = "This entry cannot be previewed."
    ui_Details:           string = "% entries · % unpacked · % packed"
    ui_SearchPlaceholder: string = "Filter archive entries"
}

private const FrenchArchiveStringsName = "lang/fr/scope.archive.tweak"
private const FrenchArchiveStrings     = #include("../../../datas/lang/fr/scope.archive.tweak")

private var g_ArchiveStrings: ArchiveStrings

func archiveStrings()->const *ArchiveStrings => &g_ArchiveStrings

func registerArchiveStrings(app: *Application)
{
    app.resources.addEmbedded(FrenchArchiveStringsName, FrenchArchiveStrings)
    Gui.registerStrings'ArchiveStrings(&g_ArchiveStrings, "scope.archive")
}

#run
{
    expect Gui.validateStrings'ArchiveStrings(cast(string) FrenchArchiveStrings)
}
