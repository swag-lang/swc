#global internal
#global namespace Viewers.Xlsx

using Core

private struct CustomNumberFormat
{
    id:     u32
    format: NumberFormat
}

// Resolves a cell's style index to its authored numeric display format.
struct CellFormats
{
    custom:   Array'CustomNumberFormat
    styles:   Array'u32
    date1904: bool
}

impl CellFormats
{
    func parse(source: string, date1904 = false)->CellFormats fail
    {
        var result: #returntype = {date1904: date1904}
        var scan     = Package.Scanner.create(source)
        var token:  Package.Token
        var inStyles = false
        var inBases  = false
        var bases:  Array'u32
        while scan.next(&token)
        {
            if token.kind == .Start
            {
                if token.isElement("numFmt")
                {
                    let id   = catch StrConv.toU32(token.attribute("numFmtId") orelse "") { fail Errors.InvalidFormatError{texts().err_Invalid} }
                    let code = token.attribute("formatCode") orelse ""
                    if code.count > 512 or result.custom.count >= 4096 do
                        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                    result.custom.add(CustomNumberFormat{id, NumberFormat{String.from(code)}})
                }
                elif token.isElement("cellXfs")
                {
                    inStyles = not token.empty
                }
                elif token.isElement("cellStyleXfs")
                {
                    inBases = not token.empty
                }
                elif token.isElement("xf") and (inStyles or inBases)
                {
                    let id = catch StrConv.toU32(token.attribute("numFmtId") orelse "0") { fail Errors.InvalidFormatError{texts().err_Invalid} }
                    if inBases
                    {
                        bases.add(id)
                    }
                    else
                    {
                        var effective = id
                        if token.attribute("applyNumberFormat") == "0" or token.attribute("numFmtId") == null
                        {
                            let parent = catch StrConv.toU64(token.attribute("xfId") orelse "0") orelse Swag.U64.Max
                            if parent < bases.count do
                                effective = bases[parent]
                        }

                        result.styles.add(effective)
                    }

                    if bases.count > 65536 or result.styles.count > 65536 do
                        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                }
            }
            elif token.kind == .End
            {
                if token.isElement("cellXfs") do
                    inStyles = false
                elif token.isElement("cellStyleXfs") do
                    inBases = false
            }
        }

        if scan.damaged do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        return result
    }

    mtd const format(value: string, style: u32)->FormattedCell fail
    {
        if .styles.isEmpty() and style == 0 do
            return FormattedCell{String.from(value)}
        if style >= .styles.count do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        let id = .styles[style]
        for custom in .custom where custom.id == id do
            return custom.format.format(value, .date1904)
        return NumberFormat.builtIn(id).format(value, .date1904)
    }
}
