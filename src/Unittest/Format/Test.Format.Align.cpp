#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Format/FormatOptions.h"
#include "Format/Formatter.h"
#include "Main/TaskContext.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();
namespace
{
    Result checkAlignRewrite(const TaskContext& parentCtx, std::string_view source, std::string_view expected, const FormatOptions& options)
    {
        Formatter formatter(options);
        SWC_RESULT(formatter.prepare(parentCtx.global(), source));
        if (formatter.text() != expected)
            return Result::Error;
        return Result::Continue;
    }
}

SWC_TEST_BEGIN(FormatAlign_ConsecutiveAssignments)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    var a = 0\n"
        "    var bb = 0\n"
        "    a = 1\n"
        "    bb = 22\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    var a = 0\n"
        "    var bb = 0\n"
        "    a  = 1\n"
        "    bb = 22\n"
        "}\n";

    FormatOptions options;
    options.alignConsecutiveAssignments = FormatAlignMode::Consecutive;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_AssignmentsBreakOnBlankLine)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    var a = 0\n"
        "    var bbb = 0\n"
        "    a = 1\n"
        "\n"
        "    bbb = 22\n"
        "}\n";

    FormatOptions options;
    options.alignConsecutiveAssignments = FormatAlignMode::Consecutive;
    return checkAlignRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_AssignmentsAcrossBlanks)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    var a = 0\n"
        "    var bbb = 0\n"
        "    a = 1\n"
        "\n"
        "    bbb = 22\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    var a = 0\n"
        "    var bbb = 0\n"
        "    a   = 1\n"
        "\n"
        "    bbb = 22\n"
        "}\n";

    FormatOptions options;
    options.alignConsecutiveAssignments = FormatAlignMode::AcrossBlanks;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_ConsecutiveDeclarations)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    var x: s32 = 0\n"
        "    var yyy: f64 = 0\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    var x:   s32 = 0\n"
        "    var yyy: f64 = 0\n"
        "}\n";

    FormatOptions options;
    options.alignConsecutiveDeclarations = FormatAlignMode::Consecutive;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_ConsecutiveConstants)
{
    static constexpr std::string_view SOURCE =
        "const A = 1\n"
        "const BBB = 22\n";

    static constexpr std::string_view EXPECTED =
        "const A   = 1\n"
        "const BBB = 22\n";

    FormatOptions options;
    options.alignConsecutiveConstants = FormatAlignMode::Consecutive;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_StructFields)
{
    static constexpr std::string_view SOURCE =
        "struct S\n"
        "{\n"
        "    x: s32\n"
        "    yyy: f64\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "struct S\n"
        "{\n"
        "    x:   s32\n"
        "    yyy: f64\n"
        "}\n";

    FormatOptions options;
    options.alignStructFields = FormatAlignMode::Consecutive;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_EnumValues)
{
    static constexpr std::string_view SOURCE =
        "enum E\n"
        "{\n"
        "    A = 1\n"
        "    BBB = 2\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "enum E\n"
        "{\n"
        "    A   = 1\n"
        "    BBB = 2\n"
        "}\n";

    FormatOptions options;
    options.alignEnumValues = FormatAlignMode::Consecutive;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_NoneRemovesAlignment)
{
    static constexpr std::string_view SOURCE =
        "const A   = 1\n"
        "const BBB = 22\n";

    static constexpr std::string_view EXPECTED =
        "const A = 1\n"
        "const BBB = 22\n";

    FormatOptions options;
    options.alignConsecutiveConstants = FormatAlignMode::None;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_TrailingComments)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    var a = 0 // one\n"
        "    var bb = 0    // two\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    var a = 0      // one\n"
        "    var bb = 0     // two\n"
        "}\n";

    FormatOptions options;
    options.alignTrailingComments   = true;
    options.trailingCommentMinSpaces = 5;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_TrailingCommentsNormalized)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    var a = 0      // one\n"
        "    var bb = 0     // two\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    var a = 0 // one\n"
        "    var bb = 0 // two\n"
        "}\n";

    FormatOptions options;
    options.alignTrailingComments    = false;
    options.trailingCommentMinSpaces = 1;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_FatArrowsConsecutive)
{
    static constexpr std::string_view SOURCE =
        "func square(x: s32) => x * x\n"
        "func longerName(x: s32) => x + 1\n";

    static constexpr std::string_view EXPECTED =
        "func square(x: s32)     => x * x\n"
        "func longerName(x: s32) => x + 1\n";

    FormatOptions options;
    options.alignFatArrows = FormatAlignMode::Consecutive;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_FatArrowsBreakOnPlainFunction)
{
    static constexpr std::string_view SOURCE =
        "func square(x: s32) => x * x\n"
        "func plain()\n"
        "{\n"
        "    return\n"
        "}\n"
        "func cube(x: s32) => x * x * x\n";

    FormatOptions options;
    options.alignFatArrows = FormatAlignMode::Consecutive;
    return checkAlignRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_SingletonTightensStalePadding)
{
    static constexpr std::string_view SOURCE =
        "struct S\n"
        "{\n"
        "    aaaa: s32\n"
        "    bb:   s32\n"
        "\n"
        "    // isolated field keeps no stale manual padding\n"
        "    lone:            s32\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "struct S\n"
        "{\n"
        "    aaaa: s32\n"
        "    bb:   s32\n"
        "\n"
        "    // isolated field keeps no stale manual padding\n"
        "    lone: s32\n"
        "}\n";

    FormatOptions options;
    options.alignStructFields = FormatAlignMode::Consecutive;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_ArrayColumns)
{
    static constexpr std::string_view SOURCE =
        "const T = [\n"
        "    { \"a\", 1 },\n"
        "    { \"bbb\", 22 },\n"
        "]\n";

    static constexpr std::string_view EXPECTED =
        "const T = [\n"
        "    { \"a\",   1 },\n"
        "    { \"bbb\", 22 },\n"
        "]\n";

    FormatOptions options;
    options.alignArrayColumns = true;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_ArrayColumnsSkipsRaggedRows)
{
    static constexpr std::string_view SOURCE =
        "const T = [\n"
        "    { \"a\", 1 },\n"
        "    { \"bbb\" },\n"
        "]\n";

    FormatOptions options;
    options.alignArrayColumns = true;
    return checkAlignRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
