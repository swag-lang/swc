#global internal
#global namespace Viewers.Xlsx

using Core

// Defaults apply only when a cell has no explicit XF. Keep wide empty declarations sparse.
struct SheetStyleDefaults
{
    columns: [512]u32
}

impl SheetStyleDefaults
{
    func parse(source: string)->SheetStyleDefaults fail
    {
        var result: #returntype
        var scan         = Package.Scanner.create(source)
        var token:  Package.Token
        var declarations = 0_u32
        while scan.next(&token)
        {
            if token.kind != .Start or not token.isElement("col")
            {
                continue
            }

            declarations += 1
            if declarations > 16384
            {
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
            }

            let value = token.attribute("style")
            if not value
            {
                continue
            }

            let style = catch StrConv.toU32(value) { fail Errors.InvalidFormatError{texts().err_Invalid} }
            let first = catch StrConv.toU64(token.attribute("min") orelse "") orelse 0
            let last  = catch StrConv.toU64(token.attribute("max") orelse "") orelse 0
            if not first or last < first or last > 16384
            {
                fail Errors.InvalidFormatError{texts().err_Invalid}
            }

            var column = first - 1
            while column < last and column < result.columns.count
            {
                result.columns[column] = style
                column += 1
            }
        }

        if scan.damaged
        {
            fail Errors.InvalidFormatError{texts().err_Invalid}
        }

        return result
    }
}
