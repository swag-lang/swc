#pragma once
#include "Support/Core/Utf8.h"

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
    Preserve,
    None,
    Consecutive,  // Align within contiguous groups only
    AcrossBlanks, // Align across single blank lines
    All,          // Align everything inside the enclosing block
};

enum class FormatShortBlockStyle : uint8_t
{
    Preserve,
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
    Preserve,
    Never,
    Always,
    ControlStatements, // Only for `if` / `while` / `for` / `switch`
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
    std::optional<bool> insertFinalNewline;           // Ensure the file ends with a single newline
    std::optional<bool> trimTrailingNewlines;         // Collapse multiple trailing newlines to one
    uint32_t            maxConsecutiveEmptyLines = 2; // Max blank lines in a row (0 = no limit)
    std::optional<bool> keepEmptyLinesAtStartOfBlock; // Preserve blank lines right after `{`
    std::optional<bool> keepEmptyLinesAtEndOfBlock;   // Preserve blank lines right before `}`
    uint32_t            minBlankLinesBetweenFunctions = 0; // Minimum blank lines between function declarations (0 = preserve)

    // -----------------------------------------------------------------------
    // End-of-line
    // -----------------------------------------------------------------------
    FormatEndOfLineStyle endOfLineStyle = FormatEndOfLineStyle::Preserve; // Line-ending style written back to the file

    // -----------------------------------------------------------------------
    // Indentation
    // -----------------------------------------------------------------------
    FormatIndentStyle   indentStyle             = FormatIndentStyle::Preserve; // Use spaces, tabs, or keep the existing style
    uint32_t            indentWidth             = 4;                           // Width of one indent level when using spaces
    uint32_t            tabWidth                = 4;                           // Visual width assumed for a tab character
    uint32_t            continuationIndentWidth = 4;                           // Extra indent for wrapped statements
    std::optional<bool> indentNamespaceBody;                                   // Indent content inside `namespace { ... }`
    std::optional<bool> indentImplBody;                                        // Indent content inside `impl ... { ... }`
    std::optional<bool> indentStructBody;                                      // Indent content inside `struct { ... }`
    std::optional<bool> indentEnumBody;                                        // Indent content inside `enum { ... }`
    std::optional<bool> indentCaseLabels;                                      // Indent `case X:` one extra level under `switch`
    std::optional<bool> indentCaseBlocks;                                      // Indent the block inside a case
    std::optional<bool> indentAttributes;                                      // Attributes follow the declaration's indent
    std::optional<bool> indentInsideParens;                                    // Indent wrapped args relative to the open paren

    // -----------------------------------------------------------------------
    // Column limit & wrapping
    // -----------------------------------------------------------------------
    uint32_t                columnLimit                = 0;                                 // Soft column limit (0 disables wrapping)
    FormatOperatorWrapStyle breakBeforeBinaryOperators = FormatOperatorWrapStyle::Preserve; // Where to wrap around binary operators
    std::optional<bool>     breakBeforeTernaryOperators;                                    // Break before `?` and `:` in `cond ? a : b`
    std::optional<bool>     breakAfterReturnType;                                           // Newline before `->` in `func foo(...)->T`
    std::optional<bool>     breakBeforeDo;                                                  // Break before trailing `do` (`if x do ...`)
    std::optional<bool>     breakBeforeElse;                                                // Place `else` on its own line
    FormatBinPackStyle      binPackArguments  = FormatBinPackStyle::Preserve;               // Call argument layout when wrapping
    FormatBinPackStyle      binPackParameters = FormatBinPackStyle::Preserve;               // Declaration parameter layout when wrapping

    // -----------------------------------------------------------------------
    // Braces & short bodies
    // -----------------------------------------------------------------------
    FormatBraceStyle      braceStyle = FormatBraceStyle::Preserve;                           // Opening brace placement policy
    std::optional<bool>   compactEmptyBraces;                                                // Keep `{}` inline on the opening line
    FormatShortBlockStyle allowShortFunctionsOnSingleLine = FormatShortBlockStyle::Preserve; // When to keep function bodies on one line
    FormatShortBlockStyle allowShortBlocksOnSingleLine    = FormatShortBlockStyle::Preserve; // When to keep generic `{ ... }` blocks on one line
    FormatShortBlockStyle allowShortEnumsOnSingleLine     = FormatShortBlockStyle::Preserve; // When to keep `enum` bodies on one line
    FormatShortBlockStyle allowShortStructsOnSingleLine   = FormatShortBlockStyle::Preserve; // When to keep `struct` bodies on one line
    std::optional<bool>   allowShortIfStatementsOnSingleLine;                                // Allow `if cond do stmt` on one line
    std::optional<bool>   allowShortLoopsOnSingleLine;                                       // Allow short `while`/`for` bodies on one line
    std::optional<bool>   allowShortCaseOnSingleLine;                                        // Allow single-statement `case` arms on one line

