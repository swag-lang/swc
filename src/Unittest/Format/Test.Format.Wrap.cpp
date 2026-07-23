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
