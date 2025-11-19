// ============================================================================
// Lexer Strings Error
// ============================================================================

// swc-option lex-only

// --- Invalid escape sequences ---
"\c"        // swc-expected-error {{lex_err_invalid_escape}}
"\d"        // swc-expected-error {{lex_err_invalid_escape}}
"\e"        // swc-expected-error {{lex_err_invalid_escape}}
"\g"        // swc-expected-error {{lex_err_invalid_escape}}
"\h"        // swc-expected-error {{lex_err_invalid_escape}}
"\i"        // swc-expected-error {{lex_err_invalid_escape}}
"\j"        // swc-expected-error {{lex_err_invalid_escape}}
"\k"        // swc-expected-error {{lex_err_invalid_escape}}
"\l"        // swc-expected-error {{lex_err_invalid_escape}}
"\m"        // swc-expected-error {{lex_err_invalid_escape}}
"\o"        // swc-expected-error {{lex_err_invalid_escape}}
"\p"        // swc-expected-error {{lex_err_invalid_escape}}
"\q"        // swc-expected-error {{lex_err_invalid_escape}}
"\s"        // swc-expected-error {{lex_err_invalid_escape}}
"\w"        // swc-expected-error {{lex_err_invalid_escape}}
"\y"        // swc-expected-error {{lex_err_invalid_escape}}
"\z"        // swc-expected-error {{lex_err_invalid_escape}}
"\1"        // swc-expected-error {{lex_err_invalid_escape}}
"\2"        // swc-expected-error {{lex_err_invalid_escape}}

// --- Unclosed string literals (missing closing quote) ---
// swc-expected-error@+ {{lex_err_string_eol}}
"unclosed
// swc-expected-error@+ {{lex_err_string_eol}}
"hello world
// swc-expected-error@+ {{lex_err_string_eol}}
"test
// swc-expected-error@+ {{lex_err_string_eol}}
"with\"escape

// --- Unclosed with trailing backslash at EOF ---
// swc-expected-error@+ {{lex_err_invalid_escape}}
"test\

// --- Invalid escape sequences in multi-line ---
"""\c"""            // swc-expected-error {{lex_err_invalid_escape}}
"""\z"""            // swc-expected-error {{lex_err_invalid_escape}}
"""test\qfail"""    // swc-expected-error {{lex_err_invalid_escape}}

// --- Invalid escape sequences ---
'\c'        // swc-expected-error {{lex_err_invalid_escape}}
'\d'        // swc-expected-error {{lex_err_invalid_escape}}
'\e'        // swc-expected-error {{lex_err_invalid_escape}}
'\g'        // swc-expected-error {{lex_err_invalid_escape}}
'\h'        // swc-expected-error {{lex_err_invalid_escape}}
'\i'        // swc-expected-error {{lex_err_invalid_escape}}
'\j'        // swc-expected-error {{lex_err_invalid_escape}}
'\k'        // swc-expected-error {{lex_err_invalid_escape}}
'\l'        // swc-expected-error {{lex_err_invalid_escape}}
'\m'        // swc-expected-error {{lex_err_invalid_escape}}
'\o'        // swc-expected-error {{lex_err_invalid_escape}}
'\p'        // swc-expected-error {{lex_err_invalid_escape}}
'\q'        // swc-expected-error {{lex_err_invalid_escape}}
'\s'        // swc-expected-error {{lex_err_invalid_escape}}
'\w'        // swc-expected-error {{lex_err_invalid_escape}}
'\y'        // swc-expected-error {{lex_err_invalid_escape}}
'\z'        // swc-expected-error {{lex_err_invalid_escape}}
'\1'        // swc-expected-error {{lex_err_invalid_escape}}
'\2'        // swc-expected-error {{lex_err_invalid_escape}}

// --- Empty character literal ---
// swc-expected-error@+ {{lex_err_empty_char}}
''

// --- Unclosed character literals (missing closing quote) ---
// swc-expected-error@+ {{lex_err_unclosed_char}}
'a
// swc-expected-error@+ {{lex_err_unclosed_char}}
'x
// swc-expected-error@+ {{lex_err_unclosed_char}}
'\n
// swc-expected-error@+ {{lex_err_unclosed_char}}
'\t

// --- Character literal with newline inside ---
// swc-expected-error@+ {{lex_err_unclosed_char}}
'test
multiple
lines'

// --- Unclosed at EOF ---
// swc-expected-error@+ {{lex_err_unclosed_char}}
'z

