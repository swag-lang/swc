#include "pch.h"

#include "Core/Timer.h"
#include "Core/Utf8Helper.h"
#include "Lexer/LangSpec.h"
#include "Lexer/Lexer.h"
#include "Lexer/SourceFile.h"
#include "Main/Context.h"
#include "Main/Global.h"
#include "Report/Diagnostic.h"
#include "Report/DiagnosticIds.h"
#include "Report/Stats.h"

SWC_BEGIN_NAMESPACE();

// Helper: does the next char after the 'x'/'u'/'U' count as a hard terminator
// for an escape in the given container token?
bool Lexer::isTerminatorAfterEscapeChar(uint8_t c, TokenId container)
{
    // We only distinguish broadly between char and string by TokenId.
    // For strings (single-line or multi-line), treat quote/EOL similarly.
    if (container == TokenId::Character)
        return c == '\'' || c == '\n' || c == '\r';

    // Strings
    return c == '"' || c == '\n' || c == '\r';
}

void Lexer::eatUtf8Char()
{
    auto [buf, wc, eat] = Utf8Helper::decodeOneChar(buffer_, endBuffer_);
    if (!buf)
    {
        reportTokenError(DiagnosticId::FileNotUtf8, static_cast<uint32_t>(buffer_ - startBuffer_));
        hasUtf8Error_  = true;
        hasTokenError_ = true;
        buffer_++;
    }
    else
    {
        buffer_ = buf;
    }
}

// Consume exactly one logical EOL (CRLF | CR | LF). Push the next line start.
void Lexer::eatOneEol()
{
    if (buffer_[0] == '\r')
    {
        if (buffer_[1] == '\n')
            buffer_ += 2;
        else
            buffer_++;
    }
    else
    {
        SWC_ASSERT(buffer_[0] == '\n');
        buffer_++;
    }

    file_->lexOut_.lines_.push_back(static_cast<uint32_t>(buffer_ - startBuffer_));
}

void Lexer::pushToken()
{
    token_.len = static_cast<uint32_t>(buffer_ - startToken_);
    prevToken_ = token_;

    if (rawMode_ && token_.id != TokenId::CommentLine && token_.id != TokenId::CommentMultiLine)
        return;
    if (token_.id == TokenId::Blank && !lexerFlags_.has(LexerFlagsEnum::ExtractBlanks))
        return;
    if (token_.id == TokenId::EndOfLine && !lexerFlags_.has(LexerFlagsEnum::ExtractLineEnds))
        return;
    if (token_.id == TokenId::CommentLine && !lexerFlags_.has(LexerFlagsEnum::ExtractComments))
        return;
    if (token_.id == TokenId::CommentMultiLine && !lexerFlags_.has(LexerFlagsEnum::ExtractComments))
        return;

    file_->lexOut_.tokens_.push_back(token_);
}

void Lexer::reportUtf8Error(DiagnosticId id, uint32_t offset, uint32_t len)
{
    if (hasUtf8Error_)
        return;
    hasUtf8Error_ = true;

    if (rawMode_)
        return;

    const auto diag = Diagnostic::error(id, ctx_->sourceFile());
    diag.last()->setLocation(ctx_->sourceFile(), offset, len);
    diag.report(*ctx_);
    file_->setHasError();
}

void Lexer::reportTokenError(DiagnosticId id, uint32_t offset, uint32_t len)
{
    if (hasTokenError_)
        return;
    hasTokenError_ = true;

    if (rawMode_)
        return;

    const auto diag = Diagnostic::error(id, ctx_->sourceFile());
    diag.last()->setLocation(ctx_->sourceFile(), offset, len);

    // Add an argument with the token string
    if (len)
    {
        const std::string_view arg = ctx_->sourceFile()->codeView(offset, len);
        diag.last()->addArgument(arg);
    }

    diag.report(*ctx_);
    file_->setHasError();
}

