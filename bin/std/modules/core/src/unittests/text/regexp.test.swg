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
    var literalPipeLeadingAlt = assume Parser.RegExp.create(#"\||a"#)
    var literalPipeTrailingAlt = assume Parser.RegExp.create(#"a|\|"#)
    var literalPipeMixedAlt = assume Parser.RegExp.create(#"a\||b"#)
    var multiLiteralPipeAlt = assume Parser.RegExp.create(#"\||a|b"#)
    var parenAlt   = assume Parser.RegExp.create(#"\(|a"#)
    var closeParenAlt = assume Parser.RegExp.create(#"\)|a"#)
    var openBracketAlt = assume Parser.RegExp.create(#"\[|a"#)
    var closeBracketAlt = assume Parser.RegExp.create(#"\]|a"#)
    var openBraceAlt = assume Parser.RegExp.create(#"\{|a"#)
    var closeBraceAlt = assume Parser.RegExp.create(#"\}|a"#)
    var captureLiteralPipeAlt = assume Parser.RegExp.create(#"(\||a)(b)"#)
    var captureAlt = assume Parser.RegExp.create(#"(a|b)(c)"#)
    var captureLeadingEmptyAlt = assume Parser.RegExp.create(#"(|a)(b)"#)
    var captureTrailingEmptyAlt = assume Parser.RegExp.create(#"(a|)(b)"#)
    var plainAlt   = assume Parser.RegExp.create(#"a|b"#)
    var leadingEmptyAlt = assume Parser.RegExp.create(#"|a"#)
    var trailingEmptyAlt = assume Parser.RegExp.create(#"a|"#)
    var doubleEmptyAlt = assume Parser.RegExp.create(#"a||b"#)
    var onlyEmptyAlt = assume Parser.RegExp.create(#"||"#)
    var middleEmptyAlt = assume Parser.RegExp.create(#"(a|)c"#)
    var escaped    = assume Parser.RegExp.create(#"\(\)\[\]\{\}\.\+\*\?"#)
    var anchors    = assume Parser.RegExp.create(#"\^\$"#)
    var slash      = assume Parser.RegExp.create(#"\/path\\file"#)
    var controls   = assume Parser.RegExp.create("\\n\\r\\t\\f\\v\\a")

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
    @assert(captureAlt.getCaptures().count == 2)
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
    @assert(plainAlt.getCaptures().count == 0)
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
    var emptyGroup = assume Parser.RegExp.create(#"([a-z]*)"#)
    var explicitEmptyGroup = assume Parser.RegExp.create(#"()"#)
    var explicitEmptyRef = assume Parser.RegExp.create(#"()-\1"#)
    var explicitEmptyAltGroup = assume Parser.RegExp.create(#"(|)"#)
    var explicitEmptyAltRef = assume Parser.RegExp.create(#"(|)-\1"#)
    var optionalAltRef = assume Parser.RegExp.create(#"(|a)-\1"#)
    var countedEmptyGroup = assume Parser.RegExp.create(#"(){2}(a)"#)
    var countedEmptyAltGroup = assume Parser.RegExp.create(#"(|){2}(a)"#)
    var emptyRef   = assume Parser.RegExp.create(#"([a-z]*)-\1"#)
    var emptyTail  = assume Parser.RegExp.create(#"([a-z]+)(\d*)"#)
    var emptyTailSep = assume Parser.RegExp.create(#"([a-z]+)(\d*)-"#)
    var nonEmptyTailRef = assume Parser.RegExp.create(#"([a-z]+)(\d+)-\2"#)
    var emptyTailRef = assume Parser.RegExp.create(#"([a-z]+)(\d*)-\2"#)

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
    var baseline      = assume Parser.RegExp.create(#"b(c)"#)
    var optionalGroup = assume Parser.RegExp.create(#"(a)?b(c)"#)
    var optionalStar  = assume Parser.RegExp.create(#"(a)*b(c)"#)
    var optionalRef   = assume Parser.RegExp.create(#"(a)?\1"#)
    var zeroRef       = assume Parser.RegExp.create(#"(a){0}\1"#)
    var zeroFirst     = assume Parser.RegExp.create(#"(a){0}(b)"#)
    var zeroNested    = assume Parser.RegExp.create(#"((a)b){0}(c)"#)
    var zeroSiblingNested = assume Parser.RegExp.create(#"((a)(b)){0}(c)"#)
    var zeroNestedRef1 = assume Parser.RegExp.create(#"((a)b){0}\1"#)
    var zeroNestedRef2 = assume Parser.RegExp.create(#"((a)b){0}\2"#)
    var zeroSiblingNestedRef1 = assume Parser.RegExp.create(#"((a)(b)){0}\1"#)
    var zeroSiblingNestedRef2 = assume Parser.RegExp.create(#"((a)(b)){0}\2"#)
    var zeroSiblingNestedRef3 = assume Parser.RegExp.create(#"((a)(b)){0}\3"#)

    @assert(baseline.match("bc"))
    let baselineCount = baseline.getCaptures().count

    @assert(optionalGroup.match("bc"))
    @assert(optionalGroup.getCapture(2) == "c")
    @assert(optionalGroup.getCaptures().count == baselineCount)

    @assert(optionalGroup.match("abc"))
    @assert(optionalGroup.getCapture(1) == "a")
    @assert(optionalGroup.getCapture(2) == "c")
    @assert(optionalGroup.match("bc"))
    @assert(optionalGroup.getCapture(2) == "c")
    @assert(optionalGroup.getCaptures().count == baselineCount)

    @assert(optionalStar.match("bc"))
    @assert(optionalStar.getCapture(2) == "c")
    @assert(optionalStar.getCaptures().count == baselineCount)

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
    var nested = assume Parser.RegExp.create(#"((a)b)(c)"#)
    var nestedRef = assume Parser.RegExp.create(#"((a)b)-\1-\2"#)
    var nestedCounted = assume Parser.RegExp.create(#"((a)b){2}(c)"#)
    var deepNested = assume Parser.RegExp.create(#"(((a)))(b)"#)
    var nestedSiblings = assume Parser.RegExp.create(#"((a)(b))(c)"#)
    var nestedLeadingEmptySibling = assume Parser.RegExp.create(#"(()(a))(b)"#)
    var nestedTrailingEmptySibling = assume Parser.RegExp.create(#"((a)())(b)"#)
    var nestedLeadingAltSibling = assume Parser.RegExp.create(#"((|a)(b))(c)"#)
    var nestedTrailingAltSibling = assume Parser.RegExp.create(#"((a)(|b))(c)"#)
    var deepNestedRef = assume Parser.RegExp.create(#"(((a)))-\1-\2-\3"#)
    var nestedSiblingsRef = assume Parser.RegExp.create(#"((a)(b))-\1-\2-\3"#)
    var nestedSiblingsCounted = assume Parser.RegExp.create(#"((a)(b)){2}(c)"#)
    var nestedLeadingEmptySiblingRef = assume Parser.RegExp.create(#"(()(a))-\1-\2-\3"#)
    var nestedTrailingEmptySiblingRef = assume Parser.RegExp.create(#"((a)())-\1-\2-\3"#)
    var nestedLeadingAltSiblingRef = assume Parser.RegExp.create(#"((|a)(b))-\1-\2-\3"#)
    var nestedTrailingAltSiblingRef = assume Parser.RegExp.create(#"((a)(|b))-\1-\2-\3"#)
    var nestedSiblingsCountedRef = assume Parser.RegExp.create(#"((a)(b)){2}\1\2\3"#)

    @assert(nested.match("abc"))
    @assert(nested.getCapture(1) == "ab")
    @assert(nested.getCapture(2) == "a")
    @assert(nested.getCapture(3) == "c")
    @assert(nested.getCaptures().count == 3)
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
    var boundary = assume Parser.RegExp.create(#"\b"#)

    let word = boundary.grep("cat")
    @assert(word != null)
    @assert(cast(string) word == "")

    @assert(boundary.grep("!?") == null)
    @assert(boundary.grep("") == null)

    let all = boundary.grepAll(" cat!")
    @assert(all.count == 2)
    @assert(all[0] == "")
    @assert(all[1] == "")
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
    var countedGroup = assume Parser.RegExp.create(#"(a){2}(b)"#)
    var countedAltGroup = assume Parser.RegExp.create(#"(a|b){2}(c)"#)
    var countedEmptyAltRange = assume Parser.RegExp.create(#"(|a){0,2}(b)"#)
    var countedRangeGroup = assume Parser.RegExp.create(#"(a){0,2}(b)"#)
    var countedSiblingRange = assume Parser.RegExp.create(#"((a)(b)){0,2}(c)"#)
    var countedSiblingRangeRef = assume Parser.RegExp.create(#"((a)(b)){0,2}\1\2\3"#)
    var countedLeadingAltSibling = assume Parser.RegExp.create(#"((|a)(b)){2}(c)"#)
    var countedTrailingAltSibling = assume Parser.RegExp.create(#"((a)(|b)){2}(c)"#)
    var countedLeadingAltSiblingRange = assume Parser.RegExp.create(#"((|a)(b)){0,2}(c)"#)
    var countedTrailingAltSiblingRange = assume Parser.RegExp.create(#"((a)(|b)){0,2}(c)"#)
    var countedLeadingAltSiblingRangeRef = assume Parser.RegExp.create(#"((|a)(b)){0,2}\1\2\3"#)
    var countedTrailingAltSiblingRangeRef = assume Parser.RegExp.create(#"((a)(|b)){0,2}\1\2\3"#)
    var countedBackRef = assume Parser.RegExp.create(#"([ab]){2}\1"#)

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
    @assert(countedAltGroup.getCaptures().count == 2)
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
    var emptyExactZero     = assume Parser.RegExp.create(#"a{0}"#)
    var emptyGroupZero     = assume Parser.RegExp.create(#"(ab){0}"#)
    var emptyDigitZero     = assume Parser.RegExp.create(#"\d{0}"#)
    var emptyUnicodeZero   = assume Parser.RegExp.create(#"\pN{0}"#)
    var leftEmptyAlt       = assume Parser.RegExp.create(#"a{0}|b"#)
    var rightEmptyAlt      = assume Parser.RegExp.create(#"a|b{0}"#)
    var innerEmptyAlt      = assume Parser.RegExp.create(#"(a|b{0})c"#)
    var exactZero   = assume Parser.RegExp.create(#"a{0}bc"#)
    var rangeZero   = assume Parser.RegExp.create(#"[ab]{0,0}c"#)
    var groupedZero = assume Parser.RegExp.create(#"(ab){0}c"#)
    var escapedZero = assume Parser.RegExp.create(#"\({0,2}a"#)
    var escapedCloseZero = assume Parser.RegExp.create(#"\){0,2}a"#)
    var escapedPipeZero  = assume Parser.RegExp.create(#"\|{0,2}a"#)
    var digitUpToTwo     = assume Parser.RegExp.create(#"\d{0,2}a"#)
    var digitExactZero   = assume Parser.RegExp.create(#"\d{0}a"#)
    var unicodeUpToTwo   = assume Parser.RegExp.create(#"\pN{0,2}a"#)
    var anythingUpToTwo  = assume Parser.RegExp.create(#".{0,2}a"#)
    var upToTwo     = assume Parser.RegExp.create(#"a{0,2}bc"#)
    var groupUpToTwo = assume Parser.RegExp.create(#"(ab){0,2}c"#)

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
    @assert(cast(string) emptyPrefix == "")
    let emptyFirst = emptyDigitZero.grep("abc")
    @assert(emptyFirst != null)
    @assert(cast(string) emptyFirst == "")
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

#test
{
    discard catch Parser.RegExp.create(#"[[:bogus:]]"#)

    @assert(@err != null)
    @assert(@err is Errors.SyntaxError)
}

#test
{
    discard catch Parser.RegExp.create(#"[[:digit]]"#)

    @assert(@err != null)
    @assert(@err is Errors.SyntaxError)
}