// --- Unclosed with escape at EOF ---
// swc-expected-error@+ {{lex_err_invalid_escape}}
'\

// --- Multiple characters ---
'ab'		// swc-expected-error {{lex_err_too_many_char_char}}
'abc'		// swc-expected-error {{lex_err_too_many_char_char}}
'test'		// swc-expected-error {{lex_err_too_many_char_char}}
'hello'		// swc-expected-error {{lex_err_too_many_char_char}}

// --- Multiple characters with escapes ---
'a\n'		// swc-expected-error {{lex_err_too_many_char_char}}
'\nz'		// swc-expected-error {{lex_err_too_many_char_char}}
'x\ty'		// swc-expected-error {{lex_err_too_many_char_char}}

// --- Incomplete hex escapes ---
'\x'        // swc-expected-error {{lex_err_empty_hex_escape}}
'\x1'       // swc-expected-error {{lex_err_incomplete_hex_escape}}
'\xG'       // swc-expected-error {{lex_err_invalid_hex_digit}}

// --- Incomplete unicode escapes ---
'\u'        // swc-expected-error {{lex_err_empty_hex_escape}}
'\u0'       // swc-expected-error {{lex_err_incomplete_hex_escape}}
'\u00'      // swc-expected-error {{lex_err_incomplete_hex_escape}}
'\u000'     // swc-expected-error {{lex_err_incomplete_hex_escape}}
'\uGGGG'    // swc-expected-error {{lex_err_invalid_hex_digit}}

// --- Incomplete extended unicode escapes ---
'\U'        // swc-expected-error {{lex_err_empty_hex_escape}}
'\U0'       // swc-expected-error {{lex_err_incomplete_hex_escape}}
'\U00'      // swc-expected-error {{lex_err_incomplete_hex_escape}}
'\U000'     // swc-expected-error {{lex_err_incomplete_hex_escape}}
'\U0000'    // swc-expected-error {{lex_err_incomplete_hex_escape}}
'\U00000'   // swc-expected-error {{lex_err_incomplete_hex_escape}}
'\U000000'  // swc-expected-error {{lex_err_incomplete_hex_escape}}
'\U0000000' // swc-expected-error {{lex_err_incomplete_hex_escape}}

// --- Character literals with tabs and spaces ---
'	'
'   '       // swc-expected-error {{lex_err_too_many_char_char}}

// --- Backslash at end ---
'a''s32
// swc-expected-error@+ {{lex_err_unclosed_char}}
'a' 's

// --- Invalid or unknown escapes ---
"\z"              // swc-expected-error {{lex_err_invalid_escape}}
"\q"              // swc-expected-error {{lex_err_invalid_escape}}
"\9"              // swc-expected-error {{lex_err_invalid_escape}}
// swc-expected-error@+ {{lex_err_string_eol}}
"\"
"\ "              // swc-expected-error {{lex_err_invalid_escape}}

// --- Hexadecimal escapes (\xXX) ---
"\xG0"            // swc-expected-error {{lex_err_invalid_hex_digit}}
"\x"              // swc-expected-error {{lex_err_empty_hex_escape}}
"\x0"             // swc-expected-error {{lex_err_incomplete_hex_escape}}
"\x_0"            // swc-expected-error {{lex_err_invalid_hex_digit}}

// --- Unicode short escapes (\uXXXX) ---
"\uG000"          // swc-expected-error {{lex_err_invalid_hex_digit}}
"\u123"           // swc-expected-error {{lex_err_incomplete_hex_escape}}
"\u"              // swc-expected-error {{lex_err_empty_hex_escape}}
"\u_"             // swc-expected-error {{lex_err_invalid_hex_digit}}

// --- Unicode long escapes (\UXXXXXXXX) ---
"\U110000"        // swc-expected-error {{lex_err_incomplete_hex_escape}}
"\U1234567"       // swc-expected-error {{lex_err_incomplete_hex_escape}}
"\U0000000G"      // swc-expected-error {{lex_err_incomplete_hex_escape}}
"\U000000"        // swc-expected-error {{lex_err_incomplete_hex_escape}}
"\U"              // swc-expected-error {{lex_err_empty_hex_escape}}

// --- Mixed / complex sequences ---
"abc\x4G"         // swc-expected-error {{lex_err_incomplete_hex_escape}}
"abc\u004"        // swc-expected-error {{lex_err_incomplete_hex_escape}}
"abc\U0000004"    // swc-expected-error {{lex_err_incomplete_hex_escape}}
