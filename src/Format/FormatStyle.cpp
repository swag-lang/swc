#include "pch.h"
#include "Format/FormatOptions.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // The canonical Swag style: the profile the repository's own sources under
    // `bin/` are written in, promoted to the compiler's built-in default. A Swag
    // tree therefore needs no configuration file to be formatted the way every
    // other Swag tree is, and `.swc-format` becomes what it should be — a place
    // to record a deliberate departure, not a prerequisite.
    //
    // Two options stay at their `Preserve` default on purpose.
    //   - `end-of-line-style`: line endings are a property of the checkout and of
    //     the platform, not of the style. Rewriting them turns every formatted
    //     file into a whole-file diff on the other operating system.
    //   - `column-limit`: the style has no column budget, so the formatter never
    //     adds or removes a statement break. Wrapping stays exactly where the
    //     author put it, which is what makes a hand-laid data table survive.
    void applySwagStyle(FormatOptions& o)
    {
        // File-level whitespace
        o.preserveBom                          = true;
        o.preserveTrailingWhitespace           = false;
        o.insertFinalNewline                   = true;
        o.trimTrailingNewlines                 = true;
        o.trimLeadingBlankLines                = true;
        o.maxConsecutiveEmptyLines             = 1;
        o.blankLineAfterOpeningBrace           = FormatBlankLineStyle::Never;
        o.blankLineBeforeClosingBrace          = FormatBlankLineStyle::Never;
        o.blankLineBeforeFunctionDefinition    = FormatBlankLineStyle::Always;
        o.blankLineBeforeTypeDefinition        = FormatBlankLineStyle::Always;
        o.blankLineBeforeCommentBlock          = FormatBlankLineStyle::Always;
        o.blankLineAfterStandaloneClosingBrace = FormatBlankLineStyle::Always;

        // Indentation
        o.indentStyle             = FormatIndentStyle::Spaces;
        o.indentWidth             = 4;
        o.tabWidth                = 4;
        o.continuationIndentWidth = 4;
        o.indentNamespaceBody     = true;
        o.indentImplBody          = true;
        o.indentStructBody        = true;
        o.indentEnumBody          = true;
        o.indentCaseLabels        = false;
        o.indentCaseBlocks        = true;
        o.indentAttributes        = true;
        o.indentInsideParens      = false;

        // Wrapping
        o.breakBeforeBinaryOperators           = FormatOperatorWrapStyle::After;
        o.breakBeforeTernaryOperators          = false;
        o.breakAfterReturnType                 = false;
        o.breakBeforeDo                        = false;
        o.breakBeforeElse                      = true;
        o.breakBeforeWhere                     = true;
        o.binPackArguments                     = FormatBinPackStyle::OnePerLine;
        o.binPackParameters                    = FormatBinPackStyle::OnePerLine;
        o.forceSingleLineArgumentLists         = false;
        o.forceSingleLineParameterLists        = false;
        o.sourceSelectsArgumentLayout          = true;
        o.sourceSelectsParameterLayout         = true;
        o.argumentListLayout                   = FormatListLayout::HangingAlign;
        o.parameterListLayout                  = FormatListLayout::HangingAlign;
        o.hugTrailingBlockArgument             = true;
        o.hugTrailingBlockItem                 = true;
        o.binPackLiteralItems                  = FormatBinPackStyle::Preserve;
        o.forceSingleLineLiteralLists          = false;
        o.sourceSelectsLiteralLayout           = true;
        o.literalListLayout                    = FormatListLayout::HangingAlign;
        o.forceSingleLineLogicalExpressions    = false;
        o.sourceSelectsLogicalExpressionLayout = true;
        o.logicalExpressionLayout              = FormatLogicalLayout::HangingAlign;
        o.logicalOperatorBreakPosition         = FormatOperatorWrapStyle::After;
        o.logicalOperandPacking                = FormatLogicalPacking::OnePerLine;

        // Braces and short bodies
        o.braceStyle                         = FormatBraceStyle::Allman;
        o.compactEmptyBraces                 = true;
        o.allowShortFunctionsOnSingleLine    = FormatShortBlockStyle::Source;
        o.allowShortBlocksOnSingleLine       = FormatShortBlockStyle::Source;
        o.allowShortEnumsOnSingleLine        = FormatShortBlockStyle::Source;
        o.allowShortStructsOnSingleLine      = FormatShortBlockStyle::Source;
        o.allowShortClosuresOnSingleLine     = FormatShortBlockStyle::Source;
        o.allowShortIfStatementsOnSingleLine = false;
        o.allowShortLoopsOnSingleLine        = false;

        // Switch
        o.caseBodyStyle         = FormatCaseBodyStyle::Uniform;
        o.blankLineBetweenCases = FormatCaseBlankStyle::MultiLine;
        o.alignCaseBodies       = FormatAlignMode::Consecutive;

        // Statements
        o.removeRedundantSemicolons  = true;
        o.removeTrailingCommas       = true;
        o.removeConditionParentheses = true;
        o.oneStatementPerLine        = true;
        o.oneEnumValuePerLine        = true;
        o.oneStructFieldPerLine      = true;
        o.inlineAccessModifiers      = true;

        // Alignment
        o.alignConsecutiveAssignments  = FormatAlignMode::Consecutive;
        o.alignConsecutiveDeclarations = FormatAlignMode::Consecutive;
        o.alignConsecutiveConstants    = FormatAlignMode::Consecutive;
        o.alignConsecutiveAliases      = FormatAlignMode::AcrossBlanks;
        o.alignStructFields            = FormatAlignMode::Consecutive;
        o.alignEnumValues              = FormatAlignMode::Consecutive;
        o.alignDeclarationInitializers = true;
        o.alignStructFieldInitializers = true;
        o.alignConstantTypes           = true;
        o.alignAttributes              = FormatAlignMode::Consecutive;
        o.alignFatArrows               = FormatAlignMode::Consecutive;
        o.alignTrailingComments        = true;
        o.trailingCommentMinSpaces     = 5;
        o.trailingCommentMaxColumn     = 0;
        o.alignOutlierGap              = 16;
        o.alignOperands                = true;
        o.alignAfterOpenBracket        = true;
        o.alignArrayColumns            = true;

        // Spacing
        o.normalizeHorizontalWhitespace    = true;
        o.spaceBeforeColonInDeclarations   = false;
        o.spaceAfterColonInDeclarations    = true;
        o.spaceBeforeColonInNamedArguments = false;
        o.spaceAfterColonInNamedArguments  = true;
        o.spaceBeforeColonInBaseClause     = false;
        o.spaceAroundAssignmentOperator    = true;
        o.spaceAroundBinaryOperators       = true;
        o.spaceAroundArrow                 = false;
        o.spaceAroundFatArrow              = true;
        o.spaceAroundRangeOperator         = false;
        o.spaceAfterComma                  = true;
        o.spaceBeforeComma                 = false;
        o.spaceAfterCast                   = true;
        o.spaceAfterKeyword                = true;
        o.spaceAfterUnaryOperator          = false;
        o.spaceInsideParentheses           = false;
        o.spaceInsideBrackets              = false;
        o.spaceInsideBraces                = false;
        o.spaceInEmptyParentheses          = false;
        o.spaceInEmptyBraces               = false;
        o.spaceBeforeAttributeBracket      = true;
        o.spaceBeforeParentheses           = FormatSpaceBeforeParens::ControlStatements;

        // Attributes
        o.attributePlacement       = FormatAttributePlacement::OwnLine;
        o.breakAfterAttribute      = true;
        o.spaceAfterAttributeComma = true;
        o.sortAttributeArguments   = false;

        // Comments
        o.commentReflow               = FormatCommentReflow::Normalize;
        o.normalizeSectionSeparators  = false;
        o.sectionSeparatorWidth       = 78;
        o.spaceAfterLineCommentPrefix = true;

        // Imports
        o.sortUsingStatements       = FormatSortOrder::Ascending;
        o.mergeUsingStatements      = false;
        o.blankLineAfterUsingBlock  = FormatBlankLineStyle::Always;
        o.blankLineAfterGlobalBlock = FormatBlankLineStyle::Always;

        // Numeric literals
        o.hexLiteralCase                 = FormatLiteralCase::Upper;
        o.hexLiteralPrefixCase           = FormatLiteralCase::Lower;
        o.floatExponentCase              = FormatLiteralCase::Lower;
        o.normalizeDigitSeparators       = false;
        o.hexDigitSeparatorGroupSize     = 4;
        o.decimalDigitSeparatorGroupSize = 3;
    }
}

void applyFormatStyle(FormatOptions& options, const FormatNamedStyle style)
{
    options = FormatOptions{};
    if (style == FormatNamedStyle::Swag)
        applySwagStyle(options);
}

SWC_END_NAMESPACE();
