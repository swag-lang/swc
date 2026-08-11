#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Format/FormatOptions.h"
#include "Format/Formatter.h"
#include "Main/TaskContext.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();
namespace
{
    Result checkFileRewrite(const TaskContext& parentCtx, std::string_view source, std::string_view expected, const FormatOptions& options)
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

SWC_TEST_BEGIN(FormatFile_InlineBodyOwnsNestedBraceIndent)
{
    static constexpr std::string_view SOURCE =
        "func run(flag: bool)\n"
        "{\n"
        " for y in 2 do\n"
        "  for x in 2\n"
        " {\n"
        "  if flag\n"
        "  {\n"
        "   break\n"
        "}\n"
        "}\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func run(flag: bool)\n"
        "{\n"
        "    for y in 2 do\n"
        "        for x in 2\n"
        "        {\n"
        "            if flag\n"
        "            {\n"
        "                break\n"
        "            }\n"
        "        }\n"
        "}\n";

    FormatOptions options;
    options.indentStyle = FormatIndentStyle::Spaces;
    options.indentWidth = 4;
    return checkFileRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatFile_InlineIfBranchStopsBeforeElse)
{
    static constexpr std::string_view SOURCE =
        "func run(flag: bool)\n"
        "{\n"
        " if flag do\n"
        " signal += func|value = 1|(arg) { use(value, arg) }\n"
        " else do\n"
        " signal += func|value = 2|(arg) { use(value, arg) }\n"
        " finish()\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func run(flag: bool)\n"
        "{\n"
        "    if flag do\n"
        "        signal += func|value = 1|(arg) { use(value, arg) }\n"
        "    else do\n"
        "        signal += func|value = 2|(arg) { use(value, arg) }\n"
        "    finish()\n"
        "}\n";

    FormatOptions options;
    options.indentStyle = FormatIndentStyle::Spaces;
    options.indentWidth = 4;
    return checkFileRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatFile_CatchHandlerAlignsAndIndents)
{
    static constexpr std::string_view SOURCE =
        "func run(flag: bool)\n"
        "{\n"
        " if flag do\n"
        "  catch work()\n"
        "   else do\n"
        "   recover()\n"
        " finish()\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func run(flag: bool)\n"
        "{\n"
        "    if flag do\n"
        "        catch work()\n"
        "        else do\n"
        "            recover()\n"
        "    finish()\n"
        "}\n";

    FormatOptions options;
    options.indentStyle = FormatIndentStyle::Spaces;
    options.indentWidth = 4;
    return checkFileRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatFile_InlineDestructuringIsNotABlock)
{
    static constexpr std::string_view SOURCE =
        "func run(point: {x, y: s32})\n"
        "{\n"
        " var first: s32\n"
        " var second: s32\n"
        " if true do\n"
        " {x: first, y: second} = point\n"
        " if false do\n"
        " {\n"
        "     x: first, y: second\n"
        " } = point\n"
        " use(first)\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func run(point: {x, y: s32})\n"
        "{\n"
        "    var first: s32\n"
        "    var second: s32\n"
        "    if true do\n"
        "        {x: first, y: second} = point\n"
        "    if false do\n"
        "        {\n"
        "            x: first, y: second\n"
        "        } = point\n"
        "    use(first)\n"
        "}\n";

    FormatOptions options;
    options.indentStyle                        = FormatIndentStyle::Spaces;
    options.indentWidth                        = 4;
    options.allowShortBlocksOnSingleLine       = FormatShortBlockStyle::Empty;
    options.allowShortIfStatementsOnSingleLine = false;
    return checkFileRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatFile_InsertFinalNewline)
{
    static constexpr std::string_view SOURCE   = "const X = 1";
    static constexpr std::string_view EXPECTED = "const X = 1\n";

    FormatOptions options;
    options.insertFinalNewline = true;
    return checkFileRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatFile_TrimLeadingBlankLines)
{
    static constexpr std::string_view SOURCE =
        "\n"
        "\n"
        "const X = 1\n";

    static constexpr std::string_view EXPECTED =
        "const X = 1\n";

    FormatOptions options;
    options.trimLeadingBlankLines = true;
    return checkFileRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatFile_TrimLeadingBlankLinesDisabled)
{
    static constexpr std::string_view SOURCE =
        "\n"
        "const X = 1\n";

    FormatOptions options;
    options.trimLeadingBlankLines = false;
    return checkFileRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatFile_ReservedIdentifiersAreFormattable)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    __internalCall()\n"
        "}\n";

