#include "pch.h"
#include "Format/FormatOptionsLoader.h"
#include "Main/FileSystem.h"
#include "Main/StructConfig.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr std::string_view FORMAT_CONFIG_FILE = ".swc-format";

    void addBlankLineStyle(StructConfigSchema& schema, const std::string_view name, FormatBlankLineStyle* target, const std::string_view description)
    {
        schema.addEnum(name, target, {{"preserve", FormatBlankLineStyle::Preserve}, {"never", FormatBlankLineStyle::Never}, {"always", FormatBlankLineStyle::Always}}, description);
    }

    void bindFileLevelSchema(StructConfigSchema& schema, FormatOptions& options)
    {
        schema.add("preserve-bom", &options.preserveBom, "Preserve UTF-8 BOM markers");
        schema.add("preserve-trailing-whitespace", &options.preserveTrailingWhitespace, "Preserve trailing whitespace already present in source");
        schema.add("insert-final-newline", &options.insertFinalNewline, "End formatted files with a newline");
        schema.add("trim-trailing-newlines", &options.trimTrailingNewlines, "Collapse multiple trailing newlines into one");
        schema.add("trim-leading-blank-lines", &options.trimLeadingBlankLines, "Remove blank lines at the very start of the file");
        schema.add("max-consecutive-empty-lines", &options.maxConsecutiveEmptyLines, "Set the maximum consecutive blank lines; use 0 to disable the limit");
        addBlankLineStyle(schema, "blank-line-after-opening-brace", &options.blankLineAfterOpeningBrace, "Choose the blank-line policy immediately after a multi-line `{`");
        addBlankLineStyle(schema, "blank-line-before-closing-brace", &options.blankLineBeforeClosingBrace, "Choose the blank-line policy immediately before a multi-line `}`");
        addBlankLineStyle(schema, "blank-line-before-function-definition", &options.blankLineBeforeFunctionDefinition, "Choose the blank-line policy before a multi-line function definition");
        addBlankLineStyle(schema, "blank-line-before-type-definition", &options.blankLineBeforeTypeDefinition, "Choose the blank-line policy before a multi-line type, impl, or namespace definition");
        addBlankLineStyle(schema, "blank-line-before-comment-block", &options.blankLineBeforeCommentBlock, "Choose the blank-line policy before a whole-line comment block that follows code");
        addBlankLineStyle(schema, "blank-line-after-standalone-closing-brace", &options.blankLineAfterStandaloneClosingBrace, "Choose the blank-line policy after a standalone `}` followed by code");
    }

    void bindEndOfLineSchema(StructConfigSchema& schema, FormatOptions& options)
    {
        schema.addEnum("end-of-line-style", &options.endOfLineStyle, {{"preserve", FormatEndOfLineStyle::Preserve}, {"lf", FormatEndOfLineStyle::Lf}, {"crlf", FormatEndOfLineStyle::CrLf}}, "Choose the formatter end-of-line style");
    }

    void bindIndentationSchema(StructConfigSchema& schema, FormatOptions& options)
    {
        schema.addEnum("indent-style", &options.indentStyle, {{"preserve", FormatIndentStyle::Preserve}, {"spaces", FormatIndentStyle::Spaces}, {"tabs", FormatIndentStyle::Tabs}}, "Choose the formatter indentation style");

        schema.add("indent-width", &options.indentWidth, "Set the indentation width when using spaces");
        schema.add("tab-width", &options.tabWidth, "Set the visual width of tab characters");
        schema.add("continuation-indent-width", &options.continuationIndentWidth, "Set the extra indentation for wrapped continuations");
        schema.add("indent-namespace-body", &options.indentNamespaceBody, "Indent content inside a `namespace` block");
        schema.add("indent-impl-body", &options.indentImplBody, "Indent content inside an `impl` block");
        schema.add("indent-struct-body", &options.indentStructBody, "Indent content inside a `struct` block");
        schema.add("indent-enum-body", &options.indentEnumBody, "Indent content inside an `enum` block");
        schema.add("indent-case-labels", &options.indentCaseLabels, "Indent `case` labels one level inside their `switch`");
        schema.add("indent-case-blocks", &options.indentCaseBlocks, "Indent each `case` body relative to its label");
        schema.add("indent-attributes", &options.indentAttributes, "Indent attributes with the declaration they apply to");
        schema.add("indent-inside-parens", &options.indentInsideParens, "Indent wrapped arguments relative to the opening parenthesis");
    }

    void bindWrappingSchema(StructConfigSchema& schema, FormatOptions& options)
    {
        schema.add("column-limit", &options.columnLimit, "Set the soft wrapping column; use 0 to disable wrapping");

        schema.addEnum("break-before-binary-operators", &options.breakBeforeBinaryOperators, {{"preserve", FormatOperatorWrapStyle::Preserve}, {"before", FormatOperatorWrapStyle::Before}, {"after", FormatOperatorWrapStyle::After}, {"none", FormatOperatorWrapStyle::None}}, "Choose where long expressions break relative to binary operators");

        schema.add("break-before-ternary-operators", &options.breakBeforeTernaryOperators, "Break long `cond ? a : b` expressions before `?` and `:`");
        schema.add("break-after-return-type", &options.breakAfterReturnType, "Break before `->` when a function signature does not fit");
        schema.add("break-before-do", &options.breakBeforeDo, "Move trailing `do` to a new line when its statement wraps");
        schema.add("break-before-else", &options.breakBeforeElse, "Place `else` on its own line in Stroustrup style");
        schema.add("break-before-where", &options.breakBeforeWhere, "Place `where` clauses on their own line");

        const std::initializer_list<std::pair<const char*, FormatBinPackStyle>> binPackChoices = {
            {"preserve", FormatBinPackStyle::Preserve},
            {"pack", FormatBinPackStyle::Pack},
            {"one-per-line", FormatBinPackStyle::OnePerLine},
        };
        schema.addEnum("bin-pack-arguments", &options.binPackArguments, binPackChoices, "Choose how call arguments span lines");
        schema.addEnum("bin-pack-parameters", &options.binPackParameters, binPackChoices, "Choose how declaration parameters span lines");

        const std::initializer_list<std::pair<const char*, FormatListLayout>> listLayoutChoices = {
            {"preserve", FormatListLayout::Preserve},
            {"hanging-indent", FormatListLayout::HangingIndent},
            {"hanging-align", FormatListLayout::HangingAlign},
            {"vertical", FormatListLayout::Vertical},
            {"block", FormatListLayout::Block},
        };
        schema.add("force-single-line-argument-lists", &options.forceSingleLineArgumentLists, "Place every editable call argument list on one line, regardless of the column limit");
        schema.add("force-single-line-parameter-lists", &options.forceSingleLineParameterLists, "Place every editable declaration parameter list on one line, regardless of the column limit");
        schema.add("source-selects-argument-layout", &options.sourceSelectsArgumentLayout, "Use the first two call arguments' source lines to choose single-line or multiline layout");
        schema.add("source-selects-parameter-layout", &options.sourceSelectsParameterLayout, "Use the first two declaration parameters' source lines to choose single-line or multiline layout");
        schema.addEnum("argument-list-layout", &options.argumentListLayout, listLayoutChoices, "Choose the layout of multiline call argument lists");
        schema.addEnum("parameter-list-layout", &options.parameterListLayout, listLayoutChoices, "Choose the layout of multiline declaration parameter lists");
        schema.addEnum("bin-pack-literal-items", &options.binPackLiteralItems, binPackChoices, "Choose how array and struct literal items span lines");
        schema.add("force-single-line-literal-lists", &options.forceSingleLineLiteralLists, "Place every editable array and struct literal item list on one line, regardless of the column limit");
        schema.add("source-selects-literal-layout", &options.sourceSelectsLiteralLayout, "Use the literal's source shape to choose single-line or multiline layout");
        schema.addEnum("literal-list-layout", &options.literalListLayout, listLayoutChoices, "Choose the layout of multiline array and struct literal item lists");

        const std::initializer_list<std::pair<const char*, FormatLogicalLayout>> logicalLayoutChoices = {
            {"preserve", FormatLogicalLayout::Preserve},
            {"hanging-indent", FormatLogicalLayout::HangingIndent},
            {"hanging-align", FormatLogicalLayout::HangingAlign},
        };
        const std::initializer_list<std::pair<const char*, FormatLogicalPacking>> logicalPackingChoices = {
            {"preserve", FormatLogicalPacking::Preserve},
            {"pack", FormatLogicalPacking::Pack},
            {"by-precedence", FormatLogicalPacking::ByPrecedence},
            {"one-per-line", FormatLogicalPacking::OnePerLine},
        };
        const std::initializer_list<std::pair<const char*, FormatOperatorWrapStyle>> logicalBreakChoices = {
            {"preserve", FormatOperatorWrapStyle::Preserve},
            {"before", FormatOperatorWrapStyle::Before},
            {"after", FormatOperatorWrapStyle::After},
        };
        schema.add("force-single-line-logical-expressions", &options.forceSingleLineLogicalExpressions, "Place every editable logical expression on one line, regardless of the column limit");
        schema.add("source-selects-logical-expression-layout", &options.sourceSelectsLogicalExpressionLayout, "Use the first two logical operands' source lines to choose single-line or multiline layout");
        schema.addEnum("logical-expression-layout", &options.logicalExpressionLayout, logicalLayoutChoices, "Choose the alignment of multiline logical expressions");
        schema.addEnum("logical-operator-break-position", &options.logicalOperatorBreakPosition, logicalBreakChoices, "Choose where logical expressions break relative to `and` and `or`");
        schema.addEnum("logical-operand-packing", &options.logicalOperandPacking, logicalPackingChoices, "Choose how logical operands span lines");
    }

    void bindBraceSchema(StructConfigSchema& schema, FormatOptions& options)
    {
        schema.addEnum("brace-style", &options.braceStyle, {{"preserve", FormatBraceStyle::Preserve}, {"attach", FormatBraceStyle::Attach}, {"allman", FormatBraceStyle::Allman}, {"stroustrup", FormatBraceStyle::Stroustrup}}, "Choose where opening braces are placed");

        schema.add("compact-empty-braces", &options.compactEmptyBraces, "Keep `{}` on the opening line");

        const std::initializer_list<std::pair<const char*, FormatShortBlockStyle>> shortChoices = {
            {"preserve", FormatShortBlockStyle::Preserve},
            {"source", FormatShortBlockStyle::Source},
            {"never", FormatShortBlockStyle::Never},
            {"empty", FormatShortBlockStyle::Empty},
            {"inline", FormatShortBlockStyle::Inline},
            {"always", FormatShortBlockStyle::Always},
        };
        schema.addEnum("allow-short-functions-on-single-line", &options.allowShortFunctionsOnSingleLine, shortChoices, "Choose when function bodies stay on one line");
        schema.addEnum("allow-short-blocks-on-single-line", &options.allowShortBlocksOnSingleLine, shortChoices, "Choose when generic `{ ... }` blocks stay on one line");
        schema.addEnum("allow-short-enums-on-single-line", &options.allowShortEnumsOnSingleLine, shortChoices, "Choose when `enum` bodies stay on one line");
        schema.addEnum("allow-short-structs-on-single-line", &options.allowShortStructsOnSingleLine, shortChoices, "Choose when `struct` bodies stay on one line");
        schema.addEnum("allow-short-closures-on-single-line", &options.allowShortClosuresOnSingleLine, shortChoices, "Choose when closure bodies embedded in expressions stay on one line");

        schema.add("allow-short-if-statements-on-single-line", &options.allowShortIfStatementsOnSingleLine, "Keep short `if x do ...` and `if x { ... }` statements on one line");
        schema.add("allow-short-loops-on-single-line", &options.allowShortLoopsOnSingleLine, "Keep short `while` and `for` bodies on one line");

        schema.addEnum("case-body-style", &options.caseBodyStyle, {{"preserve", FormatCaseBodyStyle::Preserve}, {"next-line", FormatCaseBodyStyle::NextLine}, {"same-line", FormatCaseBodyStyle::SameLine}, {"uniform", FormatCaseBodyStyle::Uniform}}, "Choose how `case` bodies are laid out");
        schema.addEnum("blank-line-between-cases", &options.blankLineBetweenCases, {{"preserve", FormatCaseBlankStyle::Preserve}, {"never", FormatCaseBlankStyle::Never}, {"always", FormatCaseBlankStyle::Always}, {"multi-line", FormatCaseBlankStyle::MultiLine}}, "Choose the blank lines between `case` arms");

        schema.add("remove-redundant-semicolons", &options.removeRedundantSemicolons, "Drop `;` at end of line");
        schema.add("remove-condition-parentheses", &options.removeConditionParentheses, "Drop the parentheses wrapping a whole control-statement condition");
        schema.add("one-statement-per-line", &options.oneStatementPerLine, "Put independent statements separated by `;` on separate lines");
        schema.add("one-enum-value-per-line", &options.oneEnumValuePerLine, "Put every value of a multi-value enum on its own line and remove separator commas");
        schema.add("one-struct-field-per-line", &options.oneStructFieldPerLine, "Put every field of a multi-field struct on its own line and remove separator commas");
    }

    void bindAlignmentSchema(StructConfigSchema& schema, FormatOptions& options)
    {
        const std::initializer_list<std::pair<const char*, FormatAlignMode>> alignChoices = {
            {"preserve", FormatAlignMode::Preserve},
            {"none", FormatAlignMode::None},
            {"consecutive", FormatAlignMode::Consecutive},
            {"across-blanks", FormatAlignMode::AcrossBlanks},
            {"all", FormatAlignMode::All},
        };
        schema.addEnum("align-consecutive-assignments", &options.alignConsecutiveAssignments, alignChoices, "Align `=` signs in adjacent assignments");
        schema.addEnum("align-consecutive-declarations", &options.alignConsecutiveDeclarations, alignChoices, "Align names and types in adjacent `let` and `var` declarations");
        schema.addEnum("align-consecutive-constants", &options.alignConsecutiveConstants, alignChoices, "Align values in adjacent `const` declarations");
        schema.addEnum("align-consecutive-aliases", &options.alignConsecutiveAliases, alignChoices, "Align `=` signs in adjacent `alias` declarations");
        schema.addEnum("align-struct-fields", &options.alignStructFields, alignChoices, "Align `:` and types in adjacent struct fields");
        schema.addEnum("align-enum-values", &options.alignEnumValues, alignChoices, "Align `=` in adjacent enum value definitions");

        schema.add("align-declaration-initializers", &options.alignDeclarationInitializers, "Also align the `=` initializer column of adjacent `let`/`var` declarations (two-column grid)");
        schema.add("align-struct-field-initializers", &options.alignStructFieldInitializers, "Also align the `=` initializer column of adjacent struct fields (two-column grid)");
        schema.add("align-constant-types", &options.alignConstantTypes, "Also align the type column of adjacent `const` declarations (two-column grid)");

        schema.addEnum("align-attributes", &options.alignAttributes, alignChoices, "Align adjacent attribute annotations");
        schema.addEnum("align-fat-arrows", &options.alignFatArrows, alignChoices, "Align `=>` of adjacent short function bodies");
        schema.addEnum("align-case-bodies", &options.alignCaseBodies, alignChoices, "Align the bodies of consecutive one-line `case` arms");

        schema.add("align-trailing-comments", &options.alignTrailingComments, "Align trailing `//` comments into a shared column");
        schema.add("trailing-comment-min-spaces", &options.trailingCommentMinSpaces, "Set the minimum spaces between code and a trailing `//` comment");
        schema.add("trailing-comment-max-column", &options.trailingCommentMaxColumn, "Set the maximum trailing-comment column; use 0 to disable the cap");
        schema.add("align-operands", &options.alignOperands, "Align operands in wrapped binary expressions");
        schema.add("align-after-open-bracket", &options.alignAfterOpenBracket, "Align wrapped arguments with their opening `(` or `[`");
        schema.add("align-array-columns", &options.alignArrayColumns, "Align the columns of multi-line array-of-struct literals");
    }

    void bindSpacingSchema(StructConfigSchema& schema, FormatOptions& options)
    {
        schema.add("normalize-horizontal-whitespace", &options.normalizeHorizontalWhitespace, "Collapse non-semantic same-line whitespace and enforce configured spacing exactly");
        schema.add("space-before-colon-in-declarations", &options.spaceBeforeColonInDeclarations, "Insert a space before `:` in declarations such as `a : u8`");
        schema.add("space-after-colon-in-declarations", &options.spaceAfterColonInDeclarations, "Insert a space after `:` in declarations such as `a: u8`");
        schema.add("space-before-colon-in-named-arguments", &options.spaceBeforeColonInNamedArguments, "Insert a space before `:` in named arguments and literal fields");
        schema.add("space-after-colon-in-named-arguments", &options.spaceAfterColonInNamedArguments, "Insert a space after `:` in named arguments and literal fields");
        schema.add("space-before-colon-in-base-clause", &options.spaceBeforeColonInBaseClause, "Insert a space before `:` in `enum E: u32` and `using base: Foo`");
        schema.add("space-around-assignment-operator", &options.spaceAroundAssignmentOperator, "Insert spaces around `=` in assignments");
        schema.add("space-around-binary-operators", &options.spaceAroundBinaryOperators, "Insert spaces around binary operators such as `+`, `*`, and `&`");
        schema.add("space-around-arrow", &options.spaceAroundArrow, "Insert spaces around `->` in function signatures");
        schema.add("space-around-fat-arrow", &options.spaceAroundFatArrow, "Insert spaces around `=>` in short function bodies");
        schema.add("space-around-range-operator", &options.spaceAroundRangeOperator, "Insert spaces around `..` and `..<` range operators");
        schema.add("space-after-comma", &options.spaceAfterComma, "Insert a space after `,`");
        schema.add("space-before-comma", &options.spaceBeforeComma, "Insert a space before `,`");
        schema.add("space-after-cast", &options.spaceAfterCast, "Insert a space after a `cast(...)` expression");
        schema.add("space-after-keyword", &options.spaceAfterKeyword, "Insert a space after control keywords such as `if`, `while`, and `for`");
        schema.add("space-after-unary-operator", &options.spaceAfterUnaryOperator, "Insert a space after unary operators such as `-` or `!`");
        schema.add("space-inside-parentheses", &options.spaceInsideParentheses, "Insert spaces just inside `(` and `)`");
        schema.add("space-inside-brackets", &options.spaceInsideBrackets, "Insert spaces just inside `[` and `]`");
        schema.add("space-inside-braces", &options.spaceInsideBraces, "Insert spaces just inside `{` and `}` in initializer lists");
        schema.add("space-in-empty-parentheses", &options.spaceInEmptyParentheses, "Insert a space inside empty `()`");
        schema.add("space-in-empty-braces", &options.spaceInEmptyBraces, "Insert a space inside empty `{}`");
        schema.add("space-before-attribute-bracket", &options.spaceBeforeAttributeBracket, "Insert a space before an inline `#[` attribute");

        schema.addEnum("space-before-parentheses", &options.spaceBeforeParentheses, {{"preserve", FormatSpaceBeforeParens::Preserve}, {"never", FormatSpaceBeforeParens::Never}, {"always", FormatSpaceBeforeParens::Always}, {"control-statements", FormatSpaceBeforeParens::ControlStatements}, {"functions", FormatSpaceBeforeParens::Functions}, {"non-empty", FormatSpaceBeforeParens::NonEmpty}}, "Choose when to insert a space between an identifier and `(`");
    }

    void bindAttributeSchema(StructConfigSchema& schema, FormatOptions& options)
    {
        schema.addEnum("attribute-placement", &options.attributePlacement, {{"preserve", FormatAttributePlacement::Preserve}, {"own-line", FormatAttributePlacement::OwnLine}, {"grouped", FormatAttributePlacement::Grouped}, {"inline", FormatAttributePlacement::Inline}}, "Choose where `#[Attr]` annotations sit relative to their declaration");

        schema.add("break-after-attribute", &options.breakAfterAttribute, "Break between an attribute and the declaration it applies to");
        schema.add("space-after-attribute-comma", &options.spaceAfterAttributeComma, "Insert a space after `,` inside `#[A, B, C]`");
        schema.add("sort-attribute-arguments", &options.sortAttributeArguments, "Sort attribute argument lists alphabetically");
    }

    void bindCommentSchema(StructConfigSchema& schema, FormatOptions& options)
    {
        schema.addEnum("comment-reflow", &options.commentReflow, {{"preserve", FormatCommentReflow::Preserve}, {"normalize", FormatCommentReflow::Normalize}, {"reflow", FormatCommentReflow::Reflow}}, "Choose how aggressively comments are rewritten to fit the column limit");

        schema.add("normalize-section-separators", &options.normalizeSectionSeparators, "Rewrite `// ####...` banners to a shared width");
        schema.add("section-separator-width", &options.sectionSeparatorWidth, "Set the target width of normalized `// ####...` banners");
        schema.add("space-after-line-comment-prefix", &options.spaceAfterLineCommentPrefix, "Insert a space after `//` when rewriting line comments");
    }

    void bindUsingSchema(StructConfigSchema& schema, FormatOptions& options)
    {
        schema.addEnum("sort-using-statements", &options.sortUsingStatements, {{"preserve", FormatSortOrder::Preserve}, {"ascending", FormatSortOrder::Ascending}, {"ascending-ci", FormatSortOrder::CaseInsensitiveAscending}}, "Choose the sort order of leading `using` statements");

        schema.add("merge-using-statements", &options.mergeUsingStatements, "Collapse adjacent `using` statements onto one line when possible");
        addBlankLineStyle(schema, "blank-line-after-using-block", &options.blankLineAfterUsingBlock, "Choose the blank-line policy after the initial `using` block");
        addBlankLineStyle(schema, "blank-line-after-global-block", &options.blankLineAfterGlobalBlock, "Choose the blank-line policy after the leading `#global` directives");
    }

    void bindLiteralSchema(StructConfigSchema& schema, FormatOptions& options)
    {
        const std::initializer_list<std::pair<const char*, FormatLiteralCase>> caseChoices = {
            {"preserve", FormatLiteralCase::Preserve},
            {"upper", FormatLiteralCase::Upper},
            {"lower", FormatLiteralCase::Lower},
        };
        schema.addEnum("hex-literal-case", &options.hexLiteralCase, caseChoices, "Choose the case of hexadecimal digits (`0xABCD` or `0xabcd`)");
        schema.addEnum("hex-literal-prefix-case", &options.hexLiteralPrefixCase, caseChoices, "Choose the case of hexadecimal and binary prefixes (`0x`/`0X` and `0b`/`0B`)");
        schema.addEnum("float-exponent-case", &options.floatExponentCase, caseChoices, "Choose the case of floating-point exponent letters (`1e10` or `1E10`)");

        schema.add("normalize-digit-separators", &options.normalizeDigitSeparators, "Rewrite long numeric literals with `_` digit separators");
        schema.add("hex-digit-separator-group-size", &options.hexDigitSeparatorGroupSize, "Set the digit group size for normalized `0x` and `0b` literals");
        schema.add("decimal-digit-separator-group-size", &options.decimalDigitSeparatorGroupSize, "Set the digit group size for normalized decimal and float literals");
    }

    void bindPragmaSchema(StructConfigSchema& schema, FormatOptions& options)
    {
        schema.add("format-off-comment", &options.formatOffComment, "Set the comment marker that disables formatting until `format-on-comment`");
        schema.add("format-on-comment", &options.formatOnComment, "Set the comment marker that resumes formatting after `format-off-comment`");
    }

    void bindFormatOptionsSchema(StructConfigSchema& schema, FormatOptions& options)
    {
        bindFileLevelSchema(schema, options);
        bindEndOfLineSchema(schema, options);
        bindIndentationSchema(schema, options);
        bindWrappingSchema(schema, options);
        bindBraceSchema(schema, options);
        bindAlignmentSchema(schema, options);
        bindSpacingSchema(schema, options);
        bindAttributeSchema(schema, options);
        bindCommentSchema(schema, options);
        bindUsingSchema(schema, options);
        bindLiteralSchema(schema, options);
        bindPragmaSchema(schema, options);
    }
}

