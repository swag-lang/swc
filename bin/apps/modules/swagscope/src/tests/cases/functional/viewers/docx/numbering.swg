#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Viewers

// Word decimal, alphabetic and Roman numbering levels map to ordered HTML lists.
#test
{
    let source    = """<w:numbering>
        <w:abstractNum w:abstractNumId="0">
            <w:lvl w:ilvl="0"><w:start w:val="3"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/></w:lvl>
            <w:lvl w:ilvl="1"><w:numFmt w:val="lowerLetter"/><w:lvlText w:val="%2)"/></w:lvl>
            <w:lvl w:ilvl="2"><w:numFmt w:val="upperRoman"/><w:lvlText w:val="%3."/></w:lvl>
        </w:abstractNum>
        <w:num w:numId="7"><w:abstractNumId w:val="0"/></w:num>
    </w:numbering>"""
    let numbering = expect Docx.NumberingCatalog.parse(source)
    let decimal   = numbering.lookup("7", 0)
    let letters   = numbering.lookup("7", 1)
    let roman     = numbering.lookup("7", 2)
    Swag.require(not decimal.limited and decimal.tag == "ol" and decimal.type == "1" and decimal.start == 3)
    Swag.require(not letters.limited and letters.tag == "ol" and letters.type == "a")
    Swag.require(not roman.limited and roman.tag == "ol" and roman.type == "I")
}

// Word bullet levels retain their common marker shape without trusting custom markup.
#test
{
    let source    = """<numbering>
        <abstractNum abstractNumId="4">
            <lvl ilvl="0"><numFmt val="bullet"/><lvlText val="▪"/></lvl>
            <lvl ilvl="1"><numFmt val="bullet"/><lvlText val="o"/></lvl>
            <lvl ilvl="2"><numFmt val="bullet"/><lvlText val="◆"/></lvl>
        </abstractNum>
        <num numId="2"><abstractNumId val="4"/></num>
    </numbering>"""
    let numbering = expect Docx.NumberingCatalog.parse(source)
    let square    = numbering.lookup("2", 0)
    let circle    = numbering.lookup("2", 1)
    let custom    = numbering.lookup("2", 2)
    Swag.require(not square.limited and square.tag == "ul" and square.type == "square")
    Swag.require(not circle.limited and circle.tag == "ul" and circle.type == "circle")
    Swag.require(custom.limited and custom.tag == "ul" and custom.type == "disc")
}

// Unknown numbering references and formats are reported for the caller to disclose.
#test
{
    let numbering   = expect Docx.NumberingCatalog.parse("""<numbering>
        <abstractNum abstractNumId="1"><lvl ilvl="0"><numFmt val="chicago"/></lvl></abstractNum>
        <num numId="5"><abstractNumId val="1"/></num>
    </numbering>""")
    let unsupported = numbering.lookup("5", 0)
    let missing     = numbering.lookup("99", 0)
    Swag.require(unsupported.limited and unsupported.tag == "ol" and unsupported.type == "1")
    Swag.require(missing.limited)
}

// Malformed levels are rejected instead of silently changing list meaning.
#test
{
    var error: Swag.Error
    discard catch Docx.NumberingCatalog.parse("<numbering><abstractNum abstractNumId=\"1\"><lvl ilvl=\"9\"/></abstractNum></numbering>") as error
    Swag.require(error.value() is Errors.InvalidFormatError)
}

// Duplicate numbering IDs are rejected instead of making list references ambiguous.
#test
{
    var error: Swag.Error
    discard catch Docx.NumberingCatalog.parse("""<numbering>
        <abstractNum abstractNumId="1"><lvl ilvl="0"><numFmt val="decimal"/></lvl></abstractNum>
        <abstractNum abstractNumId="1"><lvl ilvl="0"><numFmt val="bullet"/></lvl></abstractNum>
    </numbering>""") as error
    Swag.require(error.value() is Errors.InvalidFormatError)
}
