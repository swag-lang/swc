#global private

// '#raw' is a modifier on the string literal that follows: the content is taken verbatim.
// It composes with both delimiters, so '"""' is what a raw literal uses when the text
// itself contains a quote.

#test
{
    // No escape sequence is recognized.
    #assert(#raw "\n" == "\\n")
    #assert(#raw "\t" == "\\t")
    #assert(#raw "\u2F46" == "\\u2F46")
    #assert(#raw "C:\path\to\file" == "C:\\path\\to\\file")
    #assert(#raw "regex: \d+\.\d+" == "regex: \\d+\\.\\d+")
}

#test
{
    // A backslash never hides the closing quote in a raw literal.
    #assert(#raw "ends with a backslash \" == "ends with a backslash \\")
    #assert(@countof(#raw "\\") == 2)
}

#test
{
    // The triple delimiter carries text that contains quotes.
    #assert(#raw """say "hello" twice""" == "say \"hello\" twice")
    #assert(#raw """{"key": "value"}""" == "{\"key\": \"value\"}")
    #assert(#raw """a "" b""" == "a \"\" b")
}

// A raw literal spans several lines with the triple delimiter, and re-indentation still
// applies: that is layout, not escaping.
const RawBlock = #raw """line1
                         line2
                         line3"""

#test
{
    #assert(RawBlock == "line1\nline2\nline3")
}

// An escaped end-of-line is an escape, so a raw literal keeps the line break.
const RawKeepsEol = #raw """a\
b"""

const CookedFoldsEol = """a\
b"""

#test
{
    #assert(RawKeepsEol == "a\\\nb")
    #assert(CookedFoldsEol == "ab")
}

#test
{
    // An empty raw literal, and one holding only blanks.
    #assert(#raw "" == "")
    #assert(#raw " " == " ")
    #assert(@countof(#raw """ """) == 1)
}

#test
{
    // '#raw' is a compile-time reading rule, so the value is an ordinary string afterwards.
    let pattern = #raw "(\d+)x(\d+)"
    @assert(pattern == "(\\d+)x(\\d+)")
    @assert(@countof(pattern) == 11)

    var acc = 0
    for c in pattern
    {
        if c == '\\'u8 do
            acc += 1
    }

    @assert(acc == 2)
}
