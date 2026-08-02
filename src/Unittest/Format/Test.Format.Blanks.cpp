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

        Formatter secondPass(options);
        SWC_RESULT(secondPass.prepare(parentCtx.global(), formatter.text()));
        if (secondPass.text() != expected)
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

SWC_TEST_BEGIN(FormatBlanks_AfterOpeningBraceNever)
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
    options.blankLineAfterOpeningBrace = FormatBlankLineStyle::Never;
    options.maxConsecutiveEmptyLines   = 0;
    return checkBlanksRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_AfterOpeningBracePreserve)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "\n"
        "\n"
        "    a = 1\n"
        "}\n";

    FormatOptions options;
    options.blankLineAfterOpeningBrace = FormatBlankLineStyle::Preserve;
    options.maxConsecutiveEmptyLines   = 0;
    return checkBlanksRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_AfterOpeningBraceAlways)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    a = 1\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "\n"
        "    a = 1\n"
        "}\n";

    FormatOptions options;
    options.blankLineAfterOpeningBrace = FormatBlankLineStyle::Always;
    return checkBlanksRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_BeforeClosingBraceNever)
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
    options.blankLineBeforeClosingBrace = FormatBlankLineStyle::Never;
    options.maxConsecutiveEmptyLines    = 0;
    return checkBlanksRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_BeforeClosingBracePreserve)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    a = 1\n"
        "\n"
        "\n"
        "}\n";

    FormatOptions options;
    options.blankLineBeforeClosingBrace = FormatBlankLineStyle::Preserve;
    options.maxConsecutiveEmptyLines    = 0;
    return checkBlanksRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_BeforeClosingBraceAlways)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    a = 1\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    a = 1\n"
        "\n"
        "}\n";

    FormatOptions options;
    options.blankLineBeforeClosingBrace = FormatBlankLineStyle::Always;
    return checkBlanksRewrite(ctx, SOURCE, EXPECTED, options);
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

SWC_TEST_BEGIN(FormatBlanks_CombinedBlockEdges)
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
    options.blankLineAfterOpeningBrace  = FormatBlankLineStyle::Never;
    options.blankLineBeforeClosingBrace = FormatBlankLineStyle::Never;
    options.maxConsecutiveEmptyLines    = 0;
    return checkBlanksRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_BeforeFunctionAlways)
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
    options.blankLineBeforeFunctionDefinition = FormatBlankLineStyle::Always;
    return checkBlanksRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_BeforeFunctionKeepsDocCommentAttached)
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
    options.blankLineBeforeFunctionDefinition = FormatBlankLineStyle::Always;
    return checkBlanksRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_BeforeFunctionKeepsShortFormsStacked)
{
    static constexpr std::string_view SOURCE =
        "interface IFoo\n"
        "{\n"
        "    mtd one()\n"
        "    mtd two()\n"
        "}\n"
        "func square(x: s32) => x * x\n"
        "func cube(x: s32) => x * x * x\n";

    FormatOptions options;
    options.blankLineBeforeFunctionDefinition = FormatBlankLineStyle::Always;
    return checkBlanksRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_BeforeTypeAlways)
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
    options.blankLineBeforeTypeDefinition = FormatBlankLineStyle::Always;
    return checkBlanksRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_BeforeCommentBlockAlways)
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
    options.blankLineBeforeCommentBlock = FormatBlankLineStyle::Always;
    return checkBlanksRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_BeforeCommentBlockKeepsBlockStartAndRuns)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    // First comment: right after the brace.\n"
        "    // Second line of the same block.\n"
        "    a = 1\n"
        "}\n";

    FormatOptions options;
    options.blankLineBeforeCommentBlock = FormatBlankLineStyle::Always;
    return checkBlanksRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_BeforeCommentBlockKeepsInlineBodyStart)
{
    static constexpr std::string_view SOURCE =
        "func foo(ready: bool)\n"
        "{\n"
        "    if ready do\n"
        "\n"
        "        // First comment in the inline body.\n"
        "        work()\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo(ready: bool)\n"
        "{\n"
        "    if ready do\n"
        "        // First comment in the inline body.\n"
        "        work()\n"
        "}\n";

    FormatOptions options;
    options.blankLineBeforeCommentBlock = FormatBlankLineStyle::Always;
    options.blankLineAfterOpeningBrace  = FormatBlankLineStyle::Never;
    return checkBlanksRewrite(ctx, SOURCE, EXPECTED, options);
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
    options.blankLineAfterGlobalBlock = FormatBlankLineStyle::Always;
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
    options.blankLineAfterGlobalBlock = FormatBlankLineStyle::Always;
    options.blankLineAfterUsingBlock  = FormatBlankLineStyle::Always;
    return checkBlanksRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_BetweenCasesMultiLine)
{
    static constexpr std::string_view SOURCE =
        "func foo(x: s32)\n"
        "{\n"
        "    switch x\n"
        "    {\n"
        "    case 1: bar()\n"
        "    case 2: bar()\n"
        "    case 3:\n"
        "        bar()\n"
        "        bar()\n"
        "    case 4: bar()\n"
        "    }\n"
        "}\n"
        "func bar() {}\n";

    static constexpr std::string_view EXPECTED =
        "func foo(x: s32)\n"
        "{\n"
        "    switch x\n"
        "    {\n"
        "    case 1: bar()\n"
        "    case 2: bar()\n"
        "\n"
        "    case 3:\n"
        "        bar()\n"
        "        bar()\n"
        "\n"
        "    case 4: bar()\n"
        "    }\n"
        "}\n"
        "func bar() {}\n";

    FormatOptions options;
    options.blankLineBetweenCases = FormatCaseBlankStyle::MultiLine;
    return checkBlanksRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_BetweenCasesNeverRemovesBlanks)
{
    static constexpr std::string_view SOURCE =
        "func foo(x: s32)\n"
        "{\n"
        "    switch x\n"
        "    {\n"
        "    case 1: bar()\n"
        "\n"
        "    case 2: bar()\n"
        "    }\n"
        "}\n"
        "func bar() {}\n";

    static constexpr std::string_view EXPECTED =
        "func foo(x: s32)\n"
        "{\n"
        "    switch x\n"
        "    {\n"
        "    case 1: bar()\n"
        "    case 2: bar()\n"
        "    }\n"
        "}\n"
        "func bar() {}\n";

    FormatOptions options;
    options.blankLineBetweenCases = FormatCaseBlankStyle::Never;
    return checkBlanksRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_AfterStandaloneClosingBraceAlways)
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
    options.blankLineAfterStandaloneClosingBrace = FormatBlankLineStyle::Always;
    return checkBlanksRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_AfterStandaloneClosingBraceNever)
{
    static constexpr std::string_view SOURCE =
        "func foo(x: bool)\n"
        "{\n"
        "    if x\n"
        "    {\n"
        "        a = 1\n"
        "    }\n"
        "\n"
        "    b = 2\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo(x: bool)\n"
        "{\n"
        "    if x\n"
        "    {\n"
        "        a = 1\n"
        "    }\n"
        "    b = 2\n"
        "}\n";

    FormatOptions options;
    options.blankLineAfterStandaloneClosingBrace = FormatBlankLineStyle::Never;
    return checkBlanksRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_AfterStandaloneClosingBracePreserve)
{
    static constexpr std::string_view SOURCE =
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
    options.blankLineAfterStandaloneClosingBrace = FormatBlankLineStyle::Preserve;
    return checkBlanksRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBlanks_AfterStandaloneClosingBraceKeepsElseAttached)
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
    options.blankLineAfterStandaloneClosingBrace = FormatBlankLineStyle::Always;
    return checkBlanksRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