// Validate hex/Unicode escape sequences (\xXX, \uXXXX, \UXXXXXXXX)
void Lexer::lexEscape(TokenId containerToken, bool eatEol)
{
    // Eat the EOL right after the escape character
    if (eatEol)
    {
        if (buffer_[1] == '\r' || buffer_[1] == '\n')
        {
            buffer_++;
            eatOneEol();
            return;
        }
    }

    if (!langSpec_->isEscape(buffer_[1]))
        reportTokenError(DiagnosticId::InvalidEscapeSequence, static_cast<uint32_t>(buffer_ - startBuffer_), 2);

    // pos points to the backslash
    if (buffer_[1] != 'x' && buffer_[1] != 'u' && buffer_[1] != 'U')
    {
        buffer_++;
        if (buffer_[0] == '\r' || buffer_[0] == '\n')
            eatOneEol();
        else
            buffer_++;
        return;
    }

    const uint8_t escapeType     = buffer_[1];
    uint32_t      expectedDigits = 0;

    switch (escapeType)
    {
        case 'x':
            expectedDigits = 2; // \xXX
            break;
        case 'u':
            expectedDigits = 4; // \uXXXX
            break;
        case 'U':
            expectedDigits = 8; // \UXXXXXXXX
            break;
        default:
            SWC_ASSERT(false);
    }

    // Check if we have the required number of hex digits
    for (uint32_t i = 0; i < expectedDigits; i++)
    {
        if (!langSpec_->isHexNumber(buffer_[2 + i]))
        {
            // Not enough or invalid hex digits
            const uint32_t actualDigits = i;
            const uint32_t offset       = static_cast<uint32_t>(buffer_ - startBuffer_);

            if (actualDigits == 0)
            {
                const uint8_t first = buffer_[2]; // first expected a hex digit
                if (isTerminatorAfterEscapeChar(first, containerToken))
                    reportTokenError(DiagnosticId::EmptyHexEscape, offset, 2);
                else
                    reportTokenError(DiagnosticId::InvalidHexDigit, offset + 2);
            }
            else
                reportTokenError(DiagnosticId::IncompleteHexEscape, offset, 2 + actualDigits);

            buffer_ += 2 + actualDigits;
            return;
        }
    }

    // Valid escape sequence
    buffer_ += 2 + expectedDigits;
}

void Lexer::lexEol()
{
    token_.id = TokenId::EndOfLine;

    // Consume the first logical EOL.
    eatOneEol();

    // Collapse subsequent EOLs (any mix of CR/LF/CRLF).
    while (buffer_[0] == '\r' || buffer_[0] == '\n')
        eatOneEol();

    pushToken();
}

void Lexer::lexBlank()
{
    token_.id = TokenId::Blank;

    buffer_++;
    while (langSpec_->isBlank(buffer_[0]))
        buffer_++;

    pushToken();
}

void Lexer::lexSingleLineStringLiteral()
{
    token_.id = TokenId::StringLine;

    buffer_++;

    // Safe lookahead: zeros after endBuffer_ will stop the loop
    while (buffer_ < endBuffer_ && buffer_[0] != '"' && buffer_[0] != '\n' && buffer_[0] != '\r')
    {
        // Check for null byte (invalid UTF-8)
        if (buffer_[0] == '\0')
        {
            reportTokenError(DiagnosticId::FileNotUtf8, static_cast<uint32_t>(buffer_ - startBuffer_));
            buffer_++;
            continue;
        }

        // Escaped char
        if (buffer_[0] == '\\')
        {
            lexEscape(TokenId::StringLine, false);
            continue;
        }

        buffer_++;
    }

    // Handle newline in string literal
    if (buffer_[0] == '\n' || buffer_[0] == '\r')
        reportTokenError(DiagnosticId::NewlineInStringLiteral, static_cast<uint32_t>(buffer_ - startBuffer_));

    // Handle EOF
    if (buffer_ >= endBuffer_)
        reportTokenError(DiagnosticId::UnclosedStringLiteral, static_cast<uint32_t>(startToken_ - startBuffer_));

    // Consume closing quote if present
    if (buffer_[0] == '"')
        buffer_++;

    pushToken();
}

void Lexer::lexMultiLineStringLiteral()
{
    token_.id = TokenId::StringMultiLine;
    buffer_ += 3;

    while (buffer_ < endBuffer_)
    {
        // Check for null byte (invalid UTF-8)
        if (buffer_[0] == '\0')
        {
            reportUtf8Error(DiagnosticId::FileNotUtf8, static_cast<uint32_t>(buffer_ - startBuffer_));
            buffer_++;
            continue;
        }

        // Track line starts for accurate diagnostics later
        if (buffer_[0] == '\n' || buffer_[0] == '\r')
        {
            eatOneEol();
            continue;
        }

        // Escaped char
        if (buffer_[0] == '\\')
        {
            lexEscape(TokenId::StringMultiLine, true);
            continue;
        }

        // Closing delimiter - safe to read buffer_[1] and buffer_[2] due to padding after endBuffer_
        if (buffer_[0] == '"' && buffer_[1] == '"' && buffer_[2] == '"')
        {
            buffer_ += 3;
            token_.len = static_cast<uint32_t>(buffer_ - startToken_);
            pushToken();
            return;
        }

        buffer_++;
    }

    // EOF before closing delimiter
    reportTokenError(DiagnosticId::UnclosedStringLiteral, static_cast<uint32_t>(startToken_ - startBuffer_), 3);
    pushToken();
}