    // -----------------------------------------------------------------------
    // Alignment
    // -----------------------------------------------------------------------
    FormatAlignMode     alignConsecutiveAssignments  = FormatAlignMode::Preserve; // Align `=` in adjacent assignments
    FormatAlignMode     alignConsecutiveDeclarations = FormatAlignMode::Preserve; // Align names/types of adjacent `let`/`var` declarations
    FormatAlignMode     alignConsecutiveConstants    = FormatAlignMode::Preserve; // Align values of adjacent `const` declarations
    FormatAlignMode     alignStructFields            = FormatAlignMode::Preserve; // Align `:` and types of adjacent struct fields
    FormatAlignMode     alignEnumValues              = FormatAlignMode::Preserve; // Align `=` on enum value definitions
    FormatAlignMode     alignAttributes              = FormatAlignMode::Preserve; // Align adjacent `#[...]` attributes
    std::optional<bool> alignTrailingComments;                                    // Align `//` trailing comments into a shared column
    uint32_t            trailingCommentMinSpaces = 5;                             // Minimum spaces before a trailing `//`
    uint32_t            trailingCommentMaxColumn = 0;                             // 0 = no limit on trailing comment column
    std::optional<bool> alignOperands;                                            // Align operands of wrapped binary expressions
    std::optional<bool> alignAfterOpenBracket;                                    // Align wrapped args with the opening `(` / `[`

    // -----------------------------------------------------------------------
    // Spacing
    // -----------------------------------------------------------------------
    std::optional<bool>     spaceBeforeColonInDeclarations;                             // `a : u8`
    std::optional<bool>     spaceAfterColonInDeclarations;                              // `a: u8`
    std::optional<bool>     spaceBeforeColonInBaseClause;                               // `enum E: u32`
    std::optional<bool>     spaceAroundAssignmentOperator;                              // `a = 1`
    std::optional<bool>     spaceAroundBinaryOperators;                                 // `a + b`
    std::optional<bool>     spaceAroundArrow;                                           // `func()->int` vs `func() -> int`
    std::optional<bool>     spaceAroundFatArrow;                                        // `func() => x` vs `func()=>x`
    std::optional<bool>     spaceAroundRangeOperator;                                   // `0..10` vs `0 .. 10`
    std::optional<bool>     spaceAfterComma;                                            // `a, b`
    std::optional<bool>     spaceBeforeComma;                                           // `a ,b`
    std::optional<bool>     spaceAfterCast;                                             // `cast(int) x`
    std::optional<bool>     spaceAfterKeyword;                                          // `if (x)` vs `if(x)`
    std::optional<bool>     spaceAfterUnaryOperator;                                    // `- x` vs `-x`
    std::optional<bool>     spaceInsideParentheses;                                     // `( a, b )`
    std::optional<bool>     spaceInsideBrackets;                                        // `[ 0 ]`
    std::optional<bool>     spaceInsideBraces;                                          // `{ 1, 2 }`
    std::optional<bool>     spaceInEmptyParentheses;                                    // `( )`
    std::optional<bool>     spaceInEmptyBraces;                                         // `{ }`
    std::optional<bool>     spaceBeforeAttributeBracket;                                // `foo #[attr]`
    FormatSpaceBeforeParens spaceBeforeParentheses = FormatSpaceBeforeParens::Preserve; // When to insert a space between an identifier and `(`

    // -----------------------------------------------------------------------
    // Attributes
    // -----------------------------------------------------------------------
    FormatAttributePlacement attributePlacement = FormatAttributePlacement::Preserve; // How to place `#[Attr]` relative to its declaration
    std::optional<bool>      breakAfterAttribute;                                     // Force a line break between attribute and declaration
    std::optional<bool>      spaceAfterAttributeComma;                                // Insert a space after `,` inside `#[A, B, C]`
    std::optional<bool>      sortAttributeArguments;                                  // Sort attribute argument lists alphabetically

    // -----------------------------------------------------------------------
    // Comments
    // -----------------------------------------------------------------------
    FormatCommentReflow commentReflow = FormatCommentReflow::Preserve; // How aggressively to rewrite comments for the column limit
    std::optional<bool> normalizeSectionSeparators;                    // Rewrite `// ####...` banners to a common width
    uint32_t            sectionSeparatorWidth = 57;                    // Target column count for `// ### ... ###` banners
    std::optional<bool> spaceAfterLineCommentPrefix;                   // `// text` vs `//text`

    // -----------------------------------------------------------------------
    // Imports / using
    // -----------------------------------------------------------------------
    FormatSortOrder     sortUsingStatements = FormatSortOrder::Preserve; // Sort order for top-of-file `using` statements
    std::optional<bool> mergeUsingStatements;                            // Collapse adjacent `using` onto one line
    std::optional<bool> blankLineAfterUsingBlock;                        // Guarantee a blank line after the initial `using` block

    // -----------------------------------------------------------------------
    // Numeric literals
    // -----------------------------------------------------------------------
    FormatLiteralCase   hexLiteralCase       = FormatLiteralCase::Preserve; // Case of hex digits (`0xABCD` vs `0xabcd`)
    FormatLiteralCase   hexLiteralPrefixCase = FormatLiteralCase::Preserve; // `0x` vs `0X` (also applies to `0b` / `0B`)
    FormatLiteralCase   floatExponentCase    = FormatLiteralCase::Preserve; // `1e10` vs `1E10`
    std::optional<bool> normalizeDigitSeparators;                           // Rewrite literals to use canonical `_` digit separators
    uint32_t            hexDigitSeparatorGroupSize     = 4;                 // Group size for `0x` / `0b` literals when normalizing separators
    uint32_t            decimalDigitSeparatorGroupSize = 3;                 // Group size for decimal and float literals when normalizing separators

    // -----------------------------------------------------------------------
    // Region / disable pragmas
    // -----------------------------------------------------------------------
    Utf8 formatOffComment = "swc-format off"; // Comment marker that disables formatting until the matching on-comment
    Utf8 formatOnComment  = "swc-format on";  // Comment marker that re-enables formatting after a format-off marker
};

SWC_END_NAMESPACE();
