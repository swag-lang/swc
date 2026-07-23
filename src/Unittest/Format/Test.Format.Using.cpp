#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Format/FormatOptions.h"
#include "Format/Formatter.h"
#include "Main/TaskContext.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();
namespace
{
    Result checkUsingRewrite(const TaskContext& parentCtx, std::string_view source, std::string_view expected, const FormatOptions& options)
    {
        Formatter formatter(options);
        SWC_RESULT(formatter.prepare(parentCtx.global(), source));
        if (formatter.text() != expected)
            return Result::Error;
        return Result::Continue;
    }
}

SWC_TEST_BEGIN(FormatUsing_SortAscending)
{
    static constexpr std::string_view SOURCE =
        "using Zeta\n"
        "using Alpha\n"
        "using Beta.Sub\n"
        "const X = 1\n";

    static constexpr std::string_view EXPECTED =
        "using Alpha\n"
        "using Beta.Sub\n"
        "using Zeta\n"
        "const X = 1\n";

    FormatOptions options;
    options.sortUsingStatements = FormatSortOrder::Ascending;
    return checkUsingRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatUsing_SortCaseInsensitive)
{
    static constexpr std::string_view SOURCE =
        "using beta\n"
        "using Alpha\n"
        "const X = 1\n";

    static constexpr std::string_view EXPECTED =
        "using Alpha\n"
        "using beta\n"
        "const X = 1\n";

    FormatOptions options;
    options.sortUsingStatements = FormatSortOrder::CaseInsensitiveAscending;
    return checkUsingRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatUsing_BlankLineSplitsRuns)
{
    static constexpr std::string_view SOURCE =
        "using Zeta\n"
        "\n"
        "using Alpha\n"
        "const X = 1\n";

    FormatOptions options;
    options.sortUsingStatements = FormatSortOrder::Ascending;
    return checkUsingRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatUsing_Merge)
{
    static constexpr std::string_view SOURCE =
        "using Alpha\n"
        "using Beta\n"
        "const X = 1\n";

    static constexpr std::string_view EXPECTED =
        "using Alpha, Beta\n"
        "const X = 1\n";

    FormatOptions options;
    options.mergeUsingStatements = true;
    return checkUsingRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatUsing_SortAndMerge)
{
    static constexpr std::string_view SOURCE =
        "using Zeta\n"
        "using Alpha\n"
        "const X = 1\n";

    static constexpr std::string_view EXPECTED =
        "using Alpha, Zeta\n"
        "const X = 1\n";

    FormatOptions options;
    options.sortUsingStatements  = FormatSortOrder::Ascending;
    options.mergeUsingStatements = true;
    return checkUsingRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
