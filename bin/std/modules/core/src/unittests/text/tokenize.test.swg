#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

func assertStringArray(values: const &Array'string, expected: const [..] string)->bool
{
    if values.count != @countof(expected) do
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
    @assert(Tokenize.eatQuotes("\"core\"") == "core")
    @assert(Tokenize.eatQuotes("\"core") == "\"core")
    @assert(Tokenize.eatQuotes("c") == "c")

    @assert(Tokenize.eatCount("core", 0) == "core")
    @assert(Tokenize.eatCount("core", 2) == "re")
    @assert(Tokenize.eatCount("core", 99) == "")

    @assert(Tokenize.eatSpaces(" \t\r\ncore") == "core")
    @assert(Tokenize.eatSpaces("core") == "core")

    @assert(Tokenize.getToSpace("core value") == "core")
    @assert(Tokenize.getWhileAlnum("abc123!?") == "abc123")
}

#test
{
    let lines = Tokenize.splitLines("alpha\r\nbeta\ngamma\rdelta")
    let expected: [4] string = ["alpha", "beta", "gamma", "delta"]
    @assert(assertStringArray(lines, expected))
}

#test
{
    let bytes = Tokenize.split("alpha,beta,gamma", ',''u8, maxSplit: 2)
    let expected: [3] string = ["alpha", "beta", "gamma"]
    @assert(assertStringArray(bytes, expected))

    let byString = Tokenize.split("left::middle::right", "::", maxSplit: 1)
    let expectedString: [2] string = ["left", "middle::right"]
    @assert(assertStringArray(byString, expectedString))
}

#test
{
    let bytes = Tokenize.split(",alpha,,beta,", ',''u8, removeEmpty: false)
    let expectedBytes: [5] string = ["", "alpha", "", "beta", ""]
    @assert(assertStringArray(bytes, expectedBytes))

    let byString = Tokenize.split("::alpha::::beta::", "::", removeEmpty: false)
    let expectedString: [5] string = ["", "alpha", "", "beta", ""]
    @assert(assertStringArray(byString, expectedString))

    let byRune = Tokenize.split("|alpha||beta|", '|''rune, removeEmpty: false)
    let expectedRune: [5] string = ["", "alpha", "", "beta", ""]
    @assert(assertStringArray(byRune, expectedRune))
}
