// ============================================================================
// CHARACTER LITERALS
// ============================================================================

// --- Valid single character literals ---
'a'
'b'
'Z'
'0'
'9'
' '
'@'
'#'
'$'
'%'
'&'
'*'

// --- Valid escape sequences ---
'\n'
'\r'
'\t'
'\\'
'\"'
'\''
'\0'
'\x41'
'\u0041'
'\b'
'\f'
'\v'

// --- Hexadecimal escapes ---
'\x00'
'\x20'
'\x7F'
'\xFF'

// --- Unicode escapes ---
'\u0000'
'\u0041'
'\u00A9'
'\uFFFF'

// --- Extended Unicode escapes ---
'\U00000041'
'\U0001F600'
'\U0010FFFF'

// --- Invalid escape sequences ---
'\c'        // expected-error InvalidEscapeSequence
'\d'        // expected-error InvalidEscapeSequence
'\e'        // expected-error InvalidEscapeSequence
'\g'        // expected-error InvalidEscapeSequence
'\h'        // expected-error InvalidEscapeSequence
'\i'        // expected-error InvalidEscapeSequence
'\j'        // expected-error InvalidEscapeSequence
'\k'        // expected-error InvalidEscapeSequence
'\l'        // expected-error InvalidEscapeSequence
'\m'        // expected-error InvalidEscapeSequence
'\o'        // expected-error InvalidEscapeSequence
'\p'        // expected-error InvalidEscapeSequence
'\q'        // expected-error InvalidEscapeSequence
'\s'        // expected-error InvalidEscapeSequence
'\w'        // expected-error InvalidEscapeSequence
'\y'        // expected-error InvalidEscapeSequence
'\z'        // expected-error InvalidEscapeSequence
'\1'        // expected-error InvalidEscapeSequence
'\2'        // expected-error InvalidEscapeSequence

// --- Empty character literal ---
// expected-error@+ EmptyCharLiteral
''

// --- Unclosed character literals (missing closing quote) ---
// expected-error@+ UnclosedCharLiteral
'a
// expected-error@+ UnclosedCharLiteral
'x
// expected-error@+ UnclosedCharLiteral
'\n
// expected-error@+ UnclosedCharLiteral
'\t

// --- Character literal with newline inside ---
// expected-error@+ UnclosedCharLiteral
'test
multiple
lines'

// --- Unclosed at EOF ---
// expected-error@+ UnclosedCharLiteral
'z

// --- Unclosed with escape at EOF ---
// expected-error@+ InvalidEscapeSequence
'\

// --- Multiple characters (lexer accepts, semantic analysis may reject) ---
'ab'
'abc'
'test'
'hello'

// --- Multiple characters with escapes ---
'a\n'
'\nz'
'x\ty'

// --- Special punctuation characters ---
'('
')'
'['
']'
'{'
'}'
';'
','
'.'
':'
'?'
'!'
'~'
'|'
'^'
'<'
'>'
'='
'+'
'-'
'/'

// --- Quotes inside character literals ---
'\"'        // Double quote (valid)
'\''        // Escaped single quote (valid)

// --- Incomplete hex escapes ---
'\x'        // expected-error EmptyHexEscape
'\x1'       // expected-error IncompleteHexEscape
'\xG'       // expected-error InvalidHexDigit

// --- Incomplete unicode escapes ---
'\u'        // expected-error EmptyHexEscape
'\u0'       // expected-error IncompleteHexEscape
'\u00'      // expected-error IncompleteHexEscape
'\u000'     // expected-error IncompleteHexEscape
'\uGGGG'    // expected-error InvalidHexDigit

// --- Incomplete extended unicode escapes ---
'\U'        // expected-error EmptyHexEscape
'\U0'       // expected-error IncompleteHexEscape
'\U00'      // expected-error IncompleteHexEscape
'\U000'     // expected-error IncompleteHexEscape
'\U0000'    // expected-error IncompleteHexEscape
'\U00000'   // expected-error IncompleteHexEscape
'\U000000'  // expected-error IncompleteHexEscape
'\U0000000' // expected-error IncompleteHexEscape

// --- Character literals with tabs and spaces ---
'	'       // Tab character
'   '       // Multiple spaces

// --- Adjacent character literals (separate tokens) ---
'a' 'b'
'x''y'
'1' '2' '3'

// --- Character literals in expressions (context) ---
// Note: In the lexer, '\'' after identifiers becomes the quote operator
// These should be character literals since they don't follow identifiers
'a' + 'b'
'0' - '9'

// ============================================================================
// EDGE CASES AND BOUNDARY CONDITIONS
// ============================================================================

// --- Backslash at end ---
// expected-error@+ InvalidEscapeSequence
'test\

// --- Valid maximum values ---
'\xFF'          // Max 2-digit hex
'\uFFFF'        // Max 4-digit unicode
'\U0010FFFF'    // Max valid unicode code point

// --- Escaped backslash ---
'\\'

// --- All valid single-char escapes together ---
'\n' '\r' '\t' '\\' '\"' '\'' '\0' '\b' '\f' '\v'

// --- Character literal with only escape ---
'\x41'
'\u0041'

// --- Whitespace characters ---
' '
'\t'
'\n'
'\r'

// --- Null character ---
'\0'
'\x00'
'\u0000'
'\U00000000'