void Lexer::lexRawStringLiteral()
{
    token_.id = TokenId::StringRaw;
    buffer_ += 2;

    bool foundClosing = false;

    // Safe to read buffer_[1] due to padding after endBuffer_
    while (buffer_ < endBuffer_)
    {
        // Check for null byte (invalid UTF-8)
        if (buffer_[0] == '\0')
        {
            reportUtf8Error(DiagnosticId::FileNotUtf8, static_cast<uint32_t>(buffer_ - startBuffer_));
            buffer_++;
            continue;
        }

        if (buffer_[0] == '"' && buffer_[1] == '#')
        {
            buffer_ += 2;
            foundClosing = true;
            break;
        }

        if (buffer_[0] == '\n' || buffer_[0] == '\r')
        {
            eatOneEol();
            continue;
        }

        buffer_++;
    }

    if (!foundClosing)
        reportTokenError(DiagnosticId::UnclosedStringLiteral, static_cast<uint32_t>(startToken_ - startBuffer_), 2);

    pushToken();
}

void Lexer::lexCharacterLiteral()
{
    token_.id = TokenId::Character;
    buffer_++;

    // Check for empty character literal
    if (buffer_[0] == '\'')
    {
        reportTokenError(DiagnosticId::EmptyCharLiteral, static_cast<uint32_t>(startToken_ - startBuffer_), 2);
        buffer_++;
        pushToken();
        return;
    }

    uint32_t charCount = 0;
    while (buffer_ < endBuffer_ && buffer_[0] != '\'')
    {
        // Check for null byte (invalid UTF-8)
        if (buffer_[0] == '\0')
        {
            reportUtf8Error(DiagnosticId::FileNotUtf8, static_cast<uint32_t>(buffer_ - startBuffer_));
            buffer_++;
            continue;
        }

        // Check for EOL
        if (buffer_[0] == '\n' || buffer_[0] == '\r')
        {
            reportTokenError(DiagnosticId::UnclosedCharLiteral, static_cast<uint32_t>(startToken_ - startBuffer_));
            pushToken();
            eatOneEol();
            return;
        }

        // Handle escape sequence
        if (buffer_[0] == '\\')
            lexEscape(TokenId::Character, false);
        else
            eatUtf8Char();

        charCount++;
    }

    // Check for EOF
    if (buffer_ >= endBuffer_)
        reportTokenError(DiagnosticId::UnclosedCharLiteral, static_cast<uint32_t>(startToken_ - startBuffer_));

    // Consume closing quote if present
    if (buffer_[0] == '\'')
        buffer_++;

    // Check for too many characters
    if (charCount > 1)
        reportTokenError(DiagnosticId::TooManyCharsInCharLiteral, static_cast<uint32_t>(startToken_ - startBuffer_), static_cast<uint32_t>(buffer_ - startToken_));

    pushToken();
}

void Lexer::lexHexNumber()
{
    token_.id = TokenId::NumberHexadecimal;
    buffer_ += 2;

    bool           lastWasSep = false;
    const uint8_t* sepStart   = nullptr;
    uint32_t       digits     = 0;

    // Safe lookahead: zeros after endBuffer_ will fail isHexNumber check
    while (buffer_ < endBuffer_ && (langSpec_->isHexNumber(buffer_[0]) || langSpec_->isNumberSep(buffer_[0])))
    {
        if (langSpec_->isNumberSep(buffer_[0]))
        {
            if (lastWasSep)
            {
                while (buffer_ < endBuffer_ && langSpec_->isNumberSep(buffer_[0]))
                    buffer_++;
                reportTokenError(DiagnosticId::ConsecutiveNumberSeparators, static_cast<uint32_t>(sepStart - startBuffer_), static_cast<uint32_t>(buffer_ - sepStart));
                continue;
            }

            sepStart   = buffer_;
            lastWasSep = true;
            buffer_++;
            continue;
        }

        digits++;
        lastWasSep = false;
        buffer_++;
    }

    // Require at least one digit
    if (digits == 0)
        reportTokenError(DiagnosticId::MissingHexDigits, static_cast<uint32_t>(startToken_ - startBuffer_), 2 + (lastWasSep ? 1 : 0));

    // No trailing separator
    if (lastWasSep)
        reportTokenError(DiagnosticId::TrailingNumberSeparator, static_cast<uint32_t>(buffer_ - startBuffer_ - 1));

    // Letters immediately following the literal
    if (langSpec_->isLetter(buffer_[0]))
        reportTokenError(DiagnosticId::InvalidHexDigit, static_cast<uint32_t>(buffer_ - startBuffer_), 1);

    pushToken();
}

