#pragma once

SWC_BEGIN_NAMESPACE();

enum class FormatIndentStyle : uint8_t
{
    Preserve,
    Spaces,
    Tabs,
};

enum class FormatEndOfLineStyle : uint8_t
{
    Preserve,
    LF,
    CRLF,
};

enum class FormatBraceStyle : uint8_t
{
    Preserve,
    Attach,     // Opening brace stays on the previous line
    Allman,     // Opening brace on its own line
    Stroustrup, // Attach, but `else` / `catch` start a new line
};

enum class FormatAlignMode : uint8_t
{
    None,
    Consecutive,  // Align within contiguous groups only
    AcrossBlanks, // Align across single blank lines
    All,          // Align everything inside the enclosing block
};

enum class FormatShortBlockStyle : uint8_t
{
    Never,
    Empty,  // Only `{}` stays on the opening line
    Inline, // `do ...` / single-statement bodies may stay on one line
    Always,
};

enum class FormatAttributePlacement : uint8_t
{
    Preserve,
    OwnLine, // Each `#[Attr]` goes on its own line, above the declaration
    Grouped, // Combine attributes into a single `#[A, B, C]` line
    Inline,  // Keep the attribute on the declaration line when it fits
};

enum class FormatOperatorWrapStyle : uint8_t
{
    Preserve,
    Before, // Break before the operator (operator starts the next line)
    After,  // Break after the operator (operator ends the current line)
    None,
};

enum class FormatPointerAlignment : uint8_t
{
    Preserve,
    Left,   // `*void`
    Middle, // `* void`
    Right,  // `void*` / `void *`
};

enum class FormatSpaceBeforeParens : uint8_t
{
    Never,
    Always,
    ControlStatements, // Only for `if` / `while` / `for` / `foreach` / `switch`
    Functions,         // Only for function declarations / calls
    NonEmpty,          // Only when the parenthesized list is non-empty
};

enum class FormatLiteralCase : uint8_t
{
    Preserve,
    Upper,
    Lower,
};

enum class FormatCommentReflow : uint8_t
{
    Preserve,
    Normalize, // Normalize leading `//` spacing but keep line breaks
    Reflow,    // Rewrap block comments to the column limit
};

enum class FormatSortOrder : uint8_t
{
    Preserve,
    Ascending,
    CaseInsensitiveAscending,
};

enum class FormatBinPackStyle : uint8_t
{
    Preserve,
    Pack,       // Fit as many arguments per line as possible
    OnePerLine, // One argument per line once wrapping kicks in
};

struct FormatOptions
{
    // -----------------------------------------------------------------------
    // File-level whitespace
    // -----------------------------------------------------------------------
    bool     preserveBom                  = true;
    bool     preserveTrailingWhitespace   = true;
    bool     insertFinalNewline           = false;
    bool     trimTrailingNewlines         = true; // Collapse multiple trailing newlines to one
    uint32_t maxConsecutiveEmptyLines     = 2;    // Max blank lines in a row (0 = no limit)
    bool     keepEmptyLinesAtStartOfBlock = false;
    bool     keepEmptyLinesAtEndOfBlock   = false;

    // -----------------------------------------------------------------------
    // Indentation
    // -----------------------------------------------------------------------
    FormatIndentStyle indentStyle             = FormatIndentStyle::Preserve;
    uint32_t          indentWidth             = 4;
    uint32_t          tabWidth                = 4;
    uint32_t          continuationIndentWidth = 4;    // Extra indent for wrapped statements
    bool              indentNamespaceBody     = true; // Indent content inside `namespace { ... }`
    bool              indentImplBody          = true; // Indent content inside `impl ... { ... }`
    bool              indentStructBody        = true;
    bool              indentEnumBody          = true;
    bool              indentCaseLabels        = false; // Indent `case X:` one extra level under `switch`
    bool              indentCaseBlocks        = true;  // Indent the block inside a case
    bool              indentAttributes        = true;  // Attributes follow the declaration's indent
    bool              indentInsideParens      = false; // Indent wrapped args relative to the open paren

    // -----------------------------------------------------------------------
    // End-of-line
    // -----------------------------------------------------------------------
    FormatEndOfLineStyle endOfLineStyle = FormatEndOfLineStyle::Preserve;

    // -----------------------------------------------------------------------
    // Column limit & wrapping
    // -----------------------------------------------------------------------
    uint32_t                columnLimit                 = 0; // 0 disables the limit
    FormatOperatorWrapStyle breakBeforeBinaryOperators  = FormatOperatorWrapStyle::Preserve;
    bool                    breakBeforeTernaryOperators = false;
    bool                    breakAfterReturnType        = false; // `func foo(...)` newline before `->`
    bool                    breakBeforeDo               = false; // Break before trailing `do`
    bool                    breakBeforeElse             = true;
    FormatBinPackStyle      binPackArguments            = FormatBinPackStyle::Preserve;
    FormatBinPackStyle      binPackParameters           = FormatBinPackStyle::Preserve;

