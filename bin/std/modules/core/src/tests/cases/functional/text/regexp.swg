#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var literal = expect Parser.RegExp.create("1")

    Swag.require(literal.match("1"))
    Swag.require(not literal.match("2"))
}

#test
{
    var digitClass = expect Parser.RegExp.create("\\d")

    Swag.require(digitClass.match("7"))
    Swag.require(not digitClass.match("x"))
}

#test
{
    var exact = expect Parser.RegExp.create("abc")

    Swag.require(exact.match("abc"))
    Swag.require(not exact.match("ab"))
    Swag.require(not exact.match("abcd"))
}

#test
{
    var boxed = expect Parser.RegExp.create(#raw "(\d+)x(\d+)x(\d+)")

    Swag.require(boxed.match("2x3x4"))
    Swag.require(boxed.getCapture(1) == "2")
    Swag.require(boxed.getCapture(2) == "3")
    Swag.require(boxed.getCapture(3) == "4")
}

#test
{
    var boxed = expect Parser.RegExp.create(#raw "(\d+)x(\d+)x(\d+)")

    for 256
    {
        Swag.require(boxed.match("2x3x4"))
        Swag.require(boxed.getCapture(1) == "2")
        Swag.require(boxed.getCapture(2) == "3")
        Swag.require(boxed.getCapture(3) == "4")
    }
}

#test
{
    var insensitive = expect Parser.RegExp.create("AbC", true)
    var sensitive   = expect Parser.RegExp.create("AbC")

    Swag.require(insensitive.match("abc"))
    Swag.require(insensitive.match("ABC"))
    Swag.require(not sensitive.match("abc"))
}

#test
{
    var asciiLetters = expect Parser.RegExp.create(#raw "[a-z]+", true)
    var middleRange  = expect Parser.RegExp.create(#raw "[b-d]+", true)
    var literals     = expect Parser.RegExp.create(#raw "[abc]+")
    var noCaseList   = expect Parser.RegExp.create(#raw "[ab]+", true)
    var posixHex     = expect Parser.RegExp.create(#raw "[[:xdigit:]]+")
    var noDigits     = expect Parser.RegExp.create(#raw "[^[:digit:]]+")

    Swag.require(asciiLetters.match("ABC"))
    Swag.require(middleRange.match("BCD"))
    Swag.require(literals.match("cab"))
    Swag.require(noCaseList.match("ABBA"))
    Swag.require(posixHex.match("1A2f"))
    Swag.require(noDigits.match("abc!?"))
    Swag.require(not middleRange.match("AE"))
    Swag.require(not literals.match("cadz"))
    Swag.require(not posixHex.match("1A2g"))
    Swag.require(not noDigits.match("abc3"))
}

#test
{
    var simpleAlt  = expect Parser.RegExp.create(#raw "a|bc")
    var groupedAlt = expect Parser.RegExp.create(#raw "(ab|cd)e")

    Swag.require(simpleAlt.match("a"))
    Swag.require(simpleAlt.match("bc"))
    Swag.require(not simpleAlt.match("b"))
    Swag.require(groupedAlt.match("abe"))
    Swag.require(groupedAlt.match("cde"))
    Swag.require(not groupedAlt.match("abce"))
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

    Swag.require(wildcard.match("abc"))
    Swag.require(wildcard.match("a\u00E9c"))
    Swag.require(not wildcard.match("ac"))
    Swag.require(alnum.match("abc123"))
    Swag.require(alpha.match("abcXYZ"))
    Swag.require(not alnum.match("abc-123"))
    Swag.require(not alpha.match("abc1"))
    Swag.require(asciiOnly.match("AZ09!?"))
    Swag.require(not asciiOnly.match("\u00E9"))
    Swag.require(blanks.match(" \t"))
    Swag.require(not blanks.match(" \n"))
    Swag.require(spaces.match(" \t\n"))
    Swag.require(words.match("abc_123"))
    Swag.require(not words.match("abc-123"))
    Swag.require(notLower.match("ABC!?"))
    Swag.require(not notLower.match("AbC"))
    Swag.require(notUpper.match("abc!?"))
    Swag.require(not notUpper.match("aBc"))
    Swag.require(unicodeSym.match("+="))
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

    Swag.require(closeBracket.match("]]"))
    Swag.require(openBracket.match("[["))
    Swag.require(backslash.match("\\"))
    Swag.require(backspace.match("\b\b"))
    Swag.require(not backspace.match("ab"))
    Swag.require(backspace.grep("ab") == null)
    Swag.require(hyphen.match("--"))
    Swag.require(caret.match("^^"))
    Swag.require(digits.match("A42"))
    Swag.require(not digits.match("A4-2"))
    Swag.require(spaces.match("a \t"))
    Swag.require(not spaces.match("ab"))
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

    Swag.require(literalAlt.match("a|b"))
    Swag.require(not literalAlt.match("ab"))
    Swag.require(literalPipeLeadingAlt.match("|"))
    Swag.require(literalPipeLeadingAlt.match("a"))
    Swag.require(not literalPipeLeadingAlt.match("b"))
    Swag.require(literalPipeTrailingAlt.match("a"))
    Swag.require(literalPipeTrailingAlt.match("|"))
    Swag.require(not literalPipeTrailingAlt.match("b"))
    Swag.require(literalPipeMixedAlt.match("a|"))
    Swag.require(literalPipeMixedAlt.match("b"))
    Swag.require(not literalPipeMixedAlt.match("|"))
    Swag.require(multiLiteralPipeAlt.match("|"))
    Swag.require(multiLiteralPipeAlt.match("a"))
    Swag.require(multiLiteralPipeAlt.match("b"))
    Swag.require(not multiLiteralPipeAlt.match("ab"))
    Swag.require(parenAlt.match("("))
    Swag.require(parenAlt.match("a"))
    Swag.require(closeParenAlt.match(")"))
    Swag.require(closeParenAlt.match("a"))
    Swag.require(openBracketAlt.match("["))
    Swag.require(openBracketAlt.match("a"))
    Swag.require(closeBracketAlt.match("]"))
    Swag.require(closeBracketAlt.match("a"))
    Swag.require(openBraceAlt.match("{"))
    Swag.require(openBraceAlt.match("a"))
    Swag.require(closeBraceAlt.match("}"))
    Swag.require(closeBraceAlt.match("a"))
    Swag.require(captureLiteralPipeAlt.match("|b"))
    Swag.require(captureLiteralPipeAlt.getCapture(1) == "|")
    Swag.require(captureLiteralPipeAlt.getCapture(2) == "b")
    Swag.require(captureLiteralPipeAlt.match("ab"))
    Swag.require(captureLiteralPipeAlt.getCapture(1) == "a")
    Swag.require(captureLiteralPipeAlt.getCapture(2) == "b")
    Swag.require(captureAlt.match("ac"))
    Swag.require(captureAlt.getCapture(1) == "a")
    Swag.require(captureAlt.getCapture(2) == "c")
    Swag.require(captureAlt.captures().count == 2)
    Swag.require(captureLeadingEmptyAlt.match("b"))
    Swag.require(captureLeadingEmptyAlt.getCapture(1) == "")
    Swag.require(captureLeadingEmptyAlt.getCapture(2) == "b")
    Swag.require(captureLeadingEmptyAlt.match("ab"))
    Swag.require(captureLeadingEmptyAlt.getCapture(1) == "a")
    Swag.require(captureLeadingEmptyAlt.getCapture(2) == "b")
    Swag.require(captureTrailingEmptyAlt.match("b"))
    Swag.require(captureTrailingEmptyAlt.getCapture(1) == "")
    Swag.require(captureTrailingEmptyAlt.getCapture(2) == "b")
    Swag.require(captureTrailingEmptyAlt.match("ab"))
    Swag.require(captureTrailingEmptyAlt.getCapture(1) == "a")
    Swag.require(captureTrailingEmptyAlt.getCapture(2) == "b")
    Swag.require(plainAlt.match("a"))
    Swag.require(plainAlt.captures().isEmpty())
    Swag.require(leadingEmptyAlt.match(""))
    Swag.require(leadingEmptyAlt.match("a"))
    Swag.require(not leadingEmptyAlt.match("aa"))
    Swag.require(trailingEmptyAlt.match(""))
    Swag.require(trailingEmptyAlt.match("a"))
    Swag.require(not trailingEmptyAlt.match("aa"))
    Swag.require(doubleEmptyAlt.match(""))
    Swag.require(doubleEmptyAlt.match("a"))
    Swag.require(doubleEmptyAlt.match("b"))
    Swag.require(not doubleEmptyAlt.match("ab"))
    Swag.require(onlyEmptyAlt.match(""))
    Swag.require(not onlyEmptyAlt.match("a"))
    Swag.require(middleEmptyAlt.match("c"))
    Swag.require(middleEmptyAlt.match("ac"))
    Swag.require(not middleEmptyAlt.match("aac"))
    Swag.require(escaped.match("()[]{}.+*?"))
    Swag.require(anchors.match("^$"))
    Swag.require(slash.match("/path\\file"))
    Swag.require(controls.match("\n\r\t\f\v\a"))
}

#test
{
    var captures = expect Parser.RegExp.create(#raw "(\d+)-(\w+)")

    Swag.require(captures.match("42-test"))
    Swag.require(captures.getCapture(1) == "42")
    Swag.require(captures[2] == "test")

    let all = captures.captures()
    Swag.require(all.count >= 2)
    Swag.require(all.contains("42"))
    Swag.require(all.contains("test"))
}

#test
{
    var overload: Parser.RegExp

    Swag.require(expect overload.match(#raw "(\d+)", "123"))
    Swag.require(overload.getCapture(1) == "123")
    Swag.require(not (expect overload.match(#raw "(\d+)", "abc")))
    Swag.require(overload.captures().isEmpty())
    Swag.require(expect overload.match("AbC", "abc", true))
}

#test
{
    var repeated = expect Parser.RegExp.create(#raw "([a-z])\1")

    Swag.require(repeated.match("ll"))
    Swag.require(repeated.getCapture(1) == "l")
    Swag.require(not repeated.match("ab"))
}

#test
{
    var repeated = expect Parser.RegExp.create(#raw "([a-z]+)-\1")

    Swag.require(repeated.match("abc-abc"))
    Swag.require(repeated.getCapture(1) == "abc")
    Swag.require(not repeated.match("abc-ab"))

    for 256
    {
        Swag.require(repeated.match("xyz-xyz"))
        Swag.require(repeated.getCapture(1) == "xyz")
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

    Swag.require(emptyGroup.match(""))
    Swag.require(emptyGroup.getCapture(1) == "")

    Swag.require(explicitEmptyGroup.match(""))
    Swag.require(explicitEmptyGroup.getCapture(1) == "")
    Swag.require(explicitEmptyRef.match("-"))
    Swag.require(explicitEmptyRef.getCapture(1) == "")
    Swag.require(explicitEmptyAltGroup.match(""))
    Swag.require(explicitEmptyAltGroup.getCapture(1) == "")
    Swag.require(explicitEmptyAltRef.match("-"))
    Swag.require(explicitEmptyAltRef.getCapture(1) == "")
    Swag.require(optionalAltRef.match("-"))
    Swag.require(optionalAltRef.getCapture(1) == "")
    Swag.require(optionalAltRef.match("a-a"))
    Swag.require(optionalAltRef.getCapture(1) == "a")
    Swag.require(countedEmptyGroup.match("a"))
    Swag.require(countedEmptyGroup.getCapture(1) == "")
    Swag.require(countedEmptyGroup.getCapture(2) == "a")
    Swag.require(countedEmptyAltGroup.match("a"))
    Swag.require(countedEmptyAltGroup.getCapture(1) == "")
    Swag.require(countedEmptyAltGroup.getCapture(2) == "a")

    Swag.require(emptyRef.match("-"))
    Swag.require(emptyRef.getCapture(1) == "")

    Swag.require(emptyTail.match("abc"))
    Swag.require(emptyTail.getCapture(1) == "abc")
    Swag.require(emptyTail.getCapture(2) == "")

    Swag.require(emptyTailSep.match("abc-"))
    Swag.require(emptyTailSep.getCapture(1) == "abc")
    Swag.require(emptyTailSep.getCapture(2) == "")

    Swag.require(nonEmptyTailRef.match("abc12-12"))
    Swag.require(nonEmptyTailRef.getCapture(1) == "abc")
    Swag.require(nonEmptyTailRef.getCapture(2) == "12")

    Swag.require(emptyTailRef.match("abc-"))
    Swag.require(emptyTailRef.getCapture(1) == "abc")
    Swag.require(emptyTailRef.getCapture(2) == "")
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

    Swag.require(baseline.match("bc"))
    let baselineCount = baseline.captures().count

    Swag.require(optionalGroup.match("bc"))
    Swag.require(optionalGroup.getCapture(2) == "c")
    Swag.require(optionalGroup.captures().count == baselineCount)

    Swag.require(optionalGroup.match("abc"))
    Swag.require(optionalGroup.getCapture(1) == "a")
    Swag.require(optionalGroup.getCapture(2) == "c")
    Swag.require(optionalGroup.match("bc"))
    Swag.require(optionalGroup.getCapture(2) == "c")
    Swag.require(optionalGroup.captures().count == baselineCount)

    Swag.require(optionalStar.match("bc"))
    Swag.require(optionalStar.getCapture(2) == "c")
    Swag.require(optionalStar.captures().count == baselineCount)

    Swag.require(optionalRef.match(""))
    Swag.require(optionalRef.match("aa"))
    Swag.require(not optionalRef.match("a"))
    Swag.require(zeroRef.match(""))
    Swag.require(not zeroRef.match("a"))
    Swag.require(zeroFirst.match("b"))
    Swag.require(zeroFirst.getCapture(2) == "b")
    Swag.require(zeroNested.match("c"))
    Swag.require(zeroNested.getCapture(1) == "")
    Swag.require(zeroNested.getCapture(2) == "")
    Swag.require(zeroNested.getCapture(3) == "c")
    Swag.require(zeroSiblingNested.match("c"))
    Swag.require(zeroSiblingNested.getCapture(1) == "")
    Swag.require(zeroSiblingNested.getCapture(2) == "")
    Swag.require(zeroSiblingNested.getCapture(3) == "")
    Swag.require(zeroSiblingNested.getCapture(4) == "c")
    Swag.require(zeroNestedRef1.match(""))
    Swag.require(zeroNestedRef2.match(""))
    Swag.require(zeroSiblingNestedRef1.match(""))
    Swag.require(zeroSiblingNestedRef2.match(""))
    Swag.require(zeroSiblingNestedRef3.match(""))
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

    Swag.require(nested.match("abc"))
    Swag.require(nested.getCapture(1) == "ab")
    Swag.require(nested.getCapture(2) == "a")
    Swag.require(nested.getCapture(3) == "c")
    Swag.require(nested.captures().count == 3)
    Swag.require(nestedRef.match("ab-ab-a"))
    Swag.require(nestedRef.getCapture(1) == "ab")
    Swag.require(nestedRef.getCapture(2) == "a")
    Swag.require(nestedCounted.match("ababc"))
    Swag.require(nestedCounted.getCapture(1) == "ab")
    Swag.require(nestedCounted.getCapture(2) == "a")
    Swag.require(nestedCounted.getCapture(3) == "c")
    Swag.require(deepNested.match("ab"))
    Swag.require(deepNested.getCapture(1) == "a")
    Swag.require(deepNested.getCapture(2) == "a")
    Swag.require(deepNested.getCapture(3) == "a")
    Swag.require(deepNested.getCapture(4) == "b")
    Swag.require(nestedSiblings.match("abc"))
    Swag.require(nestedSiblings.getCapture(1) == "ab")
    Swag.require(nestedSiblings.getCapture(2) == "a")
    Swag.require(nestedSiblings.getCapture(3) == "b")
    Swag.require(nestedSiblings.getCapture(4) == "c")
    Swag.require(nestedSiblingsRef.match("ab-ab-a-b"))
    Swag.require(nestedSiblingsRef.getCapture(1) == "ab")
    Swag.require(nestedSiblingsRef.getCapture(2) == "a")
    Swag.require(nestedSiblingsRef.getCapture(3) == "b")
    Swag.require(nestedSiblingsCounted.match("ababc"))
    Swag.require(nestedSiblingsCounted.getCapture(1) == "ab")
    Swag.require(nestedSiblingsCounted.getCapture(2) == "a")
    Swag.require(nestedSiblingsCounted.getCapture(3) == "b")
    Swag.require(nestedSiblingsCounted.getCapture(4) == "c")
    Swag.require(nestedLeadingEmptySiblingRef.match("a-a--a"))
    Swag.require(nestedLeadingEmptySiblingRef.getCapture(1) == "a")
    Swag.require(nestedLeadingEmptySiblingRef.getCapture(2) == "")
    Swag.require(nestedLeadingEmptySiblingRef.getCapture(3) == "a")
    Swag.require(nestedTrailingEmptySiblingRef.match("a-a-a-"))
    Swag.require(nestedTrailingEmptySiblingRef.getCapture(1) == "a")
    Swag.require(nestedTrailingEmptySiblingRef.getCapture(2) == "a")
    Swag.require(nestedTrailingEmptySiblingRef.getCapture(3) == "")
    Swag.require(nestedSiblingsCountedRef.match("abababab"))
    Swag.require(nestedSiblingsCountedRef.getCapture(1) == "ab")
    Swag.require(nestedSiblingsCountedRef.getCapture(2) == "a")
    Swag.require(nestedSiblingsCountedRef.getCapture(3) == "b")
    Swag.require(nestedLeadingEmptySibling.match("ab"))
    Swag.require(nestedLeadingEmptySibling.getCapture(1) == "a")
    Swag.require(nestedLeadingEmptySibling.getCapture(2) == "")
    Swag.require(nestedLeadingEmptySibling.getCapture(3) == "a")
    Swag.require(nestedLeadingEmptySibling.getCapture(4) == "b")
    Swag.require(nestedTrailingEmptySibling.match("ab"))
    Swag.require(nestedTrailingEmptySibling.getCapture(1) == "a")
    Swag.require(nestedTrailingEmptySibling.getCapture(2) == "a")
    Swag.require(nestedTrailingEmptySibling.getCapture(3) == "")
    Swag.require(nestedTrailingEmptySibling.getCapture(4) == "b")
    Swag.require(nestedLeadingAltSibling.match("bc"))
    Swag.require(nestedLeadingAltSibling.getCapture(1) == "b")
    Swag.require(nestedLeadingAltSibling.getCapture(2) == "")
    Swag.require(nestedLeadingAltSibling.getCapture(3) == "b")
    Swag.require(nestedLeadingAltSibling.getCapture(4) == "c")
    Swag.require(nestedLeadingAltSibling.match("abc"))
    Swag.require(nestedLeadingAltSibling.getCapture(1) == "ab")
    Swag.require(nestedLeadingAltSibling.getCapture(2) == "a")
    Swag.require(nestedLeadingAltSibling.getCapture(3) == "b")
    Swag.require(nestedLeadingAltSibling.getCapture(4) == "c")
    Swag.require(nestedTrailingAltSibling.match("ac"))
    Swag.require(nestedTrailingAltSibling.getCapture(1) == "a")
    Swag.require(nestedTrailingAltSibling.getCapture(2) == "a")
    Swag.require(nestedTrailingAltSibling.getCapture(3) == "")
    Swag.require(nestedTrailingAltSibling.getCapture(4) == "c")
    Swag.require(nestedTrailingAltSibling.match("abc"))
    Swag.require(nestedTrailingAltSibling.getCapture(1) == "ab")
    Swag.require(nestedTrailingAltSibling.getCapture(2) == "a")
    Swag.require(nestedTrailingAltSibling.getCapture(3) == "b")
    Swag.require(nestedTrailingAltSibling.getCapture(4) == "c")
    Swag.require(deepNestedRef.match("a-a-a-a"))
    Swag.require(deepNestedRef.getCapture(1) == "a")
    Swag.require(deepNestedRef.getCapture(2) == "a")
    Swag.require(deepNestedRef.getCapture(3) == "a")
    Swag.require(nestedLeadingAltSiblingRef.match("b-b--b"))
    Swag.require(nestedLeadingAltSiblingRef.getCapture(1) == "b")
    Swag.require(nestedLeadingAltSiblingRef.getCapture(2) == "")
    Swag.require(nestedLeadingAltSiblingRef.getCapture(3) == "b")
    Swag.require(nestedTrailingAltSiblingRef.match("a-a-a-"))
    Swag.require(nestedTrailingAltSiblingRef.getCapture(1) == "a")
    Swag.require(nestedTrailingAltSiblingRef.getCapture(2) == "a")
    Swag.require(nestedTrailingAltSiblingRef.getCapture(3) == "")
}

#test
{
    var digits = expect Parser.RegExp.create(#raw "\d+")

    let prefix = digits.partialMatch("123abc")
    Swag.require(prefix != null)
    Swag.require(cast(string?, prefix) == "123")
    Swag.require(digits.partialMatch("abc123") == null)
}

#test
{
    var anchored = expect Parser.RegExp.create(#raw "^(\d+)")

    let first = anchored.partialMatch("123abc")
    Swag.require(first != null)
    Swag.require(cast(string?, first) == "123")
    Swag.require(anchored.getCapture(1) == "123")

    let second = anchored.partialMatch("456def")
    Swag.require(second != null)
    Swag.require(cast(string?, second) == "456")
    Swag.require(anchored.getCapture(1) == "456")

    Swag.require(anchored.partialMatch("abc") == null)
    Swag.require(anchored.captures().isEmpty())
}

#test
{
    var anchored = expect Parser.RegExp.create(#raw "^(\d+)")

    for 256
    {
        let prefix = anchored.partialMatch("789xyz")
        Swag.require(prefix != null)
        Swag.require(cast(string?, prefix) == "789")
        Swag.require(anchored.getCapture(1) == "789")
    }
}

#test
{
    let all = expect Parser.RegExp.grepAll(#raw "\d+", "a12b345c6")

    Swag.require(all.count == 3)
    Swag.require(all[0] == "12")
    Swag.require(all[1] == "345")
    Swag.require(all[2] == "6")
}

#test
{
    let first = expect Parser.RegExp.grep(#raw "\d+", "aa12bb34")
    let none  = expect Parser.RegExp.grepAll(#raw "\d+", null)
    var part  = expect Parser.RegExp.create(#raw "\d+")

    Swag.require(first == "12")
    Swag.require(none.isEmpty())
    Swag.require(part.partialMatch(null) == null)
}

#test
{
    var captures = expect Parser.RegExp.create(#raw "(\d+)")

    for 256
    {
        let first = captures.grep("a12")
        Swag.require(first != null)
        Swag.require(cast(string?, first) == "12")
        Swag.require(captures.getCapture(1) == "12")

        Swag.require(captures.grep("abc") == null)
        Swag.require(captures.captures().isEmpty())

        let second = captures.grep("34x")
        Swag.require(second != null)
        Swag.require(cast(string?, second) == "34")
        Swag.require(captures.getCapture(1) == "34")
    }
}

#test
{
    var endOfBuffer = expect Parser.RegExp.create(#raw "$")

    let match = endOfBuffer.grep("abc")
    Swag.require(match != null)
    Swag.require(cast(string?, match) == "")

    let all = endOfBuffer.grepAll("abc")
    Swag.require(all.count == 1)
    Swag.require(all[0] == "")
}

#test
{
    var empty = expect Parser.RegExp.create(#raw "^$")

    let match = empty.grep("")
    Swag.require(match != null)
    Swag.require(cast(string?, match) == "")

    let all = empty.grepAll("")
    Swag.require(all.count == 1)
    Swag.require(all[0] == "")
}

#test
{
    var words  = expect Parser.RegExp.create(#raw "\bcat\b")
    let first  = words.grep("\u00E9 scatter cat")
    let second = words.grep("\u00E9 scatter cat")

    Swag.require(first != null)
    Swag.require(cast(string?, first) == "cat")
    Swag.require(second != null)
    Swag.require(cast(string?, second) == "cat")
    Swag.require(words.grep("\u00E9 scatter catnap") == null)
}

#test
{
    var boundary = expect Parser.RegExp.create(#raw "\b")

    let word = boundary.grep("cat")
    Swag.require(word != null)
    Swag.require(cast(string?, word) == "")

    Swag.require(boundary.grep("!?") == null)
    Swag.require(boundary.grep("") == null)

    let all = boundary.grepAll(" cat!")
    Swag.require(all.count == 2)
    Swag.require(all[0] == "")
    Swag.require(all[1] == "")
}

#test
{
    let all = expect Parser.RegExp.grepAll(#raw "\d+", "\u00E912\u03B2345")

    Swag.require(all.count == 2)
    Swag.require(all[0] == "12")
    Swag.require(all[1] == "345")
}

#test
{
    var anchored = expect Parser.RegExp.create(#raw "^\d+")

    let atStart = anchored.grep("12 34")
    Swag.require(atStart != null)
    Swag.require(cast(string?, atStart) == "12")
    Swag.require(anchored.grep("aa12") == null)

    let all = anchored.grepAll("12 34")
    Swag.require(all.count == 1)
    Swag.require(all[0] == "12")
}

#test
{
    var words = expect Parser.RegExp.create(#raw "\bcat\b")

    Swag.require(words.grep("\u00E9cat") == null)

    let match = words.grep("\u00E9 cat")
    Swag.require(match != null)
    Swag.require(cast(string?, match) == "cat")

    let all = words.grepAll("\u00E9 cat catnap cat")
    Swag.require(all.count == 2)
    Swag.require(all[0] == "cat")
    Swag.require(all[1] == "cat")
}

#test
{
    var anchored = expect Parser.RegExp.create(#raw "^\bcat\b$")
    var letters  = expect Parser.RegExp.create(#raw "\pL+")

    Swag.require(anchored.match("cat"))
    Swag.require(not anchored.match("scatter"))
    Swag.require(letters.match("Cafe"))
    Swag.require(letters.match("CafeNoir"))
}

#test
{
    var optional   = expect Parser.RegExp.create(#raw "colou?r")
    var revRange   = expect Parser.RegExp.create(#raw "[d-b]+")
    var nonLetters = expect Parser.RegExp.create(#raw "[^a-z]+")

    Swag.require(optional.match("color"))
    Swag.require(optional.match("colour"))
    Swag.require(not optional.match("colouur"))
    Swag.require(revRange.match("bcd"))
    Swag.require(not revRange.match("abe"))
    Swag.require(nonLetters.match("123!?"))
    Swag.require(not nonLetters.match("abc"))
}

#test
{
    var star = expect Parser.RegExp.create(#raw "ba{0,}c")
    var opt  = expect Parser.RegExp.create(#raw "ba{0,1}c")
    var plus = expect Parser.RegExp.create(#raw "ba{1,}c")
    var same = expect Parser.RegExp.create(#raw "ba{1,1}c")

    Swag.require(star.match("bc"))
    Swag.require(star.match("baaac"))
    Swag.require(opt.match("bc"))
    Swag.require(opt.match("bac"))
    Swag.require(not opt.match("baac"))
    Swag.require(plus.match("bac"))
    Swag.require(plus.match("baaac"))
    Swag.require(not plus.match("bc"))
    Swag.require(same.match("bac"))
    Swag.require(not same.match("baac"))
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

    Swag.require(blanks.match(" \tabc"))
    Swag.require(nonDigits.match("abc!?"))
    Swag.require(not nonDigits.match("abc3"))
    Swag.require(nonWords.match("!? "))
    Swag.require(not nonWords.match("word_"))
    Swag.require(nonSpaces.match("abc!?"))
    Swag.require(not nonSpaces.match("abc "))
    Swag.require(unicodeLow.match("AbC"))
    Swag.require(unicodeUp.match("ABC"))
    Swag.require(not unicodeUp.match("AbC"))
    Swag.require(unicodeNum.match("123"))
    Swag.require(unicodeMath.match("+="))
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

    Swag.require(counted.match("abbc"))
    Swag.require(counted.match("abbbc"))
    Swag.require(not counted.match("abc"))
    Swag.require(not counted.match("abbbbc"))
    Swag.require(countedGroup.match("aab"))
    Swag.require(countedGroup.getCapture(1) == "a")
    Swag.require(countedGroup.getCapture(2) == "b")
    Swag.require(countedAltGroup.match("abc"))
    Swag.require(countedAltGroup.getCapture(1) == "b")
    Swag.require(countedAltGroup.getCapture(2) == "c")
    Swag.require(countedAltGroup.captures().count == 2)
    Swag.require(countedEmptyAltRange.match("b"))
    Swag.require(countedEmptyAltRange.getCapture(1) == "")
    Swag.require(countedEmptyAltRange.getCapture(2) == "b")
    Swag.require(countedEmptyAltRange.match("ab"))
    Swag.require(countedEmptyAltRange.getCapture(1) == "a")
    Swag.require(countedEmptyAltRange.getCapture(2) == "b")
    Swag.require(countedEmptyAltRange.match("aab"))
    Swag.require(countedEmptyAltRange.getCapture(1) == "a")
    Swag.require(countedEmptyAltRange.getCapture(2) == "b")
    Swag.require(countedSiblingRange.match("c"))
    Swag.require(countedSiblingRange.getCapture(1) == "")
    Swag.require(countedSiblingRange.getCapture(2) == "")
    Swag.require(countedSiblingRange.getCapture(3) == "")
    Swag.require(countedSiblingRange.getCapture(4) == "c")
    Swag.require(countedSiblingRange.match("abc"))
    Swag.require(countedSiblingRange.getCapture(1) == "ab")
    Swag.require(countedSiblingRange.getCapture(2) == "a")
    Swag.require(countedSiblingRange.getCapture(3) == "b")
    Swag.require(countedSiblingRange.getCapture(4) == "c")
    Swag.require(countedSiblingRange.match("ababc"))
    Swag.require(countedSiblingRange.getCapture(1) == "ab")
    Swag.require(countedSiblingRange.getCapture(2) == "a")
    Swag.require(countedSiblingRange.getCapture(3) == "b")
    Swag.require(countedSiblingRange.getCapture(4) == "c")
    Swag.require(countedSiblingRangeRef.match(""))
    Swag.require(countedSiblingRangeRef.match("ababab"))
    Swag.require(countedSiblingRangeRef.getCapture(1) == "ab")
    Swag.require(countedSiblingRangeRef.getCapture(2) == "a")
    Swag.require(countedSiblingRangeRef.getCapture(3) == "b")
    Swag.require(countedSiblingRangeRef.match("abababab"))
    Swag.require(countedSiblingRangeRef.getCapture(1) == "ab")
    Swag.require(countedSiblingRangeRef.getCapture(2) == "a")
    Swag.require(countedSiblingRangeRef.getCapture(3) == "b")
    Swag.require(countedLeadingAltSibling.match("babc"))
    Swag.require(countedLeadingAltSibling.getCapture(1) == "ab")
    Swag.require(countedLeadingAltSibling.getCapture(2) == "a")
    Swag.require(countedLeadingAltSibling.getCapture(3) == "b")
    Swag.require(countedLeadingAltSibling.getCapture(4) == "c")
    Swag.require(countedLeadingAltSibling.match("abbc"))
    Swag.require(countedLeadingAltSibling.getCapture(1) == "b")
    Swag.require(countedLeadingAltSibling.getCapture(2) == "")
    Swag.require(countedLeadingAltSibling.getCapture(3) == "b")
    Swag.require(countedLeadingAltSibling.getCapture(4) == "c")
    Swag.require(countedTrailingAltSibling.match("abac"))
    Swag.require(countedTrailingAltSibling.getCapture(1) == "a")
    Swag.require(countedTrailingAltSibling.getCapture(2) == "a")
    Swag.require(countedTrailingAltSibling.getCapture(3) == "")
    Swag.require(countedTrailingAltSibling.getCapture(4) == "c")
    Swag.require(countedTrailingAltSibling.match("aabc"))
    Swag.require(countedTrailingAltSibling.getCapture(1) == "ab")
    Swag.require(countedTrailingAltSibling.getCapture(2) == "a")
    Swag.require(countedTrailingAltSibling.getCapture(3) == "b")
    Swag.require(countedTrailingAltSibling.getCapture(4) == "c")
    Swag.require(countedLeadingAltSiblingRange.match("c"))
    Swag.require(countedLeadingAltSiblingRange.getCapture(1) == "")
    Swag.require(countedLeadingAltSiblingRange.getCapture(2) == "")
    Swag.require(countedLeadingAltSiblingRange.getCapture(3) == "")
    Swag.require(countedLeadingAltSiblingRange.getCapture(4) == "c")
    Swag.require(countedLeadingAltSiblingRange.match("bc"))
    Swag.require(countedLeadingAltSiblingRange.getCapture(1) == "b")
    Swag.require(countedLeadingAltSiblingRange.getCapture(2) == "")
    Swag.require(countedLeadingAltSiblingRange.getCapture(3) == "b")
    Swag.require(countedLeadingAltSiblingRange.getCapture(4) == "c")
    Swag.require(countedLeadingAltSiblingRange.match("babc"))
    Swag.require(countedLeadingAltSiblingRange.getCapture(1) == "ab")
    Swag.require(countedLeadingAltSiblingRange.getCapture(2) == "a")
    Swag.require(countedLeadingAltSiblingRange.getCapture(3) == "b")
    Swag.require(countedLeadingAltSiblingRange.getCapture(4) == "c")
    Swag.require(countedTrailingAltSiblingRange.match("c"))
    Swag.require(countedTrailingAltSiblingRange.getCapture(1) == "")
    Swag.require(countedTrailingAltSiblingRange.getCapture(2) == "")
    Swag.require(countedTrailingAltSiblingRange.getCapture(3) == "")
    Swag.require(countedTrailingAltSiblingRange.getCapture(4) == "c")
    Swag.require(countedTrailingAltSiblingRange.match("ac"))
    Swag.require(countedTrailingAltSiblingRange.getCapture(1) == "a")
    Swag.require(countedTrailingAltSiblingRange.getCapture(2) == "a")
    Swag.require(countedTrailingAltSiblingRange.getCapture(3) == "")
    Swag.require(countedTrailingAltSiblingRange.getCapture(4) == "c")
    Swag.require(countedTrailingAltSiblingRange.match("abac"))
    Swag.require(countedTrailingAltSiblingRange.getCapture(1) == "a")
    Swag.require(countedTrailingAltSiblingRange.getCapture(2) == "a")
    Swag.require(countedTrailingAltSiblingRange.getCapture(3) == "")
    Swag.require(countedTrailingAltSiblingRange.getCapture(4) == "c")
    Swag.require(countedLeadingAltSiblingRangeRef.match(""))
    Swag.require(countedLeadingAltSiblingRangeRef.match("bbb"))
    Swag.require(countedLeadingAltSiblingRangeRef.getCapture(1) == "b")
    Swag.require(countedLeadingAltSiblingRangeRef.getCapture(2) == "")
    Swag.require(countedLeadingAltSiblingRangeRef.getCapture(3) == "b")
    Swag.require(countedLeadingAltSiblingRangeRef.match("ababab"))
    Swag.require(countedLeadingAltSiblingRangeRef.getCapture(1) == "ab")
    Swag.require(countedLeadingAltSiblingRangeRef.getCapture(2) == "a")
    Swag.require(countedLeadingAltSiblingRangeRef.getCapture(3) == "b")
    Swag.require(countedTrailingAltSiblingRangeRef.match(""))
    Swag.require(countedTrailingAltSiblingRangeRef.match("aaa"))
    Swag.require(countedTrailingAltSiblingRangeRef.getCapture(1) == "a")
    Swag.require(countedTrailingAltSiblingRangeRef.getCapture(2) == "a")
    Swag.require(countedTrailingAltSiblingRangeRef.getCapture(3) == "")
    Swag.require(countedTrailingAltSiblingRangeRef.match("ababab"))
    Swag.require(countedTrailingAltSiblingRangeRef.getCapture(1) == "ab")
    Swag.require(countedTrailingAltSiblingRangeRef.getCapture(2) == "a")
    Swag.require(countedTrailingAltSiblingRangeRef.getCapture(3) == "b")
    Swag.require(countedRangeGroup.match("b"))
    Swag.require(countedRangeGroup.getCapture(2) == "b")
    Swag.require(countedRangeGroup.match("ab"))
    Swag.require(countedRangeGroup.getCapture(1) == "a")
    Swag.require(countedRangeGroup.getCapture(2) == "b")
    Swag.require(countedRangeGroup.match("aab"))
    Swag.require(countedRangeGroup.getCapture(1) == "a")
    Swag.require(countedRangeGroup.getCapture(2) == "b")
    Swag.require(countedBackRef.match("abb"))
    Swag.require(countedBackRef.match("baa"))
    Swag.require(not countedBackRef.match("aba"))
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

    Swag.require(emptyExactZero.match(""))
    Swag.require(not emptyExactZero.match("a"))
    Swag.require(emptyGroupZero.match(""))
    Swag.require(not emptyGroupZero.match("ab"))
    Swag.require(emptyDigitZero.match(""))
    Swag.require(not emptyDigitZero.match("1"))
    Swag.require(emptyUnicodeZero.match(""))
    Swag.require(not emptyUnicodeZero.match("7"))
    Swag.require(leftEmptyAlt.match(""))
    Swag.require(leftEmptyAlt.match("b"))
    Swag.require(not leftEmptyAlt.match("a"))
    Swag.require(rightEmptyAlt.match(""))
    Swag.require(rightEmptyAlt.match("a"))
    Swag.require(not rightEmptyAlt.match("b"))
    Swag.require(innerEmptyAlt.match("c"))
    Swag.require(innerEmptyAlt.match("ac"))
    Swag.require(not innerEmptyAlt.match("bc"))
    let emptyPrefix = emptyExactZero.partialMatch("abc")
    Swag.require(emptyPrefix != null)
    Swag.require(cast(string?, emptyPrefix) == "")
    let emptyFirst = emptyDigitZero.grep("abc")
    Swag.require(emptyFirst != null)
    Swag.require(cast(string?, emptyFirst) == "")
    let emptyAll = emptyGroupZero.grepAll("ab")
    Swag.require(emptyAll.count == 3)
    Swag.require(emptyAll[0] == "")
    Swag.require(emptyAll[1] == "")
    Swag.require(emptyAll[2] == "")
    Swag.require(exactZero.match("bc"))
    Swag.require(not exactZero.match("abc"))
    Swag.require(rangeZero.match("c"))
    Swag.require(not rangeZero.match("ac"))
    Swag.require(groupedZero.match("c"))
    Swag.require(not groupedZero.match("abc"))
    Swag.require(escapedZero.match("a"))
    Swag.require(escapedZero.match("(a"))
    Swag.require(escapedZero.match("((a"))
    Swag.require(not escapedZero.match("(((a"))
    Swag.require(escapedCloseZero.match("a"))
    Swag.require(escapedCloseZero.match(")a"))
    Swag.require(escapedCloseZero.match("))a"))
    Swag.require(not escapedCloseZero.match(")))a"))
    Swag.require(escapedPipeZero.match("a"))
    Swag.require(escapedPipeZero.match("|a"))
    Swag.require(escapedPipeZero.match("||a"))
    Swag.require(not escapedPipeZero.match("|||a"))
    Swag.require(digitExactZero.match("a"))
    Swag.require(not digitExactZero.match("1a"))
    Swag.require(digitUpToTwo.match("a"))
    Swag.require(digitUpToTwo.match("1a"))
    Swag.require(digitUpToTwo.match("12a"))
    Swag.require(not digitUpToTwo.match("123a"))
    Swag.require(unicodeUpToTwo.match("a"))
    Swag.require(unicodeUpToTwo.match("42a"))
    Swag.require(not unicodeUpToTwo.match("123a"))
    Swag.require(anythingUpToTwo.match("a"))
    Swag.require(anythingUpToTwo.match("xa"))
    Swag.require(anythingUpToTwo.match("xya"))
    Swag.require(not anythingUpToTwo.match("xyza"))
    Swag.require(upToTwo.match("bc"))
    Swag.require(upToTwo.match("abc"))
    Swag.require(upToTwo.match("aabc"))
    Swag.require(not upToTwo.match("aaabc"))
    Swag.require(groupUpToTwo.match("c"))
    Swag.require(groupUpToTwo.match("abc"))
    Swag.require(groupUpToTwo.match("ababc"))
    Swag.require(not groupUpToTwo.match("abababc"))
}

#test
{
    var errOutcome: Swag.Error
    discard catch Parser.RegExp.create(#raw "a{2,1}") as errOutcome
    let err = errOutcome.value()

    Swag.require(err != null)
    Swag.require(err is Errors.SyntaxError)
}

#test
{
    var err2Outcome: Swag.Error
    discard catch Parser.RegExp.create(#raw "{1}") as err2Outcome
    let err2 = err2Outcome.value()

    Swag.require(err2 != null)
    Swag.require(err2 is Errors.SyntaxError)
}

#test
{
    var err3Outcome: Swag.Error
    discard catch Parser.RegExp.create(#raw "(") as err3Outcome
    let err3 = err3Outcome.value()

    Swag.require(err3 != null)
    Swag.require(err3 is Errors.SyntaxError)
}

#test
{
    var err4Outcome: Swag.Error
    discard catch Parser.RegExp.create(#raw "[abc") as err4Outcome
    let err4 = err4Outcome.value()

    Swag.require(err4 != null)
    Swag.require(err4 is Errors.SyntaxError)
}

#test
{
    var err5Outcome: Swag.Error
    discard catch Parser.RegExp.create(#raw "\pQ") as err5Outcome
    let err5 = err5Outcome.value()

    Swag.require(err5 != null)
    Swag.require(err5 is Errors.SyntaxError)
}

#test
{
    var err6Outcome: Swag.Error
    discard catch Parser.RegExp.create(#raw "\p{Lx}") as err6Outcome
    let err6 = err6Outcome.value()

    Swag.require(err6 != null)
    Swag.require(err6 is Errors.SyntaxError)
}

#test
{
    var err7Outcome: Swag.Error
    discard catch Parser.RegExp.create("\\") as err7Outcome
    let err7 = err7Outcome.value()

    Swag.require(err7 != null)
    Swag.require(err7 is Errors.SyntaxError)
}

#test
{
    var err8Outcome: Swag.Error
    discard catch Parser.RegExp.create(#raw "\q") as err8Outcome
    let err8 = err8Outcome.value()

    Swag.require(err8 != null)
    Swag.require(err8 is Errors.SyntaxError)
}

#test
{
    var err9Outcome: Swag.Error
    discard catch Parser.RegExp.create(#raw "[\q]") as err9Outcome
    let err9 = err9Outcome.value()

    Swag.require(err9 != null)
    Swag.require(err9 is Errors.SyntaxError)
}

#test
{
    var err10Outcome: Swag.Error
    discard catch Parser.RegExp.create(#raw "\p") as err10Outcome
    let err10 = err10Outcome.value()

    Swag.require(err10 != null)
    Swag.require(err10 is Errors.SyntaxError)
}

#test
{
    var err11Outcome: Swag.Error
    discard catch Parser.RegExp.create(#raw "\p{L") as err11Outcome
    let err11 = err11Outcome.value()

    Swag.require(err11 != null)
    Swag.require(err11 is Errors.SyntaxError)
}

#test
{
    var err12Outcome: Swag.Error
    discard catch Parser.RegExp.create(#raw "[[:bogus:]]") as err12Outcome
    let err12 = err12Outcome.value()

    Swag.require(err12 != null)
    Swag.require(err12 is Errors.SyntaxError)
}

#test
{
    var err13Outcome: Swag.Error
    discard catch Parser.RegExp.create(#raw "[[:digit]]") as err13Outcome
    let err13 = err13Outcome.value()

    Swag.require(err13 != null)
    Swag.require(err13 is Errors.SyntaxError)
}

#test
{
    // A negated class rejects every value it lists, whatever the list is made of.
    var noLetters   = expect Parser.RegExp.create(#raw "[^abc]+")
    var noMixed     = expect Parser.RegExp.create(#raw "[^a-c9]+")
    var noClass     = expect Parser.RegExp.create(#raw "[^\d\s]+")
    var noSingle    = expect Parser.RegExp.create(#raw "[^x]")
    var noCaseAware = expect Parser.RegExp.create(#raw "[^a]+", true)

    Swag.require(noLetters.match("xyz"))
    Swag.require(not noLetters.match("abc"))
    Swag.require(not noLetters.match("xbz"))
    Swag.require(noMixed.match("xyz8"))
    Swag.require(not noMixed.match("9"))
    Swag.require(not noMixed.match("b"))
    Swag.require(noClass.match("ab!"))
    Swag.require(not noClass.match("a1"))
    Swag.require(not noClass.match("a b"))
    Swag.require(noSingle.match("y"))
    Swag.require(not noSingle.match("x"))
    Swag.require(noCaseAware.match("bc"))
    Swag.require(not noCaseAware.match("A"))
    Swag.require(not noCaseAware.match("a"))
}

#test
{
    var group      = expect Parser.RegExp.create(#raw "(?:ab)+")
    var mixed      = expect Parser.RegExp.create(#raw "(?:ab)(c)")
    var nestedOnly = expect Parser.RegExp.create(#raw "(?:(a)b)+")

    Swag.require(group.match("ababab"))
    Swag.require(not group.match("aba"))
    Swag.require(group.captureCount() == 0)
    Swag.require(mixed.match("abc"))
    Swag.require(mixed.getCapture(1) == "c")
    Swag.require(mixed.captureCount() == 1)
    Swag.require(nestedOnly.match("abab"))
    Swag.require(nestedOnly.getCapture(1) == "a")
}

#test
{
    var angle  = expect Parser.RegExp.create(#raw "(?<year>\d{4})-(?<month>\d{2})")
    var quoted = expect Parser.RegExp.create(#raw "(?'word'\l+)")
    var python = expect Parser.RegExp.create(#raw "(?P<num>\d+)")

    Swag.require(angle.match("2024-07"))
    Swag.require(angle.getCapture("year") == "2024")
    Swag.require(angle.getCapture("month") == "07")
    Swag.require(angle.getCapture("day") == "")
    Swag.require(angle.getCapture(1) == "2024")
    Swag.require(quoted.match("hello"))
    Swag.require(quoted.getCapture("word") == "hello")
    Swag.require(python.match("42"))
    Swag.require(python.getCapture("num") == "42")
}

#test
{
    var lazyStar  = expect Parser.RegExp.create(#raw "<(.*?)>")
    var lazyPlus  = expect Parser.RegExp.create(#raw "a+?b")
    var lazyOpt   = expect Parser.RegExp.create(#raw "ab??")
    var lazyCount = expect Parser.RegExp.create(#raw "a{1,3}?b")

    let tag = lazyStar.grep("<one><two>")
    Swag.require(tag != null)
    Swag.require(cast(string?, tag) == "<one>")
    Swag.require(lazyStar.getCapture(1) == "one")

    Swag.require(lazyPlus.match("aab"))

    let shortest = lazyOpt.grep("ab")
    Swag.require(shortest != null)
    Swag.require(cast(string?, shortest) == "a")

    Swag.require(lazyCount.match("aab"))
    Swag.require(not lazyCount.match("aaaab"))
}

#test
{
    var scoped   = expect Parser.RegExp.create(#raw "(?i)abc")
    var partial  = expect Parser.RegExp.create(#raw "ab(?i:cd)ef")
    var disabled = expect Parser.RegExp.create(#raw "(?i)ab(?-i)cd")
    var lines    = expect Parser.RegExp.create(#raw "(?m)^b$")
    var noDotAll = expect Parser.RegExp.create(#raw "(?-s)a.b")

    Swag.require(scoped.match("AbC"))
    Swag.require(partial.match("abCDef"))
    Swag.require(not partial.match("ABcdef"))
    Swag.require(disabled.match("ABcd"))
    Swag.require(not disabled.match("ABCD"))

    let line = lines.grep("a\nb\nc")
    Swag.require(line != null)
    Swag.require(cast(string?, line) == "b")

    Swag.require(noDotAll.match("axb"))
    Swag.require(not noDotAll.match("a\nb"))
}

#test
{
    var whole       = expect Parser.RegExp.create(#raw "\Aabc\z")
    var notBoundary = expect Parser.RegExp.create(#raw "a\Bb")
    var insideWord  = expect Parser.RegExp.create(#raw "\Bcat\B")

    Swag.require(whole.match("abc"))
    Swag.require(whole.grep("xabc") == null)
    Swag.require(notBoundary.match("ab"))

    let inside = insideWord.grep("scatter")
    Swag.require(inside != null)
    Swag.require(cast(string?, inside) == "cat")
    Swag.require(insideWord.grep("a cat") == null)
}

#test
{
    var hexByte = expect Parser.RegExp.create(#raw "\x41\x42")
    var hexRune = expect Parser.RegExp.create(#raw "\x{00E9}")
    var hexWide = expect Parser.RegExp.create(#raw "\x{1F600}+")
    var escape  = expect Parser.RegExp.create(#raw "\e")
    var nul     = expect Parser.RegExp.create(#raw "a\0b")
    var inClass = expect Parser.RegExp.create(#raw "[\x41-\x43]+")

    Swag.require(hexByte.match("AB"))
    Swag.require(hexRune.match("\u00E9"))
    Swag.require(hexWide.match("\U0001F600\U0001F600"))
    Swag.require(escape.match("\u001B"))
    Swag.require(not nul.match("ab"))
    Swag.require(inClass.match("ABC"))
    Swag.require(not inClass.match("D"))
}

#test
{
    var punct = expect Parser.RegExp.create(#raw "[[:punct:]]+")
    var cntrl = expect Parser.RegExp.create(#raw "[[:cntrl:]]+")
    var graph = expect Parser.RegExp.create(#raw "[[:graph:]]+")
    var print = expect Parser.RegExp.create(#raw "[[:print:]]+")

    Swag.require(punct.match("!?;"))
    Swag.require(not punct.match("a"))
    Swag.require(cntrl.match("\u0001\u0002"))
    Swag.require(not cntrl.match(" "))
    Swag.require(graph.match("ab!"))
    Swag.require(not graph.match("a b"))
    Swag.require(print.match("a b"))
    Swag.require(not print.match("a\tb"))
}

#test
{
    var decimals   = expect Parser.RegExp.create(#raw "\p{Nd}+")
    var notLetters = expect Parser.RegExp.create(#raw "\P{L}+")
    var letters    = expect Parser.RegExp.create(#raw "\p{Letter}+")
    var titles     = expect Parser.RegExp.create(#raw "\p{Lt}")

    Swag.require(decimals.match("123"))
    Swag.require(not decimals.match("12a"))
    Swag.require(notLetters.match("12!?"))
    Swag.require(not notLetters.match("12a"))
    Swag.require(letters.match("Caf\u00E9"))
    Swag.require(titles.match("\u01C5"))
}

#test
{
    // Separators and White_Space overlap, but whitespace controls are not separators.
    var separators    = expect Parser.RegExp.create(#raw "\p{Z}+")
    var named         = expect Parser.RegExp.create(#raw "\p{Separator}+")
    var spaces        = expect Parser.RegExp.create(#raw "\p{White_Space}+")
    var notSeparators = expect Parser.RegExp.create(#raw "\P{Z}+")
    let allSeparators = " \u00A0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200A\u2028\u2029\u202F\u205F\u3000"
    Swag.require(separators.match(allSeparators) and named.match(allSeparators))
    Swag.require(spaces.match(allSeparators))
    for control in ["\t", "\n", "\v", "\f", "\r", "\u0085"]
    {
        Swag.require(not separators.match(control) and not named.match(control))
        Swag.require(spaces.match(control) and notSeparators.match(control))
    }

    Swag.require(not spaces.match("\u200B"))
    Swag.require(not separators.match("\u200B"))
}

#test
{
    // The automaton works over UTF-8 bytes, so a class of scalar values above ASCII must
    // still match whole characters and nothing in between.
    var accented  = expect Parser.RegExp.create(#raw "[\x{00E0}-\x{00FF}]+")
    var anyRune   = expect Parser.RegExp.create(#raw "^.{3}$")
    var mixed     = expect Parser.RegExp.create(#raw "\w+\x{00E9}\w+")
    var wideClass = expect Parser.RegExp.create(#raw "[a\x{4E2D}\x{1F600}]+")

    Swag.require(accented.match("\u00E9\u00FF"))
    Swag.require(not accented.match("a"))
    Swag.require(anyRune.match("a\u00E9\u4E2D"))
    Swag.require(not anyRune.match("ab"))
    Swag.require(mixed.match("ab\u00E9cd"))
    Swag.require(wideClass.match("a\u4E2D\U0001F600a"))
    Swag.require(not wideClass.match("b"))

    let all = expect Parser.RegExp.grepAll(#raw "\x{00E9}+", "a\u00E9b\u00E9\u00E9c")
    Swag.require(all.count == 2)
    Swag.require(all[0] == "\u00E9")
    Swag.require(all[1] == "\u00E9\u00E9")
}

#test
{
    var digits = expect Parser.RegExp.create(#raw "\d+")

    let first = digits.find("ab 12 cd 345")
    Swag.require(first.found)
    Swag.require(first.span.start == 3)
    Swag.require(first.span.end == 5)

    let second = digits.find("ab 12 cd 345", 5)
    Swag.require(second.found)
    Swag.require(second.span.start == 9)
    Swag.require(second.span.end == 12)

    Swag.require(not digits.find("abc").found)
    Swag.require(not digits.find(null).found)

    let spans = digits.findAll("ab 12 cd 345")
    Swag.require(spans.count == 2)
    Swag.require(spans[0].start == 3)
    Swag.require(spans[1].end == 12)
}

// A failed search from beyond the subject clears captures from the prior subject.
#test
{
    var re  = expect Parser.RegExp.create("(a)")
    let hit = re.find("a")
    Swag.require(hit.found and re.getCapture(1) == "a")

    let miss = re.find("x", 2)
    Swag.require(not miss.found)
    Swag.require(not re.captureSpan(0).found)
    Swag.require(re.captures().isEmpty())
    Swag.require(re.getCapture(1).count == 0)
}

#test
{
    var re = expect Parser.RegExp.create("(a)")
    Swag.require(re.match("a"))
    Swag.require(re.grep(null) == null)
    Swag.require(not re.captureSpan(0).found and re.getCapture(1).count == 0)

    Swag.require(re.match("a"))
    Swag.require(re.partialMatch(null) == null)
    Swag.require(not re.captureSpan(0).found and re.getCapture(1).count == 0)
}

#test
{
    var parts = expect Parser.RegExp.create(#raw "(\w+)@(\w+)")

    Swag.require(parts.match("user@host"))

    let whole = parts.captureSpan(0)
    Swag.require(whole.found)
    Swag.require(whole.span.start == 0)
    Swag.require(whole.span.end == 9)

    let user = parts.captureSpan(1)
    Swag.require(user.found)
    Swag.require(user.span.start == 0)
    Swag.require(user.span.end == 4)

    let host = parts.captureSpan(2)
    Swag.require(host.found)
    Swag.require(host.span.start == 5)

    Swag.require(not parts.captureSpan(3).found)
}

#test
{
    var swap  = expect Parser.RegExp.create(#raw "(\w+)-(\w+)")
    var named = expect Parser.RegExp.create(#raw "(?<key>\w+)=(?<value>\w+)")
    var vowel = expect Parser.RegExp.create(#raw "[aeiou]")

    Swag.require(swap.replaceAll("ab-cd and ef-gh", "$2:$1") == "cd:ab and gh:ef")
    Swag.require(named.replaceAll("x=1", "${value}/${key}") == "1/x")
    Swag.require(vowel.replaceAll("banana", "*") == "b*n*n*")
    Swag.require(vowel.replaceAll("xyz", "*") == "xyz")
    Swag.require(swap.replaceAll("ab-cd", "$$0 is $0") == "$0 is ab-cd")
    Swag.require(vowel.replaceAll(null, "*") == "")
}

#test
{
    var comma = expect Parser.RegExp.create(#raw ",\s*")
    var wide  = expect Parser.RegExp.create(#raw "\d+")

    let fields = comma.split("a, b,c ,d")
    Swag.require(fields.count == 4)
    Swag.require(fields[0] == "a")
    Swag.require(fields[1] == "b")
    Swag.require(fields[2] == "c ")
    Swag.require(fields[3] == "d")

    let around = wide.split("12ab34")
    Swag.require(around.count == 3)
    Swag.require(around[0] == "")
    Swag.require(around[1] == "ab")
    Swag.require(around[2] == "")

    let none = comma.split("abc")
    Swag.require(none.count == 1)
    Swag.require(none[0] == "abc")
}

#test
{
    // A pattern a backtracking engine cannot answer: the simulation visits every position of
    // the program once per offset, so this returns at once instead of trying every split of
    // the subject.
    var nested     = expect Parser.RegExp.create(#raw "(a*)*b")
    var alternated = expect Parser.RegExp.create(#raw "(a|aa)+c")

    Swag.require(not nested.match("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
    Swag.require(nested.match("aaab"))
    Swag.require(not alternated.match("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
    Swag.require(alternated.match("aaac"))
}

#test
{
    var subject: String
    for 1000 do
        subject.append('a'u8)

    var many = expect Parser.RegExp.create(#raw "a{1000}")
    var wide = expect Parser.RegExp.create(#raw "(?:ab){0,500}c")

    Swag.require(many.match(subject.toString()))
    Swag.require(not many.match("aaa"))
    Swag.require(wide.match("ababc"))

    var tooManyOutcome: Swag.Error
    discard catch Parser.RegExp.create(#raw "a{1001}") as tooManyOutcome
    let tooMany = tooManyOutcome.value()
    Swag.require(tooMany != null)
    Swag.require(tooMany is Errors.SyntaxError)
}

#test
{
    // Constructs that are not supported must be rejected, not silently matched as something
    // else.
    var lookAheadOutcome: Swag.Error
    discard catch Parser.RegExp.create(#raw "(?=abc)") as lookAheadOutcome
    let lookAhead = lookAheadOutcome.value()
    Swag.require(lookAhead is Errors.SyntaxError)

    var lookBehindOutcome: Swag.Error
    discard catch Parser.RegExp.create(#raw "(?<=abc)") as lookBehindOutcome
    let lookBehind = lookBehindOutcome.value()
    Swag.require(lookBehind is Errors.SyntaxError)

    var possessiveOutcome: Swag.Error
    discard catch Parser.RegExp.create(#raw "a*+") as possessiveOutcome
    let possessive = possessiveOutcome.value()
    Swag.require(possessive is Errors.SyntaxError)

    var unterminatedNameOutcome: Swag.Error
    discard catch Parser.RegExp.create(#raw "(?<name") as unterminatedNameOutcome
    let unterminatedName = unterminatedNameOutcome.value()
    Swag.require(unterminatedName is Errors.SyntaxError)

    var emptyNameOutcome: Swag.Error
    discard catch Parser.RegExp.create(#raw "(?<>a)") as emptyNameOutcome
    let emptyName = emptyNameOutcome.value()
    Swag.require(emptyName is Errors.SyntaxError)

    var emptyHexOutcome: Swag.Error
    discard catch Parser.RegExp.create(#raw "\x{}") as emptyHexOutcome
    let emptyHex = emptyHexOutcome.value()
    Swag.require(emptyHex is Errors.SyntaxError)

    var tooWideOutcome: Swag.Error
    discard catch Parser.RegExp.create(#raw "\x{110000}") as tooWideOutcome
    let tooWide = tooWideOutcome.value()
    Swag.require(tooWide is Errors.SyntaxError)

    var badFlagOutcome: Swag.Error
    discard catch Parser.RegExp.create(#raw "(?y)a") as badFlagOutcome
    let badFlag = badFlagOutcome.value()
    Swag.require(badFlag is Errors.SyntaxError)

    var repeatedAssertOutcome: Swag.Error
    discard catch Parser.RegExp.create(#raw "^*") as repeatedAssertOutcome
    let repeatedAssert = repeatedAssertOutcome.value()
    Swag.require(repeatedAssert is Errors.SyntaxError)

    var classBoundOutcome: Swag.Error
    discard catch Parser.RegExp.create(#raw "[a-\d]") as classBoundOutcome
    let classBound = classBoundOutcome.value()
    Swag.require(classBound is Errors.SyntaxError)
}

#test
{
    // The search engines have to agree: what a scan finds must be what the simulation reports,
    // including when a subject holds many candidate starts.
    var subject: String
    for 200
    {
        subject.append("filler needle text x1 a@b ")
    }

    var literal  = expect Parser.RegExp.create("needle")
    var inner    = expect Parser.RegExp.create(#raw "\w+@\w+")
    var byteSet  = expect Parser.RegExp.create(#raw "[xyz]\d")
    var anchored = expect Parser.RegExp.create(#raw "^\w+")

    Swag.require(literal.findAll(subject.toString()).count == 200)
    Swag.require(inner.findAll(subject.toString()).count == 200)
    Swag.require(byteSet.findAll(subject.toString()).count == 200)
    Swag.require(anchored.findAll(subject.toString()).count == 1)

    let first = literal.find(subject.toString())
    Swag.require(first.found)
    Swag.require(first.span.start == 7)
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
    var result: #returntype

    let pieces = rng.below(3) + 1
    for var i = 0'u64; i < pieces; i += 1
    {
        var piece: String
        switch rng.below(depth == 0 ? 10 : 13)
        {
        case 0:
            piece.append(cast(u8, (cast(u64, 'a') + rng.below(3))))

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

    var result: #returntype
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

        var expression = catch Parser.RegExp.create(text) { continue }

        // The reference: the same pattern run by the simulation alone.
        var flags: Parser.Regex.Flags
        var ast     = expect Parser.Regex.Ast.parse(text, flags)
        let program = expect Parser.Regex.Program.compile(&ast, false)
        var vm:    Parser.Regex.PikeVm

        for 12
        {
            subject = buildSubject(&rng)
            let hay = subject.toSlice()

            let reference = vm.run(&program, hay, 0, subject.length, false, false)
            let found     = expression.find(subject.toString())

            compared += 1

            Swag.require(found.found == reference)
            if not reference do
                continue

            Swag.require(found.span.start == vm.matchSlots[0])
            Swag.require(found.span.end == vm.matchSlots[1])

            // Every capture engine has to report what the simulation reports, group by group.
            for var group = 1'u32; group <= expression.captureCount(); group += 1
            {
                let span     = expression.captureSpan(group)
                let opening  = vm.matchSlots[2 * group]
                let closing  = vm.matchSlots[2 * group + 1]
                let expected = opening != Parser.Regex.NoSlot and closing != Parser.Regex.NoSlot

                Swag.require(span.found == expected)
                if not expected do
                    continue
                Swag.require(span.span.start == opening)
                Swag.require(span.span.end == closing)
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
                if not vm.run(&program, hay, at, subject.length, false, false) do
                    break

                Swag.require(every[seen].start == vm.matchSlots[0])
                Swag.require(every[seen].end == vm.matchSlots[1])
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

            Swag.require(seen == every.count)

            let reference2 = vm.run(&program, hay, 0, subject.length, false, false)
            Swag.require(reference2 == reference)
        }
    }

    // A generated suite that stops generating proves nothing, so it says how much it compared.
    Swag.require(compared > 3000)
}

// Empty occurrences: 'grepAll' and 'replaceAll' see one at every position a non-empty occurrence
// does not cover, and 'split' ignores them.
#test
{
    var re  = expect Parser.RegExp.create("a*")
    let all = re.grepAll("baaa")
    Swag.require(all.count == 3 and all[0] == "" and all[1] == "aaa" and all[2] == "")
    Swag.require(re.replaceAll("baaac", "-") == "-b--c-")
    let parts = re.split("baaac")
    Swag.require(parts.count == 2 and parts[0] == "b" and parts[1] == "c")

    var empty = expect Parser.RegExp.create("")
    Swag.require(empty.grepAll("abc").count == 4)
    Swag.require(empty.replaceAll("abc", ".") == ".a.b.c.")

    var comma  = expect Parser.RegExp.create(",")
    let fields = comma.split(",a,,b,")
    Swag.require(fields.count == 5 and
                 fields[0] == "" and
                 fields[1] == "a" and
                 fields[2] == "" and
                 fields[4] == "")
    let none = comma.split("")
    Swag.require(none.count == 1 and none[0] == "")
}

// Leftmost-first alternation, lazy and counted repetition, multi-line anchors, Unicode case
// folding, backreferences, named captures, word boundaries, and a dot that crosses lines.
#test
{
    Swag.require((expect Parser.RegExp.grep("a|ab", "ab")) == "a")
    Swag.require((expect Parser.RegExp.grep("a+?", "aaa")) == "a")
    Swag.require((expect Parser.RegExp.grep("a{2,3}", "aaaa")) == "aaa")
    var re = expect Parser.RegExp.create("a{2,3}")
    Swag.require(not re.match("aaaa") and re.match("aa"))
    let lines = expect Parser.RegExp.grepAll(#raw "(?m)^\w+$", "ab\ncd\n\nef")
    Swag.require(lines.count == 3 and lines[1] == "cd" and lines[2] == "ef")
    var ci = expect Parser.RegExp.create("(?i)éa", true)
    Swag.require(ci.match("ÉA"))
    var back = expect Parser.RegExp.create(#raw "(a+)b\1")
    Swag.require(back.match("aabaa") and not back.match("aabaaa") and not back.match("aaba"))
    var named = expect Parser.RegExp.create(#raw "(?<year>\d{4})-(?<month>\d\d)")
    Swag.require(named.match("2026-09") and named.getCapture("month") == "09" and named.getCapture(1) == "2026")
    Swag.require(not named.match("x") and named.getCapture("month") == "")
    var word = expect Parser.RegExp.create(#raw "\bcat\b")
    Swag.require(word.grep("a cat!") == "cat" and word.grep("concatenate") == null)
    var dot = expect Parser.RegExp.create("a.c")
    Swag.require(dot.match("a\nc") and dot.match("a€c"))
}

// A pattern that is exponential for a backtracker stays fast.
#test
{
    var subject: String
    for 5000 do
        subject += 'a'
    var re = expect Parser.RegExp.create("(a*)*b")
    Swag.require(not re.match(subject.toString()))
    Swag.require(re.grep(subject.toString()) == null)
}

#test
{
    var re = expect Parser.RegExp.create(#raw "(\w+)@(\w+)")
    Swag.require(re.replaceAll("x@y and a@b", "$2@$1") == "y@x and b@a")
    Swag.require(re.replaceAll("x@y", "$$1 ${9}") == "$1 ")
    let spans = re.findAll("x@y, a@b")
    Swag.require(spans.count == 2)
}