void Lexer::lexBinNumber()
{
    token_.id = TokenId::NumberBinary;
    buffer_ += 2;

    bool           lastWasSep = false;
    const uint8_t* sepStart   = nullptr;
    uint32_t       digits     = 0;

    // Safe lookahead: zeros after endBuffer_ will fail the check
    while (buffer_ < endBuffer_ && (langSpec_->isBinNumber(buffer_[0]) || langSpec_->isNumberSep(buffer_[0])))
    {
        if (langSpec_->isNumberSep(buffer_[0]))
        {
            if (lastWasSep)
            {
                while (buffer_ < endBuffer_ && langSpec_->isNumberSep(buffer_[0]))
                    buffer_++;
                reportTokenError(DiagnosticId::ConsecutiveNumberSeparators, static_cast<uint32_t>(sepStart - startBuffer_), static_cast<uint32_t>(buffer_ - sepStart));
                continue;
            }

            sepStart   = buffer_;
            lastWasSep = true;
            buffer_++;
            continue;
        }

        digits++;
        lastWasSep = false;
        buffer_++;
    }

    // Require at least one digit
    if (digits == 0)
        reportTokenError(DiagnosticId::MissingBinDigits, static_cast<uint32_t>(startToken_ - startBuffer_), 2 + (lastWasSep ? 1 : 0));

    // No trailing separator
    if (lastWasSep)
        reportTokenError(DiagnosticId::TrailingNumberSeparator, static_cast<uint32_t>(buffer_ - startBuffer_ - 1));

    // Letters immediately following the literal
    if (langSpec_->isLetter(buffer_[0]))
        reportTokenError(DiagnosticId::InvalidBinDigit, static_cast<uint32_t>(buffer_ - startBuffer_), 1);

    pushToken();
}

void Lexer::lexDecimalNumber()
{
    token_.id = TokenId::NumberInteger;

    bool           lastWasSep = false;
    const uint8_t* sepStart   = nullptr;
    bool           hasDot     = false;
    bool           hasExp     = false;

    // Parse integer part - safe lookahead: zeros after endBuffer_ will fail the check
    while (buffer_ < endBuffer_ && (langSpec_->isDigit(buffer_[0]) || langSpec_->isNumberSep(buffer_[0])))
    {
        if (langSpec_->isNumberSep(buffer_[0]))
        {
            if (lastWasSep)
            {
                while (buffer_ < endBuffer_ && langSpec_->isNumberSep(buffer_[0]))
                    buffer_++;
                reportTokenError(DiagnosticId::ConsecutiveNumberSeparators, static_cast<uint32_t>(sepStart - startBuffer_), static_cast<uint32_t>(buffer_ - sepStart));
                continue;
            }

            sepStart   = buffer_;
            lastWasSep = true;
            buffer_++;
            continue;
        }

        lastWasSep = false;
        buffer_++;
    }

    // Check for trailing separator before the decimal point
    if (lastWasSep)
        reportTokenError(DiagnosticId::TrailingNumberSeparator, static_cast<uint32_t>(buffer_ - startBuffer_ - 1));

    // Parse decimal part
    if (buffer_[0] == '.')
    {
        hasDot = true;
        buffer_++;
        lastWasSep = false;

        if (langSpec_->isNumberSep(buffer_[0]))
            reportTokenError(DiagnosticId::LeadingNumberSeparator, static_cast<uint32_t>(buffer_ - startBuffer_));

        while (buffer_ < endBuffer_ && (langSpec_->isDigit(buffer_[0]) || langSpec_->isNumberSep(buffer_[0])))
        {
            if (langSpec_->isNumberSep(buffer_[0]))
            {
                if (lastWasSep)
                {
                    while (buffer_ < endBuffer_ && langSpec_->isNumberSep(buffer_[0]))
                        buffer_++;
                    reportTokenError(DiagnosticId::ConsecutiveNumberSeparators, static_cast<uint32_t>(sepStart - startBuffer_), static_cast<uint32_t>(buffer_ - sepStart));
                    continue;
                }

                sepStart   = buffer_;
                lastWasSep = true;
                buffer_++;
                continue;
            }

            lastWasSep = false;
            buffer_++;
        }

        if (hasDot)
            token_.id = TokenId::NumberFloat;
    }

    // Parse exponent part
    if (buffer_ < endBuffer_ && (buffer_[0] == 'e' || buffer_[0] == 'E'))
    {
        hasExp = true;
        buffer_++;

        // Optional sign
        if (buffer_ < endBuffer_ && (buffer_[0] == '+' || buffer_[0] == '-'))
            buffer_++;

        if (langSpec_->isNumberSep(buffer_[0]))
            reportTokenError(DiagnosticId::LeadingNumberSeparator, static_cast<uint32_t>(buffer_ - startBuffer_));

        uint32_t expDigits = 0;
        lastWasSep         = false;
        while (buffer_ < endBuffer_ && (langSpec_->isDigit(buffer_[0]) || langSpec_->isNumberSep(buffer_[0])))
        {
            if (langSpec_->isNumberSep(buffer_[0]))
            {
                if (lastWasSep)
                {
                    while (buffer_ < endBuffer_ && langSpec_->isNumberSep(buffer_[0]))
                        buffer_++;
                    reportTokenError(DiagnosticId::ConsecutiveNumberSeparators, static_cast<uint32_t>(sepStart - startBuffer_), static_cast<uint32_t>(buffer_ - sepStart));
                    continue;
                }

                sepStart   = buffer_;
                lastWasSep = true;
                buffer_++;
                continue;
            }

            expDigits++;
            lastWasSep = false;
            buffer_++;
        }

        if (expDigits == 0)
            reportTokenError(DiagnosticId::MissingExponentDigits, static_cast<uint32_t>(buffer_ - startBuffer_ - 1));

        if (hasExp)
            token_.id = TokenId::NumberFloat;
    }

    // Final trailing separator check
    if (lastWasSep)
        reportTokenError(DiagnosticId::TrailingNumberSeparator, static_cast<uint32_t>(buffer_ - startBuffer_ - 1));

    pushToken();
}

