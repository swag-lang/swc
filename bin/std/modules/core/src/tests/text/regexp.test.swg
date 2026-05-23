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
    var posixHex     = assume Parser.RegExp.create(#"[[:xdigit:]]+"#)
    var noDigits     = assume Parser.RegExp.create(#"[^[:digit:]]+"#)

    @assert(asciiLetters.match("ABC"))
    @assert(middleRange.match("BCD"))
    @assert(literals.match("cab"))
    @assert(noCaseList.match("ABBA"))
    @assert(posixHex.match("1A2f"))
    @assert(noDigits.match("abc!?"))
    @assert(!middleRange.match("AE"))
    @assert(!literals.match("cadz"))
    @assert(!posixHex.match("1A2g"))
    @assert(!noDigits.match("abc3"))
}

#test
{
    var simpleAlt  = assume Parser.RegExp.create(#"a|bc"#)
    var groupedAlt = assume Parser.RegExp.create(#"(ab|cd)e"#)

    @assert(simpleAlt.match("a"))
    @assert(simpleAlt.match("bc"))
    @assert(!simpleAlt.match("b"))
    @assert(groupedAlt.match("abe"))
    @assert(groupedAlt.match("cde"))
    @assert(!groupedAlt.match("abce"))
}

#test
{
    var wildcard   = assume Parser.RegExp.create(#"a.c"#)
    var alnum      = assume Parser.RegExp.create(#"[[:alnum:]]+"#)
    var alpha      = assume Parser.RegExp.create(#"[[:alpha:]]+"#)
    var asciiOnly  = assume Parser.RegExp.create(#"[[:ascii:]]+"#)
    var blanks     = assume Parser.RegExp.create(#"[[:blank:]]+"#)
    var spaces     = assume Parser.RegExp.create(#"[[:space:]]+"#)
    var words      = assume Parser.RegExp.create(#"[[:word:]]+"#)
    var notLower   = assume Parser.RegExp.create(#"\L+"#)
    var notUpper   = assume Parser.RegExp.create(#"\U+"#)
    var unicodeSym = assume Parser.RegExp.create(#"\pS+"#)

    @assert(wildcard.match("abc"))
    @assert(wildcard.match("a\u00E9c"))
    @assert(!wildcard.match("ac"))
    @assert(alnum.match("abc123"))
    @assert(alpha.match("abcXYZ"))
    @assert(!alnum.match("abc-123"))
    @assert(!alpha.match("abc1"))
    @assert(asciiOnly.match("AZ09!?"))
    @assert(!asciiOnly.match("\u00E9"))
    @assert(blanks.match(" \t"))
    @assert(!blanks.match(" \n"))
    @assert(spaces.match(" \t\n"))
    @assert(words.match("abc_123"))
    @assert(!words.match("abc-123"))
    @assert(notLower.match("ABC!?"))
    @assert(!notLower.match("AbC"))
    @assert(notUpper.match("abc!?"))
    @assert(!notUpper.match("aBc"))
    @assert(unicodeSym.match("+="))
}

#test
{
    var closeBracket = assume Parser.RegExp.create(#"[\]]+"#)
    var openBracket  = assume Parser.RegExp.create(#"[\[]+"#)
    var backslash    = assume Parser.RegExp.create(#"[\\]+"#)
    var backspace    = assume Parser.RegExp.create(#"[\b]+"#)
    var hyphen       = assume Parser.RegExp.create(#"[\-]+"#)
    var caret        = assume Parser.RegExp.create(#"[\^]+"#)
    var digits       = assume Parser.RegExp.create(#"[\dA]+"#)
    var spaces       = assume Parser.RegExp.create(#"[a\s]+"#)

    @assert(closeBracket.match("]]"))
    @assert(openBracket.match("[["))
    @assert(backslash.match("\\"))
    @assert(backspace.match("\b\b"))
    @assert(!backspace.match("ab"))
    @assert(backspace.grep("ab") == null)
    @assert(hyphen.match("--"))
    @assert(caret.match("^^"))
    @assert(digits.match("A42"))
    @assert(!digits.match("A4-2"))
    @assert(spaces.match("a \t"))
    @assert(!spaces.match("ab"))
}

#test
{
    var literalAlt = assume Parser.RegExp.create(#"a\|b"#)
    var parenAlt   = assume Parser.RegExp.create(#"\(|a"#)
    var escaped    = assume Parser.RegExp.create(#"\(\)\[\]\{\}\.\+\*\?"#)
    var anchors    = assume Parser.RegExp.create(#"\^\$"#)
    var slash      = assume Parser.RegExp.create(#"\/path\\file"#)
    var controls   = assume Parser.RegExp.create("\\n\\r\\t\\f\\v\\a")

    @assert(literalAlt.match("a|b"))
    @assert(!literalAlt.match("ab"))
    @assert(parenAlt.match("("))
    @assert(parenAlt.match("a"))
    @assert(escaped.match("()[]{}.+*?"))
    @assert(anchors.match("^$"))
    @assert(slash.match("/path\\file"))
    @assert(controls.match("\n\r\t\f\v\a"))
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
    var overload: Parser.RegExp

    @assert(assume overload.match(#"(\d+)"#, "123"))
    @assert(overload.getCapture(1) == "123")
    @assert(!(assume overload.match(#"(\d+)"#, "abc")))
    @assert(overload.getCaptures().count == 0)
    @assert(assume overload.match("AbC", "abc", true))
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
    assume
    {
        var repeated = Parser.RegExp.create(#"([a-z]+)-\1"#)

        @assert(repeated.match("abc-abc"))
        @assert(repeated.getCapture(1) == "abc")
        @assert(!repeated.match("abc-ab"))

        for 256
        {
            @assert(repeated.match("xyz-xyz"))
            @assert(repeated.getCapture(1) == "xyz")
        }
    }
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
    var anchored = assume Parser.RegExp.create(#"^(\d+)"#)

    let first = anchored.partialMatch("123abc")
    @assert(first != null)
    @assert(cast(string) first == "123")
    @assert(anchored.getCapture(1) == "123")

    let second = anchored.partialMatch("456def")
    @assert(second != null)
    @assert(cast(string) second == "456")
    @assert(anchored.getCapture(1) == "456")

    @assert(anchored.partialMatch("abc") == null)
    @assert(anchored.getCaptures().count == 0)
}

#test
{
    assume
    {
        var anchored = Parser.RegExp.create(#"^(\d+)"#)

        for 256
        {
            let prefix = anchored.partialMatch("789xyz")
            @assert(prefix != null)
            @assert(cast(string) prefix == "789")
            @assert(anchored.getCapture(1) == "789")
        }
    }
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
    let first = assume Parser.RegExp.grep(#"\d+"#, "aa12bb34")
    let none  = assume Parser.RegExp.grepAll(#"\d+"#, null)
    var part  = assume Parser.RegExp.create(#"\d+"#)

    @assert(first == "12")
    @assert(none.count == 0)
    @assert(part.partialMatch(null) == null)
}

#test
{
    assume
    {
        var captures = Parser.RegExp.create(#"(\d+)"#)

        for 256
        {
            let first = captures.grep("a12")
            @assert(first != null)
            @assert(cast(string) first == "12")
            @assert(captures.getCapture(1) == "12")

            @assert(captures.grep("abc") == null)
            @assert(captures.getCaptures().count == 0)

            let second = captures.grep("34x")
            @assert(second != null)
            @assert(cast(string) second == "34")
            @assert(captures.getCapture(1) == "34")
        }
    }
}

#test
{
    var endOfBuffer = assume Parser.RegExp.create(#"$"#)

    let match = endOfBuffer.grep("abc")
    @assert(match != null)
    @assert(cast(string) match == "")

    let all = endOfBuffer.grepAll("abc")
    @assert(all.count == 1)
    @assert(all[0] == "")
}

#test
{
    var empty = assume Parser.RegExp.create(#"^$"#)

    let match = empty.grep("")
    @assert(match != null)
    @assert(cast(string) match == "")

    let all = empty.grepAll("")
    @assert(all.count == 1)
    @assert(all[0] == "")
}

#test
{
    var words = assume Parser.RegExp.create(#"\bcat\b"#)
    let first  = words.grep("\u00E9 scatter cat")
    let second = words.grep("\u00E9 scatter cat")

    @assert(first != null)
    @assert(cast(string) first == "cat")
    @assert(second != null)
    @assert(cast(string) second == "cat")
    @assert(words.grep("\u00E9 scatter catnap") == null)
}

#test
{
    let all = assume Parser.RegExp.grepAll(#"\d+"#, "\u00E912\u03B2345")

    @assert(all.count == 2)
    @assert(all[0] == "12")
    @assert(all[1] == "345")
}

#test
{
    var anchored = assume Parser.RegExp.create(#"^\d+"#)

    let atStart = anchored.grep("12 34")
    @assert(atStart != null)
    @assert(cast(string) atStart == "12")
    @assert(anchored.grep("aa12") == null)

    let all = anchored.grepAll("12 34")
    @assert(all.count == 1)
    @assert(all[0] == "12")
}

#test
{
    var words = assume Parser.RegExp.create(#"\bcat\b"#)

    @assert(words.grep("\u00E9cat") == null)

    let match = words.grep("\u00E9 cat")
    @assert(match != null)
    @assert(cast(string) match == "cat")

    let all = words.grepAll("\u00E9 cat catnap cat")
    @assert(all.count == 2)
    @assert(all[0] == "cat")
    @assert(all[1] == "cat")
}

#test
{
    var anchored = assume Parser.RegExp.create(#"^\bcat\b$"#)
    var letters  = assume Parser.RegExp.create(#"\pL+"#)

    @assert(anchored.match("cat"))
    @assert(!anchored.match("scatter"))
    @assert(letters.match("Cafe"))
    @assert(letters.match("CafeNoir"))
}

#test
{
    var optional   = assume Parser.RegExp.create(#"colou?r"#)
    var revRange   = assume Parser.RegExp.create(#"[d-b]+"#)
    var nonLetters = assume Parser.RegExp.create(#"[^a-z]+"#)

    @assert(optional.match("color"))
    @assert(optional.match("colour"))
    @assert(!optional.match("colouur"))
    @assert(revRange.match("bcd"))
    @assert(!revRange.match("abe"))
    @assert(nonLetters.match("123!?"))
    @assert(!nonLetters.match("abc"))
}

#test
{
    var star = assume Parser.RegExp.create(#"ba{0,}c"#)
    var opt  = assume Parser.RegExp.create(#"ba{0,1}c"#)
    var plus = assume Parser.RegExp.create(#"ba{1,}c"#)
    var same = assume Parser.RegExp.create(#"ba{1,1}c"#)

    @assert(star.match("bc"))
    @assert(star.match("baaac"))
    @assert(opt.match("bc"))
    @assert(opt.match("bac"))
    @assert(!opt.match("baac"))
    @assert(plus.match("bac"))
    @assert(plus.match("baaac"))
    @assert(!plus.match("bc"))
    @assert(same.match("bac"))
    @assert(!same.match("baac"))
}

#test
{
    var blanks      = assume Parser.RegExp.create(#"\s+\t\l+"#)
    var nonDigits   = assume Parser.RegExp.create(#"\D+"#)
    var nonWords    = assume Parser.RegExp.create(#"\W+"#)
    var nonSpaces   = assume Parser.RegExp.create(#"\S+"#)
    var unicodeLow  = assume Parser.RegExp.create(#"\p{Ll}+"#, true)
    var unicodeUp   = assume Parser.RegExp.create(#"\p{Lu}+"#)
    var unicodeNum  = assume Parser.RegExp.create(#"\pN+"#)
    var unicodeMath = assume Parser.RegExp.create(#"\p{Sm}+"#)

    @assert(blanks.match(" \tabc"))
    @assert(nonDigits.match("abc!?"))
    @assert(!nonDigits.match("abc3"))
    @assert(nonWords.match("!? "))
    @assert(!nonWords.match("word_"))
    @assert(nonSpaces.match("abc!?"))
    @assert(!nonSpaces.match("abc "))
    @assert(unicodeLow.match("AbC"))
    @assert(unicodeUp.match("ABC"))
    @assert(!unicodeUp.match("AbC"))
    @assert(unicodeNum.match("123"))
    @assert(unicodeMath.match("+="))
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

#test
{
    discard catch Parser.RegExp.create(#"("#)

    @assert(@err != null)
    @assert(@err is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#"[abc"#)

    @assert(@err != null)
    @assert(@err is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#"\pQ"#)

    @assert(@err != null)
    @assert(@err is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#"\p{Lx}"#)

    @assert(@err != null)
    @assert(@err is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create("\\")

    @assert(@err != null)
    @assert(@err is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#"\q"#)

    @assert(@err != null)
    @assert(@err is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#"[\q]"#)

    @assert(@err != null)
    @assert(@err is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#"\p"#)

    @assert(@err != null)
    @assert(@err is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#"\p{L"#)

    @assert(@err != null)
    @assert(@err is Errors.SyntaxError)
}