FormatOptionsLoader::FormatOptionsLoader(TaskContext& ctx) :
    ctx_(&ctx)
{
}

Result FormatOptionsLoader::applyConfigFile(FormatOptions& options, const fs::path& configPath) const
{
    StructConfigSchema schema;
    bindFormatOptionsSchema(schema, options);

    const StructConfigReader reader(schema);
    return reader.readFile(*ctx_, configPath);
}

Result FormatOptionsLoader::resolveDirectory(const fs::path& directory, FormatOptions& outOptions)
{
    const fs::path normalizedDirectory = FileSystem::normalizePath(directory);
    const auto     it                  = cache_.find(normalizedDirectory);
    if (it != cache_.end())
    {
        outOptions = it->second;
        return Result::Continue;
    }

    FormatOptions options;

    fs::path parent = normalizedDirectory.parent_path();
    if (!parent.empty())
    {
        parent = FileSystem::normalizePath(parent);
        if (!FileSystem::pathEquals(parent, normalizedDirectory))
            SWC_RESULT(resolveDirectory(parent, options));
    }

    const fs::path  configPath = normalizedDirectory / FORMAT_CONFIG_FILE;
    std::error_code ec;
    const bool      exists = fs::exists(configPath, ec);
    if (!ec && exists)
        SWC_RESULT(applyConfigFile(options, configPath));

    cache_[normalizedDirectory] = options;
    outOptions                  = options;
    return Result::Continue;
}

Result FormatOptionsLoader::resolve(const fs::path& sourcePath, FormatOptions& outOptions)
{
    const fs::path directory = sourcePath.parent_path();
    if (directory.empty())
    {
        outOptions = {};
        return Result::Continue;
    }

    return resolveDirectory(directory, outOptions);
}

SWC_END_NAMESPACE();
