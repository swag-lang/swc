#include "pch.h"

#include "Core/Hash.h"
#include "Core/Timer.h"
#include "Core/Utf8Helper.h"
#include "Lexer/LangSpec.h"
#include "Lexer/Lexer.h"
#include "Lexer/SourceFile.h"
#include "Main/Context.h"
#include "Main/Global.h"
#include "Report/Diagnostic.h"
#include "Report/Stats.h"
#include <ppltasks.h>

SWC_BEGIN_NAMESPACE()

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

void Lexer::reportUtf8Error(DiagnosticId id, uint32_t offset, uint32_t len)
{
    if (hasUtf8Error_)
        return;
    hasUtf8Error_ = true;

    if (rawMode_)
        return;

    const auto diag = Diagnostic::raise(*ctx_, id, ctx_->sourceFile());
    diag.last().setLocation(ctx_->sourceFile(), offset, len);
}

void Lexer::reportTokenError(DiagnosticId id, uint32_t offset, uint32_t len)
{
    if (hasTokenError_)
        return;
    hasTokenError_ = true;

    if (rawMode_)
        return;

    const auto diag = Diagnostic::raise(*ctx_, id, ctx_->sourceFile());
    diag.last().setLocation(ctx_->sourceFile(), offset, len);

    // Add an argument with the token string
    if (len)
    {
        const std::string_view tkn = ctx_->sourceFile()->codeView(offset, len);
        diag.last().addArgument(Diagnostic::ARG_TOK, tkn);
    }
}

void Lexer::eatUtf8Char()
{
    auto [buf, wc, eat] = Utf8Helper::decodeOneChar(buffer_, endBuffer_);
    if (!buf)
    {
        reportTokenError(DiagnosticId::LexFileNotUtf8, static_cast<uint32_t>(buffer_ - startBuffer_));
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
    token_.byteLength = static_cast<uint32_t>(buffer_ - startToken_);

    const TokenId tokenId = token_.id;

    // Update previous token's flags before filtering
    // This must happen even for tokens that will be filtered out
    if (!file_->lexOut_.tokens_.empty())
    {
        auto& back = file_->lexOut_.tokens_.back();
        if (tokenId == TokenId::Blank)
            back.flags |= TokenFlags::BlankAfter;
        else if (tokenId == TokenId::EndOfLine)
            back.flags |= TokenFlags::EolAfter;
    }

    // Update the current token's flags based on the previous token
    const TokenId prevId = prevToken_.id;
    if (prevId == TokenId::Blank)
        token_.flags |= TokenFlags::BlankBefore;
    else if (prevId == TokenId::EndOfLine)
        token_.flags |= TokenFlags::EolBefore;

    // Always update prevToken, even for filtered tokens
    prevToken_ = token_;

    // Use switch for better branch prediction and consolidate similar checks
    switch (tokenId)
    {
    case TokenId::Blank:
    case TokenId::EndOfLine:
        if (rawMode_ || !has_any(lexerFlags_, LexerFlags::ExtractTrivia))
            return;
        file_->lexOut_.trivia_.push_back({.tokenRef = static_cast<uint32_t>(file_->lexOut_.tokens_.size()), .token = token_});
        break;
    case TokenId::CommentLine:
    case TokenId::CommentMultiLine:
        if (!rawMode_ && !has_any(lexerFlags_, LexerFlags::ExtractTrivia))
            return;
        file_->lexOut_.trivia_.push_back({.tokenRef = static_cast<uint32_t>(file_->lexOut_.tokens_.size()), .token = token_});
        break;
    default:
        if (rawMode_)
            return;
        file_->lexOut_.tokens_.push_back(token_);
        break;
    }
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
        reportTokenError(DiagnosticId::LexInvalidEscapeSequence, static_cast<uint32_t>(buffer_ - startBuffer_), 2);

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
                    reportTokenError(DiagnosticId::LexEmptyHexEscape, offset, 2);
                else
                    reportTokenError(DiagnosticId::LexInvalidHexDigit, offset + 2);
            }
            else
                reportTokenError(DiagnosticId::LexIncompleteHexEscape, offset, 2 + actualDigits);

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
            reportTokenError(DiagnosticId::LexFileNotUtf8, static_cast<uint32_t>(buffer_ - startBuffer_));
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
        reportTokenError(DiagnosticId::LexNewlineInStringLiteral, static_cast<uint32_t>(buffer_ - startBuffer_));

    // Handle EOF
    if (buffer_ >= endBuffer_)
        reportTokenError(DiagnosticId::LexUnclosedStringLiteral, static_cast<uint32_t>(startToken_ - startBuffer_));

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
            reportUtf8Error(DiagnosticId::LexFileNotUtf8, static_cast<uint32_t>(buffer_ - startBuffer_));
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
            token_.byteLength = static_cast<uint32_t>(buffer_ - startToken_);
            pushToken();
            return;
        }

        buffer_++;
    }

    // EOF before closing delimiter
    reportTokenError(DiagnosticId::LexUnclosedStringLiteral, static_cast<uint32_t>(startToken_ - startBuffer_), 3);
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
            reportUtf8Error(DiagnosticId::LexFileNotUtf8, static_cast<uint32_t>(buffer_ - startBuffer_));
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
        reportTokenError(DiagnosticId::LexUnclosedStringLiteral, static_cast<uint32_t>(startToken_ - startBuffer_), 2);

    pushToken();
}

