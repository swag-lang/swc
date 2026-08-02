#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Format/FormatOptions.h"
#include "Format/Formatter.h"
#include "Main/TaskContext.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();
namespace
{
    Result checkWrapRewrite(const TaskContext& parentCtx, std::string_view source, std::string_view expected, const FormatOptions& options)
    {
        Formatter formatter(options);
        SWC_RESULT(formatter.prepare(parentCtx.global(), source));
        if (formatter.text() != expected)
            return Result::Error;

        Formatter secondPass(options);
        SWC_RESULT(secondPass.prepare(parentCtx.global(), formatter.text()));
        if (secondPass.text() != expected)
            return Result::Error;
        return Result::Continue;
    }
}

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
    return checkWrapRewrite(ctx, SOURCE, EXPECTED, options);
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
    return checkWrapRewrite(ctx, SOURCE, EXPECTED, options);
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
    return checkWrapRewrite(ctx, SOURCE, EXPECTED, options);
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
    return checkWrapRewrite(ctx, SOURCE, EXPECTED, options);
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
    return checkWrapRewrite(ctx, SOURCE, EXPECTED, options);
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
    return checkWrapRewrite(ctx, SOURCE, EXPECTED, options);
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
    return checkWrapRewrite(ctx, SOURCE, EXPECTED, options);
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
    return checkWrapRewrite(ctx, SOURCE, EXPECTED, options);
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
    return checkWrapRewrite(ctx, SOURCE, EXPECTED, options);
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
    return checkWrapRewrite(ctx, SOURCE, EXPECTED, options);
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
    return checkWrapRewrite(ctx, SOURCE, EXPECTED, options);
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
    return checkWrapRewrite(ctx, SOURCE, EXPECTED, options);
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
    return checkWrapRewrite(ctx, SOURCE, EXPECTED, options);
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
    return checkWrapRewrite(ctx, SOURCE, EXPECTED, options);
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
    return checkWrapRewrite(ctx, SOURCE, EXPECTED, options);
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
    return checkWrapRewrite(ctx, SOURCE, EXPECTED, options);
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
    return checkWrapRewrite(ctx, SOURCE, EXPECTED, options);
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
    return checkWrapRewrite(ctx, SOURCE, EXPECTED, options);
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
    return checkWrapRewrite(ctx, SOURCE, SOURCE, options);
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
    return checkWrapRewrite(ctx, SOURCE, EXPECTED, options);
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
    return checkWrapRewrite(ctx, SOURCE, EXPECTED, options);
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
    return checkWrapRewrite(ctx, SOURCE, EXPECTED, options);
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
    return checkWrapRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatWrap_ContinuationKeepsRelativeIndent)
{
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
        "            2\n"
        "}\n";

    FormatOptions options;
    options.indentStyle = FormatIndentStyle::Spaces;
    options.indentWidth = 4;
    return checkWrapRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
