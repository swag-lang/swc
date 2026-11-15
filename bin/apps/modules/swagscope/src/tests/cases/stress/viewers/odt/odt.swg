#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Viewers

// Repetition and explicit spaces cannot expand a tiny document beyond the reading budgets.
#[Swag.TestTag("stress")]
#test
{
    for source in ["<table:table><table:table-row table:number-rows-repeated='513'><table:table-cell><text:p>Repeated</text:p></table:table-cell></table:table-row></table:table>", "<text:p><text:s text:c='8193'/></text:p>"]
    {
        let path = odtTestPackage(source)
        defer discard catch File.delete(path)
        var error: Swag.Error
        discard catch Odt.Document.load(path) as error
        Swag.require(error.value() is Errors.UnsupportedFormatError)
    }
}
