#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertStringArray(values: Array'(string), expected: const [..] string)->bool => Slice.equals(values.toSlice(), expected)

#test
{
    Swag.require(Tokenize.eatQuotes("\"core\"") == "core")
    Swag.require(Tokenize.eatQuotes("\"core") == "\"core")
    Swag.require(Tokenize.eatQuotes("c") == "c")

    Swag.require(Tokenize.eatCount("core", 0) == "core")
    Swag.require(Tokenize.eatCount("core", 2) == "re")
    Swag.require(Tokenize.eatCount("core", 99) == "")

    Swag.require(Tokenize.eatSpaces(" \t\r\ncore") == "core")
    Swag.require(Tokenize.eatSpaces("core") == "core")

    Swag.require(Tokenize.prefixToWhitespace("core value") == "core")
    Swag.require(Tokenize.alphanumericPrefix("abc123!?") == "abc123")

    Swag.require(Tokenize.sliceToDelimiter("a,b,c", ','u8) == "a,")
    Swag.require(Tokenize.sliceToDelimiter("a,b,c", ','u8, includeDelimiter: false) == "a")
    Swag.require(Tokenize.sliceToDelimiter("a,b,c", ','u8, startByteIndex: 2) == "b,")
    Swag.require(Tokenize.sliceToDelimiter("abc", ','u8) == "abc")
    Swag.require(Tokenize.sliceToDelimiter("abc", ','u8, startByteIndex: 3) == "")
}

#test
{
    let lines = Tokenize.splitLines("alpha\r\nbeta\ngamma\rdelta")
    let expected: [4] string = ["alpha", "beta", "gamma", "delta"]
    Swag.require(assertStringArray(lines, expected))
}

#test
{
    let bytes = Tokenize.split("alpha,beta,gamma", ','u8, maxSplit: 2)
    let expected: [3] string = ["alpha", "beta", "gamma"]
    Swag.require(assertStringArray(bytes, expected))

    let byString = Tokenize.split("left::middle::right", "::", maxSplit: 1)
    let expectedString: [2] string = ["left", "middle::right"]
    Swag.require(assertStringArray(byString, expectedString))
}

#test
{
    let bytes = Tokenize.split(",alpha,,beta,", ','u8, removeEmpty: false)
    let expectedBytes: [5] string = ["", "alpha", "", "beta", ""]
    Swag.require(assertStringArray(bytes, expectedBytes))

    let byString = Tokenize.split("::alpha::::beta::", "::", removeEmpty: false)
    let expectedString: [5] string = ["", "alpha", "", "beta", ""]
    Swag.require(assertStringArray(byString, expectedString))

    let byRune = Tokenize.split("|alpha||beta|", '|'rune, removeEmpty: false)
    let expectedRune: [5] string = ["", "alpha", "", "beta", ""]
    Swag.require(assertStringArray(byRune, expectedRune))
}
