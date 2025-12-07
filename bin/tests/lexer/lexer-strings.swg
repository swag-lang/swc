// swc-option lex-only

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
'\''        // Escaped single quote (valid)

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
// MULTI-LINE STRINGS
// ============================================================================
// --- Valid multi-line strings ---
""""""
"""hello"""
"""Hello, World!"""
"""line1
line2
line3"""

"""
multi
line
string
"""

"""first line
second line
third line"""

// --- Valid multi-line with escape sequences ---
"""hello\nworld"""
"""tab\there"""
"""quote\"here"""
"""backslash\\test"""
"""\n\r\t\b\f\v"""

// --- Multi-line with trailing backslash at EOL ---
"""test\
A\
B\
"""
"""test\
A\
B"""

// --- Multi-line with embedded quotes ---
"""This is "quoted" text"""
"""Single " quote"""
"""Double "" quotes"""
"""One"Two"Three"""

// --- Multi-line empty lines ---
"""

"""

"""
line1

line2

line3
"""

// ============================================================================
// RAW STRINGS
// ============================================================================
// --- Valid raw strings ---
#""#
#"hello"#
#"Hello, World!"#
#"no\nescape"#
#"backslash\remains"#
#"quote"stays"#
#"all\t\n\r\\characters\"literal"#

// --- Multi-line raw strings ---
#"line1
line2
line3"#

#"
raw
multi
line
"#

// --- Raw strings with special characters (no escaping needed) ---
#"C:\path\to\file"#
#"regex: \d+\.\d+"#
#"JSON: {"key": "value"}"#
#"<html>\n\t<body></body>\n</html>"#

// --- Raw strings with embedded quotes ---
#"This is "quoted" text"#
#"Multiple """" quotes"#
#"Mix of ' and " quotes"#

// --- Edge cases ---
#""#                // Empty raw string
#" "#               // Single space
#"	"#              // Single tab
#"
"#                  // Single newline

// ============================================================================
// SINGLE-LINE STRINGS
// ============================================================================
// --- Valid single-line strings ---
""
"hello"
"Hello, World!"
"123"
"abc123xyz"
"with spaces"
"with\ttabs"
"multiple   spaces"

// --- Valid escape sequences ---
"\n"
"\r"
"\t"
"\\"
"\""
"\'"
"\0"
"\x41"
"\u0041"
"\b"
"\f"
"\v"
"hello\nworld"
"path\\to\\file"
"say \"hello\""
"tab\there"
"line1\nline2\nline3"
"escaped\\backslash\\test"

// --- Empty and whitespace ---
"   "
"\t\t\t"
" \t \n "           // This has \n which would cause NewlineInStringLiteral
"     "

// ============================================================================
// MIXED AND EDGE CASES
// ============================================================================
// --- Adjacent strings (separate tokens) ---
"hello" "world"
"test1""test2"
"""multi1""" """multi2"""
#"raw1"# #"raw2"#

// --- Strings with numbers ---
"123"
"3.14159"
"0x1234"
"0b1010"

// --- Strings with operators ---
"+ - * /"
"== != <= >="
"&& || !"
"<<= >>="

// --- Unicode and special characters (if supported) ---
"café"
"日本語"
"emoji: 🎉"
"Ñoño"

// --- Very long strings ---
"this is a very long string that goes on and on and on and on and on and on and on and on and on and on and on and on"

"""this is a very long multi-line string
that spans many lines and contains lots of text
and keeps going and going and going
until finally it ends"""

#"this is a very long raw string that contains \n \t \r and other escape sequences that are not interpreted"#

// ============================================================================
// EDGE CASES AND BOUNDARY CONDITIONS
// ============================================================================
// --- Valid maximum values ---
'\xFF'          // Max 2-digit hex
'\uFFFF'        // Max 4-digit unicode
'\U0010FFFF'    // Max valid unicode code point

// --- Escaped backslash ---
'\\'

// --- All valid single-char escapes together ---
'\n' '\r' '\t' '\\' '\'' '\0' '\b' '\f' '\v'

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

// --- Hexadecimal escapes (\xXX) ---
"\x00"
"\x1F"
"\x7E"
"\xFF"
"\x0A"

// --- Unicode short escapes (\uXXXX) ---
"\u0000"
"\u0041"
"\u00E9"
"\uabcd"
"\uFFFF"

// --- Basic valid escapes ---
"Hello\nWorld"
"Tab\tSeparated"
"Quote: \""
"Backslash: \\"
"Carriage\rReturn"
"FormFeed\fChar"
"Backspace\bTest"
"Vertical\vTab"

// --- Unicode long escapes (\UXXXXXXXX) ---
"\U00000000"      // valid
"\U00000041"      // valid ('A')
"\U0001F600"      // valid (😀)
"\U0000FFFF"      // valid
"\U0010FFFF"      // valid (max Unicode code point)

// --- Mixed / complex sequences ---
"abc\\ndef"       // valid (escaped backslash + newline)
"abc\x41"         // valid ('A')
"abc\u0042"       // valid ('B')
"abc\U00000043"   // valid ('C')

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
