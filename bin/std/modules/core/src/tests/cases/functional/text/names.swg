#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    let matcher = expect Text.NameMatcher.create("readme")
    Swag.require(matcher.isMatch("README.txt"))
    Swag.require(matcher.isMatch("my_readme.md"))
    Swag.require(not matcher.isMatch("manual.txt"))
    let emptyMatcher = expect Text.NameMatcher.create("")
    Swag.require(not emptyMatcher.isMatch("anything"))
}

#test
{
    let exactCase = expect Text.NameMatcher.create("Read", {matchCase: true})
    Swag.require(exactCase.isMatch("Readme"))
    Swag.require(not exactCase.isMatch("README"))

    let wholeWord = expect Text.NameMatcher.create("cat", {wholeWord: true})
    Swag.require(wholeWord.isMatch("a cat!"))
    Swag.require(not wholeWord.isMatch("category"))
    Swag.require(not wholeWord.isMatch("wildcat"))
    Swag.require(not wholeWord.isMatch("cat_cat"))
    Swag.require(not wholeWord.isMatch("caté"))
    Swag.require(Text.isWholeWordMatch("a cat!", 2, 3))
    Swag.require(not Text.isWholeWordMatch("category", 0, 3))
    Swag.require(not Text.isWholeWordMatch("cat", 2, 3))

    let startsWith = expect Text.NameMatcher.create("read", {mode: .StartsWith})
    Swag.require(startsWith.isMatch("README"))
    Swag.require(not startsWith.isMatch("my_readme"))

    let exact = expect Text.NameMatcher.create("README", {mode: .Exact})
    Swag.require(exact.isMatch("readme"))
    Swag.require(not exact.isMatch("README.txt"))
    let exactSpans = exact.findAll("readme")
    Swag.require(exactSpans.count == 1 and exactSpans[0].start == 0 and exactSpans[0].length == 6)
}

#test
{
    let matcher = expect Text.NameMatcher.create("caf", {matchCase: false})
    Swag.require(matcher.isMatch("CAFÉ"))

    let accented = expect Text.NameMatcher.create("é")
    let spans    = accented.findAll("Café été")
    Swag.require(spans.count == 3)
    Swag.require(spans[0].start == 3 and spans[0].length == 2)
    Swag.require(spans[1].start == 6 and spans[1].length == 2)
    Swag.require(spans[2].start == 9 and spans[2].length == 2)

    let unicodeMatcher = expect Text.NameMatcher.create("ÉCOLE", {comparisonType: .UnicodeNoCase})
    Swag.require(unicodeMatcher.isMatch("école"))
    let greekMatcher = expect Text.NameMatcher.create("Σ", {comparisonType: .UnicodeNoCase})
    Swag.require(greekMatcher.isMatch("σ"))

    let widthChanging      = expect Text.NameMatcher.create("\u212A", {comparisonType: .UnicodeNoCase})
    let widthChangingSpans = widthChanging.findAll("k K \u212A")
    Swag.require(widthChangingSpans.count == 3)
    Swag.require(widthChangingSpans[0].start == 0 and widthChangingSpans[0].length == 1)
    Swag.require(widthChangingSpans[1].start == 2 and widthChangingSpans[1].length == 1)
    Swag.require(widthChangingSpans[2].start == 4 and widthChangingSpans[2].length == 3)

    let replacementMatcher = expect Text.NameMatcher.create("\uFFFD", {
        comparisonType: .UnicodeNoCase,
        wholeWord: true})
    Swag.require(not replacementMatcher.isMatch("\uFFFDa"))

    let overlapping  = expect Text.NameMatcher.create("ana")
    let overlapSpans = overlapping.findAll("banana")
    Swag.require(overlapSpans.count == 1 and overlapSpans[0].start == 1)
}

#test
{
    let matcher = expect Text.NameMatcher.create(#raw "file[0-9]+", {regularExpression: true})
    let spans   = matcher.findAll("File12 file3 folder")
    Swag.require(spans.count == 2)
    Swag.require(spans[0].start == 0 and spans[0].length == 6)
    Swag.require(spans[1].start == 7 and spans[1].length == 5)

    var invalidPatternError: Swag.Error
    discard catch Text.NameMatcher.create("[", {regularExpression: true}) as invalidPatternError
    Swag.require(invalidPatternError.value() != null)

    let zeroWidth = expect Text.NameMatcher.create(#raw "a*", {regularExpression: true})
    Swag.require(zeroWidth.findAll("bbb").isEmpty())
}

#test
{
    let wholeWord = expect Text.NameMatcher.create("cat", {wholeWord: true,
                                                           regularExpression: true})
    Swag.require(wholeWord.isMatch("a cat!"))
    Swag.require(not wholeWord.isMatch("a category"))

    let exactRegex = expect Text.NameMatcher.create(#raw "file[0-9]+$", {
        mode: .Exact,
        regularExpression: true})
    Swag.require(exactRegex.isMatch("FILE12"))
    Swag.require(not exactRegex.isMatch("FILE12.txt"))
    let exactSpans = exactRegex.findAll("FILE12")
    Swag.require(exactSpans.count == 1 and exactSpans[0].length == 6)
}

#test
{
    var expression = expect Parser.RegExp.create(#raw "item[0-9]+")
    let matcher    = expect Text.NameMatcher.create(#raw "item[0-9]+", {regularExpression: true}, &expression)
    Swag.require(matcher.isMatch("item42"))
    Swag.require(not matcher.isMatch("other42"))
}

#test
{
    Swag.require(Text.compareNames("item2", "item10") < 0)
    Swag.require(Text.compareNames("Item2", "item2") == 0)
    Swag.require(Text.compareNames("Item2", "item2", {matchCase: true}) != 0)
    Swag.require(Text.compareNames("item10", "item2", {natural: false}) < 0)
    Swag.require(Text.compareNames("item2", "item10", {natural: false}) > 0)
    Swag.require(Text.compareNames("item02", "item2") < 0)

    let compareLength = func(left, right: const [..] u8)->s32 => left.count <=> right.count
    Swag.require(Text.compareNames("z", "aa", {compare: compareLength}) < 0)
}
