#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Viewers

// Excluded notes-page counters also consume the bounded frame budget.
#[Swag.TestTag("stress")]
#test
{
    var source: String = "<presentation:notes>"
    for 2049 do
        source += "<draw:frame presentation:class='page-number'/>"
    source += "</presentation:notes>"
    var styles: Odf.StyleCatalog
    var error:  Swag.Error
    discard catch Odp.readSpeakerNotes(source, &styles) as error
    Swag.require(error.value() is Errors.UnsupportedFormatError)
}
