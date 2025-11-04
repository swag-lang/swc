// swc-option lex-only

// --- Invalid escape sequences ---
"\c"        // swc-expected-error {{InvalidEscapeSequence}}
"\d"        // swc-expected-error {{InvalidEscapeSequence}}
"\e"        // swc-expected-error {{InvalidEscapeSequence}}
"\g"        // swc-expected-error {{InvalidEscapeSequence}}
"\h"        // swc-expected-error {{InvalidEscapeSequence}}
"\i"        // swc-expected-error {{InvalidEscapeSequence}}
"\j"        // swc-expected-error {{InvalidEscapeSequence}}
"\k"        // swc-expected-error {{InvalidEscapeSequence}}
"\l"        // swc-expected-error {{InvalidEscapeSequence}}
"\m"        // swc-expected-error {{InvalidEscapeSequence}}
"\o"        // swc-expected-error {{InvalidEscapeSequence}}
"\p"        // swc-expected-error {{InvalidEscapeSequence}}
"\q"        // swc-expected-error {{InvalidEscapeSequence}}
"\s"        // swc-expected-error {{InvalidEscapeSequence}}
"\w"        // swc-expected-error {{InvalidEscapeSequence}}
"\y"        // swc-expected-error {{InvalidEscapeSequence}}
"\z"        // swc-expected-error {{InvalidEscapeSequence}}
"\1"        // swc-expected-error {{InvalidEscapeSequence}}
"\2"        // swc-expected-error {{InvalidEscapeSequence}}

// --- Unclosed string literals (missing closing quote) ---
// swc-expected-error@+ {{NewlineInStringLiteral}}
"unclosed
// swc-expected-error@+ {{NewlineInStringLiteral}}
"hello world
// swc-expected-error@+ {{NewlineInStringLiteral}}
"test
// swc-expected-error@+ {{NewlineInStringLiteral}}
"with\"escape

// --- Unclosed with trailing backslash at EOF ---
// swc-expected-error@+ {{InvalidEscapeSequence}}
"test\

// --- Invalid escape sequences in multi-line ---
"""\c"""            // swc-expected-error {{InvalidEscapeSequence}}
"""\z"""            // swc-expected-error {{InvalidEscapeSequence}}
"""test\qfail"""    // swc-expected-error {{InvalidEscapeSequence}}

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

// --- Backslash at end ---
'a''s32
// swc-expected-error@+ {{UnclosedCharLiteral}}
'a' 's

// --- Invalid or unknown escapes ---
"\z"              // swc-expected-error {{InvalidEscapeSequence}}
"\q"              // swc-expected-error {{InvalidEscapeSequence}}
"\9"              // swc-expected-error {{InvalidEscapeSequence}}
// swc-expected-error@+ {{NewlineInStringLiteral}}
"\"
"\ "              // swc-expected-error {{InvalidEscapeSequence}}

// --- Hexadecimal escapes (\xXX) ---
"\xG0"            // swc-expected-error {{InvalidHexDigit}}
"\x"              // swc-expected-error {{EmptyHexEscape}}
"\x0"             // swc-expected-error {{IncompleteHexEscape}}
"\x_0"            // swc-expected-error {{InvalidHexDigit}}

// --- Unicode short escapes (\uXXXX) ---
"\uG000"          // swc-expected-error {{InvalidHexDigit}}
"\u123"           // swc-expected-error {{IncompleteHexEscape}}
"\u"              // swc-expected-error {{EmptyHexEscape}}
"\u_"             // swc-expected-error {{InvalidHexDigit}}

// --- Unicode long escapes (\UXXXXXXXX) ---
"\U110000"        // swc-expected-error {{IncompleteHexEscape}}
"\U1234567"       // swc-expected-error {{IncompleteHexEscape}}
"\U0000000G"      // swc-expected-error {{IncompleteHexEscape}}
"\U000000"        // swc-expected-error {{IncompleteHexEscape}}
"\U"              // swc-expected-error {{EmptyHexEscape}}

// --- Mixed / complex sequences ---
"abc\x4G"         // swc-expected-error {{IncompleteHexEscape}}
"abc\u004"        // swc-expected-error {{IncompleteHexEscape}}
"abc\U0000004"    // swc-expected-error {{IncompleteHexEscape}}