void Lexer::lexNumber()
{
    // Hexadecimal: 0x or 0X - safe to read buffer_[1] due to padding after endBuffer_
    if (buffer_[0] == '0' && (buffer_[1] == 'x' || buffer_[1] == 'X'))
        lexHexNumber();

    // Binary: 0b or 0B - safe to read buffer_[1] due to padding after endBuffer_
    else if (buffer_[0] == '0' && (buffer_[1] == 'b' || buffer_[1] == 'B'))
        lexBinNumber();

    // Decimal (including floats)
    else
        lexDecimalNumber();

    // Letters immediately following the literal
    if (langSpec_->isLetter(buffer_[0]))
        reportTokenError(DiagnosticId::InvalidNumberSuffix, static_cast<uint32_t>(buffer_ - startBuffer_));
}

void Lexer::lexIdentifier()
{
    token_.id = TokenId::Identifier;

    buffer_++;
    while (langSpec_->isIdentifierPart(buffer_[0]))
        buffer_++;

    const auto name = std::string_view(reinterpret_cast<std::string_view::const_pointer>(startToken_), buffer_ - startToken_);
    token_.id       = LangSpec::keyword(name);
    pushToken();
}

void Lexer::lexOperator()
{
    // Safe to read buffer_[1] and buffer_[2] due to padding after endBuffer_
    const uint8_t c = buffer_[0];

    switch (c)
    {
        case '\'':
            token_.id = TokenId::OpQuote;
            buffer_++;
            break;

        case '\\':
            token_.id = TokenId::OpBackSlash;
            buffer_++;
            break;

        case '(':
            token_.id = TokenId::OpLeftParen;
            buffer_++;
            break;

        case ')':
            token_.id = TokenId::OpRightParen;
            buffer_++;
            break;

        case '[':
            token_.id = TokenId::OpLeftSquare;
            buffer_++;
            break;

        case ']':
            token_.id = TokenId::OpRightSquare;
            buffer_++;
            break;

        case '{':
            token_.id = TokenId::OpLeftCurly;
            buffer_++;
            break;

        case '}':
            token_.id = TokenId::OpRightCurly;
            buffer_++;
            break;

        case ';':
            token_.id = TokenId::OpSemiColon;
            buffer_++;
            break;

        case ',':
            token_.id = TokenId::OpComma;
            buffer_++;
            break;

        case '@':
            token_.id = TokenId::OpAt;
            buffer_++;
            break;

        case '?':
            token_.id = TokenId::OpQuestion;
            buffer_++;
            break;

        case '~':
            token_.id = TokenId::OpTilde;
            buffer_++;
            break;

        case '=':
            if (buffer_[1] == '=')
            {
                token_.id = TokenId::OpEqualEqual;
                buffer_ += 2;
            }
            else if (buffer_[1] == '>')
            {
                token_.id = TokenId::OpEqualGreater;
                buffer_ += 2;
            }
            else
            {
                token_.id = TokenId::OpEqual;
                buffer_++;
            }
            break;

        case ':':
            token_.id = TokenId::OpColon;
            buffer_++;
            break;

        case '!':
            if (buffer_[1] == '=')
            {
                token_.id = TokenId::OpExclamationEqual;
                buffer_ += 2;
            }
            else
            {
                token_.id = TokenId::OpExclamation;
                buffer_++;
            }
            break;

        case '-':
            if (buffer_[1] == '=')
            {
                token_.id = TokenId::OpMinusEqual;
                buffer_ += 2;
            }
            else if (buffer_[1] == '>')
            {
                token_.id = TokenId::OpMinusGreater;
                buffer_ += 2;
            }
            else if (buffer_[1] == '-')
            {
                token_.id = TokenId::OpMinusMinus;
                buffer_ += 2;
            }
            else
            {
                token_.id = TokenId::OpMinus;
                buffer_++;
            }
            break;

        case '+':
            if (buffer_[1] == '=')
            {
                token_.id = TokenId::OpPlusEqual;
                buffer_ += 2;
            }
            else if (buffer_[1] == '+')
            {
                token_.id = TokenId::OpPlusPlus;
                buffer_ += 2;
            }
            else
            {
                token_.id = TokenId::OpPlus;
                buffer_++;
            }
            break;

        case '*':
            if (buffer_[1] == '=')
            {
                token_.id = TokenId::OpAsteriskEqual;
                buffer_ += 2;
            }
            else
            {
                token_.id = TokenId::OpAsterisk;
                buffer_++;
            }
            break;

        case '/':
            if (buffer_[1] == '=')
            {
                token_.id = TokenId::OpSlashEqual;
                buffer_ += 2;
            }
            else
            {
                token_.id = TokenId::OpSlash;
                buffer_++;
            }
            break;

        case '&':
            if (buffer_[1] == '=')
            {
                token_.id = TokenId::OpAmpersandEqual;
                buffer_ += 2;
            }
            else if (buffer_[1] == '&')
            {
                token_.id = TokenId::OpAmpersandAmpersand;
                buffer_ += 2;
            }
            else
            {
                token_.id = TokenId::OpAmpersand;
                buffer_++;
            }
            break;

        case '|':
            if (buffer_[1] == '=')
            {
                token_.id = TokenId::OpVerticalEqual;
                buffer_ += 2;
            }
            else if (buffer_[1] == '|')
            {
                token_.id = TokenId::OpVerticalVertical;
                buffer_ += 2;
            }
            else
            {
                token_.id = TokenId::OpVertical;
                buffer_++;
            }
            break;

        case '^':
            if (buffer_[1] == '=')
            {
                token_.id = TokenId::OpCircumflexEqual;
                buffer_ += 2;
            }
            else
            {
                token_.id = TokenId::OpCircumflex;
                buffer_++;
            }
            break;

        case '%':
            if (buffer_[1] == '=')
            {
                token_.id = TokenId::OpPercentEqual;
                buffer_ += 2;
            }
            else
            {
                token_.id = TokenId::OpPercent;
                buffer_++;
            }
            break;

        case '.':
            if (buffer_[1] == '.')
            {
                if (buffer_[2] == '.')
                {
                    token_.id = TokenId::OpDotDotDot;
                    buffer_ += 3;
                }
                else
                {
                    token_.id = TokenId::OpDotDot;
                    buffer_ += 2;
                }
            }
            else
            {
                token_.id = TokenId::OpDot;
                buffer_++;
            }
            break;

        case '<':
            if (buffer_[1] == '=')
            {
                if (buffer_[2] == '>')
                {
                    token_.id = TokenId::OpLowerEqualGreater;
                    buffer_ += 3;
                }
                else
                {
                    token_.id = TokenId::OpLowerEqual;
                    buffer_ += 2;
                }
            }
            else if (buffer_[1] == '<')
            {
                if (buffer_[2] == '=')
                {
                    token_.id = TokenId::OpLowerLowerEqual;
                    buffer_ += 3;
                }
                else
                {
                    token_.id = TokenId::OpLowerLower;
                    buffer_ += 2;
                }
            }
            else
            {
                token_.id = TokenId::OpLower;
                buffer_++;
            }
            break;

        case '>':
            if (buffer_[1] == '=')
            {
                token_.id = TokenId::OpGreaterEqual;
                buffer_ += 2;
            }
            else if (buffer_[1] == '>')
            {
                if (buffer_[2] == '=')
                {
                    token_.id = TokenId::OpGreaterGreaterEqual;
                    buffer_ += 3;
                }
                else
                {
                    token_.id = TokenId::OpGreaterGreater;
                    buffer_ += 2;
                }
            }
            else
            {
                token_.id = TokenId::OpGreater;
                buffer_++;
            }
            break;

        default:
            eatUtf8Char();
            reportTokenError(DiagnosticId::InvalidCharacter, static_cast<uint32_t>(startToken_ - startBuffer_), static_cast<uint32_t>(buffer_ - startToken_));
            break;
    }

    pushToken();
}

