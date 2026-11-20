#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// Calc's number styles survive without cached display text; raw values remain readable and omissions explicit.
#test
{
    let workbook = expect Ods.load(scopeTestDataPath("viewer.number-formats.ods"))
    Swag.require(workbook.sheets.count == 2 and workbook.cells > 40)
    Swag.require(workbook.omittedFormats == 30)

    let sheet = &workbook.sheets[0]
    Swag.require(sheet.name == "Season summary" and sheet.rowCount == 7)
    let title = unwrap sheet.cellAt({0, 0})
    Swag.require(Utf8.contains(title.text, "North Basin Monitoring"))
    let titleStyle = workbook.styles.look(title.style)
    Swag.require(titleStyle.font.bold and titleStyle.fill == 0xFF216A56)

    // Currency, percentage, date and elapsed-time cells have no cached text, so raw values remain.
    Swag.require((unwrap sheet.cellAt({2, 1})).text == "2026-05-18")
    Swag.require((unwrap sheet.cellAt({2, 2})).text == "12")
    Swag.require((unwrap sheet.cellAt({2, 3})).text == "38.25")
    Swag.require((unwrap sheet.cellAt({2, 4})).text == "0.125")
    Swag.require((unwrap sheet.cellAt({2, 5})).text == "1250.5")
    Swag.require((unwrap sheet.cellAt({2, 6})).text == "PT02H45M00S")
    Swag.require((unwrap sheet.cellAt({3, 5})).text == "-45.5")
    Swag.require((unwrap sheet.cellAt({6, 4})).text == "-0.225")
    Swag.require((unwrap sheet.cellAt({4, 5})).text == "0")
}

// Saved formatted paragraphs win over raw numbers; missing cached formulas stay explicit.
#test
{
    let path = odsTestPackage("""<table:table table:name="Everyday values"><table:table-row><table:table-cell office:value-type="currency" office:value="1234.5"><text:p>€1,234.50</text:p></table:table-cell><table:table-cell office:value-type="date" office:date-value="2026-11-15"/><table:table-cell office:value-type="boolean" office:boolean-value="true"/><table:table-cell table:formula="of:=SUM([.A1:.B1])"/><table:table-cell office:value-type="string" office:string-value="Attribute text"/><table:table-cell><text:p>Two<text:s text:c="2"/>spaces<text:line-break/>next<text:tab/>part</text:p><text:p>Last</text:p></table:table-cell></table:table-row></table:table>""")
    defer discard catch File.delete(path)
    let workbook = expect Ods.load(path)
    let sheet    = &workbook.sheets[0]
    Swag.require(sheet.cells == 6)
    Swag.require((unwrap sheet.cellAt({0, 0})).text == "€1,234.50")
    Swag.require((unwrap sheet.cellAt({0, 1})).text == "2026-11-15")
    Swag.require((unwrap sheet.cellAt({0, 2})).text == Xlsx.texts().ui_True)
    Swag.require((unwrap sheet.cellAt({0, 3})).text == "of:=SUM([.A1:.B1])")
    Swag.require((unwrap sheet.cellAt({0, 4})).text == "Attribute text")
    Swag.require((unwrap sheet.cellAt({0, 5})).text == "Two  spaces\nnext\tpart\nLast")
}

// A repeated cell resolves each column's default style; row defaults and direct styles take precedence.
#test
{
    let styles = """<styles><style name="Green" family="table-cell"><table-cell-properties background-color="#216a56"/></style><style name="Blue" family="table-cell"><table-cell-properties background-color="#234567"/></style></styles>"""
    let path   = odsTestPackage("""<table:table table:name="Defaults"><table:table-column table:default-cell-style-name="Green"/><table:table-column table:default-cell-style-name="Blue"/><table:table-row table:number-rows-repeated="2"><table:table-cell table:number-columns-repeated="2"><text:p>Repeated</text:p></table:table-cell></table:table-row><table:table-row table:default-cell-style-name="Green"><table:table-cell table:number-columns-repeated="2"><text:p>Row</text:p></table:table-cell></table:table-row><table:table-row table:default-cell-style-name="Green"><table:table-cell table:style-name="Blue"><text:p>Direct</text:p></table:table-cell></table:table-row></table:table>""", styles)
    defer discard catch File.delete(path)
    let workbook = expect Ods.load(path)
    let sheet    = &workbook.sheets[0]
    Swag.require(sheet.cells == 7 and sheet.rowCount == 4)
    Swag.require(workbook.styles.look((unwrap sheet.cellAt({0, 0})).style).fill == 0xFF216A56)
    Swag.require(workbook.styles.look((unwrap sheet.cellAt({1, 1})).style).fill == 0xFF234567)
    Swag.require(workbook.styles.look((unwrap sheet.cellAt({2, 1})).style).fill == 0xFF216A56)
    Swag.require(workbook.styles.look((unwrap sheet.cellAt({3, 0})).style).fill == 0xFF234567)
}