    // -----------------------------------------------------------------------
    // Braces & short bodies
    // -----------------------------------------------------------------------
    FormatBraceStyle      braceStyle                         = FormatBraceStyle::Allman;
    bool                  compactEmptyBraces                 = true; // `{}` stays inline
    FormatShortBlockStyle allowShortFunctionsOnSingleLine    = FormatShortBlockStyle::Empty;
    FormatShortBlockStyle allowShortBlocksOnSingleLine       = FormatShortBlockStyle::Empty;
    FormatShortBlockStyle allowShortEnumsOnSingleLine        = FormatShortBlockStyle::Empty;
    FormatShortBlockStyle allowShortStructsOnSingleLine      = FormatShortBlockStyle::Empty;
    bool                  allowShortIfStatementsOnSingleLine = true;
    bool                  allowShortLoopsOnSingleLine        = true;
    bool                  allowShortCaseOnSingleLine         = true;

    // -----------------------------------------------------------------------
    // Alignment
    // -----------------------------------------------------------------------
    FormatAlignMode alignConsecutiveAssignments  = FormatAlignMode::Consecutive;
    FormatAlignMode alignConsecutiveDeclarations = FormatAlignMode::Consecutive;
    FormatAlignMode alignConsecutiveConstants    = FormatAlignMode::Consecutive;
    FormatAlignMode alignStructFields            = FormatAlignMode::Consecutive;
    FormatAlignMode alignEnumValues              = FormatAlignMode::Consecutive;
    FormatAlignMode alignAttributes              = FormatAlignMode::None;
    bool            alignTrailingComments        = true;
    uint32_t        trailingCommentMinSpaces     = 5; // Minimum spaces before a trailing `//`
    uint32_t        trailingCommentMaxColumn     = 0; // 0 = no limit on trailing comment column
    bool            alignOperands                = false;
    bool            alignAfterOpenBracket        = false;

    // -----------------------------------------------------------------------
    // Spacing
    // -----------------------------------------------------------------------
    bool                    spaceBeforeColonInDeclarations = false; // `a : int`
    bool                    spaceAfterColonInDeclarations  = true;  // `a: int`
    bool                    spaceBeforeColonInBaseClause   = false; // `enum E: u32`
    bool                    spaceAroundAssignmentOperator  = true;  // `a = 1`
    bool                    spaceAroundBinaryOperators     = true;
    bool                    spaceAroundArrow               = false; // `func()->int`
    bool                    spaceAroundRangeOperator       = false; // `0..10`
    bool                    spaceAfterComma                = true;
    bool                    spaceBeforeComma               = false;
    bool                    spaceAfterCast                 = true;  // `cast(int) x`
    bool                    spaceAfterKeyword              = true;  // `if (x)` vs `if(x)`
    bool                    spaceAfterUnaryOperator        = false; // `- x` vs `-x`
    bool                    spaceInsideParentheses         = false; // `( a, b )`
    bool                    spaceInsideBrackets            = false; // `[ 0 ]`
    bool                    spaceInsideBraces              = false; // `{ 1, 2 }`
    bool                    spaceInEmptyParentheses        = false; // `( )`
    bool                    spaceInEmptyBraces             = false; // `{ }`
    bool                    spaceBeforeAttributeBracket    = false; // `foo #[attr]`
    FormatSpaceBeforeParens spaceBeforeParentheses         = FormatSpaceBeforeParens::Never;
    FormatPointerAlignment  pointerAlignment               = FormatPointerAlignment::Left;
    FormatPointerAlignment  referenceAlignment             = FormatPointerAlignment::Left;

    // -----------------------------------------------------------------------
    // Attributes
    // -----------------------------------------------------------------------
    FormatAttributePlacement attributePlacement       = FormatAttributePlacement::Preserve;
    bool                     breakAfterAttribute      = true;
    bool                     spaceAfterAttributeComma = true;
    bool                     sortAttributeArguments   = false;

    // -----------------------------------------------------------------------
    // Comments
    // -----------------------------------------------------------------------
    FormatCommentReflow commentReflow               = FormatCommentReflow::Preserve;
    bool                normalizeSectionSeparators  = true; // Consistent `// ###...` length
    uint32_t            sectionSeparatorWidth       = 57;   // Target width for `// ### ... ###`
    bool                preserveDocComments         = true; // Never rewrap `///` / `//!` lines
    bool                spaceAfterLineCommentPrefix = true; // `// text` vs `//text`

    // -----------------------------------------------------------------------
    // Imports / using
    // -----------------------------------------------------------------------
    FormatSortOrder sortUsingStatements      = FormatSortOrder::Preserve;
    bool            mergeUsingStatements     = false; // Collapse adjacent `using` onto one line
    bool            blankLineAfterUsingBlock = true;

    // -----------------------------------------------------------------------
    // Numeric & string literals
    // -----------------------------------------------------------------------
    FormatLiteralCase hexLiteralCase           = FormatLiteralCase::Preserve;
    FormatLiteralCase hexLiteralPrefixCase     = FormatLiteralCase::Lower;    // `0x` vs `0X`
    FormatLiteralCase integerSuffixCase        = FormatLiteralCase::Preserve; // `1'u32` suffix
    FormatLiteralCase floatExponentCase        = FormatLiteralCase::Preserve; // `1e10` / `1E10`
    bool              normalizeDigitSeparators = false;                       // Add `_` every N digits
    uint32_t          digitSeparatorGroupSize  = 4;                           // Group size for hex ints
    bool              preferSingleQuoteStrings = false;

    // -----------------------------------------------------------------------
    // Region / disable pragmas
    // -----------------------------------------------------------------------
    Utf8 formatOffComment = "swc-format off";
    Utf8 formatOnComment  = "swc-format on";
};

SWC_END_NAMESPACE();
