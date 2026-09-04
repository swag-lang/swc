#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Format/FormatOptions.h"
#include "Format/Formatter.h"
#include "Main/TaskContext.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();
namespace
{
    Result checkCommentsRewrite(const TaskContext& parentCtx, std::string_view source, std::string_view expected, const FormatOptions& options)
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
}

SWC_TEST_BEGIN(FormatComments_SpaceAfterLineCommentPrefix)
{
    static constexpr std::string_view SOURCE =
        "//hello\n"
        "// already fine\n"
        "//----\n"
        "const X = 1 //trailing\n";

    static constexpr std::string_view EXPECTED =
        "// hello\n"
        "// already fine\n"
        "//----\n"
        "const X = 1 // trailing\n";

    FormatOptions options;
    options.spaceAfterLineCommentPrefix = true;
    return checkCommentsRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatComments_NormalizeSectionSeparators)
{
    static constexpr std::string_view SOURCE =
        "// ----\n"
        "const X = 1\n";

    static constexpr std::string_view EXPECTED =
        "// -----------------\n"
        "const X = 1\n";

    FormatOptions options;
    options.normalizeSectionSeparators = true;
    options.sectionSeparatorWidth      = 20;
    return checkCommentsRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatComments_ReflowParagraph)
{
    static constexpr std::string_view SOURCE =
        "// aaa bbb ccc ddd\n"
        "// eee\n"
        "const X = 1\n";

    static constexpr std::string_view EXPECTED =
        "// aaa bbb ccc\n"
        "// ddd eee\n"
        "const X = 1\n";

    FormatOptions options;
    options.commentReflow = FormatCommentReflow::Reflow;
    options.columnLimit   = 16;
    return checkCommentsRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatComments_ReflowJoinsShortLines)
{
    static constexpr std::string_view SOURCE =
        "// aaa\n"
        "// bbb\n"
        "// ccc\n"
        "const X = 1\n";

    static constexpr std::string_view EXPECTED =
        "// aaa bbb ccc\n"
        "const X = 1\n";

    FormatOptions options;
    options.commentReflow = FormatCommentReflow::Reflow;
    options.columnLimit   = 40;
    return checkCommentsRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatComments_NormalizeMode)
{
    static constexpr std::string_view SOURCE =
        "//one\n"
        "//two words\n"
        "const X = 1\n";

    static constexpr std::string_view EXPECTED =
        "// one\n"
        "// two words\n"
        "const X = 1\n";

    FormatOptions options;
    options.commentReflow = FormatCommentReflow::Normalize;
    return checkCommentsRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatComments_LastInBlockKeepsBlockIndent)
{
    static constexpr std::string_view SOURCE =
        "func f()\n"
        "{\n"
        "    var x = 1\n"
        "    discard x\n"
        "// last\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func f()\n"
        "{\n"
        "    var x = 1\n"
        "    discard x\n"
        "    // last\n"
        "}\n";

    FormatOptions options;
    options.indentStyle = FormatIndentStyle::Spaces;
    options.indentWidth = 4;
    return checkCommentsRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatComments_LastInNestedBlockKeepsBlockIndent)
{
    static constexpr std::string_view SOURCE =
        "func f(v: s32)\n"
        "{\n"
        "    if v == 1\n"
        "    {\n"
        "        discard v\n"
        "    // inner last\n"
        "    }\n"
        "// outer last\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func f(v: s32)\n"
        "{\n"
        "    if v == 1\n"
        "    {\n"
        "        discard v\n"
        "        // inner last\n"
        "    }\n"
        "    // outer last\n"
        "}\n";

    FormatOptions options;
    options.indentStyle = FormatIndentStyle::Spaces;
    options.indentWidth = 4;
    return checkCommentsRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatComments_LastInSwitchKeepsArmIndent)
{
    static constexpr std::string_view SOURCE =
        "func f(v: s32)\n"
        "{\n"
        "    switch v\n"
        "    {\n"
        "    case 0:\n"
        "        discard v\n"
        "    case 1:\n"
        "        discard v\n"
        "    // end of the last arm\n"
        "    }\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func f(v: s32)\n"
        "{\n"
        "    switch v\n"
        "    {\n"
        "    case 0:\n"
        "        discard v\n"
        "    case 1:\n"
        "        discard v\n"
        "        // end of the last arm\n"
        "    }\n"
        "}\n";

    FormatOptions options;
    options.indentStyle      = FormatIndentStyle::Spaces;
    options.indentWidth      = 4;
    options.indentCaseLabels = false;
    options.indentCaseBlocks = true;
    return checkCommentsRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatComments_BeforeCaseLabelKeepsLabelIndent)
{
    static constexpr std::string_view SOURCE =
        "func f(v: s32)\n"
        "{\n"
        "    switch v\n"
        "    {\n"
        "    case 0:\n"
        "        discard v\n"
        "\n"
        "        // introduces the next arm\n"
        "    case 1:\n"
        "        discard v\n"
        "    }\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func f(v: s32)\n"
        "{\n"
        "    switch v\n"
        "    {\n"
        "    case 0:\n"
        "        discard v\n"
        "\n"
        "    // introduces the next arm\n"
        "    case 1:\n"
        "        discard v\n"
        "    }\n"
        "}\n";

    FormatOptions options;
    options.indentStyle      = FormatIndentStyle::Spaces;
    options.indentWidth      = 4;
    options.indentCaseLabels = false;
    options.indentCaseBlocks = true;
    return checkCommentsRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
