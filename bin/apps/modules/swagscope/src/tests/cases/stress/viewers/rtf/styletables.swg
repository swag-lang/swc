#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Viewers

// Large metadata cannot allocate an unbounded color or font catalog before reading the body.
#test
{
    for fontTable in [false, true]
    {
        var source: String
        for fontTable ? 1025 : 4097 do
            source += fontTable ? "{\\f0 Font;}" : ";"
        source += "}"
        var error: Swag.Error
        discard catch Rtf.Catalog.parse(source.toSlice(), 0, 2, fontTable) as error
        Swag.require(error.value() is Errors.UnsupportedFormatError)
    }
}
