#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Format/FormatOptions.h"
#include "Format/Formatter.h"
#include "Main/TaskContext.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();
namespace
{
    Result checkBlanksRewrite(const TaskContext& parentCtx, std::string_view source, std::string_view expected, const FormatOptions& options)
    {
        Formatter formatter(options);
        SWC_RESULT(formatter.prepare(parentCtx.global(), source));
        if (formatter.text() != expected)
            return Result::Error;
        return Result::Continue;
    }
}

SWC_TEST_BEGIN(FormatBlanks_MaxConsecutiveEmptyLinesUnlimited)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    a = 1\n"
        "\n"
        "\n"
        "\n"
        "\n"
        "    b = 2\n"
        "}\n";

    FormatOptions options;
    options.maxConsecutiveEmptyLines = 0;
    return checkBlanksRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_MaxConsecutiveEmptyLinesCollapses)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    a = 1\n"
        "\n"
        "\n"
        "\n"
        "\n"
        "    b = 2\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    a = 1\n"
        "\n"
        "\n"
        "    b = 2\n"
        "}\n";

    FormatOptions options;
    options.maxConsecutiveEmptyLines = 2;
    return checkBlanksRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_MaxConsecutiveEmptyLinesOne)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    a = 1\n"
        "\n"
        "\n"
        "\n"
        "    b = 2\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    a = 1\n"
        "\n"
        "    b = 2\n"
        "}\n";

    FormatOptions options;
    options.maxConsecutiveEmptyLines = 1;
    return checkBlanksRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_KeepEmptyLinesAtStartOfBlockRemoves)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "\n"
        "\n"
        "    a = 1\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    a = 1\n"
        "}\n";

    FormatOptions options;
    options.keepEmptyLinesAtStartOfBlock = false;
    options.maxConsecutiveEmptyLines     = 0;
    return checkBlanksRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_KeepEmptyLinesAtStartOfBlockPreserves)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "\n"
        "\n"
        "    a = 1\n"
        "}\n";

    FormatOptions options;
    options.keepEmptyLinesAtStartOfBlock = true;
    options.maxConsecutiveEmptyLines     = 0;
    return checkBlanksRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_KeepEmptyLinesAtEndOfBlockRemoves)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    a = 1\n"
        "\n"
        "\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    a = 1\n"
        "}\n";

    FormatOptions options;
    options.keepEmptyLinesAtEndOfBlock = false;
    options.maxConsecutiveEmptyLines   = 0;
    return checkBlanksRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_KeepEmptyLinesAtEndOfBlockPreserves)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    a = 1\n"
        "\n"
        "\n"
        "}\n";

    FormatOptions options;
    options.keepEmptyLinesAtEndOfBlock = true;
    options.maxConsecutiveEmptyLines   = 0;
    return checkBlanksRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_TrimTrailingNewlinesCollapsesToOne)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    a = 1\n"
        "}\n"
        "\n"
        "\n"
        "\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    a = 1\n"
        "}\n";

    FormatOptions options;
    options.trimTrailingNewlines     = true;
    options.maxConsecutiveEmptyLines = 0;
    return checkBlanksRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_TrimTrailingNewlinesDisabled)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    a = 1\n"
        "}\n"
        "\n"
        "\n"
        "\n";

    FormatOptions options;
    options.trimTrailingNewlines     = false;
    options.maxConsecutiveEmptyLines = 0;
    return checkBlanksRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_CombinedStartAndEndOfBlock)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "\n"
        "\n"
        "    a = 1\n"
        "\n"
        "\n"
        "    b = 2\n"
        "\n"
        "\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    a = 1\n"
        "\n"
        "\n"
        "    b = 2\n"
        "}\n";

    FormatOptions options;
    options.keepEmptyLinesAtStartOfBlock = false;
    options.keepEmptyLinesAtEndOfBlock   = false;
    options.maxConsecutiveEmptyLines     = 0;
    return checkBlanksRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_BetweenFunctionsInsertsBlank)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    a = 1\n"
        "}\n"
        "func bar()\n"
        "{\n"
        "    b = 2\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    a = 1\n"
        "}\n"
        "\n"
        "func bar()\n"
        "{\n"
        "    b = 2\n"
        "}\n";

    FormatOptions options;
    options.minBlankLinesBetweenFunctions = 1;
    return checkBlanksRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_BetweenFunctionsKeepsDocCommentAttached)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    a = 1\n"
        "}\n"
        "// Doc for bar.\n"
        "#[Swag.Inline]\n"
        "func bar()\n"
        "{\n"
        "    b = 2\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    a = 1\n"
        "}\n"
        "\n"
        "// Doc for bar.\n"
        "#[Swag.Inline]\n"
        "func bar()\n"
        "{\n"
        "    b = 2\n"
        "}\n";

    FormatOptions options;
    options.minBlankLinesBetweenFunctions = 1;
    return checkBlanksRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_BetweenFunctionsKeepsShortFormsStacked)
{
    static constexpr std::string_view SOURCE =
        "interface IFoo\n"
        "{\n"
        "    mtd one();\n"
        "    mtd two();\n"
        "}\n"
        "func square(x: s32) => x * x\n"
        "func cube(x: s32) => x * x * x\n";

    FormatOptions options;
    options.minBlankLinesBetweenFunctions = 1;
    return checkBlanksRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_BetweenTypesInsertsBlank)
{
    static constexpr std::string_view SOURCE =
        "struct Point\n"
        "{\n"
        "    x: f32\n"
        "}\n"
        "enum Kind\n"
        "{\n"
        "    One\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "struct Point\n"
        "{\n"
        "    x: f32\n"
        "}\n"
        "\n"
        "enum Kind\n"
        "{\n"
        "    One\n"
        "}\n";

    FormatOptions options;
    options.minBlankLinesBetweenTypes = 1;
    return checkBlanksRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_BeforeCommentsInsertsBlank)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    a = 1\n"
        "    // Second part.\n"
        "    b = 2\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    a = 1\n"
        "\n"
        "    // Second part.\n"
        "    b = 2\n"
        "}\n";

    FormatOptions options;
    options.minBlankLinesBeforeComments = 1;
    return checkBlanksRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_BeforeCommentsKeepsBlockStartAndRuns)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    // First comment: right after the brace.\n"
        "    // Second line of the same block.\n"
        "    a = 1\n"
        "}\n";

    FormatOptions options;
    options.minBlankLinesBeforeComments = 1;
    return checkBlanksRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_AfterGlobalBlockInsertsBlank)
{
    static constexpr std::string_view SOURCE =
        "#global private\n"
        "const A = 1\n";

    static constexpr std::string_view EXPECTED =
        "#global private\n"
        "\n"
        "const A = 1\n";

    FormatOptions options;
    options.blankLineAfterGlobalBlock = true;
    return checkBlanksRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_AfterGlobalThenUsingBlocks)
{
    static constexpr std::string_view SOURCE =
        "#global private\n"
        "using Alpha\n"
        "using Beta\n"
        "const A = 1\n";

    static constexpr std::string_view EXPECTED =
        "#global private\n"
        "\n"
        "using Alpha\n"
        "using Beta\n"
        "\n"
        "const A = 1\n";

    FormatOptions options;
    options.blankLineAfterGlobalBlock = true;
    options.blankLineAfterUsingBlock  = true;
    return checkBlanksRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_AfterBlocksInsertsBlank)
{
    static constexpr std::string_view SOURCE =
        "func foo(x: bool)\n"
        "{\n"
        "    if x\n"
        "    {\n"
        "        a = 1\n"
        "    }\n"
        "    b = 2\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo(x: bool)\n"
        "{\n"
        "    if x\n"
        "    {\n"
        "        a = 1\n"
        "    }\n"
        "\n"
        "    b = 2\n"
        "}\n";

    FormatOptions options;
    options.minBlankLinesAfterBlocks = 1;
    return checkBlanksRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_AfterBlocksKeepsElseAttached)
{
    static constexpr std::string_view SOURCE =
        "func foo(x: bool)\n"
        "{\n"
        "    if x\n"
        "    {\n"
        "        a = 1\n"
        "    }\n"
        "    else\n"
        "    {\n"
        "        b = 2\n"
        "    }\n"
        "}\n";

    FormatOptions options;
    options.minBlankLinesAfterBlocks = 1;
    return checkBlanksRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
