#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Viewers

// Unused metadata still has a fixed allocation bound before any worksheet can be painted.
#test
{
    let theme = Package.OfficeTheme.defaults()
    for table in ["fonts", "fills", "borders"]
    {
        var source = Format.toString("<styleSheet><%>", table)
        let item = table == "fonts" ? "<font/>" : table == "fills" ? "<fill/>" : "<border/>"
        for 4097 do source += item
        source += Format.toString("</%></styleSheet>", table)
        var error: Swag.Error
        discard catch Xlsx.CellStyles.parse(source, &theme) as error
        Swag.require(error.value() is Errors.UnsupportedFormatError)
    }
}
