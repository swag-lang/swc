#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Format/FormatOptions.h"
#include "Format/Formatter.h"
#include "Main/TaskContext.h"
#include "Unittest/Format/FormatRewriteCheck.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

SWC_TEST_BEGIN(FormatWrap_BitwiseChainsSplitByOperand)
{
    for (const std::string_view op : {"|", "&", "^"})
    {
        const std::string source   = std::format("func f()->u32\n{{\n    return firstLongOperand {} secondLongOperand {} thirdLongOperand\n}}\n", op, op);
        const std::string expected = std::format("func f()->u32\n{{\n    return firstLongOperand {}\n           secondLongOperand {}\n           thirdLongOperand\n}}\n", op, op);
        FormatOptions     options;
        options.bitwiseChainColumnLimit = 50;
        SWC_RESULT(FormatRewriteCheck::check(ctx, source, expected, options));
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_BitwiseChainsInsideCast)
{
    static constexpr std::string_view SOURCE =
        "func read(bytes: const [..] u8)->u32\n"
        "{\n"
        "    return cast(u32, (bytes[0] << 24 | bytes[1] << 16 | bytes[2] << 8 | bytes[3]))\n"
        "}\n";
    static constexpr std::string_view EXPECTED =
        "func read(bytes: const [..] u8)->u32\n"
        "{\n"
        "    return cast(u32,\n"
        "                (bytes[0] << 24 |\n"
        "                 bytes[1] << 16 |\n"
        "                 bytes[2] << 8 |\n"
        "                 bytes[3]))\n"
        "}\n";
    FormatOptions options;
    applyFormatStyle(options, FormatNamedStyle::Swag);
    options.bitwiseChainColumnLimit = 50;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_BitwiseChainsHonorOperatorPosition)
{
    static constexpr std::string_view SOURCE =
        "func f()->u32\n"
        "{\n"
        "    return firstLongOperand | secondLongOperand | thirdLongOperand\n"
        "}\n";
    static constexpr std::string_view EXPECTED =
        "func f()->u32\n"
        "{\n"
        "    return firstLongOperand\n"
        "           | secondLongOperand\n"
        "           | thirdLongOperand\n"
        "}\n";
    FormatOptions options;
    options.bitwiseChainColumnLimit    = 30;
    options.breakBeforeBinaryOperators = FormatOperatorWrapStyle::Before;
    SWC_RESULT(FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options));
    options.breakBeforeBinaryOperators = FormatOperatorWrapStyle::None;
    return FormatRewriteCheck::check(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_BitwiseChainsHonorSingleLineArguments)
{
    static constexpr std::string_view SOURCE =
        "func f()\n"
        "{\n"
        "    consume(firstLongOperand | secondLongOperand | thirdLongOperand)\n"
        "}\n";
    FormatOptions options;
    options.bitwiseChainColumnLimit      = 30;
    options.forceSingleLineArgumentLists = true;
    return FormatRewriteCheck::check(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_BitwiseChainsPreserveAuthoredLayout)
{
    static constexpr std::string_view SOURCE =
        "func f()->u32\n"
        "{\n"
        "    return firstLongOperand | secondLongOperand | thirdLongOperand |\n"
        "           fourthLongOperand\n"
        "}\n";
    FormatOptions options;
    options.bitwiseChainColumnLimit = 30;
    return FormatRewriteCheck::check(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_BitwiseChainsHonorSingleLineConditions)
{
    static constexpr std::string_view SOURCE =
        "func f()\n"
        "{\n"
        "    let value = condition and (firstLongOperand | secondLongOperand | thirdLongOperand)\n"
        "}\n";
    FormatOptions options;
    options.bitwiseChainColumnLimit           = 50;
    options.forceSingleLineLogicalExpressions = true;
    return FormatRewriteCheck::check(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_BitwiseChainsLeaveShortMasksAndTables)
{
    static constexpr std::string_view SOURCE =
        "func f()\n"
        "{\n"
        "    let short = 1 | 2 | 4\n"
        "    let mask = veryLongOperand & anotherLongOperand\n"
        "    let table = [11111111, 22222222, 33333333, 44444444]\n"
        "}\n";
    FormatOptions options;
    options.bitwiseChainColumnLimit = 30;
    return FormatRewriteCheck::check(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_BitwiseChainsCanBeDisabled)
{
    static constexpr std::string_view SOURCE =
        "func f()->u32\n"
        "{\n"
        "    return firstLongOperand | secondLongOperand | thirdLongOperand\n"
        "}\n";
    FormatOptions options;
    applyFormatStyle(options, FormatNamedStyle::Swag);
    options.bitwiseChainColumnLimit = 0;
    return FormatRewriteCheck::check(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_BitwiseChainsIgnoreTrailingCommentWidth)
{
    static constexpr std::string_view SOURCE =
        "func f()\n"
        "{\n"
        "    let mask = a | b | c // A long explanation should not split a short expression.\n"
        "}\n";
    FormatOptions options;
    options.bitwiseChainColumnLimit = 30;
    return FormatRewriteCheck::check(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_BitwiseChainsInEnumValues)
{
    static constexpr std::string_view SOURCE =
        "enum Flags\n"
        "{\n"
        "    Combined = FirstLongOperand | SecondLongOperand | ThirdLongOperand\n"
        "}\n";
    static constexpr std::string_view EXPECTED =
        "enum Flags\n"
        "{\n"
        "    Combined = FirstLongOperand |\n"
        "               SecondLongOperand |\n"
        "               ThirdLongOperand\n"
        "}\n";
    FormatOptions options;
    applyFormatStyle(options, FormatNamedStyle::Swag);
    options.bitwiseChainColumnLimit = 50;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_BitwiseChainsKeepCompactFlagsInLongCalls)
{
    static constexpr std::string_view SOURCE =
        "func f()\n"
        "{\n"
        "    consumeAnUnusuallyLongFunctionName(firstArgument, .Border | .CloseButton | .Resizable)\n"
        "}\n";
    FormatOptions options;
    applyFormatStyle(options, FormatNamedStyle::Swag);
    options.bitwiseChainColumnLimit = 50;
    return FormatRewriteCheck::check(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_BitwiseChainsInExpressionBodies)
{
    static constexpr std::string_view SOURCE =
        "func f(value = 0)->u32 => firstLongOperand | secondLongOperand | thirdLongOperand\n";
    static constexpr std::string_view EXPECTED =
        "func f(value = 0)->u32 => firstLongOperand |\n"
        "                          secondLongOperand |\n"
        "                          thirdLongOperand\n";
    FormatOptions options;
    applyFormatStyle(options, FormatNamedStyle::Swag);
    options.bitwiseChainColumnLimit = 50;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_LogicalChainsSplitByOperand)
{
    for (const std::string_view op : {"and", "or"})
    {
        const std::string source   = std::format("func f()->bool\n{{\n    return firstLongCondition {} secondLongCondition {} thirdLongCondition\n}}\n", op, op);
        const std::string expected = std::format("func f()->bool\n{{\n    return firstLongCondition {}\n           secondLongCondition {}\n           thirdLongCondition\n}}\n", op, op);
        FormatOptions     options;
        applyFormatStyle(options, FormatNamedStyle::Swag);
        options.logicalChainColumnLimit = 50;
        SWC_RESULT(FormatRewriteCheck::check(ctx, source, expected, options));
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_LogicalChainsHonorOperatorPosition)
{
    static constexpr std::string_view SOURCE =
        "func f()->bool\n{\n    return firstLongCondition and secondLongCondition and thirdLongCondition\n}\n";
    static constexpr std::string_view EXPECTED =
        "func f()->bool\n{\n    return firstLongCondition\n           and secondLongCondition\n           and thirdLongCondition\n}\n";
    FormatOptions options;
    applyFormatStyle(options, FormatNamedStyle::Swag);
    options.logicalChainColumnLimit      = 50;
    options.logicalOperatorBreakPosition = FormatOperatorWrapStyle::Before;
    SWC_RESULT(FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options));
    options.logicalOperatorBreakPosition = FormatOperatorWrapStyle::None;
    return FormatRewriteCheck::check(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_LogicalChainsHonorExplicitSingleLine)
{
    static constexpr std::string_view SOURCE =
        "func f()\n{\n    consume(firstLongCondition and secondLongCondition and thirdLongCondition)\n}\n";
    FormatOptions options;
    applyFormatStyle(options, FormatNamedStyle::Swag);
    options.logicalChainColumnLimit      = 50;
    options.forceSingleLineArgumentLists = true;
    SWC_RESULT(FormatRewriteCheck::check(ctx, SOURCE, SOURCE, options));
    options.forceSingleLineArgumentLists      = false;
    options.forceSingleLineLogicalExpressions = true;
    SWC_RESULT(FormatRewriteCheck::check(ctx, SOURCE, SOURCE, options));
    options.forceSingleLineLogicalExpressions = false;
    options.logicalChainColumnLimit           = 0;
    return FormatRewriteCheck::check(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_LogicalChainsLeaveShortAndMixedExpressions)
{
    static constexpr std::string_view SOURCE =
        "func f()\n{\n"
        "    let short = a and b and c // A long explanation does not lengthen the chain.\n"
        "    let pair = firstLongCondition and secondLongCondition\n"
        "    let mixed = firstLongCondition or secondLongCondition and thirdLongCondition or fourthLongCondition\n"
        "    consumeAnUnusuallyLongFunctionName(firstArgument, a and b and c)\n"
        "}\n";
    FormatOptions options;
    options.logicalChainColumnLimit = 30;
    return FormatRewriteCheck::check(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_LogicalChainsKeepAuthoredGrouping)
{
    static constexpr std::string_view SOURCE =
        "func f()->bool\n{\n"
        "    return firstLongCondition and secondLongCondition and\n"
        "           thirdLongCondition\n}\n";
    FormatOptions options;
    applyFormatStyle(options, FormatNamedStyle::Swag);
    options.logicalOperandPacking   = FormatLogicalPacking::Preserve;
    options.logicalChainColumnLimit = 30;
    return FormatRewriteCheck::check(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_LogicalChainsInsideCall)
{
    static constexpr std::string_view SOURCE =
        "func f()\n{\n    consume(firstLongCondition and secondLongCondition and thirdLongCondition)\n}\n";
    static constexpr std::string_view EXPECTED =
        "func f()\n{\n    consume(firstLongCondition and\n            secondLongCondition and\n            thirdLongCondition)\n}\n";
    FormatOptions options;
    applyFormatStyle(options, FormatNamedStyle::Swag);
    options.logicalChainColumnLimit = 50;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_LogicalChainsKeepParenthesizedOperands)
{
    static constexpr std::string_view SOURCE =
        "func f()->bool\n{\n    return firstLongCondition or (secondCondition and thirdCondition) or fourthLongCondition\n}\n";
    static constexpr std::string_view EXPECTED =
        "func f()->bool\n{\n    return firstLongCondition or\n           (secondCondition and thirdCondition) or\n           fourthLongCondition\n}\n";
    FormatOptions options;
    applyFormatStyle(options, FormatNamedStyle::Swag);
    options.logicalChainColumnLimit = 50;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_LogicalChainsRespectFrozenSourceAndComments)
{
    static constexpr std::string_view SOURCE =
        "// swc-format off\n"
        "func f()->bool { return firstLongCondition and secondLongCondition and thirdLongCondition }\n"
        "// swc-format on\n"
        "func g()->bool\n{\n"
        "    return firstLongCondition and /* keep this reason here */ secondLongCondition and thirdLongCondition\n"
        "}\n";
    FormatOptions options;
    options.logicalChainColumnLimit = 30;
    return FormatRewriteCheck::check(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_BreaksAfterComma)
{
    static constexpr std::string_view SOURCE =
        "func foo(a: s32, b: s32, c: s32) {}\n"
        "func bar()\n"
        "{\n"
        "    foo(11111111, 22222222, 33333333)\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo(a: s32, b: s32, c: s32) {}\n"
        "func bar()\n"
        "{\n"
        "    foo(11111111, 22222222,\n"
        "        33333333)\n"
        "}\n";

    FormatOptions options;
    options.columnLimit             = 36;
    options.continuationIndentWidth = 4;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_ForceSingleLineLists)
{
    static constexpr std::string_view SOURCE =
        "func target(first: s32,\n"
        "            second: s32,\n"
        "            third: s32) {}\n"
        "func run()\n"
        "{\n"
        "    target(11111111,\n"
        "           22222222,\n"
        "           33333333)\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func target(first: s32, second: s32, third: s32) {}\n"
        "func run()\n"
        "{\n"
        "    target(11111111, 22222222, 33333333)\n"
        "}\n";

    FormatOptions options;
    options.columnLimit                   = 20;
    options.forceSingleLineArgumentLists  = true;
    options.forceSingleLineParameterLists = true;
    options.sourceSelectsArgumentLayout   = true;
    options.sourceSelectsParameterLayout  = true;
    options.argumentListLayout            = FormatListLayout::Block;
    options.parameterListLayout           = FormatListLayout::Block;
    options.binPackArguments              = FormatBinPackStyle::OnePerLine;
    options.binPackParameters             = FormatBinPackStyle::OnePerLine;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_FormatterSelectsListLineMode)
{
    static constexpr std::string_view SOURCE =
        "func short(a: s32,\n"
        "           b: s32) {}\n"
        "func longTarget(firstValue: s32,\n"
        "                secondValue: s32, thirdValue: s32) {}\n"
        "func run()\n"
        "{\n"
        "    short(1,\n"
        "          2)\n"
        "    longTarget(11111111,\n"
        "               22222222, 33333333)\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func short(a: s32, b: s32) {}\n"
        "func longTarget(\n"
        "    firstValue: s32,\n"
        "    secondValue: s32,\n"
        "    thirdValue: s32\n"
        ") {}\n"
        "func run()\n"
        "{\n"
        "    short(1, 2)\n"
        "    longTarget(\n"
        "        11111111,\n"
        "        22222222,\n"
        "        33333333\n"
        "    )\n"
        "}\n";

    FormatOptions options;
    options.columnLimit                  = 36;
    options.continuationIndentWidth      = 4;
    options.sourceSelectsArgumentLayout  = false;
    options.sourceSelectsParameterLayout = false;
    options.argumentListLayout           = FormatListLayout::Block;
    options.parameterListLayout          = FormatListLayout::Block;
    options.binPackArguments             = FormatBinPackStyle::OnePerLine;
    options.binPackParameters            = FormatBinPackStyle::OnePerLine;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_SourceSelectsSingleLineLists)
{
    static constexpr std::string_view SOURCE =
        "func target(first: s32, second: s32,\n"
        "            third: s32) {}\n"
        "func run()\n"
        "{\n"
        "    target(11111111, 22222222,\n"
        "           33333333)\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func target(first: s32, second: s32, third: s32) {}\n"
        "func run()\n"
        "{\n"
        "    target(11111111, 22222222, 33333333)\n"
        "}\n";

    FormatOptions options;
    options.columnLimit                  = 20;
    options.sourceSelectsArgumentLayout  = true;
    options.sourceSelectsParameterLayout = true;
    options.argumentListLayout           = FormatListLayout::Block;
    options.parameterListLayout          = FormatListLayout::Block;
    options.binPackArguments             = FormatBinPackStyle::OnePerLine;
    options.binPackParameters            = FormatBinPackStyle::OnePerLine;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_SourceSelectsNestedSingleLineLists)
{
    static constexpr std::string_view SOURCE =
        "func inner(a, b, c: s32) {}\n"
        "func outer(a, b, c: s32) {}\n"
        "func run()\n"
        "{\n"
        "    outer(1, inner(2, 3,\n"
        "                   4), 5)\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func inner(a, b, c: s32) {}\n"
        "func outer(a, b, c: s32) {}\n"
        "func run()\n"
        "{\n"
        "    outer(1, inner(2, 3, 4), 5)\n"
        "}\n";

    FormatOptions options;
    options.columnLimit                   = 20;
    options.forceSingleLineParameterLists = true;
    options.sourceSelectsArgumentLayout   = true;
    options.argumentListLayout            = FormatListLayout::Block;
    options.binPackArguments              = FormatBinPackStyle::OnePerLine;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_HangingIndentLists)
{
    static constexpr std::string_view SOURCE =
        "func target(first: s32,\n"
        "            second: s32, third: s32) {}\n"
        "func run()\n"
        "{\n"
        "    target(1,\n"
        "           2, 3)\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func target(first: s32,\n"
        "    second: s32,\n"
        "    third: s32) {}\n"
        "func run()\n"
        "{\n"
        "    target(1,\n"
        "        2,\n"
        "        3)\n"
        "}\n";

    FormatOptions options;
    options.continuationIndentWidth      = 4;
    options.sourceSelectsArgumentLayout  = true;
    options.sourceSelectsParameterLayout = true;
    options.argumentListLayout           = FormatListLayout::HangingIndent;
    options.parameterListLayout          = FormatListLayout::HangingIndent;
    options.binPackArguments             = FormatBinPackStyle::OnePerLine;
    options.binPackParameters            = FormatBinPackStyle::OnePerLine;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_HangingAlignLists)
{
    static constexpr std::string_view SOURCE =
        "func target(first: s32,\n"
        "            second: s32, third: s32) {}\n"
        "func run()\n"
        "{\n"
        "    target(1,\n"
        "           2, 3)\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func target(first: s32,\n"
        "            second: s32,\n"
        "            third: s32) {}\n"
        "func run()\n"
        "{\n"
        "    target(1,\n"
        "           2,\n"
        "           3)\n"
        "}\n";

    FormatOptions options;
    options.sourceSelectsArgumentLayout  = true;
    options.sourceSelectsParameterLayout = true;
    options.argumentListLayout           = FormatListLayout::HangingAlign;
    options.parameterListLayout          = FormatListLayout::HangingAlign;
    options.binPackArguments             = FormatBinPackStyle::OnePerLine;
    options.binPackParameters            = FormatBinPackStyle::OnePerLine;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_VerticalLists)
{
    static constexpr std::string_view SOURCE =
        "func target(first: s32,\n"
        "            second: s32, third: s32) {}\n"
        "func run()\n"
        "{\n"
        "    target(1,\n"
        "           2, 3)\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func target(\n"
        "    first: s32,\n"
        "    second: s32,\n"
        "    third: s32) {}\n"
        "func run()\n"
        "{\n"
        "    target(\n"
        "        1,\n"
        "        2,\n"
        "        3)\n"
        "}\n";

    FormatOptions options;
    options.continuationIndentWidth      = 4;
    options.sourceSelectsArgumentLayout  = true;
    options.sourceSelectsParameterLayout = true;
    options.argumentListLayout           = FormatListLayout::Vertical;
    options.parameterListLayout          = FormatListLayout::Vertical;
    options.binPackArguments             = FormatBinPackStyle::OnePerLine;
    options.binPackParameters            = FormatBinPackStyle::OnePerLine;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_BlockLists)
{
    static constexpr std::string_view SOURCE =
        "func target(first: s32,\n"
        "            second: s32, third: s32) {}\n"
        "func run()\n"
        "{\n"
        "    target(1,\n"
        "           2, 3)\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func target(\n"
        "    first: s32,\n"
        "    second: s32,\n"
        "    third: s32\n"
        ") {}\n"
        "func run()\n"
        "{\n"
        "    target(\n"
        "        1,\n"
        "        2,\n"
        "        3\n"
        "    )\n"
        "}\n";

    FormatOptions options;
    options.continuationIndentWidth      = 4;
    options.sourceSelectsArgumentLayout  = true;
    options.sourceSelectsParameterLayout = true;
    options.argumentListLayout           = FormatListLayout::Block;
    options.parameterListLayout          = FormatListLayout::Block;
    options.binPackArguments             = FormatBinPackStyle::OnePerLine;
    options.binPackParameters            = FormatBinPackStyle::OnePerLine;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_ForceSingleLineLogicalExpressions)
{
    static constexpr std::string_view SOURCE =
        "func test(a, b, c, d: bool)\n"
        "{\n"
        "    if a and\n"
        "       b or\n"
        "       c and\n"
        "       d do\n"
        "        return\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func test(a, b, c, d: bool)\n"
        "{\n"
        "    if a and b or c and d do\n"
        "        return\n"
        "}\n";

    FormatOptions options;
    options.columnLimit                          = 18;
    options.forceSingleLineParameterLists        = true;
    options.forceSingleLineLogicalExpressions    = true;
    options.sourceSelectsLogicalExpressionLayout = true;
    options.logicalExpressionLayout              = FormatLogicalLayout::HangingAlign;
    options.logicalOperatorBreakPosition         = FormatOperatorWrapStyle::Before;
    options.logicalOperandPacking                = FormatLogicalPacking::OnePerLine;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_SourceSelectsSingleLineLogicalExpressions)
{
    static constexpr std::string_view SOURCE =
        "func test(a, b, c, d: bool)\n"
        "{\n"
        "    if a and b or\n"
        "       c and d do\n"
        "        return\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func test(a, b, c, d: bool)\n"
        "{\n"
        "    if a and b or c and d do\n"
        "        return\n"
        "}\n";

    FormatOptions options;
    options.columnLimit                          = 18;
    options.forceSingleLineParameterLists        = true;
    options.sourceSelectsLogicalExpressionLayout = true;
    options.logicalExpressionLayout              = FormatLogicalLayout::HangingAlign;
    options.logicalOperatorBreakPosition         = FormatOperatorWrapStyle::Before;
    options.logicalOperandPacking                = FormatLogicalPacking::OnePerLine;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_LogicalOperatorsAfter)
{
    static constexpr std::string_view SOURCE =
        "func test(a, b, c, d: bool)\n"
        "{\n"
        "    if a and\n"
        "       b or c and d do\n"
        "        return\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func test(a, b, c, d: bool)\n"
        "{\n"
        "    if a and\n"
        "       b or\n"
        "       c and d do\n"
        "        return\n"
        "}\n";

    FormatOptions options;
    options.breakBeforeBinaryOperators           = FormatOperatorWrapStyle::Before;
    options.sourceSelectsLogicalExpressionLayout = true;
    options.logicalExpressionLayout              = FormatLogicalLayout::HangingAlign;
    options.logicalOperatorBreakPosition         = FormatOperatorWrapStyle::After;
    options.logicalOperandPacking                = FormatLogicalPacking::ByPrecedence;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_LogicalOperatorsBefore)
{
    static constexpr std::string_view SOURCE =
        "func test(a, b, c, d: bool)\n"
        "{\n"
        "    if a and\n"
        "       b or c and d do\n"
        "        return\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func test(a, b, c, d: bool)\n"
        "{\n"
        "    if a\n"
        "       and b\n"
        "       or c and d do\n"
        "        return\n"
        "}\n";

    FormatOptions options;
    options.breakBeforeBinaryOperators           = FormatOperatorWrapStyle::After;
    options.sourceSelectsLogicalExpressionLayout = true;
    options.logicalExpressionLayout              = FormatLogicalLayout::HangingAlign;
    options.logicalOperatorBreakPosition         = FormatOperatorWrapStyle::Before;
    options.logicalOperandPacking                = FormatLogicalPacking::ByPrecedence;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_LogicalOperandsOnePerLine)
{
    static constexpr std::string_view SOURCE =
        "func test(a, b, c, d: bool)\n"
        "{\n"
        "    if a and\n"
        "       b or c and d do\n"
        "        return\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func test(a, b, c, d: bool)\n"
        "{\n"
        "    if a and\n"
        "       b or\n"
        "       c and\n"
        "       d do\n"
        "        return\n"
        "}\n";

    FormatOptions options;
    options.sourceSelectsLogicalExpressionLayout = true;
    options.logicalExpressionLayout              = FormatLogicalLayout::HangingAlign;
    options.logicalOperatorBreakPosition         = FormatOperatorWrapStyle::After;
    options.logicalOperandPacking                = FormatLogicalPacking::OnePerLine;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_LogicalHangingIndent)
{
    static constexpr std::string_view SOURCE =
        "func test(a, b, c, d: bool)\n"
        "{\n"
        "    if a and\n"
        "       b or c and d do\n"
        "        return\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func test(a, b, c, d: bool)\n"
        "{\n"
        "    if a and\n"
        "        b or\n"
        "        c and d do\n"
        "        return\n"
        "}\n";

    FormatOptions options;
    options.continuationIndentWidth              = 4;
    options.sourceSelectsLogicalExpressionLayout = true;
    options.logicalExpressionLayout              = FormatLogicalLayout::HangingIndent;
    options.logicalOperatorBreakPosition         = FormatOperatorWrapStyle::After;
    options.logicalOperandPacking                = FormatLogicalPacking::ByPrecedence;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_LogicalOperandsPack)
{
    static constexpr std::string_view SOURCE =
        "func test(a, b, c, d: bool)\n"
        "{\n"
        "    if a and\n"
        "       b or\n"
        "       c and\n"
        "       d do\n"
        "        return\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func test(a, b, c, d: bool)\n"
        "{\n"
        "    if a and\n"
        "       b or c and d do\n"
        "        return\n"
        "}\n";

    FormatOptions options;
    options.sourceSelectsLogicalExpressionLayout = true;
    options.logicalExpressionLayout              = FormatLogicalLayout::HangingAlign;
    options.logicalOperatorBreakPosition         = FormatOperatorWrapStyle::After;
    options.logicalOperandPacking                = FormatLogicalPacking::Pack;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_FormatterSelectsLogicalExpressionLineMode)
{
    static constexpr std::string_view SOURCE =
        "func test()\n"
        "{\n"
        "    if true and\n"
        "       false do\n"
        "        return\n"
        "    if someVeryLongCondition() and\n"
        "       anotherVeryLongCondition() do\n"
        "        return\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func test()\n"
        "{\n"
        "    if true and false do\n"
        "        return\n"
        "    if someVeryLongCondition() and\n"
        "       anotherVeryLongCondition() do\n"
        "        return\n"
        "}\n";

    FormatOptions options;
    options.columnLimit                          = 36;
    options.sourceSelectsLogicalExpressionLayout = false;
    options.logicalExpressionLayout              = FormatLogicalLayout::HangingAlign;
    options.logicalOperatorBreakPosition         = FormatOperatorWrapStyle::After;
    options.logicalOperandPacking                = FormatLogicalPacking::ByPrecedence;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_NestedLogicalExpressions)
{
    static constexpr std::string_view SOURCE =
        "func test(a, b, c, d: bool)\n"
        "{\n"
        "    if a and (b or c or\n"
        "              d) or e do\n"
        "        return\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func test(a, b, c, d: bool)\n"
        "{\n"
        "    if a and (b or c or d) or e do\n"
        "        return\n"
        "}\n";

    FormatOptions options;
    options.columnLimit                          = 18;
    options.forceSingleLineParameterLists        = true;
    options.sourceSelectsLogicalExpressionLayout = true;
    options.logicalExpressionLayout              = FormatLogicalLayout::HangingAlign;
    options.logicalOperatorBreakPosition         = FormatOperatorWrapStyle::After;
    options.logicalOperandPacking                = FormatLogicalPacking::OnePerLine;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_NormalizesAdversarialLists)
{
    static constexpr std::string_view SOURCE =
        "func target(first:s32,\n"
        "\n"
        " second :s32,third:s32)->s32\n"
        "{\n"
        " return first+second+third\n"
        "}\n"
        "func run()\n"
        "{\n"
        " let value=target(1,\n"
        "\n"
        "  2,3)\n"
        " value=target(value,\n"
        "             2,3)\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func target(first: s32,\n"
        "            second: s32,\n"
        "            third: s32)->s32\n"
        "{\n"
        "    return first + second + third\n"
        "}\n"
        "func run()\n"
        "{\n"
        "    let value = target(1,\n"
        "                       2,\n"
        "                       3)\n"
        "    value = target(value,\n"
        "                   2,\n"
        "                   3)\n"
        "}\n";

    FormatOptions options;
    options.indentStyle                    = FormatIndentStyle::Spaces;
    options.indentWidth                    = 4;
    options.spaceBeforeColonInDeclarations = false;
    options.spaceAfterColonInDeclarations  = true;
    options.spaceAroundAssignmentOperator  = true;
    options.spaceAroundBinaryOperators     = true;
    options.spaceBeforeComma               = false;
    options.spaceAfterComma                = true;
    options.sourceSelectsArgumentLayout    = true;
    options.sourceSelectsParameterLayout   = true;
    options.argumentListLayout             = FormatListLayout::HangingAlign;
    options.parameterListLayout            = FormatListLayout::HangingAlign;
    options.binPackArguments               = FormatBinPackStyle::OnePerLine;
    options.binPackParameters              = FormatBinPackStyle::OnePerLine;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_NormalizesAdversarialLogicalExpression)
{
    static constexpr std::string_view SOURCE =
        "func test(a,b,c:bool)\n"
        "{\n"
        " if a\n"
        "             and b or\n"
        " c do\n"
        "  return\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func test(a, b, c: bool)\n"
        "{\n"
        "    if a and\n"
        "       b or\n"
        "       c do\n"
        "        return\n"
        "}\n";

    FormatOptions options;
    options.indentStyle                          = FormatIndentStyle::Spaces;
    options.indentWidth                          = 4;
    options.spaceBeforeColonInDeclarations       = false;
    options.spaceAfterColonInDeclarations        = true;
    options.spaceBeforeComma                     = false;
    options.spaceAfterComma                      = true;
    options.sourceSelectsLogicalExpressionLayout = true;
    options.logicalExpressionLayout              = FormatLogicalLayout::HangingAlign;
    options.logicalOperatorBreakPosition         = FormatOperatorWrapStyle::After;
    options.logicalOperandPacking                = FormatLogicalPacking::OnePerLine;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_AlignsMultilineArgumentContents)
{
    static constexpr std::string_view SOURCE =
        "func run()\n"
        "{\n"
        " call(1,\n"
        " [\n"
        "   2,\n"
        "   3\n"
        " ],\n"
        " func()\n"
        " {\n"
        "  work()\n"
        "  work()\n"
        " })\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func run()\n"
        "{\n"
        "    call(1,\n"
        "         [\n"
        "             2,\n"
        "             3\n"
        "         ],\n"
        "         func()\n"
        "         {\n"
        "             work()\n"
        "             work()\n"
        "         })\n"
        "}\n";

    FormatOptions options;
    options.indentStyle                 = FormatIndentStyle::Spaces;
    options.indentWidth                 = 4;
    options.sourceSelectsArgumentLayout = true;
    options.argumentListLayout          = FormatListLayout::HangingAlign;
    options.binPackArguments            = FormatBinPackStyle::OnePerLine;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_ClosureCapturesStayInsideArgument)
{
    static constexpr std::string_view SOURCE =
        "func run()\n"
        "{\n"
        " call(surface, func|host = &host, frames = select(&count, 1)|(app)\n"
        " {\n"
        "  use(host, frames)\n"
        "  if ready do\n"
        "  use(frames, app)\n"
        " })\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func run()\n"
        "{\n"
        "    call(surface,\n"
        "         func|host = &host, frames = select(&count, 1)|(app)\n"
        "         {\n"
        "             use(host, frames)\n"
        "             if ready do\n"
        "                 use(frames, app)\n"
        "         })\n"
        "}\n";

    FormatOptions options;
    options.indentStyle                 = FormatIndentStyle::Spaces;
    options.indentWidth                 = 4;
    options.columnLimit                 = 40;
    options.sourceSelectsArgumentLayout = true;
    options.argumentListLayout          = FormatListLayout::HangingAlign;
    options.binPackArguments            = FormatBinPackStyle::OnePerLine;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_NoWrapWhenDisabled)
{
    static constexpr std::string_view SOURCE =
        "func foo(a: s32, b: s32, c: s32) {}\n"
        "func bar()\n"
        "{\n"
        "    foo(11111111, 22222222, 33333333)\n"
        "}\n";

    FormatOptions options;
    options.columnLimit = 0;
    return FormatRewriteCheck::check(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_BreakBeforeBinaryOperators)
{
    static constexpr std::string_view SOURCE =
        "const X = 1111 + 2222 + 3333 + 4444\n";

    static constexpr std::string_view EXPECTED =
        "const X = 1111 + 2222\n"
        "    + 3333 + 4444\n";

    FormatOptions options;
    options.columnLimit                = 24;
    options.continuationIndentWidth    = 4;
    options.breakBeforeBinaryOperators = FormatOperatorWrapStyle::Before;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_BinPackLists)
{
    static constexpr std::string_view SOURCE =
        "func target(first: s32,\n"
        "            second: s32,\n"
        "            third: s32) {}\n"
        "func run()\n"
        "{\n"
        "    target(1,\n"
        "           2,\n"
        "           3)\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func target(first: s32,\n"
        "    second: s32, third: s32) {}\n"
        "func run()\n"
        "{\n"
        "    target(1,\n"
        "        2, 3)\n"
        "}\n";

    FormatOptions options;
    options.continuationIndentWidth      = 4;
    options.sourceSelectsArgumentLayout  = true;
    options.sourceSelectsParameterLayout = true;
    options.argumentListLayout           = FormatListLayout::HangingIndent;
    options.parameterListLayout          = FormatListLayout::HangingIndent;
    options.binPackArguments             = FormatBinPackStyle::Pack;
    options.binPackParameters            = FormatBinPackStyle::Pack;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_BinPackParametersOnePerLine)
{
    static constexpr std::string_view SOURCE =
        "func foo(aaaa: s32,\n"
        "         bbbb: s32, cccc: s32) {}\n";

    static constexpr std::string_view EXPECTED =
        "func foo(aaaa: s32,\n"
        "         bbbb: s32,\n"
        "         cccc: s32) {}\n";

    FormatOptions options;
    options.binPackParameters = FormatBinPackStyle::OnePerLine;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_BinPackArgumentsOnePerLine)
{
    static constexpr std::string_view SOURCE =
        "func foo(a: s32, b: s32, c: s32) {}\n"
        "func bar()\n"
        "{\n"
        "    foo(1,\n"
        "        2, 3)\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo(a: s32, b: s32, c: s32) {}\n"
        "func bar()\n"
        "{\n"
        "    foo(1,\n"
        "        2,\n"
        "        3)\n"
        "}\n";

    FormatOptions options;
    options.binPackArguments = FormatBinPackStyle::OnePerLine;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_NoColumnLimitPreservesGeneralStatementBreaks)
{
    // General wrapping remains authored. Narrow rules such as bitwise-chain
    // wrapping do not impose a column budget on unrelated expressions.
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    result = compute(alpha, beta) + compute(gamma, delta) + compute(epsilon, zeta)\n"
        "    other = compute(a,\n"
        "                    b)\n"
        "}\n";

    // The 79-column line stays one line and the hand-wrapped call stays wrapped.
    // Only the columns move.
    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    result = compute(alpha, beta) + compute(gamma, delta) + compute(epsilon, zeta)\n"
        "    other  = compute(a,\n"
        "                     b)\n"
        "}\n";

    FormatOptions options;
    applyFormatStyle(options, FormatNamedStyle::Swag);
    if (options.columnLimit != 0)
        return Result::Error;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_ColumnLimitBreaksHighestInTheExpression)
{
    // Greedy, and greedy on the right axis: the break that keeps the most
    // structure is the shallowest and loosest-binding one that still fits, so
    // the top-level `+` wins over the commas nested in its operands.
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    result = compute(alpha, beta) + compute(gamma, delta) + compute(epsilon, zeta)\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    result = compute(alpha, beta) +\n"
        "        compute(gamma, delta) +\n"
        "        compute(epsilon, zeta)\n"
        "}\n";

    FormatOptions options;
    options.indentStyle                = FormatIndentStyle::Spaces;
    options.indentWidth                = 4;
    options.columnLimit                = 40;
    options.breakBeforeBinaryOperators = FormatOperatorWrapStyle::After;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_ColumnLimitAlignsNewOperandLinesInOnePass)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    result = compute(alpha, beta) + compute(gamma, delta) + compute(epsilon, zeta)\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    result = compute(alpha, beta) +\n"
        "             compute(gamma, delta) +\n"
        "             compute(epsilon, zeta)\n"
        "}\n";

    FormatOptions options;
    options.indentStyle                = FormatIndentStyle::Spaces;
    options.indentWidth                = 4;
    options.columnLimit                = 40;
    options.alignOperands              = true;
    options.breakBeforeBinaryOperators = FormatOperatorWrapStyle::After;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_ColumnLimitBreaksAtTheLoosestOperator)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    if alpha > beta and gamma < delta and epsilon != zeta and eta == theta\n"
        "    {\n"
        "        run()\n"
        "    }\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    if alpha > beta and\n"
        "        gamma < delta and\n"
        "        epsilon != zeta and eta == theta\n"
        "    {\n"
        "        run()\n"
        "    }\n"
        "}\n";

    FormatOptions options;
    options.indentStyle                = FormatIndentStyle::Spaces;
    options.indentWidth                = 4;
    options.columnLimit                = 40;
    options.breakBeforeBinaryOperators = FormatOperatorWrapStyle::After;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_ColumnLimitKeepsOneIndentPerStatement)
{
    // Every continuation of one statement sits at the same column: measuring
    // from the line being broken would step one level right at every break.
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    render(surface, viewport, camera, lights, materials, options, timing)\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    render(surface, viewport, camera,\n"
        "        lights, materials, options,\n"
        "        timing)\n"
        "}\n";

    FormatOptions options;
    options.indentStyle = FormatIndentStyle::Spaces;
    options.indentWidth = 4;
    options.columnLimit = 40;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_ContinuationOutsideBracketsTakesCanonicalIndent)
{
    // No bracket, so no hand-packed table to protect: the continuation lands at
    // the canonical continuation indent whatever column the source put it at.
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "   var x = 1 +\n"
        "           2\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    var x = 1 +\n"
        "        2\n"
        "}\n";

    FormatOptions options;
    options.indentStyle = FormatIndentStyle::Spaces;
    options.indentWidth = 4;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_ContinuationInsideBracketsKeepsRelativeIndent)
{
    // Inside a bracket the distance to the statement is the author's column
    // layout: a hand-packed data table survives only because it is kept.
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "   let table = [1, 2,\n"
        "                  3, 4]\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    let table = [1, 2,\n"
        "                   3, 4]\n"
        "}\n";

    FormatOptions options;
    options.indentStyle = FormatIndentStyle::Spaces;
    options.indentWidth = 4;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_WrappedCaseValuesAlignUnderTheFirstValue)
{
    static constexpr std::string_view SOURCE =
        "func foo(v: s32)\n"
        "{\n"
        "    switch v\n"
        "    {\n"
        "    case 2,\n"
        "      4,\n"
        "            6: Swag.assert(true)\n"
        "    }\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo(v: s32)\n"
        "{\n"
        "    switch v\n"
        "    {\n"
        "    case 2,\n"
        "         4,\n"
        "         6: Swag.assert(true)\n"
        "    }\n"
        "}\n";

    FormatOptions options;
    options.indentStyle      = FormatIndentStyle::Spaces;
    options.indentWidth      = 4;
    options.indentCaseLabels = false;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_SourceSelectsLiteralLayout)
{
    static constexpr std::string_view SOURCE =
        "struct Point { x: s32, y: s32 }\n"
        "func foo()\n"
        "{\n"
        "    let values = [1, 2,\n"
        "                     3, 4]\n"
        "    let point = Point{x: 1,\n"
        "                            y: 2}\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "struct Point { x: s32, y: s32 }\n"
        "func foo()\n"
        "{\n"
        "    let values = [1,\n"
        "                  2,\n"
        "                  3,\n"
        "                  4]\n"
        "    let point = Point{x: 1,\n"
        "                      y: 2}\n"
        "}\n";

    FormatOptions options;
    options.sourceSelectsLiteralLayout = true;
    options.literalListLayout          = FormatListLayout::HangingAlign;
    options.binPackLiteralItems        = FormatBinPackStyle::OnePerLine;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_HugTrailingTableArgument)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    target(cxt,\n"
        "           evt,\n"
        "           [\n"
        "               {1, 2},\n"
        "               {3, 4}])\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    target(cxt, evt, [\n"
        "        {1, 2},\n"
        "        {3, 4}])\n"
        "}\n";

    FormatOptions options;
    options.indentStyle                 = FormatIndentStyle::Spaces;
    options.indentWidth                 = 4;
    options.continuationIndentWidth     = 4;
    options.sourceSelectsArgumentLayout = true;
    options.argumentListLayout          = FormatListLayout::HangingAlign;
    options.binPackArguments            = FormatBinPackStyle::OnePerLine;
    options.hugTrailingBlockArgument    = true;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_HugTrailingClosureArgument)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    target(null,\n"
        "           func(app)\n"
        "           {\n"
        "               app.step()\n"
        "           })\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    target(null, func(app)\n"
        "    {\n"
        "        app.step()\n"
        "    })\n"
        "}\n";

    FormatOptions options;
    options.indentStyle                 = FormatIndentStyle::Spaces;
    options.indentWidth                 = 4;
    options.continuationIndentWidth     = 4;
    options.sourceSelectsArgumentLayout = true;
    options.argumentListLayout          = FormatListLayout::HangingAlign;
    options.binPackArguments            = FormatBinPackStyle::OnePerLine;
    options.hugTrailingBlockArgument    = true;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_HugTrailingBlockLiteralItem)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    let rules = [\n"
        "        first,\n"
        "        second,\n"
        "        [\n"
        "            {1, 2},\n"
        "            {3, 4}]]\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    let rules = [first, second, [\n"
        "        {1, 2},\n"
        "        {3, 4}]]\n"
        "}\n";

    FormatOptions options;
    options.indentStyle                = FormatIndentStyle::Spaces;
    options.indentWidth                = 4;
    options.continuationIndentWidth    = 4;
    options.sourceSelectsLiteralLayout = true;
    options.literalListLayout          = FormatListLayout::HangingAlign;
    options.hugTrailingBlockItem       = true;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_HugPreservesCompactTableRows)
{
    for (const std::string_view declaration : {"let rows =", "let rows: [2] Point ="})
    {
        for (const std::string_view trailingComma : {"", ","})
        {
            const std::string source   = std::format("func foo()\n{{\n    {} [\n        {{1, 2}},\n        {{3, 4}}{}\n    ]\n}}\n", declaration, trailingComma);
            const std::string expected = std::format("func foo()\n{{\n    {} [\n        {{1, 2}},\n        {{3, 4}}]\n}}\n", declaration);
            FormatOptions     options;
            applyFormatStyle(options, FormatNamedStyle::Swag);
            SWC_RESULT(FormatRewriteCheck::check(ctx, source, expected, options));
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_HugIgnoresEnclosingCallNewline)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    target({1, 2},\n"
        "           {3, 4}\n"
        "    )\n"
        "    let compact = [{1, 2}, {3, 4}]\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    target({1, 2},\n"
        "           {3, 4})\n"
        "    let compact = [{1, 2}, {3, 4}]\n"
        "}\n";

    FormatOptions options;
    applyFormatStyle(options, FormatNamedStyle::Swag);
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_HugSkipsEarlierMultilineArgument)
{
    // The first argument already owns a block, so the call has no single
    // trailing block to hug and keeps the one-argument-per-line layout.
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    target([\n"
        "               {1, 2},\n"
        "               {3, 4}],\n"
        "           [\n"
        "               {5, 6}])\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    target([\n"
        "               {1, 2},\n"
        "               {3, 4}],\n"
        "           [\n"
        "               {5, 6}])\n"
        "}\n";

    FormatOptions options;
    options.indentStyle                 = FormatIndentStyle::Spaces;
    options.indentWidth                 = 4;
    options.continuationIndentWidth     = 4;
    options.sourceSelectsArgumentLayout = true;
    options.argumentListLayout          = FormatListLayout::HangingAlign;
    options.binPackArguments            = FormatBinPackStyle::OnePerLine;
    options.hugTrailingBlockArgument    = true;
    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