void Lexer::lexSingleLineComment()
{
    token_.id = TokenId::CommentLine;

    // Skip //
    buffer_ += 2;

    // Stop before EOL (LF or CR), do not consume it here.
    // Safe lookahead: zeros after endBuffer_ will stop the loop
    while (buffer_ < endBuffer_ && buffer_[0] != '\n' && buffer_[0] != '\r')
        buffer_++;

    pushToken();
}

void Lexer::lexMultiLineComment()
{
    token_.id = TokenId::CommentMultiLine;
    buffer_ += 2;

    uint32_t depth = 1;
    while (buffer_ < endBuffer_ && depth > 0)
    {
        // Check for null byte (invalid UTF-8)
        if (buffer_[0] == '\0')
        {
            reportUtf8Error(DiagnosticId::FileNotUtf8, static_cast<uint32_t>(buffer_ - startBuffer_));
            buffer_++;
            continue;
        }

        if (buffer_[0] == '\n' || buffer_[0] == '\r')
        {
            eatOneEol();
            continue;
        }

        // Safe to check buffer_[1] due to padding after endBuffer_
        if (buffer_[0] == '/' && buffer_[1] == '*')
        {
            depth++;
            buffer_ += 2;
            continue;
        }

        if (buffer_[0] == '*' && buffer_[1] == '/')
        {
            depth--;
            buffer_ += 2;
            continue;
        }

        buffer_++;
    }

    if (depth > 0)
        reportTokenError(DiagnosticId::UnclosedComment, static_cast<uint32_t>(startToken_ - startBuffer_), 2);

    pushToken();
}

