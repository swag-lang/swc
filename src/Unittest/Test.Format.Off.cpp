#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Format/FormatOptions.h"
#include "Format/Formatter.h"
#include "Main/TaskContext.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();
namespace
{
    Result checkFormatOffRewrite(const TaskContext& parentCtx, std::string_view source, std::string_view expected, const FormatOptions& options)
    {
        Formatter formatter(options);
        SWC_RESULT(formatter.prepare(parentCtx.global(), source));
        if (formatter.text() != expected)
            return Result::Error;
        return Result::Continue;
    }
}

SWC_TEST_BEGIN(FormatOff_LineCommentDisablesNumberFormatting)
{
    static constexpr std::string_view SOURCE =
        "#assert(0xabcd)\n"
        "// swc-format off\n"
        "#assert(0xabcd)\n"
        "// swc-format on\n"
        "#assert(0xabcd)\n";

    static constexpr std::string_view EXPECTED =
        "#assert(0xABCD)\n"
        "// swc-format off\n"
        "#assert(0xabcd)\n"
        "// swc-format on\n"
        "#assert(0xABCD)\n";

    FormatOptions options;
    options.hexLiteralCase = FormatLiteralCase::Upper;
    return checkFormatOffRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatOff_NoOnComment_RestOfFileRaw)
{
    static constexpr std::string_view SOURCE =
        "#assert(0xabcd)\n"
        "// swc-format off\n"
        "#assert(0xabcd)\n"
        "#assert(0xabcd)\n";

    static constexpr std::string_view EXPECTED =
        "#assert(0xABCD)\n"
        "// swc-format off\n"
        "#assert(0xabcd)\n"
        "#assert(0xabcd)\n";

    FormatOptions options;
    options.hexLiteralCase = FormatLiteralCase::Upper;
    return checkFormatOffRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatOff_MultipleRegions)
{
    static constexpr std::string_view SOURCE =
        "#assert(0xabcd)\n"
        "// swc-format off\n"
        "#assert(0xabcd)\n"
        "// swc-format on\n"
        "#assert(0xabcd)\n"
        "// swc-format off\n"
        "#assert(0xabcd)\n"
        "// swc-format on\n"
        "#assert(0xabcd)\n";

    static constexpr std::string_view EXPECTED =
        "#assert(0xABCD)\n"
        "// swc-format off\n"
        "#assert(0xabcd)\n"
        "// swc-format on\n"
        "#assert(0xABCD)\n"
        "// swc-format off\n"
        "#assert(0xabcd)\n"
        "// swc-format on\n"
        "#assert(0xABCD)\n";

    FormatOptions options;
    options.hexLiteralCase = FormatLiteralCase::Upper;
    return checkFormatOffRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatOff_BlockComment)
{
    static constexpr std::string_view SOURCE =
        "#assert(0xabcd)\n"
        "/* swc-format off */\n"
        "#assert(0xabcd)\n"
        "/* swc-format on */\n"
        "#assert(0xabcd)\n";

    static constexpr std::string_view EXPECTED =
        "#assert(0xABCD)\n"
        "/* swc-format off */\n"
        "#assert(0xabcd)\n"
        "/* swc-format on */\n"
        "#assert(0xABCD)\n";

    FormatOptions options;
    options.hexLiteralCase = FormatLiteralCase::Upper;
    return checkFormatOffRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatOff_CustomMarkers)
{
    static constexpr std::string_view SOURCE =
        "#assert(0xabcd)\n"
        "// fmt:off\n"
        "#assert(0xabcd)\n"
        "// fmt:on\n"
        "#assert(0xabcd)\n";

    static constexpr std::string_view EXPECTED =
        "#assert(0xABCD)\n"
        "// fmt:off\n"
        "#assert(0xabcd)\n"
        "// fmt:on\n"
        "#assert(0xABCD)\n";

    FormatOptions options;
    options.hexLiteralCase   = FormatLiteralCase::Upper;
    options.formatOffComment = "fmt:off";
    options.formatOnComment  = "fmt:on";
    return checkFormatOffRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatOff_EolNotRewrittenInDisabledRegion)
{
    // The \r\n immediately after "// swc-format off" is already in the disabled
    // region (state flips after emitting the comment), so it passes through raw.
    // The \r\n after "// swc-format on" is back in enabled mode and is rewritten.
    static constexpr std::string_view SOURCE =
        "#assert(1)\r\n"
        "// swc-format off\r\n"
        "#assert(2)\r\n"
        "// swc-format on\r\n"
        "#assert(3)\r\n";

    static constexpr std::string_view EXPECTED =
        "#assert(1)\n"
        "// swc-format off\r\n"
        "#assert(2)\r\n"
        "// swc-format on\n"
        "#assert(3)\n";

    FormatOptions options;
    options.endOfLineStyle = FormatEndOfLineStyle::Lf;
    return checkFormatOffRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
