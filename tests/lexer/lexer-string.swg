// swc-option lex-only

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

// --- Empty and whitespace ---
"   "
"\t\t\t"
" \t \n "           // This has \n which would cause NewlineInStringLiteral
"     "

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

// --- Invalid escape sequences in multi-line ---
"""\c"""            // swc-expected-error {{InvalidEscapeSequence}}
"""\z"""            // swc-expected-error {{InvalidEscapeSequence}}
"""test\qfail"""    // swc-expected-error {{InvalidEscapeSequence}}

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

// --- Unclosed raw strings ---
#"unclosed          // swc-expected-error {{UnclosedStringLiteral}}
#"hello world       // swc-expected-error {{UnclosedStringLiteral}}
#"test              // swc-expected-error {{UnclosedStringLiteral}}

#"line1
line2              // swc-expected-error {{UnclosedStringLiteral}}

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
