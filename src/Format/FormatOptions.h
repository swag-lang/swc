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
    Lf,
    CrLf,
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
    std::optional<bool> preserveBom;                  // Preserve UTF-8 BOM markers already present in the file
    std::optional<bool> preserveTrailingWhitespace;   // Keep trailing whitespace on existing lines unchanged
    std::optional<bool> insertFinalNewline;            // Ensure the file ends with a single newline
    std::optional<bool> trimTrailingNewlines;          // Collapse multiple trailing newlines to one
    uint32_t            maxConsecutiveEmptyLines = 2;  // Max blank lines in a row (0 = no limit)
    std::optional<bool> keepEmptyLinesAtStartOfBlock;  // Preserve blank lines right after `{`
    std::optional<bool> keepEmptyLinesAtEndOfBlock;    // Preserve blank lines right before `}`

    // -----------------------------------------------------------------------
    // End-of-line
    // -----------------------------------------------------------------------
    FormatEndOfLineStyle endOfLineStyle = FormatEndOfLineStyle::Preserve; // Line-ending style written back to the file

    // -----------------------------------------------------------------------
    // Indentation
    // -----------------------------------------------------------------------
    FormatIndentStyle   indentStyle             = FormatIndentStyle::Preserve; // Use spaces, tabs, or keep the existing style
    uint32_t            indentWidth             = 4;                           // Width of one indent level when using spaces
    uint32_t            tabWidth                = 4;                           // @TODO Visual width assumed for a tab character
    uint32_t            continuationIndentWidth = 4;                           // @TODO Extra indent for wrapped statements
    std::optional<bool> indentNamespaceBody;                                   // @TODO Indent content inside `namespace { ... }`
    std::optional<bool> indentImplBody;                                        // @TODO Indent content inside `impl ... { ... }`
    std::optional<bool> indentStructBody;                                      // @TODO Indent content inside `struct { ... }`
    std::optional<bool> indentEnumBody;                                        // @TODO Indent content inside `enum { ... }`
    std::optional<bool> indentCaseLabels;                                      // @TODO Indent `case X:` one extra level under `switch`
    std::optional<bool> indentCaseBlocks;                                      // @TODO Indent the block inside a case
    std::optional<bool> indentAttributes;                                      // @TODO Attributes follow the declaration's indent
    std::optional<bool> indentInsideParens;                                    // @TODO Indent wrapped args relative to the open paren

    // -----------------------------------------------------------------------
    // Column limit & wrapping
    // -----------------------------------------------------------------------
    uint32_t                columnLimit                 = 0;                                 // @TODO Soft column limit (0 disables wrapping)
    FormatOperatorWrapStyle breakBeforeBinaryOperators  = FormatOperatorWrapStyle::Preserve; // @TODO Where to wrap around binary operators
    std::optional<bool>     breakBeforeTernaryOperators;                                     // @TODO Break before `?` and `:` in `cond ? a : b`
    std::optional<bool>     breakAfterReturnType;                                            // @TODO Newline before `->` in `func foo(...)->T`
    std::optional<bool>     breakBeforeDo;                                                   // @TODO Break before trailing `do` (`if x do ...`)
    std::optional<bool>     breakBeforeElse;                                                 // @TODO Place `else` on its own line
    FormatBinPackStyle      binPackArguments            = FormatBinPackStyle::Preserve;      // @TODO Call argument layout when wrapping
    FormatBinPackStyle      binPackParameters           = FormatBinPackStyle::Preserve;      // @TODO Declaration parameter layout when wrapping

    // -----------------------------------------------------------------------
    // Braces & short bodies
    // -----------------------------------------------------------------------
    FormatBraceStyle      braceStyle                         = FormatBraceStyle::Allman;     // @TODO Opening brace placement policy
    std::optional<bool>   compactEmptyBraces;                                                // @TODO Keep `{}` inline on the opening line
    FormatShortBlockStyle allowShortFunctionsOnSingleLine    = FormatShortBlockStyle::Empty; // @TODO When to keep function bodies on one line
    FormatShortBlockStyle allowShortBlocksOnSingleLine       = FormatShortBlockStyle::Empty; // @TODO When to keep generic `{ ... }` blocks on one line
    FormatShortBlockStyle allowShortEnumsOnSingleLine        = FormatShortBlockStyle::Empty; // @TODO When to keep `enum` bodies on one line
    FormatShortBlockStyle allowShortStructsOnSingleLine      = FormatShortBlockStyle::Empty; // @TODO When to keep `struct` bodies on one line
    std::optional<bool>   allowShortIfStatementsOnSingleLine;                                // @TODO Allow `if cond do stmt` on one line
    std::optional<bool>   allowShortLoopsOnSingleLine;                                       // @TODO Allow short `while`/`for`/`foreach` bodies on one line
    std::optional<bool>   allowShortCaseOnSingleLine;                                        // @TODO Allow single-statement `case` arms on one line

    // -----------------------------------------------------------------------
    // Alignment
    // -----------------------------------------------------------------------
    FormatAlignMode     alignConsecutiveAssignments  = FormatAlignMode::Consecutive; // @TODO Align `=` in adjacent assignments
    FormatAlignMode     alignConsecutiveDeclarations = FormatAlignMode::Consecutive; // @TODO Align names/types of adjacent `let`/`var` declarations
    FormatAlignMode     alignConsecutiveConstants    = FormatAlignMode::Consecutive; // @TODO Align values of adjacent `const` declarations
    FormatAlignMode     alignStructFields            = FormatAlignMode::Consecutive; // @TODO Align `:` and types of adjacent struct fields
    FormatAlignMode     alignEnumValues              = FormatAlignMode::Consecutive; // @TODO Align `=` on enum value definitions
    FormatAlignMode     alignAttributes              = FormatAlignMode::None;        // @TODO Align adjacent `#[...]` attributes
    std::optional<bool> alignTrailingComments;                                       // @TODO Align `//` trailing comments into a shared column
    uint32_t            trailingCommentMinSpaces     = 5;                            // @TODO Minimum spaces before a trailing `//`
    uint32_t            trailingCommentMaxColumn     = 0;                            // @TODO 0 = no limit on trailing comment column
    std::optional<bool> alignOperands;                                               // @TODO Align operands of wrapped binary expressions
    std::optional<bool> alignAfterOpenBracket;                                       // @TODO Align wrapped args with the opening `(` / `[`

    // -----------------------------------------------------------------------
    // Spacing
    // -----------------------------------------------------------------------
    std::optional<bool>     spaceBeforeColonInDeclarations;                             // @TODO `a : u8`
    std::optional<bool>     spaceAfterColonInDeclarations;                              // @TODO `a: u8`
    std::optional<bool>     spaceBeforeColonInBaseClause;                               // @TODO `enum E: u32`
    std::optional<bool>     spaceAroundAssignmentOperator;                              // @TODO `a = 1`
    std::optional<bool>     spaceAroundBinaryOperators;                                 // @TODO `a + b`
    std::optional<bool>     spaceAroundArrow;                                           // @TODO `func()->int` vs `func() -> int`
    std::optional<bool>     spaceAroundRangeOperator;                                   // @TODO `0..10` vs `0 .. 10`
    std::optional<bool>     spaceAfterComma;                                            // @TODO `a, b`
    std::optional<bool>     spaceBeforeComma;                                           // @TODO `a ,b`
    std::optional<bool>     spaceAfterCast;                                             // @TODO `cast(int) x`
    std::optional<bool>     spaceAfterKeyword;                                          // @TODO `if (x)` vs `if(x)`
    std::optional<bool>     spaceAfterUnaryOperator;                                    // @TODO `- x` vs `-x`
    std::optional<bool>     spaceInsideParentheses;                                     // @TODO `( a, b )`
    std::optional<bool>     spaceInsideBrackets;                                        // @TODO `[ 0 ]`
    std::optional<bool>     spaceInsideBraces;                                          // @TODO `{ 1, 2 }`
    std::optional<bool>     spaceInEmptyParentheses;                                    // @TODO `( )`
    std::optional<bool>     spaceInEmptyBraces;                                         // @TODO `{ }`
    std::optional<bool>     spaceBeforeAttributeBracket;                                // @TODO `foo #[attr]`
    FormatSpaceBeforeParens spaceBeforeParentheses = FormatSpaceBeforeParens::Never;    // @TODO When to insert a space between an identifier and `(`

    // -----------------------------------------------------------------------
    // Attributes
    // -----------------------------------------------------------------------
    FormatAttributePlacement attributePlacement       = FormatAttributePlacement::Preserve; // @TODO How to place `#[Attr]` relative to its declaration
    std::optional<bool>      breakAfterAttribute;                                           // @TODO Force a line break between attribute and declaration
    std::optional<bool>      spaceAfterAttributeComma;                                     // @TODO Insert a space after `,` inside `#[A, B, C]`
    std::optional<bool>      sortAttributeArguments;                                        // @TODO Sort attribute argument lists alphabetically

    // -----------------------------------------------------------------------
    // Comments
    // -----------------------------------------------------------------------
    FormatCommentReflow commentReflow               = FormatCommentReflow::Preserve; // @TODO How aggressively to rewrite comments for the column limit
    std::optional<bool> normalizeSectionSeparators;                                  // @TODO Rewrite `// ####...` banners to a common width
    uint32_t            sectionSeparatorWidth       = 57;                            // @TODO Target column count for `// ### ... ###` banners
    std::optional<bool> spaceAfterLineCommentPrefix;                                 // @TODO `// text` vs `//text`

    // -----------------------------------------------------------------------
    // Imports / using
    // -----------------------------------------------------------------------
    FormatSortOrder     sortUsingStatements      = FormatSortOrder::Preserve; // @TODO Sort order for top-of-file `using` statements
    std::optional<bool> mergeUsingStatements;                                  // @TODO Collapse adjacent `using` onto one line
    std::optional<bool> blankLineAfterUsingBlock;                              // @TODO Guarantee a blank line after the initial `using` block

    // -----------------------------------------------------------------------
    // Numeric literals
    // -----------------------------------------------------------------------
    FormatLiteralCase   hexLiteralCase                 = FormatLiteralCase::Preserve; // Case of hex digits (`0xABCD` vs `0xabcd`)
    FormatLiteralCase   hexLiteralPrefixCase           = FormatLiteralCase::Preserve; // `0x` vs `0X` (also applies to `0b` / `0B`)
    FormatLiteralCase   floatExponentCase              = FormatLiteralCase::Preserve; // `1e10` vs `1E10`
    std::optional<bool> normalizeDigitSeparators;                                     // Rewrite literals to use canonical `_` digit separators
    uint32_t            hexDigitSeparatorGroupSize     = 4;                           // Group size for `0x` / `0b` literals when normalizing separators
    uint32_t            decimalDigitSeparatorGroupSize = 3;                           // Group size for decimal and float literals when normalizing separators

    // -----------------------------------------------------------------------
    // Region / disable pragmas
    // -----------------------------------------------------------------------
    Utf8 formatOffComment = "swc-format off"; // Comment marker that disables formatting until the matching on-comment
    Utf8 formatOnComment  = "swc-format on";  // Comment marker that re-enables formatting after a format-off marker
};

SWC_END_NAMESPACE();
