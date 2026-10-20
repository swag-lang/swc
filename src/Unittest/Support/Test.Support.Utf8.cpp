#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Support/Core/Utf8.h"
#include "Support/Core/Utf8Helper.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

SWC_TEST_BEGIN(Utf8_MoveOperationsTransferStorage)
{
    Utf8        source(256, 'a');
    const char* sourceData = source.data();

    Utf8 constructed(std::move(source));
    if (constructed.size() != 256 || constructed.front() != 'a')
        return Result::Error;
    // Utf8 move operations promise an empty source; these assertions test that contract.
    if (constructed.data() != sourceData || !source.empty()) // NOLINT(bugprone-use-after-move)
        return Result::Error;

    Utf8        assignedSource(512, 'b');
    const char* assignedSourceData = assignedSource.data();
    Utf8        assigned(384, 'c');

    assigned = std::move(assignedSource);
    if (assigned.size() != 512 || assigned.front() != 'b')
        return Result::Error;
    if (assigned.data() != assignedSourceData || !assignedSource.empty()) // NOLINT(bugprone-use-after-move)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Utf8_ReplacementPreservesQuotesLoopsAndAliasedViews)
{
    Utf8 quoted = "old 'old' \"old\" old";
    quoted.replace_loop("old", "new");
    if (quoted != "new 'old' \"old\" new")
        return Result::Error;

    Utf8 repeated = "a        b";
    repeated.replace_loop("  ", " ", true);
    if (repeated != "a b")
        return Result::Error;

    Utf8 unchanged(128, 'x');
    unchanged.replace_loop("absent", "replacement", true);
    if (unchanged != Utf8(128, 'x'))
        return Result::Error;

    Utf8 aliased = "old new old";
    aliased.replace_loop(aliased.subView(0, 3), aliased.subView(4, 3));
    if (aliased != "new new new")
        return Result::Error;

    Utf8 binary("a\0a", 3);
    binary.replace_loop("a", "long");
    if (binary != Utf8("long\0long", 9))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Utf8_EditDistanceKeepsTranspositionsAndSuggestionOrder)
{
    struct TestCase
    {
        std::string_view a;
        std::string_view b;
        size_t           distance;
    };
    const std::array cases = {
        TestCase{"", "", 0},
        TestCase{"a", "", 1},
        TestCase{"a", "b", 1},
        TestCase{"same", "same", 0},
        TestCase{"ab", "ba", 1},
        TestCase{"abcd", "badc", 2},
        TestCase{"kitten", "sitting", 3},
        TestCase{"CA", "ABC", 3},
        TestCase{"abcdef", "abcfde", 2},
    };
    for (const TestCase& test : cases)
    {
        if (Utf8Helper::levenshtein(test.a, test.b) != test.distance || Utf8Helper::levenshtein(test.b, test.a) != test.distance)
            return Result::Error;
    }

    const std::vector<Utf8> candidates = {"get", "let", "set"};
    const auto              transposed = Utf8Helper::bestMatch("gte", candidates);
    const auto              tied       = Utf8Helper::bestMatch("bet", candidates);
    if (!transposed || *transposed != "get" || !tied || *tied != "get")
        return Result::Error;
    if (Utf8Helper::bestMatch("be", candidates) || Utf8Helper::bestMatch("unrelated", candidates) || Utf8Helper::bestMatch("get", {}))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Utf8_FixedDecimalFormatting)
{
    if (Utf8Helper::formatFixedDecimal(12.345, 2) != "12.35")
        return Result::Error;
    if (Utf8Helper::formatFixedDecimal(-0.0, 2) != "-0.00")
        return Result::Error;
    if (Utf8Helper::formatFixedDecimal(0.0, 1, true) != "+0.0")
        return Result::Error;
    if (Utf8Helper::toNiceSize(1536) != "1.5 KB")
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
