#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

#test
{
    var literal: Parser.RegExp
    discard catch literal.preprocess("1")

    @assert(literal.preprocessed.contains('1'))
}

#test
{
    var digitClass: Parser.RegExp
    discard catch digitClass.preprocess("\\d")

    @assert(digitClass.preprocessed.contains(Parser.RuneAsciiDigit))
}

#test
{
    var exact = assume Parser.RegExp.create("abc")

    @assert(exact.match("abc"))
    @assert(!exact.match("ab"))
    @assert(!exact.match("abcd"))
}

#test
{
    assume
    {
        var boxed = Parser.RegExp.create(#"(\d+)x(\d+)x(\d+)"#)

        @assert(boxed.match("2x3x4"))
        @assert(boxed.getCapture(1) == "2")
        @assert(boxed.getCapture(2) == "3")
        @assert(boxed.getCapture(3) == "4")
    }
}

#test
{
    assume
    {
        var boxed = Parser.RegExp.create(#"(\d+)x(\d+)x(\d+)"#)

        for 256
        {
            @assert(boxed.match("2x3x4"))
            @assert(boxed.getCapture(1) == "2")
            @assert(boxed.getCapture(2) == "3")
            @assert(boxed.getCapture(3) == "4")
        }
    }
}

#test
{
    var insensitive = assume Parser.RegExp.create("AbC", true)
    var sensitive   = assume Parser.RegExp.create("AbC")

    @assert(insensitive.match("abc"))
    @assert(insensitive.match("ABC"))
    @assert(!sensitive.match("abc"))
}

#test
{
    var asciiLetters = assume Parser.RegExp.create(#"[a-z]+"#, true)
    var middleRange  = assume Parser.RegExp.create(#"[b-d]+"#, true)
    var literals     = assume Parser.RegExp.create(#"[abc]+"#)
    var noCaseList   = assume Parser.RegExp.create(#"[ab]+"#, true)

    @assert(asciiLetters.match("ABC"))
    @assert(middleRange.match("BCD"))
    @assert(literals.match("cab"))
    @assert(noCaseList.match("ABBA"))
    @assert(!middleRange.match("AE"))
    @assert(!literals.match("cadz"))
}

#test
{
    var captures = assume Parser.RegExp.create(#"(\d+)-(\w+)"#)

    @assert(captures.match("42-test"))
    @assert(captures.getCapture(1) == "42")
    @assert(captures[2] == "test")

    let all = captures.getCaptures()
    @assert(all.count >= 2)
    @assert(all.contains("42"))
    @assert(all.contains("test"))
}

#test
{
    var repeated = assume Parser.RegExp.create(#"([a-z])\1"#)

    @assert(repeated.match("ll"))
    @assert(repeated.getCapture(1) == "l")
    @assert(!repeated.match("ab"))
}

#test
{
    var digits = assume Parser.RegExp.create(#"\d+"#)

    let prefix = digits.partialMatch("123abc")
    @assert(prefix != null)
    @assert(cast(string) prefix == "123")
    @assert(digits.partialMatch("abc123") == null)
}

#test
{
    let all = assume Parser.RegExp.grepAll(#"\d+"#, "a12b345c6")

    @assert(all.count == 3)
    @assert(all[0] == "12")
    @assert(all[1] == "345")
    @assert(all[2] == "6")
}

#test
{
    var counted = assume Parser.RegExp.create(#"ab{2,3}c"#)

    @assert(counted.match("abbc"))
    @assert(counted.match("abbbc"))
    @assert(!counted.match("abc"))
    @assert(!counted.match("abbbbc"))
}

#test
{
    discard catch Parser.RegExp.create(#"a{2,1}"#)

    @assert(@err != null)
    @assert(@err is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#"{1}"#)

    @assert(@err != null)
    @assert(@err is Errors.SyntaxError)
}
