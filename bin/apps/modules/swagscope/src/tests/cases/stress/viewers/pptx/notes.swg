#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Viewers

// Even excluded notes-page shapes consume the bounded scan budget.
#[Swag.TestTag("stress")]
#test
{
    var source: String = "<p:notes>"
    for 2049 do
        source += "<p:sp><p:nvSpPr><p:nvPr><p:ph type='ftr'/></p:nvPr></p:nvSpPr></p:sp>"
    source += "</p:notes>"
    var theme = Pptx.SlideTheme.defaults()
    var error: Swag.Error
    discard catch Pptx.readSpeakerNotes(source, &theme) as error
    Swag.require(error.value() is Errors.UnsupportedFormatError)
}

// A single notes body cannot retain arbitrarily much speaker prose.
#[Swag.TestTag("stress")]
#test
{
    var prose: String
    for 1025 do
        prose += "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    for 4 do
        prose += prose
    var source: String = "<p:notes><p:sp><p:txBody><a:p><a:r><a:t>"
    source += prose
    source += "</a:t></a:r></a:p></p:txBody></p:sp></p:notes>"
    var theme = Pptx.SlideTheme.defaults()
    var error: Swag.Error
    discard catch Pptx.readSpeakerNotes(source, &theme) as error
    Swag.require(error.value() is Errors.UnsupportedFormatError)
}
