// swc-option lex-only

// ============================================================================
// ESCAPE
// ============================================================================

// --- Basic valid escapes ---
"Hello\nWorld"
"Tab\tSeparated"
"Quote: \""
"Backslash: \\"
"Carriage\rReturn"
"FormFeed\fChar"
"Backspace\bTest"
"Vertical\vTab"

// --- Invalid or unknown escapes ---
"\z"              // swc-expected-error {{InvalidEscapeSequence}}
"\q"              // swc-expected-error {{InvalidEscapeSequence}}
"\9"              // swc-expected-error {{InvalidEscapeSequence}}
// swc-expected-error@+ {{NewlineInStringLiteral}}
"\"
"\\ "
"\ "              // swc-expected-error {{InvalidEscapeSequence}}

// --- Hexadecimal escapes (\xXX) ---
"\x00"
"\x1F"
"\x7E"
"\xFF"
"\x0A"
"\xG0"            // swc-expected-error {{InvalidHexDigit}}
"\x"              // swc-expected-error {{EmptyHexEscape}}
"\x0"             // swc-expected-error {{IncompleteHexEscape}}
"\x_0"            // swc-expected-error {{InvalidHexDigit}}

// --- Unicode short escapes (\uXXXX) ---
"\u0000"
"\u0041"
"\u00E9"
"\uabcd"
"\uFFFF"
"\uG000"          // swc-expected-error {{InvalidHexDigit}}
"\u123"           // swc-expected-error {{IncompleteHexEscape}}
"\u"              // swc-expected-error {{EmptyHexEscape}}
"\u_"             // swc-expected-error {{InvalidHexDigit}}

// --- Unicode long escapes (\UXXXXXXXX) ---
"\U00000000"      // valid
"\U00000041"      // valid ('A')
"\U0001F600"      // valid (😀)
"\U0000FFFF"      // valid
"\U0010FFFF"      // valid (max Unicode code point)
"\U110000"        // swc-expected-error {{IncompleteHexEscape}}
"\U1234567"       // swc-expected-error {{IncompleteHexEscape}}
"\U0000000G"      // swc-expected-error {{IncompleteHexEscape}}
"\U000000"        // swc-expected-error {{IncompleteHexEscape}}
"\U"              // swc-expected-error {{EmptyHexEscape}}

// --- Mixed / complex sequences ---
"abc\\ndef"       // valid (escaped backslash + newline)
"abc\x41"         // valid ('A')
"abc\u0042"       // valid ('B')
"abc\U00000043"   // valid ('C')
"abc\x4G"         // swc-expected-error {{IncompleteHexEscape}}
"abc\u004"        // swc-expected-error {{IncompleteHexEscape}}
"abc\U0000004"    // swc-expected-error {{IncompleteHexEscape}}