void Lexer::checkFormat(const Context& ctx, uint32_t& startOffset)
{
    // BOM (Byte Order Mark) constants
    static constexpr uint8_t UTF8[]     = {0xEF, 0xBB, 0xBF};
    static constexpr uint8_t UTF16_BE[] = {0xFE, 0xFF};
    static constexpr uint8_t UTF16_LE[] = {0xFF, 0xFE};
    static constexpr uint8_t UTF32_BE[] = {0x00, 0x00, 0xFE, 0xFF};
    static constexpr uint8_t UTF32_LE[] = {0xFF, 0xFE, 0x00, 0x00};

    const auto  file    = ctx.sourceFile();
    const auto& content = file->content();

    // Ensure we have enough bytes to check
    if (content.size() < 3)
    {
        startOffset = 0;
        return;
    }

    const uint8_t* data = content.data();

    // UTF-8 BOM
    if (content.size() >= 3 &&
        data[0] == UTF8[0] && data[1] == UTF8[1] && data[2] == UTF8[2])
    {
        startOffset = 3;
        return;
    }

    bool badFormat = false;

    // UTF-16 BOMs (2 bytes)
    if (content.size() >= 2)
    {
        if ((data[0] == UTF16_BE[0] && data[1] == UTF16_BE[1]) ||
            (data[0] == UTF16_LE[0] && data[1] == UTF16_LE[1]))
        {
            startOffset = 2;
            badFormat   = true;
        }
    }

    // 3-byte BOMs
    if (!badFormat && content.size() >= 3)
    {
        if ((data[0] == 0x0E && data[1] == 0xFE && data[2] == 0xFF) || // SCSU
            (data[0] == 0xFB && data[1] == 0xEE && data[2] == 0x28) || // BOCU-1
            (data[0] == 0xF7 && data[1] == 0x64 && data[2] == 0x4C))   // UTF-1
        {
            startOffset = 3;
            badFormat   = true;
        }
    }

    // 4-byte BOMs
    if (!badFormat && content.size() >= 4)
    {
        if ((data[0] == UTF32_BE[0] && data[1] == UTF32_BE[1] && data[2] == UTF32_BE[2] && data[3] == UTF32_BE[3]) ||
            (data[0] == UTF32_LE[0] && data[1] == UTF32_LE[1] && data[2] == UTF32_LE[2] && data[3] == UTF32_LE[3]) ||
            (data[0] == 0x2B && data[1] == 0x2F && data[2] == 0x76 && (data[3] == 0x38 || data[3] == 0x39 || data[3] == 0x2B || data[3] == 0x2F)) || // UTF-7
            (data[0] == 0xDD && data[1] == 0x73 && data[2] == 0x66 && data[3] == 0x73) ||                                                            // UTF-EBCDIC
            (data[0] == 0x84 && data[1] == 0x31 && data[2] == 0x95 && data[3] == 0x33))                                                              // GB-18030
        {
            startOffset = 4;
            badFormat   = true;
        }
    }

    if (badFormat)
    {
        reportUtf8Error(DiagnosticId::FileNotUtf8, 0, 0);
        return;
    }

    startOffset = 0;
}

