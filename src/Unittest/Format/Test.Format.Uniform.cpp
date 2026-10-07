#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Format/FormatOptions.h"
#include "Format/Formatter.h"
#include "Main/TaskContext.h"
#include "Unittest/Format/FormatRewriteCheck.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    FormatOptions swagStyle()
    {
        FormatOptions options;
        applyFormatStyle(options, FormatNamedStyle::Swag);
        return options;
    }
}

SWC_TEST_BEGIN(FormatUniform_ChainBracesEveryBranchWhenOneNeedsIt)
{
    static constexpr std::string_view SOURCE =
        "func f(a: s32)\n"
        "{\n"
        "    if a > 0\n"
        "    {\n"
        "        x = 1\n"
        "        y = 2\n"
        "    }\n"
        "    elif a == 0 do\n"
        "        x = 4\n"
        "    else do\n"
        "        x = 3\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func f(a: s32)\n"
        "{\n"
        "    if a > 0\n"
        "    {\n"
        "        x = 1\n"
        "        y = 2\n"
        "    }\n"
        "    elif a == 0\n"
        "    {\n"
        "        x = 4\n"
        "    }\n"
        "    else\n"
        "    {\n"
        "        x = 3\n"
        "    }\n"
        "}\n";

    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, swagStyle());
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatUniform_ChainDropsBracesWhenEveryBranchIsOneStatement)
{
    static constexpr std::string_view SOURCE =
        "func f(a: s32)\n"
        "{\n"
        "    if a > 0\n"
        "    {\n"
        "        x = 1\n"
        "    }\n"
        "    elif a == 0 do\n"
        "        x = 4\n"
        "    else { x = 5 }\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func f(a: s32)\n"
        "{\n"
        "    if a > 0 do\n"
        "        x = 1\n"
        "    elif a == 0 do\n"
        "        x = 4\n"
        "    else do\n"
        "        x = 5\n"
        "}\n";

    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, swagStyle());
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatUniform_ChainKeepsBracesThatHoldAnElse)
{
    // After `do`, `try a()` would take the `else` that follows as its own
    // failure handler: that branch keeps its braces, so the chain is braced.
    static constexpr std::string_view SOURCE =
        "func f(a: s32)\n"
        "{\n"
        "    if a > 0\n"
        "    {\n"
        "        try g()\n"
        "    }\n"
        "    else do\n"
        "        x = 3\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func f(a: s32)\n"
        "{\n"
        "    if a > 0\n"
        "    {\n"
        "        try g()\n"
        "    }\n"
        "    else\n"
        "    {\n"
        "        x = 3\n"
        "    }\n"
        "}\n";

    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, swagStyle());
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatUniform_ChainKeepsDeclarationsInTheirScope)
{
    // `let` belongs to the scope its braces open: neither branch can change
    // form, so the chain stays as written.
    static constexpr std::string_view SOURCE =
        "func f(a: s32)\n"
        "{\n"
        "    if a > 0\n"
        "    {\n"
        "        let y = 1\n"
        "    }\n"
        "    else do\n"
        "        let z = 2\n"
        "}\n";

    return FormatRewriteCheck::check(ctx, SOURCE, SOURCE, swagStyle());
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatUniform_ChainCommentBeforeElseStaysAttached)
{
    static constexpr std::string_view SOURCE =
        "func f(a: s32)\n"
        "{\n"
        "    if a > 0\n"
        "    {\n"
        "        x = 1\n"
        "        y = 2\n"
        "    }\n"
        "\n"
        "    // Otherwise reset.\n"
        "    else\n"
        "    {\n"
        "        x = 3\n"
        "        y = 4\n"
        "    }\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func f(a: s32)\n"
        "{\n"
        "    if a > 0\n"
        "    {\n"
        "        x = 1\n"
        "        y = 2\n"
        "    }\n"
        "    // Otherwise reset.\n"
        "    else\n"
        "    {\n"
        "        x = 3\n"
        "        y = 4\n"
        "    }\n"
        "}\n";

    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, swagStyle());
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatUniform_GuardsShareTheOneLineForm)
{
    static constexpr std::string_view SOURCE =
        "func f(a: s32)\n"
        "{\n"
        "    if a == 0 do\n"
        "        return\n"
        "    if a == 1\n"
        "    {\n"
        "        return\n"
        "    }\n"
        "    if a == 2 do\n"
        "        return\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func f(a: s32)\n"
        "{\n"
        "    if a == 0 do\n"
        "        return\n"
        "    if a == 1 do\n"
        "        return\n"
        "    if a == 2 do\n"
        "        return\n"
        "}\n";

    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, swagStyle());
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatUniform_GuardsNeverGrowBraces)
{
    // A guard reads as one line whatever its neighbour holds.
    static constexpr std::string_view SOURCE =
        "func f(a: s32)\n"
        "{\n"
        "    if a == 0 do\n"
        "        return\n"
        "    if a == 1\n"
        "    {\n"
        "        x = 1\n"
        "        return\n"
        "    }\n"
        "}\n";

    return FormatRewriteCheck::check(ctx, SOURCE, SOURCE, swagStyle());
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatUniform_ClosureStatementsExpandTogether)
{
    static constexpr std::string_view SOURCE =
        "func f()\n"
        "{\n"
        "    api.first = func(x)->bool\n"
        "    {\n"
        "        let y = x + 1\n"
        "        return y > 2\n"
        "    }\n"
        "    api.second = func(x)->bool => x > 3\n"
        "    api.third = func(x) { print(x) }\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func f()\n"
        "{\n"
        "    api.first = func(x)->bool\n"
        "    {\n"
        "        let y = x + 1\n"
        "        return y > 2\n"
        "    }\n"
        "\n"
        "    api.second = func(x)->bool\n"
        "    {\n"
        "        return x > 3\n"
        "    }\n"
        "\n"
        "    api.third = func(x)\n"
        "    {\n"
        "        print(x)\n"
        "    }\n"
        "}\n";

    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, swagStyle());
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatUniform_ClosureStatementsCompactTogether)
{
    static constexpr std::string_view SOURCE =
        "func f()\n"
        "{\n"
        "    api.first = func(x)->bool\n"
        "    {\n"
        "        return x > 2\n"
        "    }\n"
        "    api.second = func(x)->bool => x > 3\n"
        "    api.third = func(x)\n"
        "    {\n"
        "        print(x)\n"
        "    }\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func f()\n"
        "{\n"
        "    api.first  = func(x)->bool => x > 2\n"
        "    api.second = func(x)->bool => x > 3\n"
        "    api.third  = func(x) { print(x) }\n"
        "}\n";

    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, swagStyle());
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatUniform_ClosureItemsOfOneListExpandTogether)
{
    static constexpr std::string_view SOURCE =
        "func f()\n"
        "{\n"
        "    host.set({\n"
        "        first: func(x)->bool\n"
        "        {\n"
        "            let y = x + 1\n"
        "            return y > 2\n"
        "        },\n"
        "        second: func(x) { print(x) }})\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func f()\n"
        "{\n"
        "    host.set({\n"
        "        first: func(x)->bool\n"
        "        {\n"
        "            let y = x + 1\n"
        "            return y > 2\n"
        "        },\n"
        "        second: func(x)\n"
        "        {\n"
        "            print(x)\n"
        "        }})\n"
        "}\n";

    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, swagStyle());
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatUniform_FunctionsJoinTheirOneLineSiblings)
{
    static constexpr std::string_view SOURCE =
        "impl A\n"
        "{\n"
        "    mtd count()->u64 => 5\n"
        "\n"
        "    // Drops everything.\n"
        "    mtd drop()\n"
        "    {\n"
        "        .free()\n"
        "    }\n"
        "\n"
        "    mtd size()->u64\n"
        "    {\n"
        "        return 4\n"
        "    }\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "impl A\n"
        "{\n"
        "    mtd count()->u64 => 5\n"
        "\n"
        "    // Drops everything.\n"
        "    mtd drop() { .free() }\n"
        "\n"
        "    mtd size()->u64 => 4\n"
        "}\n";

    return FormatRewriteCheck::check(ctx, SOURCE, EXPECTED, swagStyle());
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatUniform_FunctionsNeverExpand)
{
    // Methods of every size live side by side: a long one is no reason to
    // expand its one-line neighbours, nor to join a short one.
    static constexpr std::string_view SOURCE =
        "impl A\n"
        "{\n"
        "    mtd count()->u64 => 5\n"
        "\n"
        "    mtd drop()\n"
        "    {\n"
        "        .free()\n"
        "    }\n"
        "\n"
        "    mtd reset()\n"
        "    {\n"
        "        .free()\n"
        "        .count = 0\n"
        "    }\n"
        "}\n";

    return FormatRewriteCheck::check(ctx, SOURCE, SOURCE, swagStyle());
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatUniform_EveryFamilyCanBeTurnedOff)
{
    static constexpr std::string_view SOURCE =
        "func f(a: s32)\n"
        "{\n"
        "    if a > 0\n"
        "    {\n"
        "        x = 1\n"
        "        y = 2\n"
        "    }\n"
        "    else do\n"
        "        x = 3\n"
        "    if a == 0 do\n"
        "        return\n"
        "    if a == 1\n"
        "    {\n"
        "        return\n"
        "    }\n"
        "\n"
        "    api.first = func(x)->bool\n"
        "    {\n"
        "        let y = x + 1\n"
        "        return y > 2\n"
        "    }\n"
        "\n"
        "    api.second = func(x)->bool => x > 3\n"
        "}\n";

    FormatOptions options         = swagStyle();
    options.uniformBranchBodies   = false;
    options.uniformGuardBodies    = FormatAlignMode::None;
    options.uniformClosureBodies  = FormatAlignMode::None;
    options.uniformFunctionBodies = FormatAlignMode::None;
    return FormatRewriteCheck::check(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
