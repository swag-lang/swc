// swc-option lex-only

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
'\c'        // swc-expected-error {{InvalidEscapeSequence}}
'\d'        // swc-expected-error {{InvalidEscapeSequence}}
'\e'        // swc-expected-error {{InvalidEscapeSequence}}
'\g'        // swc-expected-error {{InvalidEscapeSequence}}
'\h'        // swc-expected-error {{InvalidEscapeSequence}}
'\i'        // swc-expected-error {{InvalidEscapeSequence}}
'\j'        // swc-expected-error {{InvalidEscapeSequence}}
'\k'        // swc-expected-error {{InvalidEscapeSequence}}
'\l'        // swc-expected-error {{InvalidEscapeSequence}}
'\m'        // swc-expected-error {{InvalidEscapeSequence}}
'\o'        // swc-expected-error {{InvalidEscapeSequence}}
'\p'        // swc-expected-error {{InvalidEscapeSequence}}
'\q'        // swc-expected-error {{InvalidEscapeSequence}}
'\s'        // swc-expected-error {{InvalidEscapeSequence}}
'\w'        // swc-expected-error {{InvalidEscapeSequence}}
'\y'        // swc-expected-error {{InvalidEscapeSequence}}
'\z'        // swc-expected-error {{InvalidEscapeSequence}}
'\1'        // swc-expected-error {{InvalidEscapeSequence}}
'\2'        // swc-expected-error {{InvalidEscapeSequence}}

// --- Empty character literal ---
// swc-expected-error@+ {{EmptyCharLiteral}}
''

// --- Unclosed character literals (missing closing quote) ---
// swc-expected-error@+ {{UnclosedCharLiteral}}
'a
// swc-expected-error@+ {{UnclosedCharLiteral}}
'x
// swc-expected-error@+ {{UnclosedCharLiteral}}
'\n
// swc-expected-error@+ {{UnclosedCharLiteral}}
'\t

// --- Character literal with newline inside ---
// swc-expected-error@+ {{UnclosedCharLiteral}}
'test
multiple
lines'

// --- Unclosed at EOF ---
// swc-expected-error@+ {{UnclosedCharLiteral}}
'z

// --- Unclosed with escape at EOF ---
// swc-expected-error@+ {{InvalidEscapeSequence}}
'\

// --- Multiple characters ---
'ab'		// swc-expected-error {{TooManyCharsInCharLiteral}}
'abc'		// swc-expected-error {{TooManyCharsInCharLiteral}}
'test'		// swc-expected-error {{TooManyCharsInCharLiteral}}
'hello'		// swc-expected-error {{TooManyCharsInCharLiteral}}

// --- Multiple characters with escapes ---
'a\n'		// swc-expected-error {{TooManyCharsInCharLiteral}}
'\nz'		// swc-expected-error {{TooManyCharsInCharLiteral}}
'x\ty'		// swc-expected-error {{TooManyCharsInCharLiteral}}

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
'\x'        // swc-expected-error {{EmptyHexEscape}}
'\x1'       // swc-expected-error {{IncompleteHexEscape}}
'\xG'       // swc-expected-error {{InvalidHexDigit}}

// --- Incomplete unicode escapes ---
'\u'        // swc-expected-error {{EmptyHexEscape}}
'\u0'       // swc-expected-error {{IncompleteHexEscape}}
'\u00'      // swc-expected-error {{IncompleteHexEscape}}
'\u000'     // swc-expected-error {{IncompleteHexEscape}}
'\uGGGG'    // swc-expected-error {{InvalidHexDigit}}

// --- Incomplete extended unicode escapes ---
'\U'        // swc-expected-error {{EmptyHexEscape}}
'\U0'       // swc-expected-error {{IncompleteHexEscape}}
'\U00'      // swc-expected-error {{IncompleteHexEscape}}
'\U000'     // swc-expected-error {{IncompleteHexEscape}}
'\U0000'    // swc-expected-error {{IncompleteHexEscape}}
'\U00000'   // swc-expected-error {{IncompleteHexEscape}}
'\U000000'  // swc-expected-error {{IncompleteHexEscape}}
'\U0000000' // swc-expected-error {{IncompleteHexEscape}}

// --- Character literals with tabs and spaces ---
'	'
'   '       // swc-expected-error {{TooManyCharsInCharLiteral}}

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
// swc-expected-error@+ {{InvalidEscapeSequence}}
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

// --- Unicode
'é'
'日'
'本'
'語'
'🎉'
'Ñ'
'o'
'ñ'
'o'

// ============================================================================
// SUFFIX
// ============================================================================

'a''s32
// swc-expected-error@+ {{UnclosedCharLiteral}}
'a' 's