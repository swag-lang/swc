#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Format/FormatOptions.h"
#include "Format/FormatOptionsLoader.h"
#include "Format/Formatter.h"
#include "Main/TaskContext.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();
namespace
{
    Result checkStyleRewrite(const TaskContext& parentCtx, std::string_view source, std::string_view expected, const FormatOptions& options)
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

    // Written the way nobody writes it: every dimension the canonical style has
    // an opinion about is wrong here.
    constexpr std::string_view MANGLED =
        "struct   Point {\n"
        "  x:s32\n"
        "        y  :  s32\n"
        "}\n"
        "func  add( a:s32,b:s32 )->s32 {\n"
        "     return a+b ;\n"
        "}\n";
}

SWC_TEST_BEGIN(FormatStyle_PreserveNormalizesNothing)
{
    FormatOptions options;
    applyFormatStyle(options, FormatNamedStyle::Preserve);
    return checkStyleRewrite(ctx, MANGLED, MANGLED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatStyle_DefaultOptionsArePreserve)
{
    // The struct's own defaults have to stay the passive style: every test in
    // this suite builds on a default `FormatOptions` and sets one option.
    const FormatOptions defaults;
    FormatOptions       preserve;
    applyFormatStyle(preserve, FormatNamedStyle::Preserve);
    if (FormatOptionsLoader::describe(defaults) != FormatOptionsLoader::describe(preserve))
        return Result::Error;
    return checkStyleRewrite(ctx, MANGLED, MANGLED, defaults);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatStyle_SwagIsTheCanonicalLayout)
{
    static constexpr std::string_view EXPECTED =
        "struct Point\n"
        "{\n"
        "    x: s32\n"
        "    y: s32\n"
        "}\n"
        "\n"
        "func add(a: s32, b: s32)->s32\n"
        "{\n"
        "    return a + b\n"
        "}\n";

    FormatOptions options;
    applyFormatStyle(options, FormatNamedStyle::Swag);
    return checkStyleRewrite(ctx, MANGLED, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatStyle_SwagIntrinsicCallsStayStable)
{
    static constexpr std::string_view SOURCE =
        "func contextSaysJit()->bool\n"
        "{\n"
        "    return Swag.getContext().runtimeFlags & .FromCompiler ? true : false\n"
        "}\n"
        "\n"
        "func jitCallMatchesContext()->bool\n"
        "{\n"
        "    return Swag.jit() == contextSaysJit()\n"
        "}\n"
        "\n"
        "#test\n"
        "{\n"
        "    var context = Swag.getContext()\n"
        "    #assert(#defined(context.panic))\n"
        "    Swag.assert(#defined(context.panic))\n"
        "\n"
        "    Swag.setContext(context)\n"
        "    Swag.assert(Swag.getContext() == &context)\n"
        "}\n";

    FormatOptions options;
    applyFormatStyle(options, FormatNamedStyle::Swag);
    return checkStyleRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatStyle_SwagKeepsAccessModifiersWithTheirDeclarations)
{
    static constexpr std::string_view SOURCE =
        "#global public\n"
        "\n"
        "private\n"
        "func hidden() {}\n"
        "\n"
        "struct Record\n"
        "{\n"
        "    public readonly\n"
        "    count: s32\n"
        "\n"
        "    private\n"
        "    {\n"
        "        cached: bool\n"
        "    }\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "#global public\n"
        "\n"
        "private func hidden() {}\n"
        "\n"
        "struct Record\n"
        "{\n"
        "    public readonly count: s32\n"
        "\n"
        "    private\n"
        "    {\n"
        "        cached: bool\n"
        "    }\n"
        "}\n";

    FormatOptions options;
    applyFormatStyle(options, FormatNamedStyle::Swag);
    return checkStyleRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatStyle_SwagKeepsStorageAndAccessModifierOrders)
{
    static constexpr std::string_view SOURCE =
        "var first: s32\n"
        "\n"
        "// The declaration starts before either modifier.\n"
        "{} var value: s32\n"
        "\n"
        "namespace Nested\n"
        "{{\n"
        "    var first: s32\n"
        "\n"
        "    // Keep the same order inside a namespace.\n"
        "    {} var value: s32\n"
        "}}\n";

    FormatOptions options;
    applyFormatStyle(options, FormatNamedStyle::Swag);

    for (const std::string_view storage : {"late", "tls", "global"})
    {
        for (const std::string_view access : {"private", "public", "internal"})
        {
            for (const bool storageFirst : {false, true})
            {
                const std::string_view first     = storageFirst ? storage : access;
                const std::string_view second    = storageFirst ? access : storage;
                const std::string      modifiers = std::format("{} {}", first, second);
                const std::string      source    = std::format(SOURCE, modifiers, modifiers);
                SWC_RESULT(checkStyleRewrite(ctx, source, source, options));

                const std::string splitModifiers = std::format("{}\n{}", first, second);
                const std::string splitSource    = std::format(SOURCE, splitModifiers, splitModifiers);
                SWC_RESULT(checkStyleRewrite(ctx, splitSource, source, options));
            }
        }
    }

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatStyle_SwagSeparatesAccessBlocks)
{
    static constexpr std::string_view SOURCE =
        "struct Record\n"
        "{\n"
        "    public\n"
        "    {\n"
        "        first: s32\n"
        "    }\n"
        "    cached: bool\n"
        "    public\n"
        "    {\n"
        "        value: s32\n"
        "        readonly\n"
        "        {\n"
        "            count: s32\n"
        "        }\n"
        "    }\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "struct Record\n"
        "{\n"
        "    public\n"
        "    {\n"
        "        first: s32\n"
        "    }\n"
        "\n"
        "    cached: bool\n"
        "\n"
        "    public\n"
        "    {\n"
        "        value: s32\n"
        "\n"
        "        readonly\n"
        "        {\n"
        "            count: s32\n"
        "        }\n"
        "    }\n"
        "}\n";

    FormatOptions options;
    applyFormatStyle(options, FormatNamedStyle::Swag);
    return checkStyleRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatStyle_SwagLeavesLineEndingsAndColumnsAlone)
{
    // Line endings belong to the checkout and the column budget to the author:
    // the canonical style has to stay out of both, or every formatted file
    // becomes a whole-file diff on the other operating system.
    FormatOptions options;
    applyFormatStyle(options, FormatNamedStyle::Swag);
    if (options.endOfLineStyle != FormatEndOfLineStyle::Preserve || options.columnLimit != 0)
        return Result::Error;

    static constexpr std::string_view SOURCE   = "func foo()\r\n{\r\n    return\r\n}\r\n";
    static constexpr std::string_view EXPECTED = "func foo()\r\n{\r\n    return\r\n}\r\n";
    return checkStyleRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatStyle_DescribeRendersEveryOption)
{
    FormatOptions options;
    applyFormatStyle(options, FormatNamedStyle::Swag);
    const Utf8 dump = FormatOptionsLoader::describe(options);

    // A dump is meant to be redirected into a `.swc-format` file, so it has to
    // carry the value of every option and nothing that is not a key or a
    // comment.
    if (dump.find("\nbrace-style = allman\n") == std::string::npos ||
        dump.find("\nindent-width = 4\n") == std::string::npos ||
        dump.find("\nblank-line-before-access-block = always\n") == std::string::npos ||
        dump.find("\nblank-line-after-access-block = always\n") == std::string::npos ||
        dump.find("\nend-of-line-style = preserve\n") == std::string::npos ||
        dump.find("\nformat-off-comment = \"swc-format off\"\n") == std::string::npos ||
        dump.find("# Possible values: preserve, attach, allman, stroustrup\n") == std::string::npos)
        return Result::Error;

    for (const std::string_view line : std::views::split(dump.view(), '\n') | std::views::transform([](auto&& r) { return std::string_view(r); }))
    {
        if (line.empty() || line.starts_with('#'))
            continue;
        if (line.find(" = ") == std::string_view::npos)
            return Result::Error;
    }

    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
