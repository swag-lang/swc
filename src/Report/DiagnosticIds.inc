// Command line errors
SWC_DIAG_DEF(CmdLineInvalidArg, "invalid command-line argument '{arg}'")
SWC_DIAG_DEF(CmdLineInvalidArgForCmd, "invalid argument '{arg}' for command '{command}'")
SWC_DIAG_DEF(CmdLineInvalidEnumValue, "invalid value '{arg}' for option '{arg}'")
SWC_DIAG_DEF(CmdLineMissingArgValue, "missing value for argument '{arg}'")
SWC_DIAG_DEF(CmdLineInvalidBoolArg, "invalid negation '{arg}' for argument '{basearg}'; '{basearg}' is not a boolean")

// File errors
SWC_DIAG_DEF(CannotOpenFile, "cannot open file '{path}'; check that the file exists and you have read permissions")
SWC_DIAG_DEF(CannotReadFile, "cannot read file '{path}'; the file may be corrupted or inaccessible")

// Tests
SWC_DIAG_DEF(UnRaisedDirective, "directive was declared but never raised")

// Lexer errors
SWC_DIAG_DEF(FileNotUtf8, "file is not valid UTF-8; ensure the file is encoded in UTF-8 format")
SWC_DIAG_DEF(UnclosedComment, "unclosed comment; expected '*/' before end of file")
SWC_DIAG_DEF(NewlineInStringLiteral, "unexpected newline in string literal; close the string with a matching quote")
SWC_DIAG_DEF(UnclosedStringLiteral, "unclosed string literal; missing closing quote")
SWC_DIAG_DEF(ConsecutiveNumberSeparators, "invalid numeric literal; consecutive number separators are not allowed")
SWC_DIAG_DEF(LeadingNumberSeparator, "invalid numeric literal; leading number separator not allowed")
SWC_DIAG_DEF(TrailingNumberSeparator, "invalid numeric literal; trailing number separator not allowed")
SWC_DIAG_DEF(MissingHexDigits, "invalid hexadecimal literal; missing digits after '0x'")
SWC_DIAG_DEF(MissingBinDigits, "invalid binary literal; missing digits after '0b'")
SWC_DIAG_DEF(MissingExponentDigits, "invalid numeric literal; missing digits after exponent")
SWC_DIAG_DEF(InvalidBinDigit, "invalid binary digit '{tkn}'; only '0' or '1' are allowed")
SWC_DIAG_DEF(InvalidEscapeSequence, "invalid escape sequence '{tkn}'; unknown or unsupported escape")
SWC_DIAG_DEF(EmptyCharLiteral, "empty character literal; expected a single character")
SWC_DIAG_DEF(UnclosedCharLiteral, "unclosed character literal; missing closing quote")
SWC_DIAG_DEF(InvalidHexDigit, "invalid hexadecimal digit '{tkn}'; valid digits are 0–9 and A–F")
SWC_DIAG_DEF(IncompleteHexEscape, "incomplete hexadecimal escape sequence '{tkn}'; expected two hex digits")
SWC_DIAG_DEF(EmptyHexEscape, "empty hexadecimal escape sequence '{tkn}'; expected at least one hex digit")
SWC_DIAG_DEF(TooManyCharsInCharLiteral, "too many characters in character literal; only one allowed")
SWC_DIAG_DEF(InvalidNumberSuffix, "invalid number suffix '{tkn}'; not a recognized numeric type suffix")
SWC_DIAG_DEF(InvalidCharacter, "invalid character '{tkn}'; not allowed in source file")
