#include "pch.h"
#include "Format/FormatOptionsLoader.h"
#include "Main/FileSystem.h"
#include "Main/StructConfig.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr std::string_view FORMAT_CONFIG_FILE = ".swc-format";

    void bindFileLevelSchema(StructConfigSchema& schema, FormatOptions& options)
    {
        schema.add("preserve-bom", &options.preserveBom, "Preserve UTF-8 BOM markers.");
        schema.add("preserve-trailing-whitespace", &options.preserveTrailingWhitespace, "Preserve trailing whitespace already present in source.");
        schema.add("insert-final-newline", &options.insertFinalNewline, "Ensure formatted files end with a newline.");
        schema.add("trim-trailing-newlines", &options.trimTrailingNewlines, "Collapse multiple trailing newlines to a single newline.");
        schema.add("max-consecutive-empty-lines", &options.maxConsecutiveEmptyLines, "Maximum blank lines allowed in a row (0 disables the limit).");
        schema.add("keep-empty-lines-at-start-of-block", &options.keepEmptyLinesAtStartOfBlock, "Keep blank lines at the start of a `{ ... }` block.");
        schema.add("keep-empty-lines-at-end-of-block", &options.keepEmptyLinesAtEndOfBlock, "Keep blank lines at the end of a `{ ... }` block.");
    }

    void bindEndOfLineSchema(StructConfigSchema& schema, FormatOptions& options)
    {
        schema.addEnum("end-of-line-style", &options.endOfLineStyle,
                       {
                           {"preserve", FormatEndOfLineStyle::Preserve},
                           {"lf", FormatEndOfLineStyle::LF},
                           {"crlf", FormatEndOfLineStyle::CRLF},
                       },
                       "End-of-line style used by the formatter.");
    }

    void bindIndentationSchema(StructConfigSchema& schema, FormatOptions& options)
    {
        schema.addEnum("indent-style", &options.indentStyle,
                       {
                           {"preserve", FormatIndentStyle::Preserve},
                           {"spaces", FormatIndentStyle::Spaces},
                           {"tabs", FormatIndentStyle::Tabs},
                       },
                       "Indent style used by the formatter.");

        schema.add("indent-width", &options.indentWidth, "Indent width used when formatting with spaces.");
        schema.add("tab-width", &options.tabWidth, "Visual width used when interpreting tab characters.");
        schema.add("continuation-indent-width", &options.continuationIndentWidth, "Extra indent applied to wrapped continuations.");
        schema.add("indent-namespace-body", &options.indentNamespaceBody, "Indent content nested inside a `namespace` block.");
        schema.add("indent-impl-body", &options.indentImplBody, "Indent content nested inside an `impl` block.");
        schema.add("indent-struct-body", &options.indentStructBody, "Indent content nested inside a `struct` block.");
        schema.add("indent-enum-body", &options.indentEnumBody, "Indent content nested inside an `enum` block.");
        schema.add("indent-case-labels", &options.indentCaseLabels, "Indent `case` labels one level inside the enclosing `switch`.");
        schema.add("indent-case-blocks", &options.indentCaseBlocks, "Indent the body of a `case` relative to its label.");
        schema.add("indent-attributes", &options.indentAttributes, "Attributes adopt the indentation of the declaration they apply to.");
        schema.add("indent-inside-parens", &options.indentInsideParens, "Indent wrapped arguments relative to the opening parenthesis.");
    }

    void bindWrappingSchema(StructConfigSchema& schema, FormatOptions& options)
    {
        schema.add("column-limit", &options.columnLimit, "Soft column limit used when wrapping (0 disables wrapping).");

        schema.addEnum("break-before-binary-operators", &options.breakBeforeBinaryOperators,
                       {
                           {"preserve", FormatOperatorWrapStyle::Preserve},
                           {"before", FormatOperatorWrapStyle::Before},
                           {"after", FormatOperatorWrapStyle::After},
                           {"none", FormatOperatorWrapStyle::None},
                       },
                       "Where to break long expressions relative to their binary operator.");

        schema.add("break-before-ternary-operators", &options.breakBeforeTernaryOperators, "Break long `cond ? a : b` expressions before `?` and `:`.");
        schema.add("break-after-return-type", &options.breakAfterReturnType, "Insert a line break before `->` in function signatures that don't fit.");
        schema.add("break-before-do", &options.breakBeforeDo, "Place trailing `do` on a new line when its statement is wrapped.");
        schema.add("break-before-else", &options.breakBeforeElse, "Place `else` on its own line (Stroustrup style).");

        const std::initializer_list<std::pair<const char*, FormatBinPackStyle>> binPackChoices = {
            {"preserve", FormatBinPackStyle::Preserve},
            {"pack", FormatBinPackStyle::Pack},
            {"one-per-line", FormatBinPackStyle::OnePerLine},
        };
        schema.addEnum("bin-pack-arguments", &options.binPackArguments, binPackChoices, "How to lay out arguments across lines in calls.");
        schema.addEnum("bin-pack-parameters", &options.binPackParameters, binPackChoices, "How to lay out parameters across lines in declarations.");
    }

    void bindBraceSchema(StructConfigSchema& schema, FormatOptions& options)
    {
        schema.addEnum("brace-style", &options.braceStyle,
                       {
                           {"preserve", FormatBraceStyle::Preserve},
                           {"attach", FormatBraceStyle::Attach},
                           {"allman", FormatBraceStyle::Allman},
                           {"stroustrup", FormatBraceStyle::Stroustrup},
                       },
                       "Opening brace placement policy.");

        schema.add("compact-empty-braces", &options.compactEmptyBraces, "Keep `{}` on the opening line.");

        const std::initializer_list<std::pair<const char*, FormatShortBlockStyle>> shortChoices = {
            {"never", FormatShortBlockStyle::Never},
            {"empty", FormatShortBlockStyle::Empty},
            {"inline", FormatShortBlockStyle::Inline},
            {"always", FormatShortBlockStyle::Always},
        };
        schema.addEnum("allow-short-functions-on-single-line", &options.allowShortFunctionsOnSingleLine, shortChoices, "When to keep function bodies on a single line.");
        schema.addEnum("allow-short-blocks-on-single-line", &options.allowShortBlocksOnSingleLine, shortChoices, "When to keep generic `{ ... }` blocks on a single line.");
        schema.addEnum("allow-short-enums-on-single-line", &options.allowShortEnumsOnSingleLine, shortChoices, "When to keep `enum` bodies on a single line.");
        schema.addEnum("allow-short-structs-on-single-line", &options.allowShortStructsOnSingleLine, shortChoices, "When to keep `struct` bodies on a single line.");

        schema.add("allow-short-if-statements-on-single-line", &options.allowShortIfStatementsOnSingleLine, "Allow `if x do ...` / `if x { ... }` on one line.");
        schema.add("allow-short-loops-on-single-line", &options.allowShortLoopsOnSingleLine, "Allow `while`/`for`/`foreach` bodies on one line.");
        schema.add("allow-short-case-on-single-line", &options.allowShortCaseOnSingleLine, "Allow single-statement `case` arms to stay on one line.");
    }

    void bindAlignmentSchema(StructConfigSchema& schema, FormatOptions& options)
    {
        const std::initializer_list<std::pair<const char*, FormatAlignMode>> alignChoices = {
            {"none", FormatAlignMode::None},
            {"consecutive", FormatAlignMode::Consecutive},
            {"across-blanks", FormatAlignMode::AcrossBlanks},
            {"all", FormatAlignMode::All},
        };
        schema.addEnum("align-consecutive-assignments", &options.alignConsecutiveAssignments, alignChoices, "Align `=` signs in adjacent assignments.");
        schema.addEnum("align-consecutive-declarations", &options.alignConsecutiveDeclarations, alignChoices, "Align the names/types of adjacent `let`/`var` declarations.");
        schema.addEnum("align-consecutive-constants", &options.alignConsecutiveConstants, alignChoices, "Align values of adjacent `const` declarations.");
        schema.addEnum("align-struct-fields", &options.alignStructFields, alignChoices, "Align `:` and types of adjacent struct fields.");
        schema.addEnum("align-enum-values", &options.alignEnumValues, alignChoices, "Align `=` on adjacent enum value definitions.");
        schema.addEnum("align-attributes", &options.alignAttributes, alignChoices, "Align adjacent attribute annotations.");

        schema.add("align-trailing-comments", &options.alignTrailingComments, "Align `//` trailing comments into a shared column.");
        schema.add("trailing-comment-min-spaces", &options.trailingCommentMinSpaces, "Minimum number of spaces between code and a trailing `//` comment.");
        schema.add("trailing-comment-max-column", &options.trailingCommentMaxColumn, "Max column for trailing comments (0 disables the cap).");
        schema.add("align-operands", &options.alignOperands, "Align operands of wrapped binary expressions.");
        schema.add("align-after-open-bracket", &options.alignAfterOpenBracket, "Align wrapped arguments with the opening `(` / `[`.");
    }

    void bindSpacingSchema(StructConfigSchema& schema, FormatOptions& options)
    {
        schema.add("space-before-colon-in-declarations", &options.spaceBeforeColonInDeclarations, "Insert a space before `:` in declarations like `a : u8`.");
        schema.add("space-after-colon-in-declarations", &options.spaceAfterColonInDeclarations, "Insert a space after `:` in declarations like `a: u8`.");
        schema.add("space-before-colon-in-base-clause", &options.spaceBeforeColonInBaseClause, "Insert a space before `:` in `enum E: u32` / `using base: Foo`.");
        schema.add("space-around-assignment-operator", &options.spaceAroundAssignmentOperator, "Insert spaces around `=` in assignments.");
        schema.add("space-around-binary-operators", &options.spaceAroundBinaryOperators, "Insert spaces around binary operators (`+`, `*`, `&`, ...).");
        schema.add("space-around-arrow", &options.spaceAroundArrow, "Insert spaces around `->` in function signatures.");
        schema.add("space-around-range-operator", &options.spaceAroundRangeOperator, "Insert spaces around `..` / `..<` range operators.");
        schema.add("space-after-comma", &options.spaceAfterComma, "Insert a space after `,`.");
        schema.add("space-before-comma", &options.spaceBeforeComma, "Insert a space before `,`.");
        schema.add("space-after-cast", &options.spaceAfterCast, "Insert a space after a `cast(...)` expression.");
        schema.add("space-after-keyword", &options.spaceAfterKeyword, "Insert a space after control keywords such as `if`, `while`, `for`.");
        schema.add("space-after-unary-operator", &options.spaceAfterUnaryOperator, "Insert a space after unary operators like `-` or `!`.");
        schema.add("space-inside-parentheses", &options.spaceInsideParentheses, "Insert spaces just inside `(` and `)`.");
        schema.add("space-inside-brackets", &options.spaceInsideBrackets, "Insert spaces just inside `[` and `]`.");
        schema.add("space-inside-braces", &options.spaceInsideBraces, "Insert spaces just inside `{` and `}` in initializer lists.");
        schema.add("space-in-empty-parentheses", &options.spaceInEmptyParentheses, "Insert a space inside `()` when empty.");
        schema.add("space-in-empty-braces", &options.spaceInEmptyBraces, "Insert a space inside `{}` when empty.");
        schema.add("space-before-attribute-bracket", &options.spaceBeforeAttributeBracket, "Insert a space before `#[` when an attribute is placed inline.");

        schema.addEnum("space-before-parentheses", &options.spaceBeforeParentheses,
                       {
                           {"never", FormatSpaceBeforeParens::Never},
                           {"always", FormatSpaceBeforeParens::Always},
                           {"control-statements", FormatSpaceBeforeParens::ControlStatements},
                           {"functions", FormatSpaceBeforeParens::Functions},
                           {"non-empty", FormatSpaceBeforeParens::NonEmpty},
                       },
                       "When to insert a space between an identifier and `(`.");
    }

    void bindAttributeSchema(StructConfigSchema& schema, FormatOptions& options)
    {
        schema.addEnum("attribute-placement", &options.attributePlacement,
                       {
                           {"preserve", FormatAttributePlacement::Preserve},
                           {"own-line", FormatAttributePlacement::OwnLine},
                           {"grouped", FormatAttributePlacement::Grouped},
                           {"inline", FormatAttributePlacement::Inline},
                       },
                       "How to place `#[Attr]` annotations relative to their declaration.");

        schema.add("break-after-attribute", &options.breakAfterAttribute, "Force a line break between an attribute and the declaration it applies to.");
        schema.add("space-after-attribute-comma", &options.spaceAfterAttributeComma, "Insert a space after `,` inside `#[A, B, C]`.");
        schema.add("sort-attribute-arguments", &options.sortAttributeArguments, "Sort attribute argument lists alphabetically.");
    }

    void bindCommentSchema(StructConfigSchema& schema, FormatOptions& options)
    {
        schema.addEnum("comment-reflow", &options.commentReflow,
                       {
                           {"preserve", FormatCommentReflow::Preserve},
                           {"normalize", FormatCommentReflow::Normalize},
                           {"reflow", FormatCommentReflow::Reflow},
                       },
                       "How aggressively to rewrite comments to fit the column limit.");

        schema.add("normalize-section-separators", &options.normalizeSectionSeparators, "Rewrite `// ####...` banners so they share a common width.");
        schema.add("section-separator-width", &options.sectionSeparatorWidth, "Target column count for normalized `// ####...` banners.");
        schema.add("space-after-line-comment-prefix", &options.spaceAfterLineCommentPrefix, "Insert a space after `//` when rewriting line comments.");
    }

    void bindUsingSchema(StructConfigSchema& schema, FormatOptions& options)
    {
        schema.addEnum("sort-using-statements", &options.sortUsingStatements,
                       {
                           {"preserve", FormatSortOrder::Preserve},
                           {"ascending", FormatSortOrder::Ascending},
                           {"ascending-ci", FormatSortOrder::CaseInsensitiveAscending},
                       },
                       "Sort order for `using` statements at the top of a file.");

        schema.add("merge-using-statements", &options.mergeUsingStatements, "Collapse adjacent `using` statements onto a single line when possible.");
        schema.add("blank-line-after-using-block", &options.blankLineAfterUsingBlock, "Guarantee a blank line after the initial `using` block.");
    }

    void bindLiteralSchema(StructConfigSchema& schema, FormatOptions& options)
    {
        const std::initializer_list<std::pair<const char*, FormatLiteralCase>> caseChoices = {
            {"preserve", FormatLiteralCase::Preserve},
            {"upper", FormatLiteralCase::Upper},
            {"lower", FormatLiteralCase::Lower},
        };
        schema.addEnum("hex-literal-case", &options.hexLiteralCase, caseChoices, "Case of hexadecimal digits (`0xABCD` vs `0xabcd`).");
        schema.addEnum("hex-literal-prefix-case", &options.hexLiteralPrefixCase, caseChoices, "Case of the `0x` / `0X` hexadecimal prefix (also applies to `0b` / `0B`).");
        schema.addEnum("float-exponent-case", &options.floatExponentCase, caseChoices, "Case of the floating-point exponent letter (`1e10` vs `1E10`).");

        schema.add("normalize-digit-separators", &options.normalizeDigitSeparators, "Rewrite long numeric literals using `_` digit separators.");
        schema.add("hex-digit-separator-group-size", &options.hexDigitSeparatorGroupSize, "Digit grouping size used for `0x` and `0b` literals when normalizing separators.");
        schema.add("decimal-digit-separator-group-size", &options.decimalDigitSeparatorGroupSize, "Digit grouping size used for decimal and float literals when normalizing separators.");
    }

    void bindPragmaSchema(StructConfigSchema& schema, FormatOptions& options)
    {
        schema.add("format-off-comment", &options.formatOffComment, "Comment marker that disables formatting until the matching `format-on-comment`.");
        schema.add("format-on-comment", &options.formatOnComment, "Comment marker that re-enables formatting after `format-off-comment`.");
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