// A saved active sheet and hidden sheets use the usual explicit reveal and navigation.
#test
{
    let styles   = "<styles><style name='Hidden' family='table'><table-properties display='false'/></style></styles>"
    let settings = "<settings><config-item name='ActiveTable'>Notes</config-item></settings>"
    let path     = odsTestPackage("<table:table table:name='Budget'/><table:table table:name='Private' table:style-name='Hidden'/><table:table table:name='Notes'><table:table-row><table:table-cell><text:p>Welcome back</text:p></table:table-cell></table:table-row></table:table>", styles, settings)
    defer discard catch File.delete(path)
    let workbook = expect Ods.load(path)
    Swag.require(workbook.activeSheet == 2 and workbook.hiddenSheets == 1)
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, path, false)
    let panel  = assume cast(*Xlsx.Panel, window.currentView)
    Swag.require(panel.sheet == 2 and panel.visible.count == 2)
    panel.setShowHidden(true)
    Swag.require(panel.visible.count == 3)
    panel.showSheet(1)
    Swag.require(panel.sheet == 1)
}

// Huge empty repeated tails stay sparse, while a later populated row retains its real address.
#test
{
    let path = odsTestPackage("""<table:table table:name="Sparse"><table:table-column table:number-columns-repeated="16384"/><table:table-row table:number-rows-repeated="999999"><table:table-cell table:number-columns-repeated="16384"/></table:table-row><table:table-row><table:table-cell><text:p>At a million</text:p></table:table-cell><table:table-cell table:number-columns-repeated="16383"/></table:table-row><table:table-row table:number-rows-repeated="48576"><table:table-cell table:number-columns-repeated="16384"/></table:table-row></table:table>""")
    defer discard catch File.delete(path)
    let workbook = expect Ods.load(path)
    let sheet    = &workbook.sheets[0]
    Swag.require(sheet.rows.count == 1 and sheet.cells == 1 and sheet.rowCount == 1_000_000)
    Swag.require((unwrap sheet.cellAt({999999, 0})).text == "At a million")
}

// Comments and active or drawing content do not leak into saved cell text.
#test
{
    let path = odsTestPackage("""<table:table table:name="Quiet"><table:table-row><table:table-cell><text:p>Before<office:annotation><text:p>Private annotation</text:p></office:annotation>After</text:p></table:table-cell></table:table-row></table:table>""")
    defer discard catch File.delete(path)
    let workbook = expect Ods.load(path)
    Swag.require((unwrap workbook.sheets[0].cellAt({0, 0})).text == "BeforeAfter")
    Swag.require(workbook.sheets[0].simplifiedStyles)
}

// Broken structures, overlapping merges and encrypted packages fail instead of shifting cell addresses.
#test
{
    for body in ["<table:table table:name='Broken'><table:table-row>", "<table:table table:name='Overlap'><table:table-row><table:table-cell table:number-columns-spanned='2'/><table:table-cell table:number-columns-spanned='2'/></table:table-row></table:table>", "<table:table table:name='Bad repeat'><table:table-row table:number-rows-repeated='0'/></table:table>"]
    {
        let path = odsTestPackage(body)
        defer discard catch File.delete(path)
        var error: Swag.Error
        discard catch Ods.load(path) as error
        Swag.require(error.value() is Errors.InvalidFormatError)
    }

    let path = odsTestPackage("<table:table table:name='Encrypted'/>", manifest: "<manifest><encryption-data/></manifest>")
    defer discard catch File.delete(path)
    var error: Swag.Error
    discard catch Ods.load(path) as error
    Swag.require(error.value() is Errors.UnsupportedFormatError)
}

// Interior repeated hidden empty rows are compressed while trailing empty geometry stays unallocated.
#test
{
    let styles = "<styles><style name='Tall' family='table-row'><table-row-properties row-height='30pt'/></style></styles>"
    let path   = odsTestPackage("<table:table table:name='Hidden gap'><table:table-row table:visibility='collapse' table:number-rows-repeated='20'/><table:table-row><table:table-cell><text:p>After hidden rows</text:p></table:table-cell></table:table-row><table:table-row table:style-name='Tall' table:number-rows-repeated='1000000'/></table:table>", styles)
    defer discard catch File.delete(path)
    let workbook = expect Ods.load(path)
    let sheet    = &workbook.sheets[0]
    Swag.require(sheet.rows.count == 21 and sheet.rows[0].hidden and sheet.rowCount == 21 and sheet.hiddenRanges)
}

// Cell paint and inherited typography honor explicit resets without Word's toggle semantics.
#test
{
    var styles: Ods.Styles
    expect styles.read("""<styles><style name="Base" family="table-cell"><text-properties font-size="14pt" font-weight="bold" color="#216a56"/><table-cell-properties background-color="#dff1e8" border="1pt solid #216a56" vertical-align="middle" wrap-option="wrap"/></style><style name="Quiet" family="table-cell" parent-style-name="Base"><text-properties font-size="150%" font-weight="normal"/><table-cell-properties background-color="transparent" border-left="none" wrap-option="no-wrap"/></style></styles>""")
    styles.finish()
    let base  = styles.cells.look(styles.cellId("Base"))
    let quiet = styles.cells.look(styles.cellId("Quiet"))
    Swag.require(base.font.size == 14 and base.font.bold and base.fill == 0xFFDFF1E8)
    Swag.require(quiet.font.size == 21 and not quiet.font.bold and quiet.fill == 0)
    Swag.require(quiet.edges[0].width == 0 and quiet.edges[1].width > 1)
    Swag.require(not quiet.alignment.wrap and quiet.alignment.vertical == .Center)
}
