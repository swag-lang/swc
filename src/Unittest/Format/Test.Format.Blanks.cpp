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

SWC_END_NAMESPACE();

#endif
