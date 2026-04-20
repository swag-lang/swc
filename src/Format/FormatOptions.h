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
    bool     preserveBom                  = true;  // Preserve UTF-8 BOM markers already present in the file
    bool     preserveTrailingWhitespace   = true;  // Keep trailing whitespace on existing lines unchanged
    bool     insertFinalNewline           = false; // Ensure the file ends with a single newline
    bool     trimTrailingNewlines         = true;  // Collapse multiple trailing newlines to one
    uint32_t maxConsecutiveEmptyLines     = 2;     // Max blank lines in a row (0 = no limit)
    bool     keepEmptyLinesAtStartOfBlock = false; // Preserve blank lines right after `{`
    bool     keepEmptyLinesAtEndOfBlock   = false; // Preserve blank lines right before `}`

    // -----------------------------------------------------------------------
    // End-of-line
    // -----------------------------------------------------------------------
    FormatEndOfLineStyle endOfLineStyle = FormatEndOfLineStyle::Preserve; // Line-ending style written back to the file

    // -----------------------------------------------------------------------
    // Indentation
    // -----------------------------------------------------------------------
    FormatIndentStyle indentStyle             = FormatIndentStyle::Preserve; // Use spaces, tabs, or keep the existing style
    uint32_t          indentWidth             = 4;                           // Width of one indent level when using spaces
    uint32_t          tabWidth                = 4;                           // Visual width assumed for a tab character
    uint32_t          continuationIndentWidth = 4;                           // Extra indent for wrapped statements
    bool              indentNamespaceBody     = true;                        // Indent content inside `namespace { ... }`
    bool              indentImplBody          = true;                        // Indent content inside `impl ... { ... }`
    bool              indentStructBody        = true;                        // Indent content inside `struct { ... }`
    bool              indentEnumBody          = true;                        // Indent content inside `enum { ... }`
    bool              indentCaseLabels        = false;                       // Indent `case X:` one extra level under `switch`
    bool              indentCaseBlocks        = true;                        // Indent the block inside a case
    bool              indentAttributes        = true;                        // Attributes follow the declaration's indent
    bool              indentInsideParens      = false;                       // Indent wrapped args relative to the open paren

    // -----------------------------------------------------------------------
    // Column limit & wrapping
    // -----------------------------------------------------------------------
    uint32_t                columnLimit                 = 0;                                 // Soft column limit (0 disables wrapping)
    FormatOperatorWrapStyle breakBeforeBinaryOperators  = FormatOperatorWrapStyle::Preserve; // Where to wrap around binary operators
    bool                    breakBeforeTernaryOperators = false;                             // Break before `?` and `:` in `cond ? a : b`
    bool                    breakAfterReturnType        = false;                             // Newline before `->` in `func foo(...)->T`
    bool                    breakBeforeDo               = false;                             // Break before trailing `do` (`if x do ...`)
    bool                    breakBeforeElse             = true;                              // Place `else` on its own line
    FormatBinPackStyle      binPackArguments            = FormatBinPackStyle::Preserve;      // Call argument layout when wrapping
    FormatBinPackStyle      binPackParameters           = FormatBinPackStyle::Preserve;      // Declaration parameter layout when wrapping

    // -----------------------------------------------------------------------
    // Braces & short bodies
    // -----------------------------------------------------------------------
    FormatBraceStyle      braceStyle                         = FormatBraceStyle::Allman;     // Opening brace placement policy
    bool                  compactEmptyBraces                 = true;                         // Keep `{}` inline on the opening line
    FormatShortBlockStyle allowShortFunctionsOnSingleLine    = FormatShortBlockStyle::Empty; // When to keep function bodies on one line
    FormatShortBlockStyle allowShortBlocksOnSingleLine       = FormatShortBlockStyle::Empty; // When to keep generic `{ ... }` blocks on one line
    FormatShortBlockStyle allowShortEnumsOnSingleLine        = FormatShortBlockStyle::Empty; // When to keep `enum` bodies on one line
    FormatShortBlockStyle allowShortStructsOnSingleLine      = FormatShortBlockStyle::Empty; // When to keep `struct` bodies on one line
    bool                  allowShortIfStatementsOnSingleLine = true;                         // Allow `if cond do stmt` on one line
    bool                  allowShortLoopsOnSingleLine        = true;                         // Allow short `while`/`for`/`foreach` bodies on one line
    bool                  allowShortCaseOnSingleLine         = true;                         // Allow single-statement `case` arms on one line

    // -----------------------------------------------------------------------
    // Alignment
    // -----------------------------------------------------------------------
    FormatAlignMode alignConsecutiveAssignments  = FormatAlignMode::Consecutive; // Align `=` in adjacent assignments
    FormatAlignMode alignConsecutiveDeclarations = FormatAlignMode::Consecutive; // Align names/types of adjacent `let`/`var` declarations
    FormatAlignMode alignConsecutiveConstants    = FormatAlignMode::Consecutive; // Align values of adjacent `const` declarations
    FormatAlignMode alignStructFields            = FormatAlignMode::Consecutive; // Align `:` and types of adjacent struct fields
    FormatAlignMode alignEnumValues              = FormatAlignMode::Consecutive; // Align `=` on enum value definitions
    FormatAlignMode alignAttributes              = FormatAlignMode::None;        // Align adjacent `#[...]` attributes
    bool            alignTrailingComments        = true;                         // Align `//` trailing comments into a shared column
    uint32_t        trailingCommentMinSpaces     = 5;                            // Minimum spaces before a trailing `//`
    uint32_t        trailingCommentMaxColumn     = 0;                            // 0 = no limit on trailing comment column
    bool            alignOperands                = false;                        // Align operands of wrapped binary expressions
    bool            alignAfterOpenBracket        = false;                        // Align wrapped args with the opening `(` / `[`

    // -----------------------------------------------------------------------
    // Spacing
    // -----------------------------------------------------------------------
    bool                    spaceBeforeColonInDeclarations = false;                           // `a : u8`
    bool                    spaceAfterColonInDeclarations  = true;                            // `a: u8`
    bool                    spaceBeforeColonInBaseClause   = false;                           // `enum E: u32`
    bool                    spaceAroundAssignmentOperator  = true;                            // `a = 1`
    bool                    spaceAroundBinaryOperators     = true;                            // `a + b`
    bool                    spaceAroundArrow               = false;                           // `func()->int` vs `func() -> int`
    bool                    spaceAroundRangeOperator       = false;                           // `0..10` vs `0 .. 10`
    bool                    spaceAfterComma                = true;                            // `a, b`
    bool                    spaceBeforeComma               = false;                           // `a ,b`
    bool                    spaceAfterCast                 = true;                            // `cast(int) x`
    bool                    spaceAfterKeyword              = true;                            // `if (x)` vs `if(x)`
    bool                    spaceAfterUnaryOperator        = false;                           // `- x` vs `-x`
    bool                    spaceInsideParentheses         = false;                           // `( a, b )`
    bool                    spaceInsideBrackets            = false;                           // `[ 0 ]`
    bool                    spaceInsideBraces              = false;                           // `{ 1, 2 }`
    bool                    spaceInEmptyParentheses        = false;                           // `( )`
    bool                    spaceInEmptyBraces             = false;                           // `{ }`
    bool                    spaceBeforeAttributeBracket    = false;                           // `foo #[attr]`
    FormatSpaceBeforeParens spaceBeforeParentheses         = FormatSpaceBeforeParens::Never; // When to insert a space between an identifier and `(`

    // -----------------------------------------------------------------------
    // Attributes
    // -----------------------------------------------------------------------
    FormatAttributePlacement attributePlacement       = FormatAttributePlacement::Preserve; // How to place `#[Attr]` relative to its declaration
    bool                     breakAfterAttribute      = true;                               // Force a line break between attribute and declaration
    bool                     spaceAfterAttributeComma = true;                               // Insert a space after `,` inside `#[A, B, C]`
    bool                     sortAttributeArguments   = false;                              // Sort attribute argument lists alphabetically

    // -----------------------------------------------------------------------
    // Comments
    // -----------------------------------------------------------------------
    FormatCommentReflow commentReflow               = FormatCommentReflow::Preserve; // How aggressively to rewrite comments for the column limit
    bool                normalizeSectionSeparators  = true;                          // Rewrite `// ####...` banners to a common width
    uint32_t            sectionSeparatorWidth       = 57;                            // Target column count for `// ### ... ###` banners
    bool                spaceAfterLineCommentPrefix = true;                          // `// text` vs `//text`

    // -----------------------------------------------------------------------
    // Imports / using
    // -----------------------------------------------------------------------
    FormatSortOrder sortUsingStatements      = FormatSortOrder::Preserve; // Sort order for top-of-file `using` statements
    bool            mergeUsingStatements     = false;                     // Collapse adjacent `using` onto one line
    bool            blankLineAfterUsingBlock = true;                      // Guarantee a blank line after the initial `using` block

    // -----------------------------------------------------------------------
    // Numeric literals
    // -----------------------------------------------------------------------
    FormatLiteralCase hexLiteralCase           = FormatLiteralCase::Preserve; // Case of hex digits (`0xABCD` vs `0xabcd`)
    FormatLiteralCase hexLiteralPrefixCase     = FormatLiteralCase::Lower;    // `0x` vs `0X`
    FormatLiteralCase integerSuffixCase        = FormatLiteralCase::Preserve; // `1'u32` vs `1'U32`
    FormatLiteralCase floatExponentCase        = FormatLiteralCase::Preserve; // `1e10` vs `1E10`
    bool              normalizeDigitSeparators = false;                       // Add `_` every N digits in long literals
    uint32_t          digitSeparatorGroupSize  = 4;                           // Group size for hex ints when normalizing separators

    // -----------------------------------------------------------------------
    // Region / disable pragmas
    // -----------------------------------------------------------------------
    Utf8 formatOffComment = "swc-format off"; // Comment marker that disables formatting until the matching on-comment
    Utf8 formatOnComment  = "swc-format on";  // Comment marker that re-enables formatting after a format-off marker
};

SWC_END_NAMESPACE();
