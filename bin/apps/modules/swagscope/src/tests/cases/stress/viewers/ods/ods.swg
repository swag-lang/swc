#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Viewers

// Nonempty repetition cannot exceed the cell or coordinate budgets.
#[Swag.TestTag("stress")]
#test
{
    for body in ["<table:table table:name='Cells'><table:table-row table:number-rows-repeated='100001'><table:table-cell><text:p>Repeated</text:p></table:table-cell></table:table-row></table:table>", "<table:table table:name='Columns'><table:table-row><table:table-cell table:number-columns-repeated='513'><text:p>Too wide</text:p></table:table-cell></table:table-row></table:table>"]
    {
        let path = odsTestPackage(body)
        defer discard catch File.delete(path)
        var error: Swag.Error
        discard catch Ods.load(path) as error
        Swag.require(error.value() is Errors.UnsupportedFormatError)
    }
}

// Repeated text is charged before expansion, rather than allocating every copied string first.
#[Swag.TestTag("stress")]
#test
{
    var body: String = "<table:table table:name='Reading budget'><table:table-row table:number-rows-repeated='2048'><table:table-cell><text:p>"
    for 32768 do
        body += "x"
    body += "</text:p></table:table-cell></table:table-row></table:table>"
    let path = odsTestPackage(body)
    defer discard catch File.delete(path)
    var error: Swag.Error
    discard catch Ods.load(path) as error
    Swag.require(error.value() is Errors.UnsupportedFormatError)
}
