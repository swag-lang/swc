#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var literal = expect Parser.RegExp.create("1")

    Swag.assert(literal.match("1"))
    Swag.assert(!literal.match("2"))
}

#test
{
    var digitClass = expect Parser.RegExp.create("\\d")

    Swag.assert(digitClass.match("7"))
    Swag.assert(!digitClass.match("x"))
}

#test
{
    var exact = expect Parser.RegExp.create("abc")

    Swag.assert(exact.match("abc"))
    Swag.assert(!exact.match("ab"))
    Swag.assert(!exact.match("abcd"))
}

#test
{
    expect
    {
        var boxed = Parser.RegExp.create(#raw "(\d+)x(\d+)x(\d+)")

        Swag.assert(boxed.match("2x3x4"))
        Swag.assert(boxed.getCapture(1) == "2")
        Swag.assert(boxed.getCapture(2) == "3")
        Swag.assert(boxed.getCapture(3) == "4")
    }
}

#test
{
    expect
    {
        var boxed = Parser.RegExp.create(#raw "(\d+)x(\d+)x(\d+)")

        for 256
        {
            Swag.assert(boxed.match("2x3x4"))
            Swag.assert(boxed.getCapture(1) == "2")
            Swag.assert(boxed.getCapture(2) == "3")
            Swag.assert(boxed.getCapture(3) == "4")
        }
    }
}

#test
{
    var insensitive = expect Parser.RegExp.create("AbC", true)
    var sensitive   = expect Parser.RegExp.create("AbC")

    Swag.assert(insensitive.match("abc"))
    Swag.assert(insensitive.match("ABC"))
    Swag.assert(!sensitive.match("abc"))
}

#test
{
    var asciiLetters = expect Parser.RegExp.create(#raw "[a-z]+", true)
    var middleRange  = expect Parser.RegExp.create(#raw "[b-d]+", true)
    var literals     = expect Parser.RegExp.create(#raw "[abc]+")
    var noCaseList   = expect Parser.RegExp.create(#raw "[ab]+", true)
    var posixHex     = expect Parser.RegExp.create(#raw "[[:xdigit:]]+")
    var noDigits     = expect Parser.RegExp.create(#raw "[^[:digit:]]+")

    Swag.assert(asciiLetters.match("ABC"))
    Swag.assert(middleRange.match("BCD"))
    Swag.assert(literals.match("cab"))
    Swag.assert(noCaseList.match("ABBA"))
    Swag.assert(posixHex.match("1A2f"))
    Swag.assert(noDigits.match("abc!?"))
    Swag.assert(!middleRange.match("AE"))
    Swag.assert(!literals.match("cadz"))
    Swag.assert(!posixHex.match("1A2g"))
    Swag.assert(!noDigits.match("abc3"))
}

#test
{
    var simpleAlt  = expect Parser.RegExp.create(#raw "a|bc")
    var groupedAlt = expect Parser.RegExp.create(#raw "(ab|cd)e")

    Swag.assert(simpleAlt.match("a"))
    Swag.assert(simpleAlt.match("bc"))
    Swag.assert(!simpleAlt.match("b"))
    Swag.assert(groupedAlt.match("abe"))
    Swag.assert(groupedAlt.match("cde"))
    Swag.assert(!groupedAlt.match("abce"))
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

    Swag.assert(wildcard.match("abc"))
    Swag.assert(wildcard.match("a\u00E9c"))
    Swag.assert(!wildcard.match("ac"))
    Swag.assert(alnum.match("abc123"))
    Swag.assert(alpha.match("abcXYZ"))
    Swag.assert(!alnum.match("abc-123"))
    Swag.assert(!alpha.match("abc1"))
    Swag.assert(asciiOnly.match("AZ09!?"))
    Swag.assert(!asciiOnly.match("\u00E9"))
    Swag.assert(blanks.match(" \t"))
    Swag.assert(!blanks.match(" \n"))
    Swag.assert(spaces.match(" \t\n"))
    Swag.assert(words.match("abc_123"))
    Swag.assert(!words.match("abc-123"))
    Swag.assert(notLower.match("ABC!?"))
    Swag.assert(!notLower.match("AbC"))
    Swag.assert(notUpper.match("abc!?"))
    Swag.assert(!notUpper.match("aBc"))
    Swag.assert(unicodeSym.match("+="))
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

    Swag.assert(closeBracket.match("]]"))
    Swag.assert(openBracket.match("[["))
    Swag.assert(backslash.match("\\"))
    Swag.assert(backspace.match("\b\b"))
    Swag.assert(!backspace.match("ab"))
    Swag.assert(backspace.grep("ab") == null)
    Swag.assert(hyphen.match("--"))
    Swag.assert(caret.match("^^"))
    Swag.assert(digits.match("A42"))
    Swag.assert(!digits.match("A4-2"))
    Swag.assert(spaces.match("a \t"))
    Swag.assert(!spaces.match("ab"))
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

    Swag.assert(literalAlt.match("a|b"))
    Swag.assert(!literalAlt.match("ab"))
    Swag.assert(literalPipeLeadingAlt.match("|"))
    Swag.assert(literalPipeLeadingAlt.match("a"))
    Swag.assert(!literalPipeLeadingAlt.match("b"))
    Swag.assert(literalPipeTrailingAlt.match("a"))
    Swag.assert(literalPipeTrailingAlt.match("|"))
    Swag.assert(!literalPipeTrailingAlt.match("b"))
    Swag.assert(literalPipeMixedAlt.match("a|"))
    Swag.assert(literalPipeMixedAlt.match("b"))
    Swag.assert(!literalPipeMixedAlt.match("|"))
    Swag.assert(multiLiteralPipeAlt.match("|"))
    Swag.assert(multiLiteralPipeAlt.match("a"))
    Swag.assert(multiLiteralPipeAlt.match("b"))
    Swag.assert(!multiLiteralPipeAlt.match("ab"))
    Swag.assert(parenAlt.match("("))
    Swag.assert(parenAlt.match("a"))
    Swag.assert(closeParenAlt.match(")"))
    Swag.assert(closeParenAlt.match("a"))
    Swag.assert(openBracketAlt.match("["))
    Swag.assert(openBracketAlt.match("a"))
    Swag.assert(closeBracketAlt.match("]"))
    Swag.assert(closeBracketAlt.match("a"))
    Swag.assert(openBraceAlt.match("{"))
    Swag.assert(openBraceAlt.match("a"))
    Swag.assert(closeBraceAlt.match("}"))
    Swag.assert(closeBraceAlt.match("a"))
    Swag.assert(captureLiteralPipeAlt.match("|b"))
    Swag.assert(captureLiteralPipeAlt.getCapture(1) == "|")
    Swag.assert(captureLiteralPipeAlt.getCapture(2) == "b")
    Swag.assert(captureLiteralPipeAlt.match("ab"))
    Swag.assert(captureLiteralPipeAlt.getCapture(1) == "a")
    Swag.assert(captureLiteralPipeAlt.getCapture(2) == "b")
    Swag.assert(captureAlt.match("ac"))
    Swag.assert(captureAlt.getCapture(1) == "a")
    Swag.assert(captureAlt.getCapture(2) == "c")
    Swag.assert(captureAlt.captures().count == 2)
    Swag.assert(captureLeadingEmptyAlt.match("b"))
    Swag.assert(captureLeadingEmptyAlt.getCapture(1) == "")
    Swag.assert(captureLeadingEmptyAlt.getCapture(2) == "b")
    Swag.assert(captureLeadingEmptyAlt.match("ab"))
    Swag.assert(captureLeadingEmptyAlt.getCapture(1) == "a")
    Swag.assert(captureLeadingEmptyAlt.getCapture(2) == "b")
    Swag.assert(captureTrailingEmptyAlt.match("b"))
    Swag.assert(captureTrailingEmptyAlt.getCapture(1) == "")
    Swag.assert(captureTrailingEmptyAlt.getCapture(2) == "b")
    Swag.assert(captureTrailingEmptyAlt.match("ab"))
    Swag.assert(captureTrailingEmptyAlt.getCapture(1) == "a")
    Swag.assert(captureTrailingEmptyAlt.getCapture(2) == "b")
    Swag.assert(plainAlt.match("a"))
    Swag.assert(plainAlt.captures().count == 0)
    Swag.assert(leadingEmptyAlt.match(""))
    Swag.assert(leadingEmptyAlt.match("a"))
    Swag.assert(!leadingEmptyAlt.match("aa"))
    Swag.assert(trailingEmptyAlt.match(""))
    Swag.assert(trailingEmptyAlt.match("a"))
    Swag.assert(!trailingEmptyAlt.match("aa"))
    Swag.assert(doubleEmptyAlt.match(""))
    Swag.assert(doubleEmptyAlt.match("a"))
    Swag.assert(doubleEmptyAlt.match("b"))
    Swag.assert(!doubleEmptyAlt.match("ab"))
    Swag.assert(onlyEmptyAlt.match(""))
    Swag.assert(!onlyEmptyAlt.match("a"))
    Swag.assert(middleEmptyAlt.match("c"))
    Swag.assert(middleEmptyAlt.match("ac"))
    Swag.assert(!middleEmptyAlt.match("aac"))
    Swag.assert(escaped.match("()[]{}.+*?"))
    Swag.assert(anchors.match("^$"))
    Swag.assert(slash.match("/path\\file"))
    Swag.assert(controls.match("\n\r\t\f\v\a"))
}

#test
{
    var captures = expect Parser.RegExp.create(#raw "(\d+)-(\w+)")

    Swag.assert(captures.match("42-test"))
    Swag.assert(captures.getCapture(1) == "42")
    Swag.assert(captures[2] == "test")

    let all = captures.captures()
    Swag.assert(all.count >= 2)
    Swag.assert(all.contains("42"))
    Swag.assert(all.contains("test"))
}

#test
{
    var overload: Parser.RegExp

    Swag.assert(expect overload.match(#raw "(\d+)", "123"))
    Swag.assert(overload.getCapture(1) == "123")
    Swag.assert(!(expect overload.match(#raw "(\d+)", "abc")))
    Swag.assert(overload.captures().count == 0)
    Swag.assert(expect overload.match("AbC", "abc", true))
}

#test
{
    var repeated = expect Parser.RegExp.create(#raw "([a-z])\1")

    Swag.assert(repeated.match("ll"))
    Swag.assert(repeated.getCapture(1) == "l")
    Swag.assert(!repeated.match("ab"))
}

#test
{
    expect
    {
        var repeated = Parser.RegExp.create(#raw "([a-z]+)-\1")

        Swag.assert(repeated.match("abc-abc"))
        Swag.assert(repeated.getCapture(1) == "abc")
        Swag.assert(!repeated.match("abc-ab"))

        for 256
        {
            Swag.assert(repeated.match("xyz-xyz"))
            Swag.assert(repeated.getCapture(1) == "xyz")
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

    Swag.assert(emptyGroup.match(""))
    Swag.assert(emptyGroup.getCapture(1) == "")

    Swag.assert(explicitEmptyGroup.match(""))
    Swag.assert(explicitEmptyGroup.getCapture(1) == "")
    Swag.assert(explicitEmptyRef.match("-"))
    Swag.assert(explicitEmptyRef.getCapture(1) == "")
    Swag.assert(explicitEmptyAltGroup.match(""))
    Swag.assert(explicitEmptyAltGroup.getCapture(1) == "")
    Swag.assert(explicitEmptyAltRef.match("-"))
    Swag.assert(explicitEmptyAltRef.getCapture(1) == "")
    Swag.assert(optionalAltRef.match("-"))
    Swag.assert(optionalAltRef.getCapture(1) == "")
    Swag.assert(optionalAltRef.match("a-a"))
    Swag.assert(optionalAltRef.getCapture(1) == "a")
    Swag.assert(countedEmptyGroup.match("a"))
    Swag.assert(countedEmptyGroup.getCapture(1) == "")
    Swag.assert(countedEmptyGroup.getCapture(2) == "a")
    Swag.assert(countedEmptyAltGroup.match("a"))
    Swag.assert(countedEmptyAltGroup.getCapture(1) == "")
    Swag.assert(countedEmptyAltGroup.getCapture(2) == "a")

    Swag.assert(emptyRef.match("-"))
    Swag.assert(emptyRef.getCapture(1) == "")

    Swag.assert(emptyTail.match("abc"))
    Swag.assert(emptyTail.getCapture(1) == "abc")
    Swag.assert(emptyTail.getCapture(2) == "")

    Swag.assert(emptyTailSep.match("abc-"))
    Swag.assert(emptyTailSep.getCapture(1) == "abc")
    Swag.assert(emptyTailSep.getCapture(2) == "")

    Swag.assert(nonEmptyTailRef.match("abc12-12"))
    Swag.assert(nonEmptyTailRef.getCapture(1) == "abc")
    Swag.assert(nonEmptyTailRef.getCapture(2) == "12")

    Swag.assert(emptyTailRef.match("abc-"))
    Swag.assert(emptyTailRef.getCapture(1) == "abc")
    Swag.assert(emptyTailRef.getCapture(2) == "")
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

    Swag.assert(baseline.match("bc"))
    let baselineCount = baseline.captures().count

    Swag.assert(optionalGroup.match("bc"))
    Swag.assert(optionalGroup.getCapture(2) == "c")
    Swag.assert(optionalGroup.captures().count == baselineCount)

    Swag.assert(optionalGroup.match("abc"))
    Swag.assert(optionalGroup.getCapture(1) == "a")
    Swag.assert(optionalGroup.getCapture(2) == "c")
    Swag.assert(optionalGroup.match("bc"))
    Swag.assert(optionalGroup.getCapture(2) == "c")
    Swag.assert(optionalGroup.captures().count == baselineCount)

    Swag.assert(optionalStar.match("bc"))
    Swag.assert(optionalStar.getCapture(2) == "c")
    Swag.assert(optionalStar.captures().count == baselineCount)

    Swag.assert(optionalRef.match(""))
    Swag.assert(optionalRef.match("aa"))
    Swag.assert(!optionalRef.match("a"))
    Swag.assert(zeroRef.match(""))
    Swag.assert(!zeroRef.match("a"))
    Swag.assert(zeroFirst.match("b"))
    Swag.assert(zeroFirst.getCapture(2) == "b")
    Swag.assert(zeroNested.match("c"))
    Swag.assert(zeroNested.getCapture(1) == "")
    Swag.assert(zeroNested.getCapture(2) == "")
    Swag.assert(zeroNested.getCapture(3) == "c")
    Swag.assert(zeroSiblingNested.match("c"))
    Swag.assert(zeroSiblingNested.getCapture(1) == "")
    Swag.assert(zeroSiblingNested.getCapture(2) == "")
    Swag.assert(zeroSiblingNested.getCapture(3) == "")
    Swag.assert(zeroSiblingNested.getCapture(4) == "c")
    Swag.assert(zeroNestedRef1.match(""))
    Swag.assert(zeroNestedRef2.match(""))
    Swag.assert(zeroSiblingNestedRef1.match(""))
    Swag.assert(zeroSiblingNestedRef2.match(""))
    Swag.assert(zeroSiblingNestedRef3.match(""))
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

    Swag.assert(nested.match("abc"))
    Swag.assert(nested.getCapture(1) == "ab")
    Swag.assert(nested.getCapture(2) == "a")
    Swag.assert(nested.getCapture(3) == "c")
    Swag.assert(nested.captures().count == 3)
    Swag.assert(nestedRef.match("ab-ab-a"))
    Swag.assert(nestedRef.getCapture(1) == "ab")
    Swag.assert(nestedRef.getCapture(2) == "a")
    Swag.assert(nestedCounted.match("ababc"))
    Swag.assert(nestedCounted.getCapture(1) == "ab")
    Swag.assert(nestedCounted.getCapture(2) == "a")
    Swag.assert(nestedCounted.getCapture(3) == "c")
    Swag.assert(deepNested.match("ab"))
    Swag.assert(deepNested.getCapture(1) == "a")
    Swag.assert(deepNested.getCapture(2) == "a")
    Swag.assert(deepNested.getCapture(3) == "a")
    Swag.assert(deepNested.getCapture(4) == "b")
    Swag.assert(nestedSiblings.match("abc"))
    Swag.assert(nestedSiblings.getCapture(1) == "ab")
    Swag.assert(nestedSiblings.getCapture(2) == "a")
    Swag.assert(nestedSiblings.getCapture(3) == "b")
    Swag.assert(nestedSiblings.getCapture(4) == "c")
    Swag.assert(nestedSiblingsRef.match("ab-ab-a-b"))
    Swag.assert(nestedSiblingsRef.getCapture(1) == "ab")
    Swag.assert(nestedSiblingsRef.getCapture(2) == "a")
    Swag.assert(nestedSiblingsRef.getCapture(3) == "b")
    Swag.assert(nestedSiblingsCounted.match("ababc"))
    Swag.assert(nestedSiblingsCounted.getCapture(1) == "ab")
    Swag.assert(nestedSiblingsCounted.getCapture(2) == "a")
    Swag.assert(nestedSiblingsCounted.getCapture(3) == "b")
    Swag.assert(nestedSiblingsCounted.getCapture(4) == "c")
    Swag.assert(nestedLeadingEmptySiblingRef.match("a-a--a"))
    Swag.assert(nestedLeadingEmptySiblingRef.getCapture(1) == "a")
    Swag.assert(nestedLeadingEmptySiblingRef.getCapture(2) == "")
    Swag.assert(nestedLeadingEmptySiblingRef.getCapture(3) == "a")
    Swag.assert(nestedTrailingEmptySiblingRef.match("a-a-a-"))
    Swag.assert(nestedTrailingEmptySiblingRef.getCapture(1) == "a")
    Swag.assert(nestedTrailingEmptySiblingRef.getCapture(2) == "a")
    Swag.assert(nestedTrailingEmptySiblingRef.getCapture(3) == "")
    Swag.assert(nestedSiblingsCountedRef.match("abababab"))
    Swag.assert(nestedSiblingsCountedRef.getCapture(1) == "ab")
    Swag.assert(nestedSiblingsCountedRef.getCapture(2) == "a")
    Swag.assert(nestedSiblingsCountedRef.getCapture(3) == "b")
    Swag.assert(nestedLeadingEmptySibling.match("ab"))
    Swag.assert(nestedLeadingEmptySibling.getCapture(1) == "a")
    Swag.assert(nestedLeadingEmptySibling.getCapture(2) == "")
    Swag.assert(nestedLeadingEmptySibling.getCapture(3) == "a")
    Swag.assert(nestedLeadingEmptySibling.getCapture(4) == "b")
    Swag.assert(nestedTrailingEmptySibling.match("ab"))
    Swag.assert(nestedTrailingEmptySibling.getCapture(1) == "a")
    Swag.assert(nestedTrailingEmptySibling.getCapture(2) == "a")
    Swag.assert(nestedTrailingEmptySibling.getCapture(3) == "")
    Swag.assert(nestedTrailingEmptySibling.getCapture(4) == "b")
    Swag.assert(nestedLeadingAltSibling.match("bc"))
    Swag.assert(nestedLeadingAltSibling.getCapture(1) == "b")
    Swag.assert(nestedLeadingAltSibling.getCapture(2) == "")
    Swag.assert(nestedLeadingAltSibling.getCapture(3) == "b")
    Swag.assert(nestedLeadingAltSibling.getCapture(4) == "c")
    Swag.assert(nestedLeadingAltSibling.match("abc"))
    Swag.assert(nestedLeadingAltSibling.getCapture(1) == "ab")
    Swag.assert(nestedLeadingAltSibling.getCapture(2) == "a")
    Swag.assert(nestedLeadingAltSibling.getCapture(3) == "b")
    Swag.assert(nestedLeadingAltSibling.getCapture(4) == "c")
    Swag.assert(nestedTrailingAltSibling.match("ac"))
    Swag.assert(nestedTrailingAltSibling.getCapture(1) == "a")
    Swag.assert(nestedTrailingAltSibling.getCapture(2) == "a")
    Swag.assert(nestedTrailingAltSibling.getCapture(3) == "")
    Swag.assert(nestedTrailingAltSibling.getCapture(4) == "c")
    Swag.assert(nestedTrailingAltSibling.match("abc"))
    Swag.assert(nestedTrailingAltSibling.getCapture(1) == "ab")
    Swag.assert(nestedTrailingAltSibling.getCapture(2) == "a")
    Swag.assert(nestedTrailingAltSibling.getCapture(3) == "b")
    Swag.assert(nestedTrailingAltSibling.getCapture(4) == "c")
    Swag.assert(deepNestedRef.match("a-a-a-a"))
    Swag.assert(deepNestedRef.getCapture(1) == "a")
    Swag.assert(deepNestedRef.getCapture(2) == "a")
    Swag.assert(deepNestedRef.getCapture(3) == "a")
    Swag.assert(nestedLeadingAltSiblingRef.match("b-b--b"))
    Swag.assert(nestedLeadingAltSiblingRef.getCapture(1) == "b")
    Swag.assert(nestedLeadingAltSiblingRef.getCapture(2) == "")
    Swag.assert(nestedLeadingAltSiblingRef.getCapture(3) == "b")
    Swag.assert(nestedTrailingAltSiblingRef.match("a-a-a-"))
    Swag.assert(nestedTrailingAltSiblingRef.getCapture(1) == "a")
    Swag.assert(nestedTrailingAltSiblingRef.getCapture(2) == "a")
    Swag.assert(nestedTrailingAltSiblingRef.getCapture(3) == "")
}

#test
{
    var digits = expect Parser.RegExp.create(#raw "\d+")

    let prefix = digits.partialMatch("123abc")
    Swag.assert(prefix != null)
    Swag.assert(cast(string?) prefix == "123")
    Swag.assert(digits.partialMatch("abc123") == null)
}

#test
{
    var anchored = expect Parser.RegExp.create(#raw "^(\d+)")

    let first = anchored.partialMatch("123abc")
    Swag.assert(first != null)
    Swag.assert(cast(string?) first == "123")
    Swag.assert(anchored.getCapture(1) == "123")

    let second = anchored.partialMatch("456def")
    Swag.assert(second != null)
    Swag.assert(cast(string?) second == "456")
    Swag.assert(anchored.getCapture(1) == "456")

    Swag.assert(anchored.partialMatch("abc") == null)
    Swag.assert(anchored.captures().count == 0)
}

#test
{
    expect
    {
        var anchored = Parser.RegExp.create(#raw "^(\d+)")

        for 256
        {
            let prefix = anchored.partialMatch("789xyz")
            Swag.assert(prefix != null)
            Swag.assert(cast(string?) prefix == "789")
            Swag.assert(anchored.getCapture(1) == "789")
        }
    }
}

#test
{
    let all = expect Parser.RegExp.grepAll(#raw "\d+", "a12b345c6")

    Swag.assert(all.count == 3)
    Swag.assert(all[0] == "12")
    Swag.assert(all[1] == "345")
    Swag.assert(all[2] == "6")
}

#test
{
    let first = expect Parser.RegExp.grep(#raw "\d+", "aa12bb34")
    let none  = expect Parser.RegExp.grepAll(#raw "\d+", null)
    var part  = expect Parser.RegExp.create(#raw "\d+")

    Swag.assert(first == "12")
    Swag.assert(none.count == 0)
    Swag.assert(part.partialMatch(null) == null)
}

#test
{
    expect
    {
        var captures = Parser.RegExp.create(#raw "(\d+)")

        for 256
        {
            let first = captures.grep("a12")
            Swag.assert(first != null)
            Swag.assert(cast(string?) first == "12")
            Swag.assert(captures.getCapture(1) == "12")

            Swag.assert(captures.grep("abc") == null)
            Swag.assert(captures.captures().count == 0)

            let second = captures.grep("34x")
            Swag.assert(second != null)
            Swag.assert(cast(string?) second == "34")
            Swag.assert(captures.getCapture(1) == "34")
        }
    }
}

#test
{
    var endOfBuffer = expect Parser.RegExp.create(#raw "$")

    let match = endOfBuffer.grep("abc")
    Swag.assert(match != null)
    Swag.assert(cast(string?) match == "")

    let all = endOfBuffer.grepAll("abc")
    Swag.assert(all.count == 1)
    Swag.assert(all[0] == "")
}

#test
{
    var empty = expect Parser.RegExp.create(#raw "^$")

    let match = empty.grep("")
    Swag.assert(match != null)
    Swag.assert(cast(string?) match == "")

    let all = empty.grepAll("")
    Swag.assert(all.count == 1)
    Swag.assert(all[0] == "")
}

#test
{
    var words  = expect Parser.RegExp.create(#raw "\bcat\b")
    let first  = words.grep("\u00E9 scatter cat")
    let second = words.grep("\u00E9 scatter cat")

    Swag.assert(first != null)
    Swag.assert(cast(string?) first == "cat")
    Swag.assert(second != null)
    Swag.assert(cast(string?) second == "cat")
    Swag.assert(words.grep("\u00E9 scatter catnap") == null)
}

#test
{
    var boundary = expect Parser.RegExp.create(#raw "\b")

    let word = boundary.grep("cat")
    Swag.assert(word != null)
    Swag.assert(cast(string?) word == "")

    Swag.assert(boundary.grep("!?") == null)
    Swag.assert(boundary.grep("") == null)

    let all = boundary.grepAll(" cat!")
    Swag.assert(all.count == 2)
    Swag.assert(all[0] == "")
    Swag.assert(all[1] == "")
}

#test
{
    let all = expect Parser.RegExp.grepAll(#raw "\d+", "\u00E912\u03B2345")

    Swag.assert(all.count == 2)
    Swag.assert(all[0] == "12")
    Swag.assert(all[1] == "345")
}

#test
{
    var anchored = expect Parser.RegExp.create(#raw "^\d+")

    let atStart = anchored.grep("12 34")
    Swag.assert(atStart != null)
    Swag.assert(cast(string?) atStart == "12")
    Swag.assert(anchored.grep("aa12") == null)

    let all = anchored.grepAll("12 34")
    Swag.assert(all.count == 1)
    Swag.assert(all[0] == "12")
}

#test
{
    var words = expect Parser.RegExp.create(#raw "\bcat\b")

    Swag.assert(words.grep("\u00E9cat") == null)

    let match = words.grep("\u00E9 cat")
    Swag.assert(match != null)
    Swag.assert(cast(string?) match == "cat")

    let all = words.grepAll("\u00E9 cat catnap cat")
    Swag.assert(all.count == 2)
    Swag.assert(all[0] == "cat")
    Swag.assert(all[1] == "cat")
}

#test
{
    var anchored = expect Parser.RegExp.create(#raw "^\bcat\b$")
    var letters  = expect Parser.RegExp.create(#raw "\pL+")

    Swag.assert(anchored.match("cat"))
    Swag.assert(!anchored.match("scatter"))
    Swag.assert(letters.match("Cafe"))
    Swag.assert(letters.match("CafeNoir"))
}

#test
{
    var optional   = expect Parser.RegExp.create(#raw "colou?r")
    var revRange   = expect Parser.RegExp.create(#raw "[d-b]+")
    var nonLetters = expect Parser.RegExp.create(#raw "[^a-z]+")

    Swag.assert(optional.match("color"))
    Swag.assert(optional.match("colour"))
    Swag.assert(!optional.match("colouur"))
    Swag.assert(revRange.match("bcd"))
    Swag.assert(!revRange.match("abe"))
    Swag.assert(nonLetters.match("123!?"))
    Swag.assert(!nonLetters.match("abc"))
}

#test
{
    var star = expect Parser.RegExp.create(#raw "ba{0,}c")
    var opt  = expect Parser.RegExp.create(#raw "ba{0,1}c")
    var plus = expect Parser.RegExp.create(#raw "ba{1,}c")
    var same = expect Parser.RegExp.create(#raw "ba{1,1}c")

    Swag.assert(star.match("bc"))
    Swag.assert(star.match("baaac"))
    Swag.assert(opt.match("bc"))
    Swag.assert(opt.match("bac"))
    Swag.assert(!opt.match("baac"))
    Swag.assert(plus.match("bac"))
    Swag.assert(plus.match("baaac"))
    Swag.assert(!plus.match("bc"))
    Swag.assert(same.match("bac"))
    Swag.assert(!same.match("baac"))
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

    Swag.assert(blanks.match(" \tabc"))
    Swag.assert(nonDigits.match("abc!?"))
    Swag.assert(!nonDigits.match("abc3"))
    Swag.assert(nonWords.match("!? "))
    Swag.assert(!nonWords.match("word_"))
    Swag.assert(nonSpaces.match("abc!?"))
    Swag.assert(!nonSpaces.match("abc "))
    Swag.assert(unicodeLow.match("AbC"))
    Swag.assert(unicodeUp.match("ABC"))
    Swag.assert(!unicodeUp.match("AbC"))
    Swag.assert(unicodeNum.match("123"))
    Swag.assert(unicodeMath.match("+="))
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

    Swag.assert(counted.match("abbc"))
    Swag.assert(counted.match("abbbc"))
    Swag.assert(!counted.match("abc"))
    Swag.assert(!counted.match("abbbbc"))
    Swag.assert(countedGroup.match("aab"))
    Swag.assert(countedGroup.getCapture(1) == "a")
    Swag.assert(countedGroup.getCapture(2) == "b")
    Swag.assert(countedAltGroup.match("abc"))
    Swag.assert(countedAltGroup.getCapture(1) == "b")
    Swag.assert(countedAltGroup.getCapture(2) == "c")
    Swag.assert(countedAltGroup.captures().count == 2)
    Swag.assert(countedEmptyAltRange.match("b"))
    Swag.assert(countedEmptyAltRange.getCapture(1) == "")
    Swag.assert(countedEmptyAltRange.getCapture(2) == "b")
    Swag.assert(countedEmptyAltRange.match("ab"))
    Swag.assert(countedEmptyAltRange.getCapture(1) == "a")
    Swag.assert(countedEmptyAltRange.getCapture(2) == "b")
    Swag.assert(countedEmptyAltRange.match("aab"))
    Swag.assert(countedEmptyAltRange.getCapture(1) == "a")
    Swag.assert(countedEmptyAltRange.getCapture(2) == "b")
    Swag.assert(countedSiblingRange.match("c"))
    Swag.assert(countedSiblingRange.getCapture(1) == "")
    Swag.assert(countedSiblingRange.getCapture(2) == "")
    Swag.assert(countedSiblingRange.getCapture(3) == "")
    Swag.assert(countedSiblingRange.getCapture(4) == "c")
    Swag.assert(countedSiblingRange.match("abc"))
    Swag.assert(countedSiblingRange.getCapture(1) == "ab")
    Swag.assert(countedSiblingRange.getCapture(2) == "a")
    Swag.assert(countedSiblingRange.getCapture(3) == "b")
    Swag.assert(countedSiblingRange.getCapture(4) == "c")
    Swag.assert(countedSiblingRange.match("ababc"))
    Swag.assert(countedSiblingRange.getCapture(1) == "ab")
    Swag.assert(countedSiblingRange.getCapture(2) == "a")
    Swag.assert(countedSiblingRange.getCapture(3) == "b")
    Swag.assert(countedSiblingRange.getCapture(4) == "c")
    Swag.assert(countedSiblingRangeRef.match(""))
    Swag.assert(countedSiblingRangeRef.match("ababab"))
    Swag.assert(countedSiblingRangeRef.getCapture(1) == "ab")
    Swag.assert(countedSiblingRangeRef.getCapture(2) == "a")
    Swag.assert(countedSiblingRangeRef.getCapture(3) == "b")
    Swag.assert(countedSiblingRangeRef.match("abababab"))
    Swag.assert(countedSiblingRangeRef.getCapture(1) == "ab")
    Swag.assert(countedSiblingRangeRef.getCapture(2) == "a")
    Swag.assert(countedSiblingRangeRef.getCapture(3) == "b")
    Swag.assert(countedLeadingAltSibling.match("babc"))
    Swag.assert(countedLeadingAltSibling.getCapture(1) == "ab")
    Swag.assert(countedLeadingAltSibling.getCapture(2) == "a")
    Swag.assert(countedLeadingAltSibling.getCapture(3) == "b")
    Swag.assert(countedLeadingAltSibling.getCapture(4) == "c")
    Swag.assert(countedLeadingAltSibling.match("abbc"))
    Swag.assert(countedLeadingAltSibling.getCapture(1) == "b")
    Swag.assert(countedLeadingAltSibling.getCapture(2) == "")
    Swag.assert(countedLeadingAltSibling.getCapture(3) == "b")
    Swag.assert(countedLeadingAltSibling.getCapture(4) == "c")
    Swag.assert(countedTrailingAltSibling.match("abac"))
    Swag.assert(countedTrailingAltSibling.getCapture(1) == "a")
    Swag.assert(countedTrailingAltSibling.getCapture(2) == "a")
    Swag.assert(countedTrailingAltSibling.getCapture(3) == "")
    Swag.assert(countedTrailingAltSibling.getCapture(4) == "c")
    Swag.assert(countedTrailingAltSibling.match("aabc"))
    Swag.assert(countedTrailingAltSibling.getCapture(1) == "ab")
    Swag.assert(countedTrailingAltSibling.getCapture(2) == "a")
    Swag.assert(countedTrailingAltSibling.getCapture(3) == "b")
    Swag.assert(countedTrailingAltSibling.getCapture(4) == "c")
    Swag.assert(countedLeadingAltSiblingRange.match("c"))
    Swag.assert(countedLeadingAltSiblingRange.getCapture(1) == "")
    Swag.assert(countedLeadingAltSiblingRange.getCapture(2) == "")
    Swag.assert(countedLeadingAltSiblingRange.getCapture(3) == "")
    Swag.assert(countedLeadingAltSiblingRange.getCapture(4) == "c")
    Swag.assert(countedLeadingAltSiblingRange.match("bc"))
    Swag.assert(countedLeadingAltSiblingRange.getCapture(1) == "b")
    Swag.assert(countedLeadingAltSiblingRange.getCapture(2) == "")
    Swag.assert(countedLeadingAltSiblingRange.getCapture(3) == "b")
    Swag.assert(countedLeadingAltSiblingRange.getCapture(4) == "c")
    Swag.assert(countedLeadingAltSiblingRange.match("babc"))
    Swag.assert(countedLeadingAltSiblingRange.getCapture(1) == "ab")
    Swag.assert(countedLeadingAltSiblingRange.getCapture(2) == "a")
    Swag.assert(countedLeadingAltSiblingRange.getCapture(3) == "b")
    Swag.assert(countedLeadingAltSiblingRange.getCapture(4) == "c")
    Swag.assert(countedTrailingAltSiblingRange.match("c"))
    Swag.assert(countedTrailingAltSiblingRange.getCapture(1) == "")
    Swag.assert(countedTrailingAltSiblingRange.getCapture(2) == "")
    Swag.assert(countedTrailingAltSiblingRange.getCapture(3) == "")
    Swag.assert(countedTrailingAltSiblingRange.getCapture(4) == "c")
    Swag.assert(countedTrailingAltSiblingRange.match("ac"))
    Swag.assert(countedTrailingAltSiblingRange.getCapture(1) == "a")
    Swag.assert(countedTrailingAltSiblingRange.getCapture(2) == "a")
    Swag.assert(countedTrailingAltSiblingRange.getCapture(3) == "")
    Swag.assert(countedTrailingAltSiblingRange.getCapture(4) == "c")
    Swag.assert(countedTrailingAltSiblingRange.match("abac"))
    Swag.assert(countedTrailingAltSiblingRange.getCapture(1) == "a")
    Swag.assert(countedTrailingAltSiblingRange.getCapture(2) == "a")
    Swag.assert(countedTrailingAltSiblingRange.getCapture(3) == "")
    Swag.assert(countedTrailingAltSiblingRange.getCapture(4) == "c")
    Swag.assert(countedLeadingAltSiblingRangeRef.match(""))
    Swag.assert(countedLeadingAltSiblingRangeRef.match("bbb"))
    Swag.assert(countedLeadingAltSiblingRangeRef.getCapture(1) == "b")
    Swag.assert(countedLeadingAltSiblingRangeRef.getCapture(2) == "")
    Swag.assert(countedLeadingAltSiblingRangeRef.getCapture(3) == "b")
    Swag.assert(countedLeadingAltSiblingRangeRef.match("ababab"))
    Swag.assert(countedLeadingAltSiblingRangeRef.getCapture(1) == "ab")
    Swag.assert(countedLeadingAltSiblingRangeRef.getCapture(2) == "a")
    Swag.assert(countedLeadingAltSiblingRangeRef.getCapture(3) == "b")
    Swag.assert(countedTrailingAltSiblingRangeRef.match(""))
    Swag.assert(countedTrailingAltSiblingRangeRef.match("aaa"))
    Swag.assert(countedTrailingAltSiblingRangeRef.getCapture(1) == "a")
    Swag.assert(countedTrailingAltSiblingRangeRef.getCapture(2) == "a")
    Swag.assert(countedTrailingAltSiblingRangeRef.getCapture(3) == "")
    Swag.assert(countedTrailingAltSiblingRangeRef.match("ababab"))
    Swag.assert(countedTrailingAltSiblingRangeRef.getCapture(1) == "ab")
    Swag.assert(countedTrailingAltSiblingRangeRef.getCapture(2) == "a")
    Swag.assert(countedTrailingAltSiblingRangeRef.getCapture(3) == "b")
    Swag.assert(countedRangeGroup.match("b"))
    Swag.assert(countedRangeGroup.getCapture(2) == "b")
    Swag.assert(countedRangeGroup.match("ab"))
    Swag.assert(countedRangeGroup.getCapture(1) == "a")
    Swag.assert(countedRangeGroup.getCapture(2) == "b")
    Swag.assert(countedRangeGroup.match("aab"))
    Swag.assert(countedRangeGroup.getCapture(1) == "a")
    Swag.assert(countedRangeGroup.getCapture(2) == "b")
    Swag.assert(countedBackRef.match("abb"))
    Swag.assert(countedBackRef.match("baa"))
    Swag.assert(!countedBackRef.match("aba"))
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

    Swag.assert(emptyExactZero.match(""))
    Swag.assert(!emptyExactZero.match("a"))
    Swag.assert(emptyGroupZero.match(""))
    Swag.assert(!emptyGroupZero.match("ab"))
    Swag.assert(emptyDigitZero.match(""))
    Swag.assert(!emptyDigitZero.match("1"))
    Swag.assert(emptyUnicodeZero.match(""))
    Swag.assert(!emptyUnicodeZero.match("7"))
    Swag.assert(leftEmptyAlt.match(""))
    Swag.assert(leftEmptyAlt.match("b"))
    Swag.assert(!leftEmptyAlt.match("a"))
    Swag.assert(rightEmptyAlt.match(""))
    Swag.assert(rightEmptyAlt.match("a"))
    Swag.assert(!rightEmptyAlt.match("b"))
    Swag.assert(innerEmptyAlt.match("c"))
    Swag.assert(innerEmptyAlt.match("ac"))
    Swag.assert(!innerEmptyAlt.match("bc"))
    let emptyPrefix = emptyExactZero.partialMatch("abc")
    Swag.assert(emptyPrefix != null)
    Swag.assert(cast(string?) emptyPrefix == "")
    let emptyFirst = emptyDigitZero.grep("abc")
    Swag.assert(emptyFirst != null)
    Swag.assert(cast(string?) emptyFirst == "")
    let emptyAll = emptyGroupZero.grepAll("ab")
    Swag.assert(emptyAll.count == 3)
    Swag.assert(emptyAll[0] == "")
    Swag.assert(emptyAll[1] == "")
    Swag.assert(emptyAll[2] == "")
    Swag.assert(exactZero.match("bc"))
    Swag.assert(!exactZero.match("abc"))
    Swag.assert(rangeZero.match("c"))
    Swag.assert(!rangeZero.match("ac"))
    Swag.assert(groupedZero.match("c"))
    Swag.assert(!groupedZero.match("abc"))
    Swag.assert(escapedZero.match("a"))
    Swag.assert(escapedZero.match("(a"))
    Swag.assert(escapedZero.match("((a"))
    Swag.assert(!escapedZero.match("(((a"))
    Swag.assert(escapedCloseZero.match("a"))
    Swag.assert(escapedCloseZero.match(")a"))
    Swag.assert(escapedCloseZero.match("))a"))
    Swag.assert(!escapedCloseZero.match(")))a"))
    Swag.assert(escapedPipeZero.match("a"))
    Swag.assert(escapedPipeZero.match("|a"))
    Swag.assert(escapedPipeZero.match("||a"))
    Swag.assert(!escapedPipeZero.match("|||a"))
    Swag.assert(digitExactZero.match("a"))
    Swag.assert(!digitExactZero.match("1a"))
    Swag.assert(digitUpToTwo.match("a"))
    Swag.assert(digitUpToTwo.match("1a"))
    Swag.assert(digitUpToTwo.match("12a"))
    Swag.assert(!digitUpToTwo.match("123a"))
    Swag.assert(unicodeUpToTwo.match("a"))
    Swag.assert(unicodeUpToTwo.match("42a"))
    Swag.assert(!unicodeUpToTwo.match("123a"))
    Swag.assert(anythingUpToTwo.match("a"))
    Swag.assert(anythingUpToTwo.match("xa"))
    Swag.assert(anythingUpToTwo.match("xya"))
    Swag.assert(!anythingUpToTwo.match("xyza"))
    Swag.assert(upToTwo.match("bc"))
    Swag.assert(upToTwo.match("abc"))
    Swag.assert(upToTwo.match("aabc"))
    Swag.assert(!upToTwo.match("aaabc"))
    Swag.assert(groupUpToTwo.match("c"))
    Swag.assert(groupUpToTwo.match("abc"))
    Swag.assert(groupUpToTwo.match("ababc"))
    Swag.assert(!groupUpToTwo.match("abababc"))
}

#test
{
    discard catch Parser.RegExp.create(#raw "a{2,1}") as err

    Swag.assert(err != null)
    Swag.assert(err is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#raw "{1}") as err2

    Swag.assert(err2 != null)
    Swag.assert(err2 is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#raw "(") as err3

    Swag.assert(err3 != null)
    Swag.assert(err3 is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#raw "[abc") as err4

    Swag.assert(err4 != null)
    Swag.assert(err4 is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#raw "\pQ") as err5

    Swag.assert(err5 != null)
    Swag.assert(err5 is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#raw "\p{Lx}") as err6

    Swag.assert(err6 != null)
    Swag.assert(err6 is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create("\\") as err7

    Swag.assert(err7 != null)
    Swag.assert(err7 is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#raw "\q") as err8

    Swag.assert(err8 != null)
    Swag.assert(err8 is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#raw "[\q]") as err9

    Swag.assert(err9 != null)
    Swag.assert(err9 is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#raw "\p") as err10

    Swag.assert(err10 != null)
    Swag.assert(err10 is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#raw "\p{L") as err11

    Swag.assert(err11 != null)
    Swag.assert(err11 is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#raw "[[:bogus:]]") as err12

    Swag.assert(err12 != null)
    Swag.assert(err12 is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#raw "[[:digit]]") as err13

    Swag.assert(err13 != null)
    Swag.assert(err13 is Errors.SyntaxError)
}

#test
{
    // A negated class rejects every value it lists, whatever the list is made of.
    var noLetters   = expect Parser.RegExp.create(#raw "[^abc]+")
    var noMixed     = expect Parser.RegExp.create(#raw "[^a-c9]+")
    var noClass     = expect Parser.RegExp.create(#raw "[^\d\s]+")
    var noSingle    = expect Parser.RegExp.create(#raw "[^x]")
    var noCaseAware = expect Parser.RegExp.create(#raw "[^a]+", true)

    Swag.assert(noLetters.match("xyz"))
    Swag.assert(!noLetters.match("abc"))
    Swag.assert(!noLetters.match("xbz"))
    Swag.assert(noMixed.match("xyz8"))
    Swag.assert(!noMixed.match("9"))
    Swag.assert(!noMixed.match("b"))
    Swag.assert(noClass.match("ab!"))
    Swag.assert(!noClass.match("a1"))
    Swag.assert(!noClass.match("a b"))
    Swag.assert(noSingle.match("y"))
    Swag.assert(!noSingle.match("x"))
    Swag.assert(noCaseAware.match("bc"))
    Swag.assert(!noCaseAware.match("A"))
    Swag.assert(!noCaseAware.match("a"))
}

#test
{
    var group      = expect Parser.RegExp.create(#raw "(?:ab)+")
    var mixed      = expect Parser.RegExp.create(#raw "(?:ab)(c)")
    var nestedOnly = expect Parser.RegExp.create(#raw "(?:(a)b)+")

    Swag.assert(group.match("ababab"))
    Swag.assert(!group.match("aba"))
    Swag.assert(group.captureCount() == 0)
    Swag.assert(mixed.match("abc"))
    Swag.assert(mixed.getCapture(1) == "c")
    Swag.assert(mixed.captureCount() == 1)
    Swag.assert(nestedOnly.match("abab"))
    Swag.assert(nestedOnly.getCapture(1) == "a")
}

#test
{
    var angle  = expect Parser.RegExp.create(#raw "(?<year>\d{4})-(?<month>\d{2})")
    var quoted = expect Parser.RegExp.create(#raw "(?'word'\l+)")
    var python = expect Parser.RegExp.create(#raw "(?P<num>\d+)")

    Swag.assert(angle.match("2024-07"))
    Swag.assert(angle.getCapture("year") == "2024")
    Swag.assert(angle.getCapture("month") == "07")
    Swag.assert(angle.getCapture("day") == "")
    Swag.assert(angle.getCapture(1) == "2024")
    Swag.assert(quoted.match("hello"))
    Swag.assert(quoted.getCapture("word") == "hello")
    Swag.assert(python.match("42"))
    Swag.assert(python.getCapture("num") == "42")
}

#test
{
    var lazyStar  = expect Parser.RegExp.create(#raw "<(.*?)>")
    var lazyPlus  = expect Parser.RegExp.create(#raw "a+?b")
    var lazyOpt   = expect Parser.RegExp.create(#raw "ab??")
    var lazyCount = expect Parser.RegExp.create(#raw "a{1,3}?b")

    let tag = lazyStar.grep("<one><two>")
    Swag.assert(tag != null)
    Swag.assert(cast(string?) tag == "<one>")
    Swag.assert(lazyStar.getCapture(1) == "one")

    Swag.assert(lazyPlus.match("aab"))

    let shortest = lazyOpt.grep("ab")
    Swag.assert(shortest != null)
    Swag.assert(cast(string?) shortest == "a")

    Swag.assert(lazyCount.match("aab"))
    Swag.assert(!lazyCount.match("aaaab"))
}

#test
{
    var scoped   = expect Parser.RegExp.create(#raw "(?i)abc")
    var partial  = expect Parser.RegExp.create(#raw "ab(?i:cd)ef")
    var disabled = expect Parser.RegExp.create(#raw "(?i)ab(?-i)cd")
    var lines    = expect Parser.RegExp.create(#raw "(?m)^b$")
    var noDotAll = expect Parser.RegExp.create(#raw "(?-s)a.b")

    Swag.assert(scoped.match("AbC"))
    Swag.assert(partial.match("abCDef"))
    Swag.assert(!partial.match("ABcdef"))
    Swag.assert(disabled.match("ABcd"))
    Swag.assert(!disabled.match("ABCD"))

    let line = lines.grep("a\nb\nc")
    Swag.assert(line != null)
    Swag.assert(cast(string?) line == "b")

    Swag.assert(noDotAll.match("axb"))
    Swag.assert(!noDotAll.match("a\nb"))
}

#test
{
    var whole       = expect Parser.RegExp.create(#raw "\Aabc\z")
    var notBoundary = expect Parser.RegExp.create(#raw "a\Bb")
    var insideWord  = expect Parser.RegExp.create(#raw "\Bcat\B")

    Swag.assert(whole.match("abc"))
    Swag.assert(whole.grep("xabc") == null)
    Swag.assert(notBoundary.match("ab"))

    let inside = insideWord.grep("scatter")
    Swag.assert(inside != null)
    Swag.assert(cast(string?) inside == "cat")
    Swag.assert(insideWord.grep("a cat") == null)
}

#test
{
    var hexByte = expect Parser.RegExp.create(#raw "\x41\x42")
    var hexRune = expect Parser.RegExp.create(#raw "\x{00E9}")
    var hexWide = expect Parser.RegExp.create(#raw "\x{1F600}+")
    var escape  = expect Parser.RegExp.create(#raw "\e")
    var nul     = expect Parser.RegExp.create(#raw "a\0b")
    var inClass = expect Parser.RegExp.create(#raw "[\x41-\x43]+")

    Swag.assert(hexByte.match("AB"))
    Swag.assert(hexRune.match("\u00E9"))
    Swag.assert(hexWide.match("\U0001F600\U0001F600"))
    Swag.assert(escape.match("\u001B"))
    Swag.assert(!nul.match("ab"))
    Swag.assert(inClass.match("ABC"))
    Swag.assert(!inClass.match("D"))
}

#test
{
    var punct = expect Parser.RegExp.create(#raw "[[:punct:]]+")
    var cntrl = expect Parser.RegExp.create(#raw "[[:cntrl:]]+")
    var graph = expect Parser.RegExp.create(#raw "[[:graph:]]+")
    var print = expect Parser.RegExp.create(#raw "[[:print:]]+")

    Swag.assert(punct.match("!?;"))
    Swag.assert(!punct.match("a"))
    Swag.assert(cntrl.match("\u0001\u0002"))
    Swag.assert(!cntrl.match(" "))
    Swag.assert(graph.match("ab!"))
    Swag.assert(!graph.match("a b"))
    Swag.assert(print.match("a b"))
    Swag.assert(!print.match("a\tb"))
}

#test
{
    var decimals   = expect Parser.RegExp.create(#raw "\p{Nd}+")
    var notLetters = expect Parser.RegExp.create(#raw "\P{L}+")
    var letters    = expect Parser.RegExp.create(#raw "\p{Letter}+")
    var titles     = expect Parser.RegExp.create(#raw "\p{Lt}")

    Swag.assert(decimals.match("123"))
    Swag.assert(!decimals.match("12a"))
    Swag.assert(notLetters.match("12!?"))
    Swag.assert(!notLetters.match("12a"))
    Swag.assert(letters.match("Caf\u00E9"))
    Swag.assert(titles.match("\u01C5"))
}

#test
{
    // The automaton works over UTF-8 bytes, so a class of scalar values above ASCII must
    // still match whole characters and nothing in between.
    var accented  = expect Parser.RegExp.create(#raw "[\x{00E0}-\x{00FF}]+")
    var anyRune   = expect Parser.RegExp.create(#raw "^.{3}$")
    var mixed     = expect Parser.RegExp.create(#raw "\w+\x{00E9}\w+")
    var wideClass = expect Parser.RegExp.create(#raw "[a\x{4E2D}\x{1F600}]+")

    Swag.assert(accented.match("\u00E9\u00FF"))
    Swag.assert(!accented.match("a"))
    Swag.assert(anyRune.match("a\u00E9\u4E2D"))
    Swag.assert(!anyRune.match("ab"))
    Swag.assert(mixed.match("ab\u00E9cd"))
    Swag.assert(wideClass.match("a\u4E2D\U0001F600a"))
    Swag.assert(!wideClass.match("b"))

    let all = expect Parser.RegExp.grepAll(#raw "\x{00E9}+", "a\u00E9b\u00E9\u00E9c")
    Swag.assert(all.count == 2)
    Swag.assert(all[0] == "\u00E9")
    Swag.assert(all[1] == "\u00E9\u00E9")
}

#test
{
    var digits = expect Parser.RegExp.create(#raw "\d+")

    let first = digits.find("ab 12 cd 345")
    Swag.assert(first.found)
    Swag.assert(first.span.start == 3)
    Swag.assert(first.span.end == 5)

    let second = digits.find("ab 12 cd 345", 5)
    Swag.assert(second.found)
    Swag.assert(second.span.start == 9)
    Swag.assert(second.span.end == 12)

    Swag.assert(!digits.find("abc").found)
    Swag.assert(!digits.find(null).found)

    let spans = digits.findAll("ab 12 cd 345")
    Swag.assert(spans.count == 2)
    Swag.assert(spans[0].start == 3)
    Swag.assert(spans[1].end == 12)
}

#test
{
    var parts = expect Parser.RegExp.create(#raw "(\w+)@(\w+)")

    Swag.assert(parts.match("user@host"))

    let whole = parts.captureSpan(0)
    Swag.assert(whole.found)
    Swag.assert(whole.span.start == 0)
    Swag.assert(whole.span.end == 9)

    let user = parts.captureSpan(1)
    Swag.assert(user.found)
    Swag.assert(user.span.start == 0)
    Swag.assert(user.span.end == 4)

    let host = parts.captureSpan(2)
    Swag.assert(host.found)
    Swag.assert(host.span.start == 5)

    Swag.assert(!parts.captureSpan(3).found)
}

#test
{
    var swap  = expect Parser.RegExp.create(#raw "(\w+)-(\w+)")
    var named = expect Parser.RegExp.create(#raw "(?<key>\w+)=(?<value>\w+)")
    var vowel = expect Parser.RegExp.create(#raw "[aeiou]")

    Swag.assert(swap.replaceAll("ab-cd and ef-gh", "$2:$1") == "cd:ab and gh:ef")
    Swag.assert(named.replaceAll("x=1", "${value}/${key}") == "1/x")
    Swag.assert(vowel.replaceAll("banana", "*") == "b*n*n*")
    Swag.assert(vowel.replaceAll("xyz", "*") == "xyz")
    Swag.assert(swap.replaceAll("ab-cd", "$$0 is $0") == "$0 is ab-cd")
    Swag.assert(vowel.replaceAll(null, "*") == "")
}

#test
{
    var comma = expect Parser.RegExp.create(#raw ",\s*")
    var wide  = expect Parser.RegExp.create(#raw "\d+")

    let fields = comma.split("a, b,c ,d")
    Swag.assert(fields.count == 4)
    Swag.assert(fields[0] == "a")
    Swag.assert(fields[1] == "b")
    Swag.assert(fields[2] == "c ")
    Swag.assert(fields[3] == "d")

    let around = wide.split("12ab34")
    Swag.assert(around.count == 3)
    Swag.assert(around[0] == "")
    Swag.assert(around[1] == "ab")
    Swag.assert(around[2] == "")

    let none = comma.split("abc")
    Swag.assert(none.count == 1)
    Swag.assert(none[0] == "abc")
}

#test
{
    // A pattern a backtracking engine cannot answer: the simulation visits every position of
    // the program once per offset, so this returns at once instead of trying every split of
    // the subject.
    var nested     = expect Parser.RegExp.create(#raw "(a*)*b")
    var alternated = expect Parser.RegExp.create(#raw "(a|aa)+c")

    Swag.assert(!nested.match("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
    Swag.assert(nested.match("aaab"))
    Swag.assert(!alternated.match("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
    Swag.assert(alternated.match("aaac"))
}

#test
{
    var many = expect Parser.RegExp.create(#raw "a{1000}")
    var wide = expect Parser.RegExp.create(#raw "(?:ab){0,500}c")

    var subject: String
    for 1000 do
        subject.append('a'u8)

    Swag.assert(many.match(subject.toString()))
    Swag.assert(!many.match("aaa"))
    Swag.assert(wide.match("ababc"))

    discard catch Parser.RegExp.create(#raw "a{1001}") as tooMany
    Swag.assert(tooMany != null)
    Swag.assert(tooMany is Errors.SyntaxError)
}

#test
{
    // Constructs that are not supported must be rejected, not silently matched as something
    // else.
    discard catch Parser.RegExp.create(#raw "(?=abc)") as lookAhead
    Swag.assert(lookAhead is Errors.SyntaxError)

    discard catch Parser.RegExp.create(#raw "(?<=abc)") as lookBehind
    Swag.assert(lookBehind is Errors.SyntaxError)

    discard catch Parser.RegExp.create(#raw "a*+") as possessive
    Swag.assert(possessive is Errors.SyntaxError)

    discard catch Parser.RegExp.create(#raw "(?<name") as unterminatedName
    Swag.assert(unterminatedName is Errors.SyntaxError)

    discard catch Parser.RegExp.create(#raw "(?<>a)") as emptyName
    Swag.assert(emptyName is Errors.SyntaxError)

    discard catch Parser.RegExp.create(#raw "\x{}") as emptyHex
    Swag.assert(emptyHex is Errors.SyntaxError)

    discard catch Parser.RegExp.create(#raw "\x{110000}") as tooWide
    Swag.assert(tooWide is Errors.SyntaxError)

    discard catch Parser.RegExp.create(#raw "(?y)a") as badFlag
    Swag.assert(badFlag is Errors.SyntaxError)

    discard catch Parser.RegExp.create(#raw "^*") as repeatedAssert
    Swag.assert(repeatedAssert is Errors.SyntaxError)

    discard catch Parser.RegExp.create(#raw "[a-\d]") as classBound
    Swag.assert(classBound is Errors.SyntaxError)
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

    Swag.assert(literal.findAll(subject.toString()).count == 200)
    Swag.assert(inner.findAll(subject.toString()).count == 200)
    Swag.assert(byteSet.findAll(subject.toString()).count == 200)
    Swag.assert(anchored.findAll(subject.toString()).count == 1)

    let first = literal.find(subject.toString())
    Swag.assert(first.found)
    Swag.assert(first.span.start == 7)
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
        result.append(Alphabet[rng.below(Alphabet.count)])
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
            let hay = Swag.makeSlice((subject.toString()).buffer, subject.length)

            let reference = vm.run(&program, hay, 0, subject.length, false, false)
            let found     = expression.find(subject.toString())

            compared += 1

            Swag.assert(found.found == reference)
            if !reference do
                continue

            Swag.assert(found.span.start == vm.matchSlots[0])
            Swag.assert(found.span.end == vm.matchSlots[1])

            // Every capture engine has to report what the simulation reports, group by group.
            for var group = 1'u32; group <= expression.captureCount(); group += 1
            {
                let span     = expression.captureSpan(group)
                let opening  = vm.matchSlots[2 * group]
                let closing  = vm.matchSlots[2 * group + 1]
                let expected = opening != Parser.Regex.NoSlot and closing != Parser.Regex.NoSlot

                Swag.assert(span.found == expected)
                if !expected do
                    continue
                Swag.assert(span.span.start == opening)
                Swag.assert(span.span.end == closing)
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

                Swag.assert(every[seen].start == vm.matchSlots[0])
                Swag.assert(every[seen].end == vm.matchSlots[1])
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

            Swag.assert(seen == every.count)

            let reference2 = vm.run(&program, hay, 0, subject.length, false, false)
            Swag.assert(reference2 == reference)
        }
    }

    // A generated suite that stops generating proves nothing, so it says how much it compared.
    Swag.assert(compared > 3000)
}
