#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Viewers

// Repeated column defaults stop at the worksheet declaration budget even outside the visible grid.
#[Swag.TestTag("stress")]
#test
{
    var source: String = "<cols>"
    for 16385 do
        source += "<col min='16384' max='16384' style='1'/>"
    source += "</cols>"
    var error: Swag.Error
    discard catch Xlsx.SheetStyleDefaults.parse(source) as error
    Swag.require(error.value() is Errors.UnsupportedFormatError)
}