    const FormatOptions options;
    return checkFileRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatFile_IndentInsideParensEnforcesContinuation)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    bar(1,\n"
        "                2)\n"
        "}\n"
        "func bar(a, b: s32) {}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    bar(1,\n"
        "        2)\n"
        "}\n"
        "func bar(a, b: s32) {}\n";

    FormatOptions options;
    options.indentStyle        = FormatIndentStyle::Spaces;
    options.indentWidth        = 4;
    options.indentInsideParens = true;
    return checkFileRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatFile_AlignOperandsOnWrappedCondition)
{
    static constexpr std::string_view SOURCE =
        "func foo(a, b: bool)\n"
        "{\n"
        "    if a and\n"
        "            b do\n"
        "        return\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo(a, b: bool)\n"
        "{\n"
        "    if a and\n"
        "       b do\n"
        "        return\n"
        "}\n";

    FormatOptions options;
    options.indentStyle   = FormatIndentStyle::Spaces;
    options.indentWidth   = 4;
    options.alignOperands = true;
    return checkFileRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatFile_WhereClauseIndent)
{
    static constexpr std::string_view SOURCE =
        "func(T) foo(x: T)\n"
        "        where T == s32\n"
        "{\n"
        "    return\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func(T) foo(x: T)\n"
        "    where T == s32\n"
        "{\n"
        "    return\n"
        "}\n";

    FormatOptions options;
    options.indentStyle = FormatIndentStyle::Spaces;
    options.indentWidth = 4;
    return checkFileRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatFile_WhereBlockIndent)
{
    static constexpr std::string_view SOURCE =
        "func(T) foo(x: T)\n"
        "    where\n"
        "{\n"
        "    return T == s32\n"
        "}\n"
        "{\n"
        "    return\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func(T) foo(x: T)\n"
        "    where\n"
        "    {\n"
        "        return T == s32\n"
        "    }\n"
        "{\n"
        "    return\n"
        "}\n";

    FormatOptions options;
    options.indentStyle = FormatIndentStyle::Spaces;
    options.indentWidth = 4;
    return checkFileRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatFile_EndOfLineStyleLf)
{
    static constexpr std::string_view SOURCE =
        "const X = 1\r\n"
        "const Y = 2\r\n";

    static constexpr std::string_view EXPECTED =
        "const X = 1\n"
        "const Y = 2\n";

    FormatOptions options;
    options.endOfLineStyle = FormatEndOfLineStyle::Lf;
    return checkFileRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatFile_EndOfLineStyleCrLf)
{
    static constexpr std::string_view SOURCE =
        "const X = 1\n"
        "const Y = 2\n";

    static constexpr std::string_view EXPECTED =
        "const X = 1\r\n"
        "const Y = 2\r\n";

    FormatOptions options;
    options.endOfLineStyle = FormatEndOfLineStyle::CrLf;
    return checkFileRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatFile_TrimTrailingWhitespace)
{
    static constexpr std::string_view SOURCE =
        "const X = 1   \n"
        "const Y = 2\t\n";

    static constexpr std::string_view EXPECTED =
        "const X = 1\n"
        "const Y = 2\n";

    FormatOptions options;
    options.preserveTrailingWhitespace = false;
    return checkFileRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatFile_BlankLineAfterUsingBlock)
{
    static constexpr std::string_view SOURCE =
        "using A\n"
        "using B\n"
        "const X = 1\n";

    static constexpr std::string_view EXPECTED =
        "using A\n"
        "using B\n"
        "\n"
        "const X = 1\n";

    FormatOptions options;
    options.blankLineAfterUsingBlock = FormatBlankLineStyle::Always;
    return checkFileRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatFile_BlankLineBeforeFunctionDefinition)
{
    // Only multi-line definitions are separated: empty / one-line bodies and
    // prototypes keep stacking as written.
    static constexpr std::string_view SOURCE =
        "func foo() {}\n"
        "func bar()\n"
        "{\n"
        "    return\n"
        "}\n"
        "#[Swag.Inline]\n"
        "func baz()\n"
        "{\n"
        "    return\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo() {}\n"
        "\n"
        "func bar()\n"
        "{\n"
        "    return\n"
        "}\n"
        "\n"
        "#[Swag.Inline]\n"
        "func baz()\n"
        "{\n"
        "    return\n"
        "}\n";

    FormatOptions options;
    options.blankLineBeforeFunctionDefinition = FormatBlankLineStyle::Always;
    return checkFileRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatFile_IndentStyleSpacesNormalizesTabs)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "\treturn\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    return\n"
        "}\n";

    FormatOptions options;
    options.indentStyle = FormatIndentStyle::Spaces;
    options.indentWidth = 4;
    return checkFileRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatFile_IndentStyleTabs)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    return\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "\treturn\n"
        "}\n";

    FormatOptions options;
    options.indentStyle = FormatIndentStyle::Tabs;
    options.indentWidth = 4;
    return checkFileRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatFile_ReindentFixesBadIndent)
{
    static constexpr std::string_view SOURCE =
        "func foo(x: bool)\n"
        "{\n"
        "  if x\n"
        "      {\n"
        "     return\n"
        "      }\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo(x: bool)\n"
        "{\n"
        "    if x\n"
        "    {\n"
        "        return\n"
        "    }\n"
        "}\n";

    FormatOptions options;
    options.indentStyle = FormatIndentStyle::Spaces;
    options.indentWidth = 4;
    return checkFileRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatFile_ElseBeforeNestedIfAligns)
{
    static constexpr std::string_view SOURCE =
        "func foo(a: s32)\n"
        "{\n"
        "    if a == 1 do\n"
        "        bar()\n"
        "        else do\n"
        "        if a == 2 do\n"
        "            bar()\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo(a: s32)\n"
        "{\n"
        "    if a == 1 do\n"
        "        bar()\n"
        "    else do\n"
        "        if a == 2 do\n"
        "            bar()\n"
        "}\n";

    FormatOptions options;
    options.indentStyle = FormatIndentStyle::Spaces;
    options.indentWidth = 4;
    return checkFileRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatFile_IndentNamespaceBodyOff)
{
    static constexpr std::string_view SOURCE =
        "namespace N\n"
        "{\n"
        "    const X = 1\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "namespace N\n"
        "{\n"
        "const X = 1\n"
        "}\n";

    FormatOptions options;
    options.indentStyle         = FormatIndentStyle::Spaces;
    options.indentWidth         = 4;
    options.indentNamespaceBody = false;
    return checkFileRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatFile_IndentCaseLabels)
{
    static constexpr std::string_view SOURCE =
        "func foo(x: s32)\n"
        "{\n"
        "    switch x\n"
        "    {\n"
        "    case 1:\n"
        "        break\n"
        "    }\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo(x: s32)\n"
        "{\n"
        "    switch x\n"
        "    {\n"
        "        case 1:\n"
        "            break\n"
        "    }\n"
        "}\n";

    FormatOptions options;
    options.indentStyle      = FormatIndentStyle::Spaces;
    options.indentWidth      = 4;
    options.indentCaseLabels = true;
    SWC_RESULT(checkFileRewrite(ctx, SOURCE, EXPECTED, options));

    options.indentCaseLabels = false;
    return checkFileRewrite(ctx, EXPECTED, SOURCE, options);
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
