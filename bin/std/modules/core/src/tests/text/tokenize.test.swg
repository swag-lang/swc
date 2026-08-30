#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertStringArray(values: Array'(string), expected: const [..] string)->bool
{
    if values.count != expected.count do
        return false

    for i in values.count
    {
        if values[i] != expected[i] do
            return false
    }

    return true
}

#test
{
    Swag.assert(Tokenize.eatQuotes("\"core\"") == "core")
    Swag.assert(Tokenize.eatQuotes("\"core") == "\"core")
    Swag.assert(Tokenize.eatQuotes("c") == "c")

    Swag.assert(Tokenize.eatCount("core", 0) == "core")
    Swag.assert(Tokenize.eatCount("core", 2) == "re")
    Swag.assert(Tokenize.eatCount("core", 99) == "")

    Swag.assert(Tokenize.eatSpaces(" \t\r\ncore") == "core")
    Swag.assert(Tokenize.eatSpaces("core") == "core")

    Swag.assert(Tokenize.prefixToWhitespace("core value") == "core")
    Swag.assert(Tokenize.alphanumericPrefix("abc123!?") == "abc123")

    Swag.assert(Tokenize.sliceToDelimiter("a,b,c", ','u8) == "a,")
    Swag.assert(Tokenize.sliceToDelimiter("a,b,c", ','u8, includeDelimiter: false) == "a")
    Swag.assert(Tokenize.sliceToDelimiter("a,b,c", ','u8, startByteIndex: 2) == "b,")
    Swag.assert(Tokenize.sliceToDelimiter("abc", ','u8) == "abc")
    Swag.assert(Tokenize.sliceToDelimiter("abc", ','u8, startByteIndex: 3) == "")
}

#test
{
    let lines                = Tokenize.splitLines("alpha\r\nbeta\ngamma\rdelta")
    let expected: [4] string = ["alpha", "beta", "gamma", "delta"]
    Swag.assert(assertStringArray(lines, expected))
}

#test
{
    let bytes                = Tokenize.split("alpha,beta,gamma", ','u8, maxSplit: 2)
    let expected: [3] string = ["alpha", "beta", "gamma"]
    Swag.assert(assertStringArray(bytes, expected))

    let byString = Tokenize.split("left::middle::right", "::", maxSplit: 1)
    let expectedString: [2] string = ["left", "middle::right"]
    Swag.assert(assertStringArray(byString, expectedString))
}

#test
{
    let bytes = Tokenize.split(",alpha,,beta,", ','u8, removeEmpty: false)
    let expectedBytes: [5] string = ["", "alpha", "", "beta", ""]
    Swag.assert(assertStringArray(bytes, expectedBytes))

    let byString = Tokenize.split("::alpha::::beta::", "::", removeEmpty: false)
    let expectedString: [5] string = ["", "alpha", "", "beta", ""]
    Swag.assert(assertStringArray(byString, expectedString))

    let byRune = Tokenize.split("|alpha||beta|", '|'rune, removeEmpty: false)
    let expectedRune: [5] string = ["", "alpha", "", "beta", ""]
    Swag.assert(assertStringArray(byRune, expectedRune))
}
