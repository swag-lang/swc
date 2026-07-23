#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Format/FormatOptions.h"
#include "Format/Formatter.h"
#include "Main/TaskContext.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();
namespace
{
    Result checkBracesRewrite(const TaskContext& parentCtx, std::string_view source, std::string_view expected, const FormatOptions& options)
    {
        Formatter formatter(options);
        SWC_RESULT(formatter.prepare(parentCtx.global(), source));
        if (formatter.text() != expected)
            return Result::Error;
        return Result::Continue;
    }
}

SWC_TEST_BEGIN(FormatBraces_AllmanMovesBraceToOwnLine)
{
    static constexpr std::string_view SOURCE =
        "func foo() {\n"
        "    return\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    return\n"
        "}\n";

    FormatOptions options;
    options.braceStyle = FormatBraceStyle::Allman;
    return checkBracesRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBraces_AttachJoinsBrace)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    return\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo() {\n"
        "    return\n"
        "}\n";

    FormatOptions options;
    options.braceStyle = FormatBraceStyle::Attach;
    return checkBracesRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBraces_AllmanOnControlBlocks)
{
    static constexpr std::string_view SOURCE =
        "func foo(x: bool)\n"
        "{\n"
        "    if x {\n"
        "        return\n"
        "    }\n"
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
    options.braceStyle = FormatBraceStyle::Allman;
    return checkBracesRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBraces_BreakBeforeElse)
{
    static constexpr std::string_view SOURCE =
        "func foo(x: bool)\n"
        "{\n"
        "    if x\n"
        "    {\n"
        "        return\n"
        "    } else\n"
        "    {\n"
        "        return\n"
        "    }\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo(x: bool)\n"
        "{\n"
        "    if x\n"
        "    {\n"
        "        return\n"
        "    }\n"
        "    else\n"
        "    {\n"
        "        return\n"
        "    }\n"
        "}\n";

    FormatOptions options;
    options.breakBeforeElse = true;
    return checkBracesRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBraces_JoinElseToBrace)
{
    static constexpr std::string_view SOURCE =
        "func foo(x: bool)\n"
        "{\n"
        "    if x\n"
        "    {\n"
        "        return\n"
        "    }\n"
        "    else\n"
        "    {\n"
        "        return\n"
        "    }\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo(x: bool)\n"
        "{\n"
        "    if x\n"
        "    {\n"
        "        return\n"
        "    } else\n"
        "    {\n"
        "        return\n"
        "    }\n"
        "}\n";

    FormatOptions options;
    options.breakBeforeElse = false;
    return checkBracesRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBraces_CompactEmptyBraces)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo() {}\n";

    FormatOptions options;
    options.compactEmptyBraces = true;
    return checkBracesRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBraces_ShortFunctionsNeverSplits)
{
    static constexpr std::string_view SOURCE =
        "func bar() {}\n"
        "func foo() { bar() }\n";

    static constexpr std::string_view EXPECTED =
        "func bar() {}\n"
        "func foo() {\n"
        "    bar()\n"
        "}\n";

    FormatOptions options;
    options.allowShortFunctionsOnSingleLine = FormatShortBlockStyle::Never;
    return checkBracesRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBraces_ShortFunctionsNeverKeepsEmpty)
{
    static constexpr std::string_view SOURCE =
        "func foo() {}\n";

    FormatOptions options;
    options.allowShortFunctionsOnSingleLine = FormatShortBlockStyle::Never;
    return checkBracesRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBraces_ShortBlocksInlineJoins)
{
    static constexpr std::string_view SOURCE =
        "func foo(x: bool)\n"
        "{\n"
        "    if x\n"
        "    {\n"
        "        bar()\n"
        "    }\n"
        "}\n"
        "func bar() {}\n";

    static constexpr std::string_view EXPECTED =
        "func foo(x: bool)\n"
        "{\n"
        "    if x { bar() }\n"
        "}\n"
        "func bar() {}\n";

    FormatOptions options;
    options.allowShortBlocksOnSingleLine = FormatShortBlockStyle::Inline;
    return checkBracesRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBraces_ShortIfNeverSplits)
{
    static constexpr std::string_view SOURCE =
        "func foo(x: bool)\n"
        "{\n"
        "    if x { bar() }\n"
        "}\n"
        "func bar() {}\n";

    static constexpr std::string_view EXPECTED =
        "func foo(x: bool)\n"
        "{\n"
        "    if x {\n"
        "        bar()\n"
        "    }\n"
        "}\n"
        "func bar() {}\n";

    FormatOptions options;
    options.allowShortIfStatementsOnSingleLine = false;
    return checkBracesRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBraces_ShortLoopsJoin)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    for i in 3\n"
        "    {\n"
        "        bar()\n"
        "    }\n"
        "}\n"
        "func bar() {}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    for i in 3 { bar() }\n"
        "}\n"
        "func bar() {}\n";

    FormatOptions options;
    options.allowShortLoopsOnSingleLine = true;
    return checkBracesRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBraces_ShortEnumsSplit)
{
    static constexpr std::string_view SOURCE =
        "enum E { A }\n";

    static constexpr std::string_view EXPECTED =
        "enum E {\n"
        "    A\n"
        "}\n";

    FormatOptions options;
    options.allowShortEnumsOnSingleLine = FormatShortBlockStyle::Never;
    return checkBracesRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBraces_ShortCaseSplits)
{
    static constexpr std::string_view SOURCE =
        "func foo(x: s32)\n"
        "{\n"
        "    switch x\n"
        "    {\n"
        "    case 1: bar()\n"
        "    default: bar()\n"
        "    }\n"
        "}\n"
        "func bar() {}\n";

    static constexpr std::string_view EXPECTED =
        "func foo(x: s32)\n"
        "{\n"
        "    switch x\n"
        "    {\n"
        "    case 1:\n"
        "        bar()\n"
        "    default:\n"
        "        bar()\n"
        "    }\n"
        "}\n"
        "func bar() {}\n";

    FormatOptions options;
    options.allowShortCaseOnSingleLine = false;
    return checkBracesRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBraces_ShortCaseJoins)
{
    static constexpr std::string_view SOURCE =
        "func foo(x: s32)\n"
        "{\n"
        "    switch x\n"
        "    {\n"
        "    case 1:\n"
        "        bar()\n"
        "    }\n"
        "}\n"
        "func bar() {}\n";

    static constexpr std::string_view EXPECTED =
        "func foo(x: s32)\n"
        "{\n"
        "    switch x\n"
        "    {\n"
        "    case 1: bar()\n"
        "    }\n"
        "}\n"
        "func bar() {}\n";

    FormatOptions options;
    options.allowShortCaseOnSingleLine = true;
    return checkBracesRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBraces_ShortStructsKeepTupleTypes)
{
    static constexpr std::string_view SOURCE =
        "func foo()->{ x: f32, y: f32 }\n"
        "{\n"
        "    var result: retval\n"
        "    return result\n"
        "}\n"
        "var g: { a: s32, b: s32 }\n";

    FormatOptions options;
    options.allowShortStructsOnSingleLine = FormatShortBlockStyle::Never;
    return checkBracesRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBraces_ShortStructsStillSplitDeclarations)
{
    static constexpr std::string_view SOURCE =
        "struct Point { x: f32, y: f32 }\n";

    static constexpr std::string_view EXPECTED =
        "struct Point {\n"
        "    x: f32, y: f32\n"
        "}\n";

    FormatOptions options;
    options.allowShortStructsOnSingleLine = FormatShortBlockStyle::Never;
    return checkBracesRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBraces_ShortFunctionsKeepClosureArguments)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    bar(func(x: s32) { baz(x) })\n"
        "    bar(func|v = 1|(x: s32) { baz(v) })\n"
        "}\n"
        "func bar(cb: func(s32)) {}\n"
        "func baz(x: s32) {}\n";

    FormatOptions options;
    options.allowShortFunctionsOnSingleLine = FormatShortBlockStyle::Never;
    return checkBracesRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBraces_ShortBlocksKeepInitializerLiterals)
{
    static constexpr std::string_view SOURCE =
        "struct(T) Box\n"
        "{\n"
        "    values: [2] T\n"
        "}\n"
        "func foo()\n"
        "{\n"
        "    var a = Box'(s32){values: [21, 34]}\n"
        "    var b = struct { field: u16 }{field: 12'u16}\n"
        "}\n";

    FormatOptions options;
    options.allowShortBlocksOnSingleLine  = FormatShortBlockStyle::Never;
    options.allowShortStructsOnSingleLine = FormatShortBlockStyle::Never;
    return checkBracesRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatBraces_ShortFunctionsInlineKeepsClosureBodies)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    bar(func(x: s32)\n"
        "    {\n"
        "        baz(x)\n"
        "    })\n"
        "}\n"
        "func bar(cb: func(s32)) {}\n"
        "func baz(x: s32) {}\n";

    FormatOptions options;
    options.allowShortFunctionsOnSingleLine = FormatShortBlockStyle::Inline;
    return checkBracesRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