void Lexer::lexCharacterLiteral()
{
    token_.id = TokenId::Character;
    buffer_++;

    // Check for empty character literal
    if (buffer_[0] == '\'')
    {
        reportTokenError(DiagnosticId::LexEmptyCharLiteral, static_cast<uint32_t>(startToken_ - startBuffer_), 2);
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
            reportUtf8Error(DiagnosticId::LexFileNotUtf8, static_cast<uint32_t>(buffer_ - startBuffer_));
            buffer_++;
            continue;
        }

        // Check for EOL
        if (buffer_[0] == '\n' || buffer_[0] == '\r')
        {
            reportTokenError(DiagnosticId::LexUnclosedCharLiteral, static_cast<uint32_t>(startToken_ - startBuffer_));
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
        reportTokenError(DiagnosticId::LexUnclosedCharLiteral, static_cast<uint32_t>(startToken_ - startBuffer_));

    // Consume closing quote if present
    if (buffer_[0] == '\'')
        buffer_++;

    // Check for too many characters
    if (charCount > 1)
        reportTokenError(DiagnosticId::LexTooManyCharsInCharLiteral, static_cast<uint32_t>(startToken_ - startBuffer_), static_cast<uint32_t>(buffer_ - startToken_));

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
    while (langSpec_->isHexNumber(buffer_[0]) || langSpec_->isNumberSep(buffer_[0]))
    {
        if (langSpec_->isNumberSep(buffer_[0]))
        {
            if (lastWasSep)
            {
                while (langSpec_->isNumberSep(buffer_[0]))
                    buffer_++;
                reportTokenError(DiagnosticId::LexConsecutiveNumberSeparators, static_cast<uint32_t>(sepStart - startBuffer_), static_cast<uint32_t>(buffer_ - sepStart));
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
        reportTokenError(DiagnosticId::LexMissingHexDigits, static_cast<uint32_t>(startToken_ - startBuffer_), 2 + (lastWasSep ? 1 : 0));

    // No trailing separator
    if (lastWasSep)
        reportTokenError(DiagnosticId::LexTrailingNumberSeparator, static_cast<uint32_t>(buffer_ - startBuffer_ - 1));

    // Letters immediately following the literal
    if (langSpec_->isLetter(buffer_[0]))
        reportTokenError(DiagnosticId::LexInvalidHexDigit, static_cast<uint32_t>(buffer_ - startBuffer_), 1);

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
    while (langSpec_->isBinNumber(buffer_[0]) || langSpec_->isNumberSep(buffer_[0]))
    {
        if (langSpec_->isNumberSep(buffer_[0]))
        {
            if (lastWasSep)
            {
                while (langSpec_->isNumberSep(buffer_[0]))
                    buffer_++;
                reportTokenError(DiagnosticId::LexConsecutiveNumberSeparators, static_cast<uint32_t>(sepStart - startBuffer_), static_cast<uint32_t>(buffer_ - sepStart));
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
        reportTokenError(DiagnosticId::LexMissingBinDigits, static_cast<uint32_t>(startToken_ - startBuffer_), 2 + (lastWasSep ? 1 : 0));

    // No trailing separator
    if (lastWasSep)
        reportTokenError(DiagnosticId::LexTrailingNumberSeparator, static_cast<uint32_t>(buffer_ - startBuffer_ - 1));

    // Letters immediately following the literal
    if (langSpec_->isLetter(buffer_[0]))
        reportTokenError(DiagnosticId::LexInvalidBinDigit, static_cast<uint32_t>(buffer_ - startBuffer_), 1);

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
    while (langSpec_->isDigit(buffer_[0]) || langSpec_->isNumberSep(buffer_[0]))
    {
        if (langSpec_->isNumberSep(buffer_[0]))
        {
            if (lastWasSep)
            {
                while (langSpec_->isNumberSep(buffer_[0]))
                    buffer_++;
                reportTokenError(DiagnosticId::LexConsecutiveNumberSeparators, static_cast<uint32_t>(sepStart - startBuffer_), static_cast<uint32_t>(buffer_ - sepStart));
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
        reportTokenError(DiagnosticId::LexTrailingNumberSeparator, static_cast<uint32_t>(buffer_ - startBuffer_ - 1));

    // Parse decimal part
    if (buffer_[0] == '.')
    {
        hasDot = true;
        buffer_++;
        lastWasSep = false;

        if (langSpec_->isNumberSep(buffer_[0]))
            reportTokenError(DiagnosticId::LexLeadingNumberSeparator, static_cast<uint32_t>(buffer_ - startBuffer_));

        while (buffer_ < endBuffer_ && (langSpec_->isDigit(buffer_[0]) || langSpec_->isNumberSep(buffer_[0])))
        {
            if (langSpec_->isNumberSep(buffer_[0]))
            {
                if (lastWasSep)
                {
                    while (langSpec_->isNumberSep(buffer_[0]))
                        buffer_++;
                    reportTokenError(DiagnosticId::LexConsecutiveNumberSeparators, static_cast<uint32_t>(sepStart - startBuffer_), static_cast<uint32_t>(buffer_ - sepStart));
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

    // Final trailing separator check
    if (lastWasSep)
        reportTokenError(DiagnosticId::LexTrailingNumberSeparator, static_cast<uint32_t>(buffer_ - startBuffer_ - 1));

    // Parse exponent part
    if (buffer_[0] == 'e' || buffer_[0] == 'E')
    {
        hasExp = true;
        buffer_++;

        // Optional sign
        if (buffer_[0] == '+' || buffer_[0] == '-')
            buffer_++;

        if (langSpec_->isNumberSep(buffer_[0]))
            reportTokenError(DiagnosticId::LexLeadingNumberSeparator, static_cast<uint32_t>(buffer_ - startBuffer_));

        uint32_t expDigits = 0;
        lastWasSep         = false;
        while (langSpec_->isDigit(buffer_[0]) || langSpec_->isNumberSep(buffer_[0]))
        {
            if (langSpec_->isNumberSep(buffer_[0]))
            {
                if (lastWasSep)
                {
                    while (langSpec_->isNumberSep(buffer_[0]))
                        buffer_++;
                    reportTokenError(DiagnosticId::LexConsecutiveNumberSeparators, static_cast<uint32_t>(sepStart - startBuffer_), static_cast<uint32_t>(buffer_ - sepStart));
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
            reportTokenError(DiagnosticId::LexMissingExponentDigits, static_cast<uint32_t>(buffer_ - startBuffer_ - 1));

        if (hasExp)
            token_.id = TokenId::NumberFloat;
    }

    // Final trailing separator check
    if (lastWasSep)
        reportTokenError(DiagnosticId::LexTrailingNumberSeparator, static_cast<uint32_t>(buffer_ - startBuffer_ - 1));

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
        reportTokenError(DiagnosticId::LexInvalidNumberSuffix, static_cast<uint32_t>(buffer_ - startBuffer_));
}

void Lexer::lexIdentifier()
{
    // Get identifier name
    buffer_++;
    while (langSpec_->isIdentifierPart(buffer_[0]))
        buffer_++;

    const auto name = std::string_view(reinterpret_cast<std::string_view::const_pointer>(startToken_), buffer_ - startToken_);

    // Is this a keyword?
    const uint64_t hash64 = hash(name);
    token_.id             = ctx_->global().langSpec().keyword(name, hash64);

    if (token_.id == TokenId::Identifier)
    {
        auto idx             = static_cast<uint32_t>(file_->lexOut_.identifiers_.size());
        auto [ptr, inserted] = identifierMap_.try_emplace(name, hash64, idx);
        if (!inserted)
        {
            idx = *ptr;
        }
        else
        {
            SWC_ASSERT(*ptr == idx);
            file_->lexOut_.identifiers_.push_back({.hash = hash64, .byteStart = token_.byteStart});
        }
        token_.byteStart = *ptr;
    }

    pushToken();
}

void Lexer::lexOperator()
{
    // Safe to read buffer_[1] and buffer_[2] due to padding after endBuffer_
    const uint8_t c = buffer_[0];

    switch (c)
    {
    case '\'':
        token_.id = TokenId::SymQuote;
        buffer_++;
        break;

    case '\\':
        token_.id = TokenId::SymBackSlash;
        buffer_++;
        break;

    case '(':
        token_.id = TokenId::SymLeftParen;
        buffer_++;
        break;

    case ')':
        token_.id = TokenId::SymRightParen;
        buffer_++;
        break;

    case '[':
        token_.id = TokenId::SymLeftBracket;
        buffer_++;
        break;

    case ']':
        token_.id = TokenId::SymRightBracket;
        buffer_++;
        break;

    case '{':
        token_.id = TokenId::SymLeftCurly;
        buffer_++;
        break;

    case '}':
        token_.id = TokenId::SymRightCurly;
        buffer_++;
        break;

    case ';':
        token_.id = TokenId::SymSemiColon;
        buffer_++;
        break;

    case ',':
        token_.id = TokenId::SymComma;
        buffer_++;
        break;

    case '@':
        token_.id = TokenId::SymAt;
        buffer_++;
        break;

    case '?':
        token_.id = TokenId::SymQuestion;
        buffer_++;
        break;

    case '~':
        token_.id = TokenId::SymTilde;
        buffer_++;
        break;

    case '=':
        if (buffer_[1] == '=')
        {
            token_.id = TokenId::SymEqualEqual;
            buffer_ += 2;
        }
        else if (buffer_[1] == '>')
        {
            token_.id = TokenId::SymEqualGreater;
            buffer_ += 2;
        }
        else
        {
            token_.id = TokenId::SymEqual;
            buffer_++;
        }
        break;

    case ':':
        token_.id = TokenId::SymColon;
        buffer_++;
        break;

    case '!':
        if (buffer_[1] == '=')
        {
            token_.id = TokenId::SymExclamationEqual;
            buffer_ += 2;
        }
        else
        {
            token_.id = TokenId::SymExclamation;
            buffer_++;
        }
        break;

    case '-':
        if (buffer_[1] == '=')
        {
            token_.id = TokenId::SymMinusEqual;
            buffer_ += 2;
        }
        else if (buffer_[1] == '>')
        {
            token_.id = TokenId::SymMinusGreater;
            buffer_ += 2;
        }
        else if (buffer_[1] == '-')
        {
            token_.id = TokenId::SymMinusMinus;
            buffer_ += 2;
        }
        else
        {
            token_.id = TokenId::SymMinus;
            buffer_++;
        }
        break;

    case '+':
        if (buffer_[1] == '=')
        {
            token_.id = TokenId::SymPlusEqual;
            buffer_ += 2;
        }
        else if (buffer_[1] == '+')
        {
            token_.id = TokenId::SymPlusPlus;
            buffer_ += 2;
        }
        else
        {
            token_.id = TokenId::SymPlus;
            buffer_++;
        }
        break;

    case '*':
        if (buffer_[1] == '=')
        {
            token_.id = TokenId::SymAsteriskEqual;
            buffer_ += 2;
        }
        else
        {
            token_.id = TokenId::SymAsterisk;
            buffer_++;
        }
        break;

    case '/':
        if (buffer_[1] == '=')
        {
            token_.id = TokenId::SymSlashEqual;
            buffer_ += 2;
        }
        else
        {
            token_.id = TokenId::SymSlash;
            buffer_++;
        }
        break;

    case '&':
        if (buffer_[1] == '=')
        {
            token_.id = TokenId::SymAmpersandEqual;
            buffer_ += 2;
        }
        else if (buffer_[1] == '&')
        {
            token_.id = TokenId::SymAmpersandAmpersand;
            buffer_ += 2;
        }
        else
        {
            token_.id = TokenId::SymAmpersand;
            buffer_++;
        }
        break;

    case '|':
        if (buffer_[1] == '=')
        {
            token_.id = TokenId::SymVerticalEqual;
            buffer_ += 2;
        }
        else if (buffer_[1] == '|')
        {
            token_.id = TokenId::SymVerticalVertical;
            buffer_ += 2;
        }
        else
        {
            token_.id = TokenId::SymVertical;
            buffer_++;
        }
        break;

    case '^':
        if (buffer_[1] == '=')
        {
            token_.id = TokenId::SymCircumflexEqual;
            buffer_ += 2;
        }
        else
        {
            token_.id = TokenId::SymCircumflex;
            buffer_++;
        }
        break;

    case '%':
        if (buffer_[1] == '=')
        {
            token_.id = TokenId::SymPercentEqual;
            buffer_ += 2;
        }
        else
        {
            token_.id = TokenId::SymPercent;
            buffer_++;
        }
        break;

    case '.':
        if (buffer_[1] == '.')
        {
            if (buffer_[2] == '.')
            {
                token_.id = TokenId::SymDotDotDot;
                buffer_ += 3;
            }
            else
            {
                token_.id = TokenId::SymDotDot;
                buffer_ += 2;
            }
        }
        else
        {
            token_.id = TokenId::SymDot;
            buffer_++;
        }
        break;

    case '<':
        if (buffer_[1] == '=')
        {
            if (buffer_[2] == '>')
            {
                token_.id = TokenId::SymLowerEqualGreater;
                buffer_ += 3;
            }
            else
            {
                token_.id = TokenId::SymLowerEqual;
                buffer_ += 2;
            }
        }
        else if (buffer_[1] == '<')
        {
            if (buffer_[2] == '=')
            {
                token_.id = TokenId::SymLowerLowerEqual;
                buffer_ += 3;
            }
            else
            {
                token_.id = TokenId::SymLowerLower;
                buffer_ += 2;
            }
        }
        else
        {
            token_.id = TokenId::SymLower;
            buffer_++;
        }
        break;

    case '>':
        if (buffer_[1] == '=')
        {
            token_.id = TokenId::SymGreaterEqual;
            buffer_ += 2;
        }
        else if (buffer_[1] == '>')
        {
            if (buffer_[2] == '=')
            {
                token_.id = TokenId::SymGreaterGreaterEqual;
                buffer_ += 3;
            }
            else
            {
                token_.id = TokenId::SymGreaterGreater;
                buffer_ += 2;
            }
        }
        else
        {
            token_.id = TokenId::SymGreater;
            buffer_++;
        }
        break;

    default:
        eatUtf8Char();
        reportTokenError(DiagnosticId::LexInvalidCharacter, static_cast<uint32_t>(startToken_ - startBuffer_), static_cast<uint32_t>(buffer_ - startToken_));
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
            reportUtf8Error(DiagnosticId::LexFileNotUtf8, static_cast<uint32_t>(buffer_ - startBuffer_));
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
        reportTokenError(DiagnosticId::LexUnclosedComment, static_cast<uint32_t>(startToken_ - startBuffer_), 2);

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
        reportUtf8Error(DiagnosticId::LexFileNotUtf8, 0, 0);
        return;
    }

    startOffset = 0;
}

Result Lexer::tokenizeRaw(Context& ctx)
{
    rawMode_          = true;
    const auto result = tokenize(ctx);
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
        hasTokenError_    = false;
        startToken_       = buffer_;
        token_.byteStart  = static_cast<uint32_t>(startToken_ - startBuffer_);
        token_.byteLength = 1;

        // Check for null byte (invalid UTF-8)
        if (buffer_[0] == '\0')
        {
            reportUtf8Error(DiagnosticId::LexFileNotUtf8, static_cast<uint32_t>(buffer_ - startBuffer_));
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
    token_.id         = TokenId::EndOfFile;
    token_.byteLength = 0;
    file_->lexOut_.tokens_.push_back(token_);

#if SWC_HAS_STATS
    if (!rawMode_)
        Stats::get().numTokens.fetch_add(file_->lexOut_.tokens_.size());
#endif

    return Result::Success;
}

SWC_END_NAMESPACE()
