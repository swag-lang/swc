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
"\z"              // expected-error InvalidEscapeSequence
"\q"              // expected-error InvalidEscapeSequence
"\9"              // expected-error InvalidEscapeSequence
// expected-error@+ StringLiteralEol
"\"
"\\ "             // valid — escaped backslash + space
"\ "              // expected-error InvalidEscapeSequence

// --- Hexadecimal escapes (\xXX) ---
"\x00"            // valid (NUL)
"\x1F"            // valid
"\x7E"            // valid (~)
"\xFF"            // valid
"\x0A"            // valid (newline)
"\xG0"            // expected-error InvalidHexDigit
"\x"              // expected-error InvalidHexDigit
"\x0"             // expected-error IncompleteHexEscape
"\x_0"            // expected-error InvalidHexDigit

// --- Unicode short escapes (\uXXXX) ---
"\u0000"          // valid
"\u0041"          // valid ('A')
"\u00E9"          // valid (é)
"\uabcd"          // valid
"\uFFFF"          // valid (last BMP code point)
"\uG000"          // expected-error InvalidHexDigit
"\u123"           // expected-error IncompleteHexEscape
"\u"              // expected-error InvalidHexDigit
"\u_"             // expected-error InvalidHexDigit

// --- Unicode long escapes (\UXXXXXXXX) ---
"\U00000000"      // valid
"\U00000041"      // valid ('A')
"\U0001F600"      // valid (😀)
"\U0000FFFF"      // valid
"\U0010FFFF"      // valid (max Unicode code point)
"\U110000"        // expected-error IncompleteHexEscape
"\U1234567"       // expected-error IncompleteHexEscape
"\U0000000G"      // expected-error IncompleteHexEscape
"\U000000"        // expected-error IncompleteHexEscape
"\U"              // expected-error InvalidHexDigit

// --- Mixed / complex sequences ---
"abc\\ndef"       // valid (escaped backslash + newline)
"abc\x41"         // valid ('A')
"abc\u0042"       // valid ('B')
"abc\U00000043"   // valid ('C')
"abc\x4G"         // expected-error IncompleteHexEscape
"abc\u004"        // expected-error IncompleteHexEscape
"abc\U0000004"    // expected-error IncompleteHexEscape