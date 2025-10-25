// Command line errors
SWC_DIAG_DEF(CmdLineInvalidArg, "invalid command-line argument '{arg}'")
SWC_DIAG_DEF(CmdLineInvalidArgForCmd, "invalid argument '{arg}' for command '{command}'")
SWC_DIAG_DEF(CmdLineInvalidEnumValue, "invalid value '{value}' for argument '{arg}'; value must be one of '{values}'")
SWC_DIAG_DEF(CmdLineMissingArgValue, "missing value for argument '{arg}'")
SWC_DIAG_DEF(CmdLineInvalidBoolArg, "invalid negation for argument '{arg}'; '{arg}' is not a boolean")

// File errors
SWC_DIAG_DEF(CannotOpenFile, "cannot open file '{path}'; check that the file exists and you have read permissions")
SWC_DIAG_DEF(CannotReadFile, "cannot read file '{path}'; the file may be corrupted or inaccessible")

// Tests
SWC_DIAG_DEF(UnRaisedDirective, "directive was declared but never raised")

// Lexer errors
SWC_DIAG_DEF(LexFileNotUtf8, "file is not valid UTF-8; ensure the file is encoded in UTF-8 format")
SWC_DIAG_DEF(LexUnclosedComment, "unclosed comment; expected '*/' before end of file")
SWC_DIAG_DEF(LexNewlineInStringLiteral, "unexpected newline in string literal; close the string with a matching quote")
SWC_DIAG_DEF(LexUnclosedStringLiteral, "unclosed string literal; missing closing quote")
SWC_DIAG_DEF(LexConsecutiveNumberSeparators, "invalid numeric literal; consecutive number separators are not allowed")
SWC_DIAG_DEF(LexLeadingNumberSeparator, "invalid numeric literal; leading number separator not allowed")
SWC_DIAG_DEF(LexTrailingNumberSeparator, "invalid numeric literal; trailing number separator not allowed")
SWC_DIAG_DEF(LexMissingHexDigits, "invalid hexadecimal literal; missing digits after '0x'")
SWC_DIAG_DEF(LexMissingBinDigits, "invalid binary literal; missing digits after '0b'")
SWC_DIAG_DEF(LexMissingExponentDigits, "invalid numeric literal; missing digits after exponent")
SWC_DIAG_DEF(LexInvalidBinDigit, "invalid binary digit '{tkn}'; only '0' or '1' are allowed")
SWC_DIAG_DEF(LexInvalidEscapeSequence, "invalid escape sequence '{tkn}'; unknown or unsupported escape")
SWC_DIAG_DEF(LexEmptyCharLiteral, "empty character literal; expected a single character")
SWC_DIAG_DEF(LexUnclosedCharLiteral, "unclosed character literal; missing closing quote")
SWC_DIAG_DEF(LexInvalidHexDigit, "invalid hexadecimal digit '{tkn}'; valid digits are 0–9 and A–F")
SWC_DIAG_DEF(LexIncompleteHexEscape, "incomplete hexadecimal escape sequence '{tkn}'; expected two hex digits")
SWC_DIAG_DEF(LexEmptyHexEscape, "empty hexadecimal escape sequence '{tkn}'; expected at least one hex digit")
SWC_DIAG_DEF(LexTooManyCharsInCharLiteral, "too many characters in character literal; only one allowed")
SWC_DIAG_DEF(LexInvalidNumberSuffix, "invalid number suffix '{tkn}'; not a recognized numeric type suffix")
SWC_DIAG_DEF(LexInvalidCharacter, "invalid character '{tkn}'; not allowed in source file")

// Parser errors
SWC_DIAG_DEF(UnterminatedCurlyBlock, "unterminated curly block; expected '}' before end of file")

