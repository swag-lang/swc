#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Viewers

// Page and shape counts remain bounded even for tiny repeated object payloads.
#[Swag.TestTag("stress")]
#test
{
    var pages: String
    for 201 do
        pages += "<draw:page draw:name='Page'/>"
    var shapes: String = "<draw:page draw:name='Shapes'>"
    for 2049 do
        shapes += "<draw:rect svg:x='0in' svg:y='0in' svg:width='1in' svg:height='1in'/>"
    shapes += "</draw:page>"
    for body in [pages, shapes]
    {
        let path = odpTestPackage(body.toString())
        defer discard catch File.delete(path)
        var error: Swag.Error
        discard catch Odp.load(path) as error
        Swag.require(error.value() is Errors.UnsupportedFormatError)
    }
}
