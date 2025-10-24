// Command line errors
SWAG_DIAG_DEF(CmdLineInvalidArg, "invalid command-line argument '%0'")
SWAG_DIAG_DEF(CmdLineInvalidArgForCmd, "invalid argument '%0' for command '%1'")
SWAG_DIAG_DEF(CmdLineInvalidEnumValue, "invalid value '%0' for option '%1'; expected one of the allowed enum values")
SWAG_DIAG_DEF(CmdLineMissingArgValue, "missing value for argument '%0'")
SWAG_DIAG_DEF(CmdLineInvalidBoolArg, "invalid value '%1' for boolean argument '%0'; expected 'true' or 'false'")

// File errors
SWAG_DIAG_DEF(CannotOpenFile, "cannot open file '%0'; check that the file exists and you have read permissions")
SWAG_DIAG_DEF(CannotReadFile, "cannot read file '%0'; the file may be corrupted or inaccessible")

// Tests
SWAG_DIAG_DEF(UnRaisedDirective, "directive was declared but never raised")

// Lexer errors
SWAG_DIAG_DEF(FileNotUtf8, "file '%0' is not valid UTF-8; ensure the file is encoded in UTF-8 format")
SWAG_DIAG_DEF(UnclosedComment, "unclosed comment; expected '*/' before end of file")
SWAG_DIAG_DEF(NewlineInStringLiteral, "unexpected newline in string literal; close the string with a matching quote")
SWAG_DIAG_DEF(UnclosedStringLiteral, "unclosed string literal; missing closing quote")
SWAG_DIAG_DEF(ConsecutiveNumberSeparators, "invalid numeric literal: consecutive number separators are not allowed")
SWAG_DIAG_DEF(LeadingNumberSeparator, "invalid numeric literal: leading number separator not allowed")
SWAG_DIAG_DEF(TrailingNumberSeparator, "invalid numeric literal: trailing number separator not allowed")
SWAG_DIAG_DEF(MissingHexDigits, "invalid hexadecimal literal: missing digits after '0x'")
SWAG_DIAG_DEF(MissingBinDigits, "invalid binary literal: missing digits after '0b'")
SWAG_DIAG_DEF(MissingExponentDigits, "invalid numeric literal: missing digits after exponent")
SWAG_DIAG_DEF(InvalidBinDigit, "invalid binary digit '%0'; only '0' or '1' are allowed")
SWAG_DIAG_DEF(InvalidEscapeSequence, "invalid escape sequence '%0'; unknown or unsupported escape")
SWAG_DIAG_DEF(EmptyCharLiteral, "empty character literal; expected a single character")
SWAG_DIAG_DEF(UnclosedCharLiteral, "unclosed character literal; missing closing quote")
SWAG_DIAG_DEF(InvalidHexDigit, "invalid hexadecimal digit '%0'; valid digits are 0–9 and A–F")
SWAG_DIAG_DEF(IncompleteHexEscape, "incomplete hexadecimal escape sequence '%0'; expected two hex digits")
SWAG_DIAG_DEF(EmptyHexEscape, "empty hexadecimal escape sequence '%0'; expected at least one hex digit")
SWAG_DIAG_DEF(TooManyCharsInCharLiteral, "too many characters in character literal; only one allowed")
SWAG_DIAG_DEF(InvalidNumberSuffix, "invalid number suffix '%0'; not a recognized numeric type suffix")
SWAG_DIAG_DEF(InvalidCharacter, "invalid character '%0'; not allowed in source file")

// Notes
SWAG_DIAG_DEF(NoteEscapesSequence, "valid escape sequences are '\\n', '\\r', '\\t', '\\x', '\\u', '\\U'...")
