#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Format/FormatOptions.h"
#include "Format/Formatter.h"
#include "Main/TaskContext.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();
namespace
{
    Result checkAttributesRewrite(const TaskContext& parentCtx, std::string_view source, std::string_view expected, const FormatOptions& options)
    {
        Formatter formatter(options);
        SWC_RESULT(formatter.prepare(parentCtx.global(), source));
        if (formatter.text() != expected)
            return Result::Error;
        return Result::Continue;
    }
}

SWC_TEST_BEGIN(FormatAttributes_OwnLine)
{
    static constexpr std::string_view SOURCE =
        "#[Swag.Inline] func foo() {}\n";

    static constexpr std::string_view EXPECTED =
        "#[Swag.Inline]\n"
        "func foo() {}\n";

    FormatOptions options;
    options.attributePlacement = FormatAttributePlacement::OwnLine;
    return checkAttributesRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAttributes_Inline)
{
    static constexpr std::string_view SOURCE =
        "#[Swag.Inline]\n"
        "func foo() {}\n";

    static constexpr std::string_view EXPECTED =
        "#[Swag.Inline] func foo() {}\n";

    FormatOptions options;
    options.attributePlacement = FormatAttributePlacement::Inline;
    return checkAttributesRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAttributes_BreakAfterAttribute)
{
    static constexpr std::string_view SOURCE =
        "#[Swag.Inline] func foo() {}\n";

    static constexpr std::string_view EXPECTED =
        "#[Swag.Inline]\n"
        "func foo() {}\n";

    FormatOptions options;
    options.breakAfterAttribute = true;
    return checkAttributesRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAttributes_Grouped)
{
    static constexpr std::string_view SOURCE =
        "#[Swag.Inline]\n"
        "#[Swag.ConstExpr]\n"
        "func foo() {}\n";

    static constexpr std::string_view EXPECTED =
        "#[Swag.Inline, Swag.ConstExpr]\n"
        "func foo() {}\n";

    FormatOptions options;
    options.attributePlacement = FormatAttributePlacement::Grouped;
    return checkAttributesRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAttributes_SortArguments)
{
    static constexpr std::string_view SOURCE =
        "#[Swag.Overload, Swag.ConstExpr]\n"
        "func foo() {}\n"
        "func foo(x: s32) {}\n";

    static constexpr std::string_view EXPECTED =
        "#[Swag.ConstExpr, Swag.Overload]\n"
        "func foo() {}\n"
        "func foo(x: s32) {}\n";

    FormatOptions options;
    options.sortAttributeArguments = true;
    return checkAttributesRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAttributes_SpaceAfterAttributeComma)
{
    static constexpr std::string_view SOURCE =
        "#[Swag.ConstExpr,Swag.Inline]\n"
        "func foo() {}\n";

    static constexpr std::string_view EXPECTED =
        "#[Swag.ConstExpr, Swag.Inline]\n"
        "func foo() {}\n";

    FormatOptions options;
    options.spaceAfterAttributeComma = true;
    return checkAttributesRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
