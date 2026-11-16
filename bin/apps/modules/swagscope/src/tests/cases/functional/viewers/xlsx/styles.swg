#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// Relationship-resolved styles and theme colors retain the character of an authored worksheet.
#test
{
    let workbook = expect Xlsx.Workbook.load(scopeTestDataPath("viewer.styles.xlsx"))
    Swag.require(not workbook.sheets[0].simplifiedStyles and not workbook.sheets[0].showGridLines)
    let title  = workbook.styles.look(2)
    let header = workbook.styles.look(3)
    let note   = workbook.styles.look(5)
    Swag.require(title.font.size == 22 and title.font.bold and title.font.color != 0xFF000000)
    Swag.require(header.font.color == 0xFFFFFFFF and header.fill == 0xFF216A56)
    Swag.require(note.alignment.wrap and note.alignment.indent == 1 and note.font.italic)
    Swag.require(workbook.styles.look(4).edges[2].width == 2 and workbook.styles.look(4).fill == 0xFFDFF1E8)
    Swag.require(workbook.styles.look(7).font.bold and workbook.styles.look(7).font.size == 22)
    Swag.require(workbook.sheets[0].cellAt({11, 3})!.text == "$1,327.80")
}

// XF apply switches inherit base components; direct font and zero alignment values reset them.
#test
{
    let theme     = Package.OfficeTheme.defaults()
    let source    = "<styleSheet><fonts><font><b val='0'/><sz val='11'/></font><font><b/><sz val='20'/></font></fonts><fills><fill/><fill><patternFill patternType='solid'><fgColor rgb='FF102030'/></patternFill></fill></fills><borders><border/><border><bottom style='double'><color indexed='2'/></bottom></border></borders><cellStyleXfs><xf fontId='1' fillId='1' borderId='1'><alignment horizontal='right' vertical='top' wrapText='1' indent='2'/></xf></cellStyleXfs><cellXfs><xf xfId='0' fontId='0' fillId='0' borderId='0' applyFont='0' applyFill='0' applyBorder='0' applyAlignment='0'><alignment wrapText='0'/></xf><xf xfId='0' fontId='0' fillId='0' borderId='0'><alignment horizontal='left' wrapText='0' indent='0'/></xf></cellXfs></styleSheet>"
    let styles    = expect Xlsx.CellStyles.parse(source, &theme)
    let inherited = styles.look(0)
    let direct    = styles.look(1)
    Swag.require(inherited.font.bold and inherited.font.size == 20 and inherited.fill == 0xFF102030)
    Swag.require(inherited.edges[3].doubleLine and inherited.edges[3].color == 0xFFFF0000)
    Swag.require(inherited.alignment.wrap and
                 inherited.alignment.indent == 2 and
                 inherited.alignment.horizontal == .Right)
    Swag.require(not direct.font.bold and direct.font.size == 11 and direct.fill == 0 and not direct.hasBorder())
    Swag.require(not direct.alignment.wrap and
                 direct.alignment.indent == 0 and
                 direct.alignment.horizontal == .Left)
}

// Spreadsheet themes, indexed palettes and luminance tints resolve to bounded opaque colors.
#test
{
    var theme = Package.OfficeTheme.defaults()
    theme.colors[4] = "216A56"
    let colors = expect Xlsx.CellColors.parse("<styleSheet><colors><indexedColors><rgbColor rgb='FF123456'/></indexedColors></colors></styleSheet>", &theme)
    struct Case {source: string; color: u32}
    for test in [Case{"<color theme='0'/>", 0xFFFFFFFF}, Case{"<color theme='1'/>", 0xFF000000},
                 Case{"<color theme='4'/>", 0xFF216A56}, Case{"<color indexed='0'/>", 0xFF123456},
                 Case{"<color indexed='2'/>", 0xFFFF0000}, Case{"<color rgb='FF000000' tint='0.5'/>", 0xFF808080}]
    {
        var scan = Package.Scanner.create(test.source)
        var token: Package.Token
        Swag.require(scan.next(&token))
        let color = colors.color(&token)
        Swag.require(color.valid and color.argb == test.color)
    }
}

// Unsupported visual effects keep the cell value and name their simplified presentation.
#test
{
    let path = formattedWorkbookVariant("xl/styles/book.xml", "<xf numFmtId=\"164\"/>", "<xf numFmtId=\"164\" fontId=\"999\"><alignment textRotation=\"45\"/></xf>")
    defer discard catch File.delete(path)
    let workbook = expect Xlsx.Workbook.load(path)
    Swag.require(workbook.sheets[0].simplifiedStyles and workbook.sheets[0].cellAt({1, 1})!.text == "$1,250.50")
    Swag.require(Utf8.contains(workbook.sheets[0].details(), Xlsx.texts().ui_StylesSimplified))
}

// The Normal font is identified by the built-in named style, independently of cell XF order.
#test
{
    let theme  = Package.OfficeTheme.defaults()
    let source = "<styleSheet><fonts><font><sz val='24'/></font><font><sz val='9'/></font></fonts><cellStyleXfs><xf fontId='0'/><xf fontId='1'/></cellStyleXfs><cellXfs><xf fontId='0'/></cellXfs><cellStyles><cellStyle name='Normal' builtinId='0' xfId='1'/></cellStyles></styleSheet>"
    let styles = expect Xlsx.CellStyles.parse(source, &theme)
    Swag.require(styles.look(0).font.size == 24 and styles.normalFont.size == 9)
}
