#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var literal = expect Parser.RegExp.create("1")

    @assert(literal.match("1"))
    @assert(!literal.match("2"))
}

#test
{
    var digitClass = expect Parser.RegExp.create("\\d")

    @assert(digitClass.match("7"))
    @assert(!digitClass.match("x"))
}

#test
{
    var exact = expect Parser.RegExp.create("abc")

    @assert(exact.match("abc"))
    @assert(!exact.match("ab"))
    @assert(!exact.match("abcd"))
}

#test
{
    expect
    {
        var boxed = Parser.RegExp.create(#raw "(\d+)x(\d+)x(\d+)")

        @assert(boxed.match("2x3x4"))
        @assert(boxed.getCapture(1) == "2")
        @assert(boxed.getCapture(2) == "3")
        @assert(boxed.getCapture(3) == "4")
    }
}

#test
{
    expect
    {
        var boxed = Parser.RegExp.create(#raw "(\d+)x(\d+)x(\d+)")

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
    var insensitive = expect Parser.RegExp.create("AbC", true)
    var sensitive   = expect Parser.RegExp.create("AbC")

    @assert(insensitive.match("abc"))
    @assert(insensitive.match("ABC"))
    @assert(!sensitive.match("abc"))
}

#test
{
    var asciiLetters = expect Parser.RegExp.create(#raw "[a-z]+", true)
    var middleRange  = expect Parser.RegExp.create(#raw "[b-d]+", true)
    var literals     = expect Parser.RegExp.create(#raw "[abc]+")
    var noCaseList   = expect Parser.RegExp.create(#raw "[ab]+", true)
    var posixHex     = expect Parser.RegExp.create(#raw "[[:xdigit:]]+")
    var noDigits     = expect Parser.RegExp.create(#raw "[^[:digit:]]+")

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
    var simpleAlt  = expect Parser.RegExp.create(#raw "a|bc")
    var groupedAlt = expect Parser.RegExp.create(#raw "(ab|cd)e")

    @assert(simpleAlt.match("a"))
    @assert(simpleAlt.match("bc"))
    @assert(!simpleAlt.match("b"))
    @assert(groupedAlt.match("abe"))
    @assert(groupedAlt.match("cde"))
    @assert(!groupedAlt.match("abce"))
}

#test
{
    var wildcard   = expect Parser.RegExp.create(#raw "a.c")
    var alnum      = expect Parser.RegExp.create(#raw "[[:alnum:]]+")
    var alpha      = expect Parser.RegExp.create(#raw "[[:alpha:]]+")
    var asciiOnly  = expect Parser.RegExp.create(#raw "[[:ascii:]]+")
    var blanks     = expect Parser.RegExp.create(#raw "[[:blank:]]+")
    var spaces     = expect Parser.RegExp.create(#raw "[[:space:]]+")
    var words      = expect Parser.RegExp.create(#raw "[[:word:]]+")
    var notLower   = expect Parser.RegExp.create(#raw "\L+")
    var notUpper   = expect Parser.RegExp.create(#raw "\U+")
    var unicodeSym = expect Parser.RegExp.create(#raw "\pS+")

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
    var closeBracket = expect Parser.RegExp.create(#raw "[\]]+")
    var openBracket  = expect Parser.RegExp.create(#raw "[\[]+")
    var backslash    = expect Parser.RegExp.create(#raw "[\\]+")
    var backspace    = expect Parser.RegExp.create(#raw "[\b]+")
    var hyphen       = expect Parser.RegExp.create(#raw "[\-]+")
    var caret        = expect Parser.RegExp.create(#raw "[\^]+")
    var digits       = expect Parser.RegExp.create(#raw "[\dA]+")
    var spaces       = expect Parser.RegExp.create(#raw "[a\s]+")

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
    var literalAlt              = expect Parser.RegExp.create(#raw "a\|b")
    var literalPipeLeadingAlt   = expect Parser.RegExp.create(#raw "\||a")
    var literalPipeTrailingAlt  = expect Parser.RegExp.create(#raw "a|\|")
    var literalPipeMixedAlt     = expect Parser.RegExp.create(#raw "a\||b")
    var multiLiteralPipeAlt     = expect Parser.RegExp.create(#raw "\||a|b")
    var parenAlt                = expect Parser.RegExp.create(#raw "\(|a")
    var closeParenAlt           = expect Parser.RegExp.create(#raw "\)|a")
    var openBracketAlt          = expect Parser.RegExp.create(#raw "\[|a")
    var closeBracketAlt         = expect Parser.RegExp.create(#raw "\]|a")
    var openBraceAlt            = expect Parser.RegExp.create(#raw "\{|a")
    var closeBraceAlt           = expect Parser.RegExp.create(#raw "\}|a")
    var captureLiteralPipeAlt   = expect Parser.RegExp.create(#raw "(\||a)(b)")
    var captureAlt              = expect Parser.RegExp.create(#raw "(a|b)(c)")
    var captureLeadingEmptyAlt  = expect Parser.RegExp.create(#raw "(|a)(b)")
    var captureTrailingEmptyAlt = expect Parser.RegExp.create(#raw "(a|)(b)")
    var plainAlt                = expect Parser.RegExp.create(#raw "a|b")
    var leadingEmptyAlt         = expect Parser.RegExp.create(#raw "|a")
    var trailingEmptyAlt        = expect Parser.RegExp.create(#raw "a|")
    var doubleEmptyAlt          = expect Parser.RegExp.create(#raw "a||b")
    var onlyEmptyAlt            = expect Parser.RegExp.create(#raw "||")
    var middleEmptyAlt          = expect Parser.RegExp.create(#raw "(a|)c")
    var escaped                 = expect Parser.RegExp.create(#raw "\(\)\[\]\{\}\.\+\*\?")
    var anchors                 = expect Parser.RegExp.create(#raw "\^\$")
    var slash                   = expect Parser.RegExp.create(#raw "\/path\\file")
    var controls                = expect Parser.RegExp.create("\\n\\r\\t\\f\\v\\a")

    @assert(literalAlt.match("a|b"))
    @assert(!literalAlt.match("ab"))
    @assert(literalPipeLeadingAlt.match("|"))
    @assert(literalPipeLeadingAlt.match("a"))
    @assert(!literalPipeLeadingAlt.match("b"))
    @assert(literalPipeTrailingAlt.match("a"))
    @assert(literalPipeTrailingAlt.match("|"))
    @assert(!literalPipeTrailingAlt.match("b"))
    @assert(literalPipeMixedAlt.match("a|"))
    @assert(literalPipeMixedAlt.match("b"))
    @assert(!literalPipeMixedAlt.match("|"))
    @assert(multiLiteralPipeAlt.match("|"))
    @assert(multiLiteralPipeAlt.match("a"))
    @assert(multiLiteralPipeAlt.match("b"))
    @assert(!multiLiteralPipeAlt.match("ab"))
    @assert(parenAlt.match("("))
    @assert(parenAlt.match("a"))
    @assert(closeParenAlt.match(")"))
    @assert(closeParenAlt.match("a"))
    @assert(openBracketAlt.match("["))
    @assert(openBracketAlt.match("a"))
    @assert(closeBracketAlt.match("]"))
    @assert(closeBracketAlt.match("a"))
    @assert(openBraceAlt.match("{"))
    @assert(openBraceAlt.match("a"))
    @assert(closeBraceAlt.match("}"))
    @assert(closeBraceAlt.match("a"))
    @assert(captureLiteralPipeAlt.match("|b"))
    @assert(captureLiteralPipeAlt.getCapture(1) == "|")
    @assert(captureLiteralPipeAlt.getCapture(2) == "b")
    @assert(captureLiteralPipeAlt.match("ab"))
    @assert(captureLiteralPipeAlt.getCapture(1) == "a")
    @assert(captureLiteralPipeAlt.getCapture(2) == "b")
    @assert(captureAlt.match("ac"))
    @assert(captureAlt.getCapture(1) == "a")
    @assert(captureAlt.getCapture(2) == "c")
    @assert(captureAlt.captures().count == 2)
    @assert(captureLeadingEmptyAlt.match("b"))
    @assert(captureLeadingEmptyAlt.getCapture(1) == "")
    @assert(captureLeadingEmptyAlt.getCapture(2) == "b")
    @assert(captureLeadingEmptyAlt.match("ab"))
    @assert(captureLeadingEmptyAlt.getCapture(1) == "a")
    @assert(captureLeadingEmptyAlt.getCapture(2) == "b")
    @assert(captureTrailingEmptyAlt.match("b"))
    @assert(captureTrailingEmptyAlt.getCapture(1) == "")
    @assert(captureTrailingEmptyAlt.getCapture(2) == "b")
    @assert(captureTrailingEmptyAlt.match("ab"))
    @assert(captureTrailingEmptyAlt.getCapture(1) == "a")
    @assert(captureTrailingEmptyAlt.getCapture(2) == "b")
    @assert(plainAlt.match("a"))
    @assert(plainAlt.captures().count == 0)
    @assert(leadingEmptyAlt.match(""))
    @assert(leadingEmptyAlt.match("a"))
    @assert(!leadingEmptyAlt.match("aa"))
    @assert(trailingEmptyAlt.match(""))
    @assert(trailingEmptyAlt.match("a"))
    @assert(!trailingEmptyAlt.match("aa"))
    @assert(doubleEmptyAlt.match(""))
    @assert(doubleEmptyAlt.match("a"))
    @assert(doubleEmptyAlt.match("b"))
    @assert(!doubleEmptyAlt.match("ab"))
    @assert(onlyEmptyAlt.match(""))
    @assert(!onlyEmptyAlt.match("a"))
    @assert(middleEmptyAlt.match("c"))
    @assert(middleEmptyAlt.match("ac"))
    @assert(!middleEmptyAlt.match("aac"))
    @assert(escaped.match("()[]{}.+*?"))
    @assert(anchors.match("^$"))
    @assert(slash.match("/path\\file"))
    @assert(controls.match("\n\r\t\f\v\a"))
}

#test
{
    var captures = expect Parser.RegExp.create(#raw "(\d+)-(\w+)")

    @assert(captures.match("42-test"))
    @assert(captures.getCapture(1) == "42")
    @assert(captures[2] == "test")

    let all = captures.captures()
    @assert(all.count >= 2)
    @assert(all.contains("42"))
    @assert(all.contains("test"))
}

#test
{
    var overload: Parser.RegExp

    @assert(expect overload.match(#raw "(\d+)", "123"))
    @assert(overload.getCapture(1) == "123")
    @assert(!(expect overload.match(#raw "(\d+)", "abc")))
    @assert(overload.captures().count == 0)
    @assert(expect overload.match("AbC", "abc", true))
}

#test
{
    var repeated = expect Parser.RegExp.create(#raw "([a-z])\1")

    @assert(repeated.match("ll"))
    @assert(repeated.getCapture(1) == "l")
    @assert(!repeated.match("ab"))
}

#test
{
    expect
    {
        var repeated = Parser.RegExp.create(#raw "([a-z]+)-\1")

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
    var emptyGroup            = expect Parser.RegExp.create(#raw "([a-z]*)")
    var explicitEmptyGroup    = expect Parser.RegExp.create(#raw "()")
    var explicitEmptyRef      = expect Parser.RegExp.create(#raw "()-\1")
    var explicitEmptyAltGroup = expect Parser.RegExp.create(#raw "(|)")
    var explicitEmptyAltRef   = expect Parser.RegExp.create(#raw "(|)-\1")
    var optionalAltRef        = expect Parser.RegExp.create(#raw "(|a)-\1")
    var countedEmptyGroup     = expect Parser.RegExp.create(#raw "(){2}(a)")
    var countedEmptyAltGroup  = expect Parser.RegExp.create(#raw "(|){2}(a)")
    var emptyRef              = expect Parser.RegExp.create(#raw "([a-z]*)-\1")
    var emptyTail             = expect Parser.RegExp.create(#raw "([a-z]+)(\d*)")
    var emptyTailSep          = expect Parser.RegExp.create(#raw "([a-z]+)(\d*)-")
    var nonEmptyTailRef       = expect Parser.RegExp.create(#raw "([a-z]+)(\d+)-\2")
    var emptyTailRef          = expect Parser.RegExp.create(#raw "([a-z]+)(\d*)-\2")

    @assert(emptyGroup.match(""))
    @assert(emptyGroup.getCapture(1) == "")

    @assert(explicitEmptyGroup.match(""))
    @assert(explicitEmptyGroup.getCapture(1) == "")
    @assert(explicitEmptyRef.match("-"))
    @assert(explicitEmptyRef.getCapture(1) == "")
    @assert(explicitEmptyAltGroup.match(""))
    @assert(explicitEmptyAltGroup.getCapture(1) == "")
    @assert(explicitEmptyAltRef.match("-"))
    @assert(explicitEmptyAltRef.getCapture(1) == "")
    @assert(optionalAltRef.match("-"))
    @assert(optionalAltRef.getCapture(1) == "")
    @assert(optionalAltRef.match("a-a"))
    @assert(optionalAltRef.getCapture(1) == "a")
    @assert(countedEmptyGroup.match("a"))
    @assert(countedEmptyGroup.getCapture(1) == "")
    @assert(countedEmptyGroup.getCapture(2) == "a")
    @assert(countedEmptyAltGroup.match("a"))
    @assert(countedEmptyAltGroup.getCapture(1) == "")
    @assert(countedEmptyAltGroup.getCapture(2) == "a")

    @assert(emptyRef.match("-"))
    @assert(emptyRef.getCapture(1) == "")

    @assert(emptyTail.match("abc"))
    @assert(emptyTail.getCapture(1) == "abc")
    @assert(emptyTail.getCapture(2) == "")

    @assert(emptyTailSep.match("abc-"))
    @assert(emptyTailSep.getCapture(1) == "abc")
    @assert(emptyTailSep.getCapture(2) == "")

    @assert(nonEmptyTailRef.match("abc12-12"))
    @assert(nonEmptyTailRef.getCapture(1) == "abc")
    @assert(nonEmptyTailRef.getCapture(2) == "12")

    @assert(emptyTailRef.match("abc-"))
    @assert(emptyTailRef.getCapture(1) == "abc")
    @assert(emptyTailRef.getCapture(2) == "")
}

#test
{
    var baseline              = expect Parser.RegExp.create(#raw "b(c)")
    var optionalGroup         = expect Parser.RegExp.create(#raw "(a)?b(c)")
    var optionalStar          = expect Parser.RegExp.create(#raw "(a)*b(c)")
    var optionalRef           = expect Parser.RegExp.create(#raw "(a)?\1")
    var zeroRef               = expect Parser.RegExp.create(#raw "(a){0}\1")
    var zeroFirst             = expect Parser.RegExp.create(#raw "(a){0}(b)")
    var zeroNested            = expect Parser.RegExp.create(#raw "((a)b){0}(c)")
    var zeroSiblingNested     = expect Parser.RegExp.create(#raw "((a)(b)){0}(c)")
    var zeroNestedRef1        = expect Parser.RegExp.create(#raw "((a)b){0}\1")
    var zeroNestedRef2        = expect Parser.RegExp.create(#raw "((a)b){0}\2")
    var zeroSiblingNestedRef1 = expect Parser.RegExp.create(#raw "((a)(b)){0}\1")
    var zeroSiblingNestedRef2 = expect Parser.RegExp.create(#raw "((a)(b)){0}\2")
    var zeroSiblingNestedRef3 = expect Parser.RegExp.create(#raw "((a)(b)){0}\3")

    @assert(baseline.match("bc"))
    let baselineCount = baseline.captures().count

    @assert(optionalGroup.match("bc"))
    @assert(optionalGroup.getCapture(2) == "c")
    @assert(optionalGroup.captures().count == baselineCount)

    @assert(optionalGroup.match("abc"))
    @assert(optionalGroup.getCapture(1) == "a")
    @assert(optionalGroup.getCapture(2) == "c")
    @assert(optionalGroup.match("bc"))
    @assert(optionalGroup.getCapture(2) == "c")
    @assert(optionalGroup.captures().count == baselineCount)

    @assert(optionalStar.match("bc"))
    @assert(optionalStar.getCapture(2) == "c")
    @assert(optionalStar.captures().count == baselineCount)

    @assert(optionalRef.match(""))
    @assert(optionalRef.match("aa"))
    @assert(!optionalRef.match("a"))
    @assert(zeroRef.match(""))
    @assert(!zeroRef.match("a"))
    @assert(zeroFirst.match("b"))
    @assert(zeroFirst.getCapture(2) == "b")
    @assert(zeroNested.match("c"))
    @assert(zeroNested.getCapture(1) == "")
    @assert(zeroNested.getCapture(2) == "")
    @assert(zeroNested.getCapture(3) == "c")
    @assert(zeroSiblingNested.match("c"))
    @assert(zeroSiblingNested.getCapture(1) == "")
    @assert(zeroSiblingNested.getCapture(2) == "")
    @assert(zeroSiblingNested.getCapture(3) == "")
    @assert(zeroSiblingNested.getCapture(4) == "c")
    @assert(zeroNestedRef1.match(""))
    @assert(zeroNestedRef2.match(""))
    @assert(zeroSiblingNestedRef1.match(""))
    @assert(zeroSiblingNestedRef2.match(""))
    @assert(zeroSiblingNestedRef3.match(""))
}

#test
{
    var nested                        = expect Parser.RegExp.create(#raw "((a)b)(c)")
    var nestedRef                     = expect Parser.RegExp.create(#raw "((a)b)-\1-\2")
    var nestedCounted                 = expect Parser.RegExp.create(#raw "((a)b){2}(c)")
    var deepNested                    = expect Parser.RegExp.create(#raw "(((a)))(b)")
    var nestedSiblings                = expect Parser.RegExp.create(#raw "((a)(b))(c)")
    var nestedLeadingEmptySibling     = expect Parser.RegExp.create(#raw "(()(a))(b)")
    var nestedTrailingEmptySibling    = expect Parser.RegExp.create(#raw "((a)())(b)")
    var nestedLeadingAltSibling       = expect Parser.RegExp.create(#raw "((|a)(b))(c)")
    var nestedTrailingAltSibling      = expect Parser.RegExp.create(#raw "((a)(|b))(c)")
    var deepNestedRef                 = expect Parser.RegExp.create(#raw "(((a)))-\1-\2-\3")
    var nestedSiblingsRef             = expect Parser.RegExp.create(#raw "((a)(b))-\1-\2-\3")
    var nestedSiblingsCounted         = expect Parser.RegExp.create(#raw "((a)(b)){2}(c)")
    var nestedLeadingEmptySiblingRef  = expect Parser.RegExp.create(#raw "(()(a))-\1-\2-\3")
    var nestedTrailingEmptySiblingRef = expect Parser.RegExp.create(#raw "((a)())-\1-\2-\3")
    var nestedLeadingAltSiblingRef    = expect Parser.RegExp.create(#raw "((|a)(b))-\1-\2-\3")
    var nestedTrailingAltSiblingRef   = expect Parser.RegExp.create(#raw "((a)(|b))-\1-\2-\3")
    var nestedSiblingsCountedRef      = expect Parser.RegExp.create(#raw "((a)(b)){2}\1\2\3")

    @assert(nested.match("abc"))
    @assert(nested.getCapture(1) == "ab")
    @assert(nested.getCapture(2) == "a")
    @assert(nested.getCapture(3) == "c")
    @assert(nested.captures().count == 3)
    @assert(nestedRef.match("ab-ab-a"))
    @assert(nestedRef.getCapture(1) == "ab")
    @assert(nestedRef.getCapture(2) == "a")
    @assert(nestedCounted.match("ababc"))
    @assert(nestedCounted.getCapture(1) == "ab")
    @assert(nestedCounted.getCapture(2) == "a")
    @assert(nestedCounted.getCapture(3) == "c")
    @assert(deepNested.match("ab"))
    @assert(deepNested.getCapture(1) == "a")
    @assert(deepNested.getCapture(2) == "a")
    @assert(deepNested.getCapture(3) == "a")
    @assert(deepNested.getCapture(4) == "b")
    @assert(nestedSiblings.match("abc"))
    @assert(nestedSiblings.getCapture(1) == "ab")
    @assert(nestedSiblings.getCapture(2) == "a")
    @assert(nestedSiblings.getCapture(3) == "b")
    @assert(nestedSiblings.getCapture(4) == "c")
    @assert(nestedSiblingsRef.match("ab-ab-a-b"))
    @assert(nestedSiblingsRef.getCapture(1) == "ab")
    @assert(nestedSiblingsRef.getCapture(2) == "a")
    @assert(nestedSiblingsRef.getCapture(3) == "b")
    @assert(nestedSiblingsCounted.match("ababc"))
    @assert(nestedSiblingsCounted.getCapture(1) == "ab")
    @assert(nestedSiblingsCounted.getCapture(2) == "a")
    @assert(nestedSiblingsCounted.getCapture(3) == "b")
    @assert(nestedSiblingsCounted.getCapture(4) == "c")
    @assert(nestedLeadingEmptySiblingRef.match("a-a--a"))
    @assert(nestedLeadingEmptySiblingRef.getCapture(1) == "a")
    @assert(nestedLeadingEmptySiblingRef.getCapture(2) == "")
    @assert(nestedLeadingEmptySiblingRef.getCapture(3) == "a")
    @assert(nestedTrailingEmptySiblingRef.match("a-a-a-"))
    @assert(nestedTrailingEmptySiblingRef.getCapture(1) == "a")
    @assert(nestedTrailingEmptySiblingRef.getCapture(2) == "a")
    @assert(nestedTrailingEmptySiblingRef.getCapture(3) == "")
    @assert(nestedSiblingsCountedRef.match("abababab"))
    @assert(nestedSiblingsCountedRef.getCapture(1) == "ab")
    @assert(nestedSiblingsCountedRef.getCapture(2) == "a")
    @assert(nestedSiblingsCountedRef.getCapture(3) == "b")
    @assert(nestedLeadingEmptySibling.match("ab"))
    @assert(nestedLeadingEmptySibling.getCapture(1) == "a")
    @assert(nestedLeadingEmptySibling.getCapture(2) == "")
    @assert(nestedLeadingEmptySibling.getCapture(3) == "a")
    @assert(nestedLeadingEmptySibling.getCapture(4) == "b")
    @assert(nestedTrailingEmptySibling.match("ab"))
    @assert(nestedTrailingEmptySibling.getCapture(1) == "a")
    @assert(nestedTrailingEmptySibling.getCapture(2) == "a")
    @assert(nestedTrailingEmptySibling.getCapture(3) == "")
    @assert(nestedTrailingEmptySibling.getCapture(4) == "b")
    @assert(nestedLeadingAltSibling.match("bc"))
    @assert(nestedLeadingAltSibling.getCapture(1) == "b")
    @assert(nestedLeadingAltSibling.getCapture(2) == "")
    @assert(nestedLeadingAltSibling.getCapture(3) == "b")
    @assert(nestedLeadingAltSibling.getCapture(4) == "c")
    @assert(nestedLeadingAltSibling.match("abc"))
    @assert(nestedLeadingAltSibling.getCapture(1) == "ab")
    @assert(nestedLeadingAltSibling.getCapture(2) == "a")
    @assert(nestedLeadingAltSibling.getCapture(3) == "b")
    @assert(nestedLeadingAltSibling.getCapture(4) == "c")
    @assert(nestedTrailingAltSibling.match("ac"))
    @assert(nestedTrailingAltSibling.getCapture(1) == "a")
    @assert(nestedTrailingAltSibling.getCapture(2) == "a")
    @assert(nestedTrailingAltSibling.getCapture(3) == "")
    @assert(nestedTrailingAltSibling.getCapture(4) == "c")
    @assert(nestedTrailingAltSibling.match("abc"))
    @assert(nestedTrailingAltSibling.getCapture(1) == "ab")
    @assert(nestedTrailingAltSibling.getCapture(2) == "a")
    @assert(nestedTrailingAltSibling.getCapture(3) == "b")
    @assert(nestedTrailingAltSibling.getCapture(4) == "c")
    @assert(deepNestedRef.match("a-a-a-a"))
    @assert(deepNestedRef.getCapture(1) == "a")
    @assert(deepNestedRef.getCapture(2) == "a")
    @assert(deepNestedRef.getCapture(3) == "a")
    @assert(nestedLeadingAltSiblingRef.match("b-b--b"))
    @assert(nestedLeadingAltSiblingRef.getCapture(1) == "b")
    @assert(nestedLeadingAltSiblingRef.getCapture(2) == "")
    @assert(nestedLeadingAltSiblingRef.getCapture(3) == "b")
    @assert(nestedTrailingAltSiblingRef.match("a-a-a-"))
    @assert(nestedTrailingAltSiblingRef.getCapture(1) == "a")
    @assert(nestedTrailingAltSiblingRef.getCapture(2) == "a")
    @assert(nestedTrailingAltSiblingRef.getCapture(3) == "")
}

#test
{
    var digits = expect Parser.RegExp.create(#raw "\d+")

    let prefix = digits.partialMatch("123abc")
    @assert(prefix != null)
    @assert(cast(#null string) prefix == "123")
    @assert(digits.partialMatch("abc123") == null)
}

#test
{
    var anchored = expect Parser.RegExp.create(#raw "^(\d+)")

    let first = anchored.partialMatch("123abc")
    @assert(first != null)
    @assert(cast(#null string) first == "123")
    @assert(anchored.getCapture(1) == "123")

    let second = anchored.partialMatch("456def")
    @assert(second != null)
    @assert(cast(#null string) second == "456")
    @assert(anchored.getCapture(1) == "456")

    @assert(anchored.partialMatch("abc") == null)
    @assert(anchored.captures().count == 0)
}

#test
{
    expect
    {
        var anchored = Parser.RegExp.create(#raw "^(\d+)")

        for 256
        {
            let prefix = anchored.partialMatch("789xyz")
            @assert(prefix != null)
            @assert(cast(#null string) prefix == "789")
            @assert(anchored.getCapture(1) == "789")
        }
    }
}

#test
{
    let all = expect Parser.RegExp.grepAll(#raw "\d+", "a12b345c6")

    @assert(all.count == 3)
    @assert(all[0] == "12")
    @assert(all[1] == "345")
    @assert(all[2] == "6")
}

#test
{
    let first = expect Parser.RegExp.grep(#raw "\d+", "aa12bb34")
    let none  = expect Parser.RegExp.grepAll(#raw "\d+", null)
    var part  = expect Parser.RegExp.create(#raw "\d+")

    @assert(first == "12")
    @assert(none.count == 0)
    @assert(part.partialMatch(null) == null)
}

#test
{
    expect
    {
        var captures = Parser.RegExp.create(#raw "(\d+)")

        for 256
        {
            let first = captures.grep("a12")
            @assert(first != null)
            @assert(cast(#null string) first == "12")
            @assert(captures.getCapture(1) == "12")

            @assert(captures.grep("abc") == null)
            @assert(captures.captures().count == 0)

            let second = captures.grep("34x")
            @assert(second != null)
            @assert(cast(#null string) second == "34")
            @assert(captures.getCapture(1) == "34")
        }
    }
}

#test
{
    var endOfBuffer = expect Parser.RegExp.create(#raw "$")

    let match = endOfBuffer.grep("abc")
    @assert(match != null)
    @assert(cast(#null string) match == "")

    let all = endOfBuffer.grepAll("abc")
    @assert(all.count == 1)
    @assert(all[0] == "")
}

#test
{
    var empty = expect Parser.RegExp.create(#raw "^$")

    let match = empty.grep("")
    @assert(match != null)
    @assert(cast(#null string) match == "")

    let all = empty.grepAll("")
    @assert(all.count == 1)
    @assert(all[0] == "")
}

#test
{
    var words  = expect Parser.RegExp.create(#raw "\bcat\b")
    let first  = words.grep("\u00E9 scatter cat")
    let second = words.grep("\u00E9 scatter cat")

    @assert(first != null)
    @assert(cast(#null string) first == "cat")
    @assert(second != null)
    @assert(cast(#null string) second == "cat")
    @assert(words.grep("\u00E9 scatter catnap") == null)
}

#test
{
    var boundary = expect Parser.RegExp.create(#raw "\b")

    let word = boundary.grep("cat")
    @assert(word != null)
    @assert(cast(#null string) word == "")

    @assert(boundary.grep("!?") == null)
    @assert(boundary.grep("") == null)

    let all = boundary.grepAll(" cat!")
    @assert(all.count == 2)
    @assert(all[0] == "")
    @assert(all[1] == "")
}

#test
{
    let all = expect Parser.RegExp.grepAll(#raw "\d+", "\u00E912\u03B2345")

    @assert(all.count == 2)
    @assert(all[0] == "12")
    @assert(all[1] == "345")
}

#test
{
    var anchored = expect Parser.RegExp.create(#raw "^\d+")

    let atStart = anchored.grep("12 34")
    @assert(atStart != null)
    @assert(cast(#null string) atStart == "12")
    @assert(anchored.grep("aa12") == null)

    let all = anchored.grepAll("12 34")
    @assert(all.count == 1)
    @assert(all[0] == "12")
}

#test
{
    var words = expect Parser.RegExp.create(#raw "\bcat\b")

    @assert(words.grep("\u00E9cat") == null)

    let match = words.grep("\u00E9 cat")
    @assert(match != null)
    @assert(cast(#null string) match == "cat")

    let all = words.grepAll("\u00E9 cat catnap cat")
    @assert(all.count == 2)
    @assert(all[0] == "cat")
    @assert(all[1] == "cat")
}

#test
{
    var anchored = expect Parser.RegExp.create(#raw "^\bcat\b$")
    var letters  = expect Parser.RegExp.create(#raw "\pL+")

    @assert(anchored.match("cat"))
    @assert(!anchored.match("scatter"))
    @assert(letters.match("Cafe"))
    @assert(letters.match("CafeNoir"))
}

#test
{
    var optional   = expect Parser.RegExp.create(#raw "colou?r")
    var revRange   = expect Parser.RegExp.create(#raw "[d-b]+")
    var nonLetters = expect Parser.RegExp.create(#raw "[^a-z]+")

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
    var star = expect Parser.RegExp.create(#raw "ba{0,}c")
    var opt  = expect Parser.RegExp.create(#raw "ba{0,1}c")
    var plus = expect Parser.RegExp.create(#raw "ba{1,}c")
    var same = expect Parser.RegExp.create(#raw "ba{1,1}c")

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
    var blanks      = expect Parser.RegExp.create(#raw "\s+\t\l+")
    var nonDigits   = expect Parser.RegExp.create(#raw "\D+")
    var nonWords    = expect Parser.RegExp.create(#raw "\W+")
    var nonSpaces   = expect Parser.RegExp.create(#raw "\S+")
    var unicodeLow  = expect Parser.RegExp.create(#raw "\p{Ll}+", true)
    var unicodeUp   = expect Parser.RegExp.create(#raw "\p{Lu}+")
    var unicodeNum  = expect Parser.RegExp.create(#raw "\pN+")
    var unicodeMath = expect Parser.RegExp.create(#raw "\p{Sm}+")

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
    var counted                           = expect Parser.RegExp.create(#raw "ab{2,3}c")
    var countedGroup                      = expect Parser.RegExp.create(#raw "(a){2}(b)")
    var countedAltGroup                   = expect Parser.RegExp.create(#raw "(a|b){2}(c)")
    var countedEmptyAltRange              = expect Parser.RegExp.create(#raw "(|a){0,2}(b)")
    var countedRangeGroup                 = expect Parser.RegExp.create(#raw "(a){0,2}(b)")
    var countedSiblingRange               = expect Parser.RegExp.create(#raw "((a)(b)){0,2}(c)")
    var countedSiblingRangeRef            = expect Parser.RegExp.create(#raw "((a)(b)){0,2}\1\2\3")
    var countedLeadingAltSibling          = expect Parser.RegExp.create(#raw "((|a)(b)){2}(c)")
    var countedTrailingAltSibling         = expect Parser.RegExp.create(#raw "((a)(|b)){2}(c)")
    var countedLeadingAltSiblingRange     = expect Parser.RegExp.create(#raw "((|a)(b)){0,2}(c)")
    var countedTrailingAltSiblingRange    = expect Parser.RegExp.create(#raw "((a)(|b)){0,2}(c)")
    var countedLeadingAltSiblingRangeRef  = expect Parser.RegExp.create(#raw "((|a)(b)){0,2}\1\2\3")
    var countedTrailingAltSiblingRangeRef = expect Parser.RegExp.create(#raw "((a)(|b)){0,2}\1\2\3")
    var countedBackRef                    = expect Parser.RegExp.create(#raw "([ab]){2}\1")

    @assert(counted.match("abbc"))
    @assert(counted.match("abbbc"))
    @assert(!counted.match("abc"))
    @assert(!counted.match("abbbbc"))
    @assert(countedGroup.match("aab"))
    @assert(countedGroup.getCapture(1) == "a")
    @assert(countedGroup.getCapture(2) == "b")
    @assert(countedAltGroup.match("abc"))
    @assert(countedAltGroup.getCapture(1) == "b")
    @assert(countedAltGroup.getCapture(2) == "c")
    @assert(countedAltGroup.captures().count == 2)
    @assert(countedEmptyAltRange.match("b"))
    @assert(countedEmptyAltRange.getCapture(1) == "")
    @assert(countedEmptyAltRange.getCapture(2) == "b")
    @assert(countedEmptyAltRange.match("ab"))
    @assert(countedEmptyAltRange.getCapture(1) == "a")
    @assert(countedEmptyAltRange.getCapture(2) == "b")
    @assert(countedEmptyAltRange.match("aab"))
    @assert(countedEmptyAltRange.getCapture(1) == "a")
    @assert(countedEmptyAltRange.getCapture(2) == "b")
    @assert(countedSiblingRange.match("c"))
    @assert(countedSiblingRange.getCapture(1) == "")
    @assert(countedSiblingRange.getCapture(2) == "")
    @assert(countedSiblingRange.getCapture(3) == "")
    @assert(countedSiblingRange.getCapture(4) == "c")
    @assert(countedSiblingRange.match("abc"))
    @assert(countedSiblingRange.getCapture(1) == "ab")
    @assert(countedSiblingRange.getCapture(2) == "a")
    @assert(countedSiblingRange.getCapture(3) == "b")
    @assert(countedSiblingRange.getCapture(4) == "c")
    @assert(countedSiblingRange.match("ababc"))
    @assert(countedSiblingRange.getCapture(1) == "ab")
    @assert(countedSiblingRange.getCapture(2) == "a")
    @assert(countedSiblingRange.getCapture(3) == "b")
    @assert(countedSiblingRange.getCapture(4) == "c")
    @assert(countedSiblingRangeRef.match(""))
    @assert(countedSiblingRangeRef.match("ababab"))
    @assert(countedSiblingRangeRef.getCapture(1) == "ab")
    @assert(countedSiblingRangeRef.getCapture(2) == "a")
    @assert(countedSiblingRangeRef.getCapture(3) == "b")
    @assert(countedSiblingRangeRef.match("abababab"))
    @assert(countedSiblingRangeRef.getCapture(1) == "ab")
    @assert(countedSiblingRangeRef.getCapture(2) == "a")
    @assert(countedSiblingRangeRef.getCapture(3) == "b")
    @assert(countedLeadingAltSibling.match("babc"))
    @assert(countedLeadingAltSibling.getCapture(1) == "ab")
    @assert(countedLeadingAltSibling.getCapture(2) == "a")
    @assert(countedLeadingAltSibling.getCapture(3) == "b")
    @assert(countedLeadingAltSibling.getCapture(4) == "c")
    @assert(countedLeadingAltSibling.match("abbc"))
    @assert(countedLeadingAltSibling.getCapture(1) == "b")
    @assert(countedLeadingAltSibling.getCapture(2) == "")
    @assert(countedLeadingAltSibling.getCapture(3) == "b")
    @assert(countedLeadingAltSibling.getCapture(4) == "c")
    @assert(countedTrailingAltSibling.match("abac"))
    @assert(countedTrailingAltSibling.getCapture(1) == "a")
    @assert(countedTrailingAltSibling.getCapture(2) == "a")
    @assert(countedTrailingAltSibling.getCapture(3) == "")
    @assert(countedTrailingAltSibling.getCapture(4) == "c")
    @assert(countedTrailingAltSibling.match("aabc"))
    @assert(countedTrailingAltSibling.getCapture(1) == "ab")
    @assert(countedTrailingAltSibling.getCapture(2) == "a")
    @assert(countedTrailingAltSibling.getCapture(3) == "b")
    @assert(countedTrailingAltSibling.getCapture(4) == "c")
    @assert(countedLeadingAltSiblingRange.match("c"))
    @assert(countedLeadingAltSiblingRange.getCapture(1) == "")
    @assert(countedLeadingAltSiblingRange.getCapture(2) == "")
    @assert(countedLeadingAltSiblingRange.getCapture(3) == "")
    @assert(countedLeadingAltSiblingRange.getCapture(4) == "c")
    @assert(countedLeadingAltSiblingRange.match("bc"))
    @assert(countedLeadingAltSiblingRange.getCapture(1) == "b")
    @assert(countedLeadingAltSiblingRange.getCapture(2) == "")
    @assert(countedLeadingAltSiblingRange.getCapture(3) == "b")
    @assert(countedLeadingAltSiblingRange.getCapture(4) == "c")
    @assert(countedLeadingAltSiblingRange.match("babc"))
    @assert(countedLeadingAltSiblingRange.getCapture(1) == "ab")
    @assert(countedLeadingAltSiblingRange.getCapture(2) == "a")
    @assert(countedLeadingAltSiblingRange.getCapture(3) == "b")
    @assert(countedLeadingAltSiblingRange.getCapture(4) == "c")
    @assert(countedTrailingAltSiblingRange.match("c"))
    @assert(countedTrailingAltSiblingRange.getCapture(1) == "")
    @assert(countedTrailingAltSiblingRange.getCapture(2) == "")
    @assert(countedTrailingAltSiblingRange.getCapture(3) == "")
    @assert(countedTrailingAltSiblingRange.getCapture(4) == "c")
    @assert(countedTrailingAltSiblingRange.match("ac"))
    @assert(countedTrailingAltSiblingRange.getCapture(1) == "a")
    @assert(countedTrailingAltSiblingRange.getCapture(2) == "a")
    @assert(countedTrailingAltSiblingRange.getCapture(3) == "")
    @assert(countedTrailingAltSiblingRange.getCapture(4) == "c")
    @assert(countedTrailingAltSiblingRange.match("abac"))
    @assert(countedTrailingAltSiblingRange.getCapture(1) == "a")
    @assert(countedTrailingAltSiblingRange.getCapture(2) == "a")
    @assert(countedTrailingAltSiblingRange.getCapture(3) == "")
    @assert(countedTrailingAltSiblingRange.getCapture(4) == "c")
    @assert(countedLeadingAltSiblingRangeRef.match(""))
    @assert(countedLeadingAltSiblingRangeRef.match("bbb"))
    @assert(countedLeadingAltSiblingRangeRef.getCapture(1) == "b")
    @assert(countedLeadingAltSiblingRangeRef.getCapture(2) == "")
    @assert(countedLeadingAltSiblingRangeRef.getCapture(3) == "b")
    @assert(countedLeadingAltSiblingRangeRef.match("ababab"))
    @assert(countedLeadingAltSiblingRangeRef.getCapture(1) == "ab")
    @assert(countedLeadingAltSiblingRangeRef.getCapture(2) == "a")
    @assert(countedLeadingAltSiblingRangeRef.getCapture(3) == "b")
    @assert(countedTrailingAltSiblingRangeRef.match(""))
    @assert(countedTrailingAltSiblingRangeRef.match("aaa"))
    @assert(countedTrailingAltSiblingRangeRef.getCapture(1) == "a")
    @assert(countedTrailingAltSiblingRangeRef.getCapture(2) == "a")
    @assert(countedTrailingAltSiblingRangeRef.getCapture(3) == "")
    @assert(countedTrailingAltSiblingRangeRef.match("ababab"))
    @assert(countedTrailingAltSiblingRangeRef.getCapture(1) == "ab")
    @assert(countedTrailingAltSiblingRangeRef.getCapture(2) == "a")
    @assert(countedTrailingAltSiblingRangeRef.getCapture(3) == "b")
    @assert(countedRangeGroup.match("b"))
    @assert(countedRangeGroup.getCapture(2) == "b")
    @assert(countedRangeGroup.match("ab"))
    @assert(countedRangeGroup.getCapture(1) == "a")
    @assert(countedRangeGroup.getCapture(2) == "b")
    @assert(countedRangeGroup.match("aab"))
    @assert(countedRangeGroup.getCapture(1) == "a")
    @assert(countedRangeGroup.getCapture(2) == "b")
    @assert(countedBackRef.match("abb"))
    @assert(countedBackRef.match("baa"))
    @assert(!countedBackRef.match("aba"))
}

#test
{
    var emptyExactZero   = expect Parser.RegExp.create(#raw "a{0}")
    var emptyGroupZero   = expect Parser.RegExp.create(#raw "(ab){0}")
    var emptyDigitZero   = expect Parser.RegExp.create(#raw "\d{0}")
    var emptyUnicodeZero = expect Parser.RegExp.create(#raw "\pN{0}")
    var leftEmptyAlt     = expect Parser.RegExp.create(#raw "a{0}|b")
    var rightEmptyAlt    = expect Parser.RegExp.create(#raw "a|b{0}")
    var innerEmptyAlt    = expect Parser.RegExp.create(#raw "(a|b{0})c")
    var exactZero        = expect Parser.RegExp.create(#raw "a{0}bc")
    var rangeZero        = expect Parser.RegExp.create(#raw "[ab]{0,0}c")
    var groupedZero      = expect Parser.RegExp.create(#raw "(ab){0}c")
    var escapedZero      = expect Parser.RegExp.create(#raw "\({0,2}a")
    var escapedCloseZero = expect Parser.RegExp.create(#raw "\){0,2}a")
    var escapedPipeZero  = expect Parser.RegExp.create(#raw "\|{0,2}a")
    var digitUpToTwo     = expect Parser.RegExp.create(#raw "\d{0,2}a")
    var digitExactZero   = expect Parser.RegExp.create(#raw "\d{0}a")
    var unicodeUpToTwo   = expect Parser.RegExp.create(#raw "\pN{0,2}a")
    var anythingUpToTwo  = expect Parser.RegExp.create(#raw ".{0,2}a")
    var upToTwo          = expect Parser.RegExp.create(#raw "a{0,2}bc")
    var groupUpToTwo     = expect Parser.RegExp.create(#raw "(ab){0,2}c")

    @assert(emptyExactZero.match(""))
    @assert(!emptyExactZero.match("a"))
    @assert(emptyGroupZero.match(""))
    @assert(!emptyGroupZero.match("ab"))
    @assert(emptyDigitZero.match(""))
    @assert(!emptyDigitZero.match("1"))
    @assert(emptyUnicodeZero.match(""))
    @assert(!emptyUnicodeZero.match("7"))
    @assert(leftEmptyAlt.match(""))
    @assert(leftEmptyAlt.match("b"))
    @assert(!leftEmptyAlt.match("a"))
    @assert(rightEmptyAlt.match(""))
    @assert(rightEmptyAlt.match("a"))
    @assert(!rightEmptyAlt.match("b"))
    @assert(innerEmptyAlt.match("c"))
    @assert(innerEmptyAlt.match("ac"))
    @assert(!innerEmptyAlt.match("bc"))
    let emptyPrefix = emptyExactZero.partialMatch("abc")
    @assert(emptyPrefix != null)
    @assert(cast(#null string) emptyPrefix == "")
    let emptyFirst = emptyDigitZero.grep("abc")
    @assert(emptyFirst != null)
    @assert(cast(#null string) emptyFirst == "")
    let emptyAll = emptyGroupZero.grepAll("ab")
    @assert(emptyAll.count == 3)
    @assert(emptyAll[0] == "")
    @assert(emptyAll[1] == "")
    @assert(emptyAll[2] == "")
    @assert(exactZero.match("bc"))
    @assert(!exactZero.match("abc"))
    @assert(rangeZero.match("c"))
    @assert(!rangeZero.match("ac"))
    @assert(groupedZero.match("c"))
    @assert(!groupedZero.match("abc"))
    @assert(escapedZero.match("a"))
    @assert(escapedZero.match("(a"))
    @assert(escapedZero.match("((a"))
    @assert(!escapedZero.match("(((a"))
    @assert(escapedCloseZero.match("a"))
    @assert(escapedCloseZero.match(")a"))
    @assert(escapedCloseZero.match("))a"))
    @assert(!escapedCloseZero.match(")))a"))
    @assert(escapedPipeZero.match("a"))
    @assert(escapedPipeZero.match("|a"))
    @assert(escapedPipeZero.match("||a"))
    @assert(!escapedPipeZero.match("|||a"))
    @assert(digitExactZero.match("a"))
    @assert(!digitExactZero.match("1a"))
    @assert(digitUpToTwo.match("a"))
    @assert(digitUpToTwo.match("1a"))
    @assert(digitUpToTwo.match("12a"))
    @assert(!digitUpToTwo.match("123a"))
    @assert(unicodeUpToTwo.match("a"))
    @assert(unicodeUpToTwo.match("42a"))
    @assert(!unicodeUpToTwo.match("123a"))
    @assert(anythingUpToTwo.match("a"))
    @assert(anythingUpToTwo.match("xa"))
    @assert(anythingUpToTwo.match("xya"))
    @assert(!anythingUpToTwo.match("xyza"))
    @assert(upToTwo.match("bc"))
    @assert(upToTwo.match("abc"))
    @assert(upToTwo.match("aabc"))
    @assert(!upToTwo.match("aaabc"))
    @assert(groupUpToTwo.match("c"))
    @assert(groupUpToTwo.match("abc"))
    @assert(groupUpToTwo.match("ababc"))
    @assert(!groupUpToTwo.match("abababc"))
}

#test
{
    discard catch Parser.RegExp.create(#raw "a{2,1}") as err

    @assert(err != null)
    @assert(err is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#raw "{1}") as err2

    @assert(err2 != null)
    @assert(err2 is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#raw "(") as err3

    @assert(err3 != null)
    @assert(err3 is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#raw "[abc") as err4

    @assert(err4 != null)
    @assert(err4 is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#raw "\pQ") as err5

    @assert(err5 != null)
    @assert(err5 is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#raw "\p{Lx}") as err6

    @assert(err6 != null)
    @assert(err6 is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create("\\") as err7

    @assert(err7 != null)
    @assert(err7 is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#raw "\q") as err8

    @assert(err8 != null)
    @assert(err8 is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#raw "[\q]") as err9

    @assert(err9 != null)
    @assert(err9 is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#raw "\p") as err10

    @assert(err10 != null)
    @assert(err10 is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#raw "\p{L") as err11

    @assert(err11 != null)
    @assert(err11 is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#raw "[[:bogus:]]") as err12

    @assert(err12 != null)
    @assert(err12 is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#raw "[[:digit]]") as err13

    @assert(err13 != null)
    @assert(err13 is Errors.SyntaxError)
}

#test
{
    // A negated class rejects every value it lists, whatever the list is made of.
    var noLetters   = expect Parser.RegExp.create(#raw "[^abc]+")
    var noMixed     = expect Parser.RegExp.create(#raw "[^a-c9]+")
    var noClass     = expect Parser.RegExp.create(#raw "[^\d\s]+")
    var noSingle    = expect Parser.RegExp.create(#raw "[^x]")
    var noCaseAware = expect Parser.RegExp.create(#raw "[^a]+", true)

    @assert(noLetters.match("xyz"))
    @assert(!noLetters.match("abc"))
    @assert(!noLetters.match("xbz"))
    @assert(noMixed.match("xyz8"))
    @assert(!noMixed.match("9"))
    @assert(!noMixed.match("b"))
    @assert(noClass.match("ab!"))
    @assert(!noClass.match("a1"))
    @assert(!noClass.match("a b"))
    @assert(noSingle.match("y"))
    @assert(!noSingle.match("x"))
    @assert(noCaseAware.match("bc"))
    @assert(!noCaseAware.match("A"))
    @assert(!noCaseAware.match("a"))
}

#test
{
    var group      = expect Parser.RegExp.create(#raw "(?:ab)+")
    var mixed      = expect Parser.RegExp.create(#raw "(?:ab)(c)")
    var nestedOnly = expect Parser.RegExp.create(#raw "(?:(a)b)+")

    @assert(group.match("ababab"))
    @assert(!group.match("aba"))
    @assert(group.captureCount() == 0)
    @assert(mixed.match("abc"))
    @assert(mixed.getCapture(1) == "c")
    @assert(mixed.captureCount() == 1)
    @assert(nestedOnly.match("abab"))
    @assert(nestedOnly.getCapture(1) == "a")
}

#test
{
    var angle  = expect Parser.RegExp.create(#raw "(?<year>\d{4})-(?<month>\d{2})")
    var quoted = expect Parser.RegExp.create(#raw "(?'word'\l+)")
    var python = expect Parser.RegExp.create(#raw "(?P<num>\d+)")

    @assert(angle.match("2024-07"))
    @assert(angle.getCapture("year") == "2024")
    @assert(angle.getCapture("month") == "07")
    @assert(angle.getCapture("day") == "")
    @assert(angle.getCapture(1) == "2024")
    @assert(quoted.match("hello"))
    @assert(quoted.getCapture("word") == "hello")
    @assert(python.match("42"))
    @assert(python.getCapture("num") == "42")
}

#test
{
    var lazyStar  = expect Parser.RegExp.create(#raw "<(.*?)>")
    var lazyPlus  = expect Parser.RegExp.create(#raw "a+?b")
    var lazyOpt   = expect Parser.RegExp.create(#raw "ab??")
    var lazyCount = expect Parser.RegExp.create(#raw "a{1,3}?b")

    let tag = lazyStar.grep("<one><two>")
    @assert(tag != null)
    @assert(cast(#null string) tag == "<one>")
    @assert(lazyStar.getCapture(1) == "one")

    @assert(lazyPlus.match("aab"))

    let shortest = lazyOpt.grep("ab")
    @assert(shortest != null)
    @assert(cast(#null string) shortest == "a")

    @assert(lazyCount.match("aab"))
    @assert(!lazyCount.match("aaaab"))
}

#test
{
    var scoped   = expect Parser.RegExp.create(#raw "(?i)abc")
    var partial  = expect Parser.RegExp.create(#raw "ab(?i:cd)ef")
    var disabled = expect Parser.RegExp.create(#raw "(?i)ab(?-i)cd")
    var lines    = expect Parser.RegExp.create(#raw "(?m)^b$")
    var noDotAll = expect Parser.RegExp.create(#raw "(?-s)a.b")

    @assert(scoped.match("AbC"))
    @assert(partial.match("abCDef"))
    @assert(!partial.match("ABcdef"))
    @assert(disabled.match("ABcd"))
    @assert(!disabled.match("ABCD"))

    let line = lines.grep("a\nb\nc")
    @assert(line != null)
    @assert(cast(#null string) line == "b")

    @assert(noDotAll.match("axb"))
    @assert(!noDotAll.match("a\nb"))
}

#test
{
    var whole       = expect Parser.RegExp.create(#raw "\Aabc\z")
    var notBoundary = expect Parser.RegExp.create(#raw "a\Bb")
    var insideWord  = expect Parser.RegExp.create(#raw "\Bcat\B")

    @assert(whole.match("abc"))
    @assert(whole.grep("xabc") == null)
    @assert(notBoundary.match("ab"))

    let inside = insideWord.grep("scatter")
    @assert(inside != null)
    @assert(cast(#null string) inside == "cat")
    @assert(insideWord.grep("a cat") == null)
}

#test
{
    var hexByte = expect Parser.RegExp.create(#raw "\x41\x42")
    var hexRune = expect Parser.RegExp.create(#raw "\x{00E9}")
    var hexWide = expect Parser.RegExp.create(#raw "\x{1F600}+")
    var escape  = expect Parser.RegExp.create(#raw "\e")
    var nul     = expect Parser.RegExp.create(#raw "a\0b")
    var inClass = expect Parser.RegExp.create(#raw "[\x41-\x43]+")

    @assert(hexByte.match("AB"))
    @assert(hexRune.match("\u00E9"))
    @assert(hexWide.match("\U0001F600\U0001F600"))
    @assert(escape.match("\u001B"))
    @assert(!nul.match("ab"))
    @assert(inClass.match("ABC"))
    @assert(!inClass.match("D"))
}

#test
{
    var punct = expect Parser.RegExp.create(#raw "[[:punct:]]+")
    var cntrl = expect Parser.RegExp.create(#raw "[[:cntrl:]]+")
    var graph = expect Parser.RegExp.create(#raw "[[:graph:]]+")
    var print = expect Parser.RegExp.create(#raw "[[:print:]]+")

    @assert(punct.match("!?;"))
    @assert(!punct.match("a"))
    @assert(cntrl.match("\u0001\u0002"))
    @assert(!cntrl.match(" "))
    @assert(graph.match("ab!"))
    @assert(!graph.match("a b"))
    @assert(print.match("a b"))
    @assert(!print.match("a\tb"))
}

#test
{
    var decimals   = expect Parser.RegExp.create(#raw "\p{Nd}+")
    var notLetters = expect Parser.RegExp.create(#raw "\P{L}+")
    var letters    = expect Parser.RegExp.create(#raw "\p{Letter}+")
    var titles     = expect Parser.RegExp.create(#raw "\p{Lt}")

    @assert(decimals.match("123"))
    @assert(!decimals.match("12a"))
    @assert(notLetters.match("12!?"))
    @assert(!notLetters.match("12a"))
    @assert(letters.match("Caf\u00E9"))
    @assert(titles.match("\u01C5"))
}

#test
{
    // The automaton works over UTF-8 bytes, so a class of scalar values above ASCII must
    // still match whole characters and nothing in between.
    var accented  = expect Parser.RegExp.create(#raw "[\x{00E0}-\x{00FF}]+")
    var anyRune   = expect Parser.RegExp.create(#raw "^.{3}$")
    var mixed     = expect Parser.RegExp.create(#raw "\w+\x{00E9}\w+")
    var wideClass = expect Parser.RegExp.create(#raw "[a\x{4E2D}\x{1F600}]+")

    @assert(accented.match("\u00E9\u00FF"))
    @assert(!accented.match("a"))
    @assert(anyRune.match("a\u00E9\u4E2D"))
    @assert(!anyRune.match("ab"))
    @assert(mixed.match("ab\u00E9cd"))
    @assert(wideClass.match("a\u4E2D\U0001F600a"))
    @assert(!wideClass.match("b"))

    let all = expect Parser.RegExp.grepAll(#raw "\x{00E9}+", "a\u00E9b\u00E9\u00E9c")
    @assert(all.count == 2)
    @assert(all[0] == "\u00E9")
    @assert(all[1] == "\u00E9\u00E9")
}

#test
{
    var digits = expect Parser.RegExp.create(#raw "\d+")

    let first = digits.find("ab 12 cd 345")
    @assert(first.found)
    @assert(first.span.start == 3)
    @assert(first.span.end == 5)

    let second = digits.find("ab 12 cd 345", 5)
    @assert(second.found)
    @assert(second.span.start == 9)
    @assert(second.span.end == 12)

    @assert(!digits.find("abc").found)
    @assert(!digits.find(null).found)

    let spans = digits.findAll("ab 12 cd 345")
    @assert(spans.count == 2)
    @assert(spans[0].start == 3)
    @assert(spans[1].end == 12)
}

#test
{
    var parts = expect Parser.RegExp.create(#raw "(\w+)@(\w+)")

    @assert(parts.match("user@host"))

    let whole = parts.captureSpan(0)
    @assert(whole.found)
    @assert(whole.span.start == 0)
    @assert(whole.span.end == 9)

    let user = parts.captureSpan(1)
    @assert(user.found)
    @assert(user.span.start == 0)
    @assert(user.span.end == 4)

    let host = parts.captureSpan(2)
    @assert(host.found)
    @assert(host.span.start == 5)

    @assert(!parts.captureSpan(3).found)
}

#test
{
    var swap  = expect Parser.RegExp.create(#raw "(\w+)-(\w+)")
    var named = expect Parser.RegExp.create(#raw "(?<key>\w+)=(?<value>\w+)")
    var vowel = expect Parser.RegExp.create(#raw "[aeiou]")

    @assert(swap.replaceAll("ab-cd and ef-gh", "$2:$1") == "cd:ab and gh:ef")
    @assert(named.replaceAll("x=1", "${value}/${key}") == "1/x")
    @assert(vowel.replaceAll("banana", "*") == "b*n*n*")
    @assert(vowel.replaceAll("xyz", "*") == "xyz")
    @assert(swap.replaceAll("ab-cd", "$$0 is $0") == "$0 is ab-cd")
    @assert(vowel.replaceAll(null, "*") == "")
}

#test
{
    var comma = expect Parser.RegExp.create(#raw ",\s*")
    var wide  = expect Parser.RegExp.create(#raw "\d+")

    let fields = comma.split("a, b,c ,d")
    @assert(fields.count == 4)
    @assert(fields[0] == "a")
    @assert(fields[1] == "b")
    @assert(fields[2] == "c ")
    @assert(fields[3] == "d")

    let around = wide.split("12ab34")
    @assert(around.count == 3)
    @assert(around[0] == "")
    @assert(around[1] == "ab")
    @assert(around[2] == "")

    let none = comma.split("abc")
    @assert(none.count == 1)
    @assert(none[0] == "abc")
}

#test
{
    // A pattern a backtracking engine cannot answer: the simulation visits every position of
    // the program once per offset, so this returns at once instead of trying every split of
    // the subject.
    var nested     = expect Parser.RegExp.create(#raw "(a*)*b")
    var alternated = expect Parser.RegExp.create(#raw "(a|aa)+c")

    @assert(!nested.match("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
    @assert(nested.match("aaab"))
    @assert(!alternated.match("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
    @assert(alternated.match("aaac"))
}

#test
{
    var many = expect Parser.RegExp.create(#raw "a{1000}")
    var wide = expect Parser.RegExp.create(#raw "(?:ab){0,500}c")

    var subject: String
    for 1000 do
        subject.append('a'u8)

    @assert(many.match(subject.toString()))
    @assert(!many.match("aaa"))
    @assert(wide.match("ababc"))

    discard catch Parser.RegExp.create(#raw "a{1001}") as tooMany
    @assert(tooMany != null)
    @assert(tooMany is Errors.SyntaxError)
}

#test
{
    // Constructs that are not supported must be rejected, not silently matched as something
    // else.
    discard catch Parser.RegExp.create(#raw "(?=abc)") as lookAhead
    @assert(lookAhead is Errors.SyntaxError)

    discard catch Parser.RegExp.create(#raw "(?<=abc)") as lookBehind
    @assert(lookBehind is Errors.SyntaxError)

    discard catch Parser.RegExp.create(#raw "a*+") as possessive
    @assert(possessive is Errors.SyntaxError)

    discard catch Parser.RegExp.create(#raw "(?<name") as unterminatedName
    @assert(unterminatedName is Errors.SyntaxError)

    discard catch Parser.RegExp.create(#raw "(?<>a)") as emptyName
    @assert(emptyName is Errors.SyntaxError)

    discard catch Parser.RegExp.create(#raw "\x{}") as emptyHex
    @assert(emptyHex is Errors.SyntaxError)

    discard catch Parser.RegExp.create(#raw "\x{110000}") as tooWide
    @assert(tooWide is Errors.SyntaxError)

    discard catch Parser.RegExp.create(#raw "(?y)a") as badFlag
    @assert(badFlag is Errors.SyntaxError)

    discard catch Parser.RegExp.create(#raw "^*") as repeatedAssert
    @assert(repeatedAssert is Errors.SyntaxError)

    discard catch Parser.RegExp.create(#raw "[a-\d]") as classBound
    @assert(classBound is Errors.SyntaxError)
}

#test
{
    // The search engines have to agree: what a scan finds must be what the simulation reports,
    // including when a subject holds many candidate starts.
    var literal  = expect Parser.RegExp.create("needle")
    var inner    = expect Parser.RegExp.create(#raw "\w+@\w+")
    var byteSet  = expect Parser.RegExp.create(#raw "[xyz]\d")
    var anchored = expect Parser.RegExp.create(#raw "^\w+")

    var subject: String
    for 200
    {
        subject.append("filler needle text x1 a@b ")
    }

    @assert(literal.findAll(subject.toString()).count == 200)
    @assert(inner.findAll(subject.toString()).count == 200)
    @assert(byteSet.findAll(subject.toString()).count == 200)
    @assert(anchored.findAll(subject.toString()).count == 1)

    let first = literal.find(subject.toString())
    @assert(first.found)
    @assert(first.span.start == 7)
}

// A deterministic pseudo-random source, so a failure names one seed and reproduces exactly.
struct Rng
{
    state: u64 = 0x2545_F491_4F6C_DD1D
}

impl Rng
{
    #[Swag.Safety(.Overflow, false)]
    mtd next()->u64
    {
        .state ^= .state << 13
        .state ^= .state >> 7
        .state ^= .state << 17
        return .state
    }

    mtd below(bound: u64)->u64 => .next() % bound
}

// Builds one pattern out of the constructs the engines have to agree on. Backreferences are
// left out: only one engine can run them, so there is nothing to compare.
func buildPattern(rng: *Rng, depth: u32)->String
{
    var result: retval

    let pieces = rng.below(3) + 1
    for var i = 0'u64; i < pieces; i += 1
    {
        var piece: String
        switch rng.below(depth == 0 ? 10 : 13)
        {
        case 0:
            piece.append(cast(u8) (cast(u64) 'a' + rng.below(3)))

        case 1:
            piece.append("[ab]")

        case 2:
            piece.append("[^a]")

        case 3:
            piece.append("\\d")

        case 4:
            piece.append("\\w")

        case 5:
            piece.append(".")

        case 6:
            piece.append("[a-c1-2]")

        case 7:
            piece.append("\\s")

        case 8:
            piece.append("\\b")

        case 9:
            piece.append("\\B")

        case 10:
            piece.append("(")
            piece.append(buildPattern(rng, depth - 1))
            piece.append("|")
            piece.append(buildPattern(rng, depth - 1))
            piece.append(")")

        case 12:
            piece.append("(")
            piece.append(buildPattern(rng, depth - 1))
            piece.append(")")

        case 11:
            piece.append("(?:")
            piece.append(buildPattern(rng, depth - 1))
            piece.append(")")
        }

        switch rng.below(8)
        {
        case 0: piece.append("*")
        case 1: piece.append("+")
        case 2: piece.append("?")
        case 3: piece.append("{1,2}")
        case 4: piece.append("*?")
        }

        result.append(piece.toString())
    }

    return result
}

func buildSubject(rng: *Rng)->String
{
    // The subject is not all ASCII: a word boundary reads scalar values, and the automata
    // have to hand a subject holding one of these to the engine that decodes them.
    const Alphabet = "aabbc12 x\u00E9\u00E9\u4E2D"

    var result: retval
    let length = rng.below(18)
    for var i = 0'u64; i < length; i += 1 do
        result.append(Alphabet[rng.below(@countof(Alphabet))])
    return result
}

#test
{
    // Every search but the simulation is an optimization: the vectorized scans, the two
    // automata and the backtracking replay all have to report exactly what the simulation
    // reports. This compares them on a few thousand generated patterns, because that is the
    // only way to reach the corners each of them takes.
    var rng: Rng

    // The subject outlives the expression on purpose: an expression keeps a borrow of the
    // subject it last searched, since that is where its capture groups point.
    var subject: String
    var compared = 0'u32

    for 400
    {
        var body = buildPattern(&rng, 2)

        var pattern: String
        if rng.below(4) == 0 do
            pattern.append("^")
        pattern.append(body.toString())
        if rng.below(4) == 0 do
            pattern.append("$")

        let text = pattern.toString()

        var expression = catch Parser.RegExp.create(text) as compileError
        if compileError != null do
            continue

        // The reference: the same pattern run by the simulation alone.
        var flags: Parser.Regex.Flags
        var ast     = expect Parser.Regex.Ast.parse(text, flags)
        let program = expect Parser.Regex.Program.compile(&ast, false)
        var vm:    Parser.Regex.PikeVm

        for 12
        {
            subject = buildSubject(&rng)
            let hay = @mkslice(@dataof(subject.toString()), subject.length)

            let reference = vm.run(&program, hay, 0, subject.length, false, false)
            let found     = expression.find(subject.toString())

            compared += 1

            @assert(found.found == reference)
            if !reference do
                continue

            @assert(found.span.start == vm.matchSlots[0])
            @assert(found.span.end == vm.matchSlots[1])

            // Every capture engine has to report what the simulation reports, group by group.
            for var group = 1'u32; group <= expression.captureCount(); group += 1
            {
                let span     = expression.captureSpan(group)
                let opening  = vm.matchSlots[2 * group]
                let closing  = vm.matchSlots[2 * group + 1]
                let expected = opening != Parser.Regex.NoSlot and closing != Parser.Regex.NoSlot

                @assert(span.found == expected)
                if !expected do
                    continue
                @assert(span.span.start == opening)
                @assert(span.span.end == closing)
            }

            // Every occurrence, found the way a caller asks for them, against the same
            // occurrences found one at a time by the simulation alone. The iteration has
            // strategies of its own -- it tries the pattern in place where no scan can skip
            // ahead -- and they have to report exactly what one search at a time reports.
            let every = expression.findAll(subject.toString())
            var at    = 0'u64
            var seen  = 0'u64

            while at <= subject.length
            {
                if !vm.run(&program, hay, at, subject.length, false, false) do
                    break

                @assert(every[seen].start == vm.matchSlots[0])
                @assert(every[seen].end == vm.matchSlots[1])
                seen += 1

                if vm.matchSlots[1] > vm.matchSlots[0]
                {
                    at = vm.matchSlots[1]
                    continue
                }

                at = vm.matchSlots[1] + 1
                while at < subject.length and (subject.toString()[at] & 0xC0) == 0x80 do
                    at += 1
            }

            @assert(seen == every.count)

            let reference2 = vm.run(&program, hay, 0, subject.length, false, false)
            @assert(reference2 == reference)
        }
    }

    // A generated suite that stops generating proves nothing, so it says how much it compared.
    @assert(compared > 3000)
}
