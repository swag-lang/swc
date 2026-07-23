#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Format/FormatOptions.h"
#include "Format/Formatter.h"
#include "Main/TaskContext.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();
namespace
{
    Result checkSpacingRewrite(const TaskContext& parentCtx, std::string_view source, std::string_view expected, const FormatOptions& options)
    {
        Formatter formatter(options);
        SWC_RESULT(formatter.prepare(parentCtx.global(), source));
        if (formatter.text() != expected)
            return Result::Error;
        return Result::Continue;
    }
}

SWC_TEST_BEGIN(FormatSpacing_SpaceAfterComma)
{
    static constexpr std::string_view SOURCE =
        "func foo(a: s32,b: s32,c: s32) {}\n"
        "func bar()\n"
        "{\n"
        "    foo(1,2 ,3)\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo(a: s32, b: s32, c: s32) {}\n"
        "func bar()\n"
        "{\n"
        "    foo(1, 2, 3)\n"
        "}\n";

    FormatOptions options;
    options.spaceAfterComma  = true;
    options.spaceBeforeComma = false;
    return checkSpacingRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatSpacing_TrueOptionsKeepManualAlignment)
{
    // A `true` spacing option inserts missing blanks but never shrinks wider
    // runs: those are manual alignment.
    static constexpr std::string_view SOURCE =
        "func bar()\n"
        "{\n"
        "    var x:    s32 = 0\n"
        "    var yy    =    1\n"
        "}\n";

    FormatOptions options;
    options.spaceAfterColonInDeclarations = true;
    options.spaceAroundAssignmentOperator = true;
    options.spaceAfterComma               = true;
    return checkSpacingRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatSpacing_NoSpaceAfterComma)
{
    static constexpr std::string_view SOURCE =
        "func bar()\n"
        "{\n"
        "    var x = [1, 2, 3]\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func bar()\n"
        "{\n"
        "    var x = [1,2,3]\n"
        "}\n";

    FormatOptions options;
    options.spaceAfterComma = false;
    return checkSpacingRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatSpacing_SpaceAroundAssignment)
{
    static constexpr std::string_view SOURCE =
        "func bar()\n"
        "{\n"
        "    var x=1\n"
        "    x+=2\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func bar()\n"
        "{\n"
        "    var x = 1\n"
        "    x += 2\n"
        "}\n";

    FormatOptions options;
    options.spaceAroundAssignmentOperator = true;
    return checkSpacingRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatSpacing_NoSpaceAroundAssignment)
{
    static constexpr std::string_view SOURCE =
        "const X = 1\n";

    static constexpr std::string_view EXPECTED =
        "const X=1\n";

    FormatOptions options;
    options.spaceAroundAssignmentOperator = false;
    return checkSpacingRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatSpacing_SpaceAroundBinaryOperators)
{
    static constexpr std::string_view SOURCE =
        "const X = 1+2*3\n"
        "const Y = X<8\n";

    static constexpr std::string_view EXPECTED =
        "const X = 1 + 2 * 3\n"
        "const Y = X < 8\n";

    FormatOptions options;
    options.spaceAroundBinaryOperators = true;
    return checkSpacingRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatSpacing_NoSpaceAroundBinaryOperators)
{
    static constexpr std::string_view SOURCE =
        "const X = 1 + 2 * 3\n";

    static constexpr std::string_view EXPECTED =
        "const X = 1+2*3\n";

    FormatOptions options;
    options.spaceAroundBinaryOperators = false;
    return checkSpacingRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatSpacing_SpaceAroundArrow)
{
    static constexpr std::string_view SOURCE =
        "func foo()->s32\n"
        "{\n"
        "    return 1\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo() -> s32\n"
        "{\n"
        "    return 1\n"
        "}\n";

    FormatOptions options;
    options.spaceAroundArrow = true;
    SWC_RESULT(checkSpacingRewrite(ctx, SOURCE, EXPECTED, options));

    options.spaceAroundArrow = false;
    return checkSpacingRewrite(ctx, EXPECTED, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatSpacing_FatArrow)
{
    static constexpr std::string_view SOURCE =
        "func foo(x: s32)=>x + 1\n";

    static constexpr std::string_view EXPECTED =
        "func foo(x: s32) => x + 1\n";

    FormatOptions options;
    options.spaceAroundFatArrow = true;
    SWC_RESULT(checkSpacingRewrite(ctx, SOURCE, EXPECTED, options));

    options.spaceAroundFatArrow = false;
    return checkSpacingRewrite(ctx, EXPECTED, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatSpacing_ColonInDeclarations)
{
    static constexpr std::string_view SOURCE =
        "func bar()\n"
        "{\n"
        "    var x:s32 = 0\n"
        "    var y : s32 = 0\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func bar()\n"
        "{\n"
        "    var x: s32 = 0\n"
        "    var y: s32 = 0\n"
        "}\n";

    FormatOptions options;
    options.spaceBeforeColonInDeclarations = false;
    options.spaceAfterColonInDeclarations  = true;
    return checkSpacingRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatSpacing_ColonInBaseClause)
{
    static constexpr std::string_view SOURCE =
        "enum E:u32 { A }\n";

    static constexpr std::string_view EXPECTED =
        "enum E: u32 { A }\n";

    FormatOptions options;
    options.spaceBeforeColonInBaseClause  = false;
    options.spaceAfterColonInDeclarations = true;
    return checkSpacingRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatSpacing_InsideParentheses)
{
    static constexpr std::string_view SOURCE =
        "func foo(a: s32) {}\n"
        "func bar()\n"
        "{\n"
        "    foo(1)\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo( a: s32 ) {}\n"
        "func bar()\n"
        "{\n"
        "    foo( 1 )\n"
        "}\n";

    FormatOptions options;
    options.spaceInsideParentheses = true;
    SWC_RESULT(checkSpacingRewrite(ctx, SOURCE, EXPECTED, options));

    options.spaceInsideParentheses = false;
    return checkSpacingRewrite(ctx, EXPECTED, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatSpacing_InEmptyParentheses)
{
    static constexpr std::string_view SOURCE =
        "func foo() {}\n";

    static constexpr std::string_view EXPECTED =
        "func foo( ) {}\n";

    FormatOptions options;
    options.spaceInEmptyParentheses = true;
    SWC_RESULT(checkSpacingRewrite(ctx, SOURCE, EXPECTED, options));

    options.spaceInEmptyParentheses = false;
    return checkSpacingRewrite(ctx, EXPECTED, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatSpacing_InsideBrackets)
{
    static constexpr std::string_view SOURCE =
        "func bar()\n"
        "{\n"
        "    var a = [1, 2]\n"
        "    var b = a[0]\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func bar()\n"
        "{\n"
        "    var a = [ 1, 2 ]\n"
        "    var b = a[ 0 ]\n"
        "}\n";

    FormatOptions options;
    options.spaceInsideBrackets = true;
    SWC_RESULT(checkSpacingRewrite(ctx, SOURCE, EXPECTED, options));

    options.spaceInsideBrackets = false;
    return checkSpacingRewrite(ctx, EXPECTED, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatSpacing_AfterCast)
{
    static constexpr std::string_view SOURCE =
        "func bar()\n"
        "{\n"
        "    var x = cast(s64) 12\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func bar()\n"
        "{\n"
        "    var x = cast(s64)12\n"
        "}\n";

    FormatOptions options;
    options.spaceAfterCast = false;
    SWC_RESULT(checkSpacingRewrite(ctx, SOURCE, EXPECTED, options));

    options.spaceAfterCast = true;
    return checkSpacingRewrite(ctx, EXPECTED, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatSpacing_AfterKeyword)
{
    static constexpr std::string_view SOURCE =
        "func bar(x: bool)\n"
        "{\n"
        "    if(x) do return\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func bar(x: bool)\n"
        "{\n"
        "    if (x) do return\n"
        "}\n";

    FormatOptions options;
    options.spaceAfterKeyword = true;
    SWC_RESULT(checkSpacingRewrite(ctx, SOURCE, EXPECTED, options));

    options.spaceAfterKeyword = false;
    return checkSpacingRewrite(ctx, EXPECTED, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatSpacing_AfterUnaryOperator)
{
    static constexpr std::string_view SOURCE =
        "func bar(v: bool)\n"
        "{\n"
        "    var x = - 1\n"
        "    var y = ! v\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func bar(v: bool)\n"
        "{\n"
        "    var x = -1\n"
        "    var y = !v\n"
        "}\n";

    FormatOptions options;
    options.spaceAfterUnaryOperator = false;
    return checkSpacingRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatSpacing_BeforeParenthesesControl)
{
    // Swag forbids a blank before call / declaration parentheses, so the
    // option only drives the parenthesized condition of control statements.
    static constexpr std::string_view SOURCE =
        "func bar(x: bool)\n"
        "{\n"
        "    if (x) do return\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func bar(x: bool)\n"
        "{\n"
        "    if(x) do return\n"
        "}\n";

    FormatOptions options;
    options.spaceBeforeParentheses = FormatSpaceBeforeParens::Never;
    SWC_RESULT(checkSpacingRewrite(ctx, SOURCE, EXPECTED, options));

    options.spaceBeforeParentheses = FormatSpaceBeforeParens::ControlStatements;
    return checkSpacingRewrite(ctx, EXPECTED, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatSpacing_InsideBracesOfLiterals)
{
    static constexpr std::string_view SOURCE =
        "struct Point { x: s32, y: s32 }\n"
        "func bar()\n"
        "{\n"
        "    var p = Point{1, 2}\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "struct Point { x: s32, y: s32 }\n"
        "func bar()\n"
        "{\n"
        "    var p = Point{ 1, 2 }\n"
        "}\n";

    FormatOptions options;
    options.spaceInsideBraces = true;
    return checkSpacingRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
