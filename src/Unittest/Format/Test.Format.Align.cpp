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

        Formatter secondPass(options);
        SWC_RESULT(secondPass.prepare(parentCtx.global(), formatter.text()));
        if (secondPass.text() != expected)
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

SWC_TEST_BEGIN(FormatAlign_ConsecutiveAliases)
{
    static constexpr std::string_view SOURCE =
        "alias A      = u8\n"
        "alias Longer = u16\n"
        "alias X = u32\n";

    static constexpr std::string_view EXPECTED =
        "alias A      = u8\n"
        "alias Longer = u16\n"
        "alias X      = u32\n";

    FormatOptions options;
    options.normalizeHorizontalWhitespace = true;
    options.alignConsecutiveAliases       = FormatAlignMode::Consecutive;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_AliasesAcrossAttributesAndBlankLines)
{
    static constexpr std::string_view SOURCE =
        "#[Swag.Strict]\n"
        "public alias A = u8\n"
        "\n"
        "#[Swag.Strict]\n"
        "public alias LongerName = u16\n";

    static constexpr std::string_view EXPECTED =
        "#[Swag.Strict]\n"
        "public alias A          = u8\n"
        "\n"
        "#[Swag.Strict]\n"
        "public alias LongerName = u16\n";

    FormatOptions options;
    options.normalizeHorizontalWhitespace = true;
    options.alignConsecutiveAliases       = FormatAlignMode::AcrossBlanks;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_AssignmentsBreakOnIndentation)
{
    static constexpr std::string_view SOURCE =
        "func foo(index: s32)\n"
        "{\n"
        "    if index != 0 do\n"
        "        len = append(len, 1)\n"
        "    len     = append(len, 2)\n"
        "    len     = append(len, 3)\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo(index: s32)\n"
        "{\n"
        "    if index != 0 do\n"
        "        len = append(len, 1)\n"
        "    len = append(len, 2)\n"
        "    len = append(len, 3)\n"
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
    options.alignTrailingComments    = true;
    options.trailingCommentMinSpaces = 5;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_TrailingCommentsBreakOnIndentation)
{
    static constexpr std::string_view SOURCE =
        "func foo(x: bool)\n"
        "{\n"
        "    if x do\n"
        "        a = 1 // nested\n"
        "    longer = 2 // outer one\n"
        "    b = 3 // outer two\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo(x: bool)\n"
        "{\n"
        "    if x do\n"
        "        a = 1     // nested\n"
        "    longer = 2     // outer one\n"
        "    b = 3          // outer two\n"
        "}\n";

    FormatOptions options;
    options.alignTrailingComments    = true;
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

SWC_TEST_BEGIN(FormatAlign_StructFieldsWithTypeQualifiers)
{
    static constexpr std::string_view SOURCE =
        "struct Wnd {}\n"
        "struct EditView\n"
        "{\n"
        "    using wnd: Wnd\n"
        "    main: *Wnd\n"
        "    capture: #null *Wnd\n"
        "    zoom: f32 = 1\n"
        "    inPlaceEdit: bool\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "struct Wnd {}\n"
        "struct EditView\n"
        "{\n"
        "    using wnd:   Wnd\n"
        "    main:        *Wnd\n"
        "    capture:     #null *Wnd\n"
        "    zoom:        f32 = 1\n"
        "    inPlaceEdit: bool\n"
        "}\n";

    FormatOptions options;
    options.alignStructFields = FormatAlignMode::Consecutive;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_StructFieldGridMixed)
{
    // Mixed typed / untyped / initialized fields line up in two columns: the
    // type column (after `:`) and the initializer column (`=`).
    static constexpr std::string_view SOURCE =
        "struct GameInfo\n"
        "{\n"
        "    gameStatus: String\n"
        "    whiteTurn = true\n"
        "    castle: bool = true\n"
        "    priseEnPassant = -1\n"
        "    possibleMoves: Array\n"
        "    selectedCell = -1\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "struct GameInfo\n"
        "{\n"
        "    gameStatus:    String\n"
        "    whiteTurn           = true\n"
        "    castle:        bool = true\n"
        "    priseEnPassant      = -1\n"
        "    possibleMoves: Array\n"
        "    selectedCell        = -1\n"
        "}\n";

    FormatOptions options;
    options.alignStructFields            = FormatAlignMode::Consecutive;
    options.alignStructFieldInitializers = true;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_StructFieldGridOffKeepsSingleColumn)
{
    // Without the grid option, the untyped field still fragments the type
    // groups: each colon field is a singleton tightened to one space.
    static constexpr std::string_view SOURCE =
        "struct S\n"
        "{\n"
        "    aaaa: s32\n"
        "    b = 1\n"
        "    cc: s32\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "struct S\n"
        "{\n"
        "    aaaa: s32\n"
        "    b = 1\n"
        "    cc: s32\n"
        "}\n";

    FormatOptions options;
    options.alignStructFields = FormatAlignMode::Consecutive;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_DeclarationGridInitializers)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    var x: s32 = 0\n"
        "    var yyy = 1\n"
        "    var z: bool = true\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    var x: s32  = 0\n"
        "    var yyy     = 1\n"
        "    var z: bool = true\n"
        "}\n";

    FormatOptions options;
    options.alignConsecutiveDeclarations = FormatAlignMode::Consecutive;
    options.alignDeclarationInitializers = true;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_ConstantGridTypes)
{
    // Constants align the value by default; the grid option adds the type
    // column so `const NAME: Type = value` lines up on both `:` and `=`.
    static constexpr std::string_view SOURCE =
        "const A: s32 = 1\n"
        "const BBB = 22\n"
        "const C: bool = true\n";

    static constexpr std::string_view EXPECTED =
        "const A: s32  = 1\n"
        "const BBB     = 22\n"
        "const C: bool = true\n";

    FormatOptions options;
    options.alignConsecutiveConstants = FormatAlignMode::Consecutive;
    options.alignConstantTypes        = true;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_QualifiedConstantGridTypes)
{
    static constexpr std::string_view SOURCE =
        "private const A: s32 = 1\n"
        "private const BBB = 22\n"
        "private const C: bool = true\n";

    static constexpr std::string_view EXPECTED =
        "private const A: s32  = 1\n"
        "private const BBB     = 22\n"
        "private const C: bool = true\n";

    FormatOptions options;
    options.alignConsecutiveConstants = FormatAlignMode::Consecutive;
    options.alignConstantTypes        = true;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_QualifiedDeclarationPrefixes)
{
    static constexpr std::string_view SOURCE =
        "private var x: s32 = 0\n"
        "private var yyy = 1\n"
        "private var z: bool = true\n"
        "\n"
        "struct S\n"
        "{\n"
        "    public a: s32\n"
        "    public longer: u64\n"
        "}\n"
        "\n"
        "private func square(x: s32) => x * x\n"
        "private func longerName(x: s32) => x + 1\n";

    static constexpr std::string_view EXPECTED =
        "private var x: s32  = 0\n"
        "private var yyy     = 1\n"
        "private var z: bool = true\n"
        "\n"
        "struct S\n"
        "{\n"
        "    public a:      s32\n"
        "    public longer: u64\n"
        "}\n"
        "\n"
        "private func square(x: s32)     => x * x\n"
        "private func longerName(x: s32) => x + 1\n";

    FormatOptions options;
    options.alignConsecutiveDeclarations = FormatAlignMode::Consecutive;
    options.alignDeclarationInitializers = true;
    options.alignStructFields            = FormatAlignMode::Consecutive;
    options.alignFatArrows               = FormatAlignMode::Consecutive;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_CaseBodiesConsecutive)
{
    static constexpr std::string_view SOURCE =
        "func foo(x: s32)->s32\n"
        "{\n"
        "    switch x\n"
        "    {\n"
        "    case 1: return 8\n"
        "    case 100: return 192\n"
        "    default: return 0\n"
        "    }\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo(x: s32)->s32\n"
        "{\n"
        "    switch x\n"
        "    {\n"
        "    case 1:   return 8\n"
        "    case 100: return 192\n"
        "    default:  return 0\n"
        "    }\n"
        "}\n";

    FormatOptions options;
    options.alignCaseBodies = FormatAlignMode::Consecutive;
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

SWC_TEST_BEGIN(FormatAlign_HangingLineFollowsAlignedAnchor)
{
    // Padding the `=` pushes `func(` five columns right; the wrapped parameter
    // line has to travel with it instead of staying at the source column.
    static constexpr std::string_view SOURCE =
        "alias LongerName = u8\n"
        "alias Short = func(a: u8, b: u8,\n"
        "                   c: u8)\n";

    static constexpr std::string_view EXPECTED =
        "alias LongerName = u8\n"
        "alias Short      = func(a: u8, b: u8,\n"
        "                        c: u8)\n";

    FormatOptions options;
    options.indentStyle                   = FormatIndentStyle::Spaces;
    options.normalizeHorizontalWhitespace = true;
    options.alignConsecutiveAliases       = FormatAlignMode::Consecutive;
    options.alignAfterOpenBracket         = true;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_AfterOpenBracketUsesLiteralBrace)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    add({a: 1,\n"
        "    b: 2})\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    add({a: 1,\n"
        "         b: 2})\n"
        "}\n";

    FormatOptions options;
    options.indentStyle           = FormatIndentStyle::Spaces;
    options.alignAfterOpenBracket = true;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_AfterOpenBracketKeepsDataTableRows)
{
    // The `[` ends its line, so it carries no item to align with: the rows
    // keep the statement's continuation indent instead of marching right.
    static constexpr std::string_view SOURCE =
        "const T = [\n"
        "    1, 2,\n"
        "    3, 4]\n";

    FormatOptions options;
    options.indentStyle           = FormatIndentStyle::Spaces;
    options.alignAfterOpenBracket = true;
    return checkAlignRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_OperandsInsideBracketAnchorOnBracket)
{
    // The wrapped operand belongs to the argument list, not to the statement:
    // anchoring it on `bar` would pull it out of the call.
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    bar(aaa,\n"
        "        bbb ==\n"
        "        ccc)\n"
        "}\n";

    FormatOptions options;
    options.indentStyle   = FormatIndentStyle::Spaces;
    options.alignOperands = true;
    return checkAlignRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_OperandsOutsideBracketAnchorOnStatement)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    let x = aaa ==\n"
        "    bbb\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    let x = aaa ==\n"
        "            bbb\n"
        "}\n";

    FormatOptions options;
    options.indentStyle   = FormatIndentStyle::Spaces;
    options.alignOperands = true;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_OutlierGapLeavesLongLineAlone)
{
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    a = 1\n"
        "    bb = 2\n"
        "    thisNameIsFarLongerThanTheOthers = 3\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    a  = 1\n"
        "    bb = 2\n"
        "    thisNameIsFarLongerThanTheOthers = 3\n"
        "}\n";

    FormatOptions options;
    options.alignConsecutiveAssignments = FormatAlignMode::Consecutive;
    options.alignOutlierGap             = 16;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_OutlierGapKeepsGradedTable)
{
    // Every step is inside the allowed gap, so the whole run is one table even
    // though the first and last names are far apart.
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    a = 1\n"
        "    aaaaaaaaaa = 2\n"
        "    aaaaaaaaaaaaaaaaaaaa = 3\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    a                    = 1\n"
        "    aaaaaaaaaa           = 2\n"
        "    aaaaaaaaaaaaaaaaaaaa = 3\n"
        "}\n";

    FormatOptions options;
    options.alignConsecutiveAssignments = FormatAlignMode::Consecutive;
    options.alignOutlierGap             = 16;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_OutlierGapDropsBothEnds)
{
    // A pair that only stands next to each other keeps its column; the two
    // lines isolated at either end of the group are left with one space.
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    a = 1\n"
        "    someMiddleName = 2\n"
        "    someMiddleNam = 3\n"
        "    andThisOneIsTheLongestNameOfThemAll = 4\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    a = 1\n"
        "    someMiddleName = 2\n"
        "    someMiddleNam  = 3\n"
        "    andThisOneIsTheLongestNameOfThemAll = 4\n"
        "}\n";

    FormatOptions options;
    options.alignConsecutiveAssignments = FormatAlignMode::Consecutive;
    options.alignOutlierGap             = 8;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_AcrossBlanksReadsTheCappedBlankCount)
{
    // The blank-line cap is applied when the gap is rendered, so a run of three
    // that comes out as one must not break the group on the way there.
    static constexpr std::string_view SOURCE =
        "alias Short = s32\n"
        "\n"
        "\n"
        "\n"
        "alias LongerName = s32\n";

    static constexpr std::string_view EXPECTED =
        "alias Short      = s32\n"
        "\n"
        "alias LongerName = s32\n";

    FormatOptions options;
    options.alignConsecutiveAliases  = FormatAlignMode::AcrossBlanks;
    options.maxConsecutiveEmptyLines = 1;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_AccessModifierLineDoesNotBreakTheGroup)
{
    // `internal` alone on a line is the first half of the field below it, so the
    // three fields are one column, not three groups of one.
    static constexpr std::string_view SOURCE =
        "struct Mixed\n"
        "{\n"
        "    internal\n"
        "    hash: u32\n"
        "    readonly\n"
        "    key: u64\n"
        "    other: f32\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "struct Mixed\n"
        "{\n"
        "    internal\n"
        "    hash:  u32\n"
        "    readonly\n"
        "    key:   u64\n"
        "    other: f32\n"
        "}\n";

    FormatOptions options;
    options.alignStructFields = FormatAlignMode::Consecutive;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatAlign_WrappedArgumentsFollowTheAlignedHead)
{
    // Alignment pads `let col` after wrapping has already placed the arguments
    // under the open parenthesis. The wrapped lines have to move with it, or the
    // file only settles on the next run of the formatter.
    static constexpr std::string_view SOURCE =
        "func foo()\n"
        "{\n"
        "    let alpha = 1\n"
        "    let col = make(a,\n"
        "b, c)\n"
        "}\n";

    static constexpr std::string_view EXPECTED =
        "func foo()\n"
        "{\n"
        "    let alpha = 1\n"
        "    let col   = make(a,\n"
        "                     b,\n"
        "                     c)\n"
        "}\n";

    FormatOptions options;
    options.indentStyle                  = FormatIndentStyle::Spaces;
    options.indentWidth                  = 4;
    options.alignConsecutiveDeclarations = FormatAlignMode::Consecutive;
    options.alignDeclarationInitializers = true;
    options.binPackArguments             = FormatBinPackStyle::OnePerLine;
    options.argumentListLayout           = FormatListLayout::HangingAlign;
    return checkAlignRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