Result Lexer::tokenizeRaw(Context& ctx)
{
    rawMode_          = true;
    const auto result = tokenize(ctx, LexerFlagsEnum::ExtractComments);
    rawMode_          = false;
    return result;
}

Result Lexer::tokenize(Context& ctx, LexerFlags flags)
{
#if SWC_HAS_STATS
    Timer time(&Stats::get().timeLexer);
#endif

    file_ = ctx.sourceFile();

    file_->lexOut_.tokens_.clear();
    file_->lexOut_.lines_.clear();
    prevToken_ = {};

    langSpec_   = &ctx.global().langSpec();
    ctx_        = &ctx;
    lexerFlags_ = flags;

    uint32_t startOffset = 0;
    checkFormat(ctx, startOffset);

    const auto base = file_->content().data();
    buffer_         = base + startOffset;
    startBuffer_    = base;
    endBuffer_      = startBuffer_ + file_->size();

    // Reserve space based on file size
    file_->lexOut_.tokens_.reserve(file_->content().size() / 10);
    if (!rawMode_)
        file_->lexOut_.lines_.reserve(file_->content().size() / 60);
    file_->lexOut_.lines_.push_back(0);

    while (buffer_ < endBuffer_)
    {
        hasTokenError_ = false;
        startToken_    = buffer_;
        token_.start   = static_cast<uint32_t>(startToken_ - startBuffer_);
        token_.len     = 1;

        // Check for null byte (invalid UTF-8)
        if (buffer_[0] == '\0')
        {
            reportUtf8Error(DiagnosticId::FileNotUtf8, static_cast<uint32_t>(buffer_ - startBuffer_));
            hasTokenError_ = true;
            buffer_++;
            continue;
        }

        // End of line (LF, CRLF, or CR)
        if (buffer_[0] == '\n' || buffer_[0] == '\r')
        {
            lexEol();
            continue;
        }

        // Blanks
        if (langSpec_->isBlank(buffer_[0]))
        {
            lexBlank();
            continue;
        }

        // Number literal
        if (langSpec_->isDigit(buffer_[0]))
        {
            lexNumber();
            continue;
        }

        // String literal (raw) - safe to read buffer_[1] due to padding after endBuffer_
        if (buffer_[0] == '#' && buffer_[1] == '"')
        {
            lexRawStringLiteral();
            continue;
        }

        // String literal (multi-line) - safe to read buffer_[1] and buffer_[2] due to padding after endBuffer_
        if (buffer_[0] == '"' && buffer_[1] == '"' && buffer_[2] == '"')
        {
            lexMultiLineStringLiteral();
            continue;
        }

        // String literal (single-line)
        if (buffer_[0] == '"')
        {
            lexSingleLineStringLiteral();
            continue;
        }

        // Line comment - safe to read buffer_[1] due to padding after endBuffer_
        if (buffer_[0] == '/' && buffer_[1] == '/')
        {
            lexSingleLineComment();
            continue;
        }

        // Multi-line comment - safe to read buffer_[1] due to padding after endBuffer_
        if (buffer_[0] == '/' && buffer_[1] == '*')
        {
            lexMultiLineComment();
            continue;
        }

        // Identifier or keyword
        if (langSpec_->isIdentifierStart(buffer_[0]))
        {
            lexIdentifier();
            continue;
        }

        // Character literal or quote operator - context-sensitive
        // A single quote is a character literal only after blank, identifier, number, or string
        if (buffer_[0] == '\'')
        {
            if (prevToken_.id != TokenId::Identifier &&
                prevToken_.id != TokenId::Character &&
                prevToken_.id != TokenId::NumberHexadecimal &&
                prevToken_.id != TokenId::NumberBinary &&
                prevToken_.id != TokenId::NumberInteger &&
                prevToken_.id != TokenId::NumberFloat &&
                prevToken_.id != TokenId::StringLine &&
                prevToken_.id != TokenId::StringMultiLine &&
                prevToken_.id != TokenId::StringRaw)
            {
                lexCharacterLiteral();
                continue;
            }
        }

        // Operators and punctuation
        lexOperator();
    }

    // End marker
    token_.id  = TokenId::EndOfFile;
    token_.len = 0;
    file_->lexOut_.tokens_.push_back(token_);

#if SWC_HAS_STATS
    if (!rawMode_)
        Stats::get().numTokens.fetch_add(file_->lexOut_.tokens_.size());
#endif

    return Result::Success;
}

SWC_END_NAMESPACE();
