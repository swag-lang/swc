#include "pch.h"

#include "LangSpec.h"
#include "Lexer/Lexer.h"
#include "Lexer/SourceFile.h"
#include "Main/CompilerContext.h"
#include "Main/CompilerInstance.h"
#include "Report/Diagnostic.h"
#include "Report/DiagnosticIds.h"

// BOM (Byte Order Mark) constants
namespace BOM
{
    constexpr uint8_t UTF8[]     = {0xEF, 0xBB, 0xBF};
    constexpr uint8_t UTF16_BE[] = {0xFE, 0xFF};
    constexpr uint8_t UTF16_LE[] = {0xFF, 0xFE};
    constexpr uint8_t UTF32_BE[] = {0x00, 0x00, 0xFE, 0xFF};
    constexpr uint8_t UTF32_LE[] = {0xFF, 0xFE, 0x00, 0x00};
}

void Lexer::pushToken()
{
    if (!lexerFlags_.has(LEXER_EXTRACT_COMMENTS_MODE) || token_.id == TokenId::Comment)
        tokens_.push_back(token_);
}

void Lexer::reportError(DiagnosticId id, uint32_t offset, uint32_t len) const
{
    if (lexerFlags_.has(LEXER_EXTRACT_COMMENTS_MODE))
        return;

    Diagnostic diag(ctx_->sourceFile());
    const auto elem = diag.addError(id);
    elem->setLocation(ctx_->sourceFile(), offset, len);
    diag.report(*ci_);
}

// Consume exactly one logical EOL (CRLF | CR | LF). Push the next line start.
void Lexer::consumeOneEol()
{
    SWAG_ASSERT(buffer_ < end_);

    if (buffer_[0] == '\r')
    {
        if (buffer_[1] == '\n')
            buffer_ += 2;
        else
            buffer_ += 1;
    }
    else
    {
        SWAG_ASSERT(buffer_[0] == '\n');
        buffer_ += 1;
    }

    lines_.push_back(static_cast<uint32_t>(buffer_ - startBuffer_));
}

void Lexer::parseEol()
{
    token_.id                 = TokenId::Eol;
    const uint8_t* startToken = buffer_;

    // Consume the first logical EOL.
    consumeOneEol();

    // Collapse subsequent EOLs (any mix of CR/LF/CRLF).
    while (buffer_[0] == '\r' || buffer_[0] == '\n')
        consumeOneEol();

    token_.len = static_cast<uint32_t>(buffer_ - startToken);
    pushToken();
}

void Lexer::parseBlank()
{
    token_.id                 = TokenId::Blank;
    const uint8_t* startToken = buffer_;

    buffer_++;

    // Optimized: null terminator will stop the loop
    while (langSpec_->isBlank(buffer_[0]))
        buffer_++;

    token_.len = static_cast<uint32_t>(buffer_ - startToken);
    pushToken();
}

void Lexer::parseSingleLineStringLiteral()
{
    token_.id                 = TokenId::StringLiteral;
    token_.subTokenStringId   = SubTokenStringId::Line;
    const uint8_t* startToken = buffer_;

    buffer_ += 1;

    // Optimized: check for null terminator along with other terminators
    while (buffer_[0] != '"' && buffer_[0] != '\n' && buffer_[0] != '\r' && buffer_[0] != '\0')
    {
        // Escaped char
        if (buffer_[0] == '\\')
        {
            // Safe to read buffer_[1] due to null padding
            if (buffer_[1] == '\0')
            {
                reportError(DiagnosticId::UnclosedStringLiteral, static_cast<uint32_t>(startToken - startBuffer_));
                token_.len = static_cast<uint32_t>(buffer_ - startToken);
                pushToken();
                return;
            }

            // Validate escape sequence
            if (!langSpec_->isEscape(buffer_[1]))
            {
                reportError(DiagnosticId::InvalidEscapeSequence, static_cast<uint32_t>(buffer_ - startBuffer_), 2);
            }

            buffer_ += 2; // skip '\' and escaped char
            continue;
        }

        buffer_ += 1;
    }

    // Handle newline in string literal
    if (buffer_[0] == '\n' || buffer_[0] == '\r')
    {
        const auto errorOffset = static_cast<uint32_t>(buffer_ - startBuffer_);
        reportError(DiagnosticId::StringLiteralEol, errorOffset);
        token_.len = static_cast<uint32_t>(buffer_ - startToken);
        pushToken();
        return;
    }

    // Handle EOF
    if (buffer_[0] == '\0')
    {
        reportError(DiagnosticId::UnclosedStringLiteral, static_cast<uint32_t>(startToken - startBuffer_));
        token_.len = static_cast<uint32_t>(buffer_ - startToken);
        pushToken();
        return;
    }

    buffer_ += 1; // consume closing quote
    token_.len = static_cast<uint32_t>(buffer_ - startToken);
    pushToken();
}

void Lexer::parseMultiLineStringLiteral()
{
    token_.id                 = TokenId::StringLiteral;
    token_.subTokenStringId   = SubTokenStringId::MultiLine;
    const uint8_t* startToken = buffer_;

    buffer_ += 3;

    while (buffer_[0] != '\0')
    {
        // Track line starts for accurate diagnostics later
        if (buffer_[0] == '\n' || buffer_[0] == '\r')
        {
            consumeOneEol();
            continue;
        }

        // Escaped char
        if (buffer_[0] == '\\')
        {
            // Safe to read buffer_[1] due to null padding
            if (buffer_[1] == '\0')
            {
                reportError(DiagnosticId::UnclosedStringLiteral, static_cast<uint32_t>(startToken - startBuffer_), 3);
                token_.len = static_cast<uint32_t>(buffer_ - startToken);
                pushToken();
                return;
            }

            // Validate escape sequence
            if (!langSpec_->isEscape(buffer_[1]))
            {
                reportError(DiagnosticId::InvalidEscapeSequence, static_cast<uint32_t>(buffer_ - startBuffer_), 2);
            }

            buffer_ += 2; // skip '\' and escaped char
            continue;
        }

        // Closing delimiter - safe to read buffer_[1] and buffer_[2] due to null padding
        if (buffer_[0] == '"' && buffer_[1] == '"' && buffer_[2] == '"')
        {
            buffer_ += 3;
            token_.len = static_cast<uint32_t>(buffer_ - startToken);
            pushToken();
            return;
        }

        buffer_++;
    }

    // EOF before closing delimiter
    reportError(DiagnosticId::UnclosedStringLiteral, static_cast<uint32_t>(startToken - startBuffer_), 3);
    token_.len = static_cast<uint32_t>(buffer_ - startToken);
    pushToken();
}

void Lexer::parseRawStringLiteral()
{
    token_.id                 = TokenId::StringLiteral;
    token_.subTokenStringId   = SubTokenStringId::Raw;
    const uint8_t* startToken = buffer_;

    buffer_ += 2;

    bool foundClosing = false;
    // Safe to read buffer_[1] due to null padding
    while (buffer_[0] != '\0')
    {
        if (buffer_[0] == '"' && buffer_[1] == '#')
        {
            buffer_ += 2;
            foundClosing = true;
            break;
        }

        if (buffer_[0] == '\n' || buffer_[0] == '\r')
        {
            consumeOneEol();
            continue;
        }

        buffer_++;
    }

    if (!foundClosing)
    {
        reportError(DiagnosticId::UnclosedStringLiteral, static_cast<uint32_t>(startToken - startBuffer_));
    }

    token_.len = static_cast<uint32_t>(buffer_ - startToken);
    pushToken();
}

void Lexer::parseHexNumber()
{
    token_.subTokenNumberId   = SubTokenNumberId::Hexadecimal;
    const uint8_t* startToken = buffer_;

    buffer_ += 2;

    bool hasError = false;

    if (langSpec_->isNumberSep(buffer_[0]))
    {
        reportError(DiagnosticId::NumberSepStart, static_cast<uint32_t>(buffer_ - startBuffer_));
        hasError = true;
    }

    bool     lastWasSep = false;
    uint32_t digits     = 0;

    // Optimized: null will fail isHexNumber check
    while (langSpec_->isHexNumber(buffer_[0]))
    {
        if (langSpec_->isNumberSep(buffer_[0]))
        {
            if (!hasError && lastWasSep)
            {
                const uint8_t* sepStart = buffer_;
                while (langSpec_->isNumberSep(buffer_[0]))
                    buffer_++;
                reportError(DiagnosticId::NumberSepMulti, static_cast<uint32_t>(sepStart - startBuffer_), static_cast<uint32_t>(buffer_ - sepStart));
                hasError = true;
                continue;
            }

            lastWasSep = true;
            buffer_++;
            continue;
        }

        digits++;
        lastWasSep = false;
        buffer_++;
    }

    // Require at least one digit
    if (!hasError && digits == 0)
    {
        reportError(DiagnosticId::MissingHexDigits, static_cast<uint32_t>(startToken - startBuffer_), 2 + (lastWasSep ? 1 : 0));
        hasError = true;
    }

    // No trailing separator
    if (!hasError && lastWasSep)
    {
        reportError(DiagnosticId::NumberSepEnd, static_cast<uint32_t>(buffer_ - startBuffer_ - 1));
        hasError = true;
    }

    // Letters immediately following the literal
    if (!hasError && langSpec_->isLetter(buffer_[0]))
    {
        reportError(DiagnosticId::SyntaxHexNumber, static_cast<uint32_t>(buffer_ - startBuffer_));
    }

    token_.len = static_cast<uint32_t>(buffer_ - startToken);
    pushToken();
}

void Lexer::parseBinNumber()
{
    token_.subTokenNumberId   = SubTokenNumberId::Binary;
    const uint8_t* startToken = buffer_;

    buffer_ += 2;

    bool hasError = false;

    if (langSpec_->isNumberSep(buffer_[0]))
    {
        reportError(DiagnosticId::NumberSepStart, static_cast<uint32_t>(buffer_ - startBuffer_));
        hasError = true;
    }

    bool     lastWasSep = false;
    uint32_t digits     = 0;

    // Optimized: null will fail the check
    while (buffer_[0] == '0' || buffer_[0] == '1' || langSpec_->isNumberSep(buffer_[0]))
    {
        if (langSpec_->isNumberSep(buffer_[0]))
        {
            if (!hasError && lastWasSep)
            {
                const uint8_t* sepStart = buffer_;
                while (langSpec_->isNumberSep(buffer_[0]))
                    buffer_++;
                reportError(DiagnosticId::NumberSepMulti, static_cast<uint32_t>(sepStart - startBuffer_), static_cast<uint32_t>(buffer_ - sepStart));
                hasError = true;
                continue;
            }

            lastWasSep = true;
            buffer_++;
            continue;
        }

        digits++;
        lastWasSep = false;
        buffer_++;
    }

    // Require at least one digit
    if (!hasError && digits == 0)
    {
        reportError(DiagnosticId::MissingBinDigits, static_cast<uint32_t>(startToken - startBuffer_), 2 + (lastWasSep ? 1 : 0));
        hasError = true;
    }

    // No trailing separator
    if (!hasError && lastWasSep)
    {
        reportError(DiagnosticId::NumberSepEnd, static_cast<uint32_t>(buffer_ - startBuffer_ - 1));
        hasError = true;
    }

    // Letters immediately following the literal
    if (!hasError && langSpec_->isLetter(buffer_[0]))
    {
        reportError(DiagnosticId::SyntaxBinNumber, static_cast<uint32_t>(buffer_ - startBuffer_));
    }

    token_.len = static_cast<uint32_t>(buffer_ - startToken);
    pushToken();
}

void Lexer::parseDecimalNumber()
{
    token_.subTokenNumberId   = SubTokenNumberId::Decimal;
    const uint8_t* startToken = buffer_;

    bool hasError   = false;
    bool lastWasSep = false;
    bool hasDot     = false;
    bool hasExp     = false;

    // Parse integer part - optimized: null will fail the check
    while (langSpec_->isDigit(buffer_[0]) || langSpec_->isNumberSep(buffer_[0]))
    {
        if (langSpec_->isNumberSep(buffer_[0]))
        {
            if (!hasError && lastWasSep)
            {
                const uint8_t* sepStart = buffer_;
                while (langSpec_->isNumberSep(buffer_[0]))
                    buffer_++;
                reportError(DiagnosticId::NumberSepMulti, static_cast<uint32_t>(sepStart - startBuffer_), static_cast<uint32_t>(buffer_ - sepStart));
                hasError = true;
                continue;
            }

            lastWasSep = true;
            buffer_++;
            continue;
        }

        lastWasSep = false;
        buffer_++;
    }

    // Check for trailing separator before the decimal point
    if (!hasError && lastWasSep)
    {
        reportError(DiagnosticId::NumberSepEnd, static_cast<uint32_t>(buffer_ - startBuffer_ - 1));
        hasError = true;
    }

    // Parse decimal part
    if (buffer_[0] == '.')
    {
        // Look ahead to ensure it's not a range operator (..)
        if (buffer_[1] == '.')
        {
            // This is a range operator, stop number parsing
            token_.len = static_cast<uint32_t>(buffer_ - startToken);
            pushToken();
            return;
        }

        hasDot = true;
        buffer_++;
        lastWasSep = false;

        if (langSpec_->isNumberSep(buffer_[0]))
        {
            reportError(DiagnosticId::NumberSepStart, static_cast<uint32_t>(buffer_ - startBuffer_));
            hasError = true;
        }           

        while (langSpec_->isDigit(buffer_[0]) || langSpec_->isNumberSep(buffer_[0]))
        {
            if (langSpec_->isNumberSep(buffer_[0]))
            {
                if (!hasError && lastWasSep)
                {
                    const uint8_t* sepStart = buffer_;
                    while (langSpec_->isNumberSep(buffer_[0]))
                        buffer_++;
                    reportError(DiagnosticId::NumberSepMulti, static_cast<uint32_t>(sepStart - startBuffer_), static_cast<uint32_t>(buffer_ - sepStart));
                    hasError = true;
                    continue;
                }

                lastWasSep = true;
                buffer_++;
                continue;
            }

            lastWasSep = false;
            buffer_++;
        }

        if (hasDot)
            token_.subTokenNumberId = SubTokenNumberId::Float;
    }

    // Parse exponent part
    if (buffer_[0] == 'e' || buffer_[0] == 'E')
    {
        hasExp = true;
        buffer_++;

        // Optional sign
        if (buffer_[0] == '+' || buffer_[0] == '-')
            buffer_++;

        uint32_t expDigits = 0;
        while (langSpec_->isDigit(buffer_[0]))
        {
            expDigits++;
            buffer_++;
        }

        if (expDigits == 0)
        {
            reportError(DiagnosticId::InvalidExponent, static_cast<uint32_t>(buffer_ - startBuffer_ - 1));
        }

        if (hasExp)
            token_.subTokenNumberId = SubTokenNumberId::Float;
    }

    if (langSpec_->isNumberSep(buffer_[0]))
    {
        reportError(DiagnosticId::NumberSepEnd, static_cast<uint32_t>(buffer_ - startBuffer_));
    }

    token_.len = static_cast<uint32_t>(buffer_ - startToken);
    pushToken();
}

void Lexer::parseNumber()
{
    token_.id = TokenId::NumberLiteral;

    // Hexadecimal: 0x or 0X - safe to read buffer_[1] due to null padding
    if (buffer_[0] == '0' && (buffer_[1] == 'x' || buffer_[1] == 'X'))
    {
        parseHexNumber();
        return;
    }

    // Binary: 0b or 0B - safe to read buffer_[1] due to null padding
    if (buffer_[0] == '0' && (buffer_[1] == 'b' || buffer_[1] == 'B'))
    {
        parseBinNumber();
        return;
    }

    // Decimal (including floats)
    parseDecimalNumber();
}

void Lexer::parseIdentifier()
{
    token_.id                 = TokenId::Identifier;
    const uint8_t* startToken = buffer_;

    buffer_++;

    // Optimized: null will fail isIdentifierPart check
    while (langSpec_->isIdentifierPart(buffer_[0]))
        buffer_++;

    token_.len = static_cast<uint32_t>(buffer_ - startToken);

    // Check if this is a keyword
    // This would require a keyword lookup table in langSpec_
    // For now, just push as identifier
    pushToken();
}

void Lexer::parseOperator()
{
    token_.id = TokenId::Operator;

    // Optimized: safe to read buffer_[1] and buffer_[2] due to null padding
    const uint8_t c1 = buffer_[0];
    const uint8_t c2 = buffer_[1];
    const uint8_t c3 = buffer_[2];

    // Three-character operators
    if ((c1 == '<' && c2 == '<' && c3 == '=') || // <<=
        (c1 == '>' && c2 == '>' && c3 == '=') || // >>=
        (c1 == '.' && c2 == '.' && c3 == '.'))   // ...
    {
        buffer_ += 3;
        token_.len = 3;
        pushToken();
        return;
    }

    // Two-character operators
    if ((c1 == '=' && c2 == '=') || // ==
        (c1 == '!' && c2 == '=') || // !=
        (c1 == '<' && c2 == '=') || // <=
        (c1 == '>' && c2 == '=') || // >=
        (c1 == '&' && c2 == '&') || // &&
        (c1 == '|' && c2 == '|') || // ||
        (c1 == '+' && c2 == '=') || // +=
        (c1 == '-' && c2 == '=') || // -=
        (c1 == '*' && c2 == '=') || // *=
        (c1 == '/' && c2 == '=') || // /=
        (c1 == '%' && c2 == '=') || // %=
        (c1 == '&' && c2 == '=') || // &=
        (c1 == '|' && c2 == '=') || // |=
        (c1 == '^' && c2 == '=') || // ^=
        (c1 == '+' && c2 == '+') || // ++
        (c1 == '-' && c2 == '-') || // --
        (c1 == '<' && c2 == '<') || //
        (c1 == '>' && c2 == '>') || // >>
        (c1 == '-' && c2 == '>') || // ->
        (c1 == ':' && c2 == ':') || // ::
        (c1 == '.' && c2 == '.'))   // ..
    {
        buffer_ += 2;
        token_.len = 2;
        pushToken();
        return;
    }

    // Single-character operators and punctuation
    buffer_++;
    token_.len = 1;
    pushToken();
}

void Lexer::parseSingleLineComment()
{
    token_.id                 = TokenId::Comment;
    token_.subTokenCommentId  = SubTokenCommentId::Line;
    const uint8_t* startToken = buffer_;

    // Skip //
    buffer_ += 2;

    // Stop before EOL (LF or CR), do not consume it here.
    // Optimized: null will also stop the loop
    while (buffer_[0] != '\n' && buffer_[0] != '\r' && buffer_[0] != '\0')
        buffer_++;

    token_.len = static_cast<uint32_t>(buffer_ - startToken);
    pushToken();
}

void Lexer::parseMultiLineComment()
{
    token_.id                 = TokenId::Comment;
    token_.subTokenCommentId  = SubTokenCommentId::MultiLine;
    const uint8_t* startToken = buffer_;

    buffer_ += 2;
    uint32_t depth = 1;

    while (buffer_[0] != '\0' && depth > 0)
    {
        if (buffer_[0] == '\n' || buffer_[0] == '\r')
        {
            consumeOneEol();
            continue;
        }

        // Safe to check buffer_[1] due to null padding
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
    {
        reportError(DiagnosticId::UnclosedComment, static_cast<uint32_t>(startToken - startBuffer_), 2);
    }

    token_.len = static_cast<uint32_t>(buffer_ - startToken);
    pushToken();
}

void Lexer::checkFormat(const CompilerInstance& ci, const CompilerContext& ctx, uint32_t& startOffset) const
{
    const auto file    = ctx.sourceFile();
    const auto content = file->content();

    // Ensure we have enough bytes to check
    if (content.size() < 3)
    {
        startOffset = 0;
        return;
    }

    const uint8_t* data = content.data();

    // UTF-8 BOM
    if (content.size() >= 3 &&
        data[0] == BOM::UTF8[0] && data[1] == BOM::UTF8[1] && data[2] == BOM::UTF8[2])
    {
        startOffset = 3;
        return;
    }

    bool badFormat = false;

    // UTF-16 BOMs (2 bytes)
    if (content.size() >= 2)
    {
        if ((data[0] == BOM::UTF16_BE[0] && data[1] == BOM::UTF16_BE[1]) ||
            (data[0] == BOM::UTF16_LE[0] && data[1] == BOM::UTF16_LE[1]))
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
        if ((data[0] == BOM::UTF32_BE[0] && data[1] == BOM::UTF32_BE[1] &&
             data[2] == BOM::UTF32_BE[2] && data[3] == BOM::UTF32_BE[3]) ||
            (data[0] == BOM::UTF32_LE[0] && data[1] == BOM::UTF32_LE[1] &&
             data[2] == BOM::UTF32_LE[2] && data[3] == BOM::UTF32_LE[3]) ||
            (data[0] == 0x2B && data[1] == 0x2F && data[2] == 0x76 &&
             (data[3] == 0x38 || data[3] == 0x39 || data[3] == 0x2B || data[3] == 0x2F)) || // UTF-7
            (data[0] == 0xDD && data[1] == 0x73 && data[2] == 0x66 && data[3] == 0x73) ||   // UTF-EBCDIC
            (data[0] == 0x84 && data[1] == 0x31 && data[2] == 0x95 && data[3] == 0x33))     // GB-18030
        {
            startOffset = 4;
            badFormat   = true;
        }
    }

    if (badFormat)
    {
        reportError(DiagnosticId::FileNotUtf8, 0, 0);
        return;
    }

    startOffset = 0;
}

Result Lexer::tokenize(const CompilerInstance& ci, const CompilerContext& ctx, LexerFlags flags)
{
    tokens_.clear();
    lines_.clear();

    const auto file = ctx.sourceFile();
    langSpec_       = &ci.langSpec();
    ci_             = &ci;
    ctx_            = &ctx;
    lexerFlags_     = flags;

    uint32_t startOffset = 0;
    checkFormat(ci, ctx, startOffset);

    const auto base = file->content().data();
    buffer_         = base + startOffset;
    end_            = base + file->content().size();
    startBuffer_    = base;

    // Reserve space based on file size
    tokens_.reserve(file->content().size() / 8);
    lines_.reserve(file->content().size() / 80);
    lines_.push_back(0);

    while (buffer_ < end_)
    {
        const auto startToken = buffer_;
        token_.start          = static_cast<uint32_t>(startToken - startBuffer_);
        token_.len            = 1;

        // End of line (LF, CRLF, or CR)
        if (buffer_[0] == '\n' || buffer_[0] == '\r')
        {
            parseEol();
            continue;
        }

        // Blanks
        if (langSpec_->isBlank(buffer_[0]))
        {
            parseBlank();
            continue;
        }

        // Number literal
        if (langSpec_->isDigit(buffer_[0]))
        {
            parseNumber();
            continue;
        }

        // String literal (raw) - safe to read buffer_[1] due to null padding
        if (buffer_[0] == '#' && buffer_[1] == '"')
        {
            parseRawStringLiteral();
            continue;
        }

        // String literal (multi-line) - safe to read buffer_[1] and buffer_[2] due to null padding
        if (buffer_[0] == '"' && buffer_[1] == '"' && buffer_[2] == '"')
        {
            parseMultiLineStringLiteral();
            continue;
        }

        // String literal (single-line)
        if (buffer_[0] == '"')
        {
            parseSingleLineStringLiteral();
            continue;
        }

        // Line comment - safe to read buffer_[1] due to null padding
        if (buffer_[0] == '/' && buffer_[1] == '/')
        {
            parseSingleLineComment();
            continue;
        }

        // Multi-line comment - safe to read buffer_[1] due to null padding
        if (buffer_[0] == '/' && buffer_[1] == '*')
        {
            parseMultiLineComment();
            continue;
        }

        // Identifier or keyword
        if (langSpec_->isIdentifierStart(buffer_[0]))
        {
            parseIdentifier();
            continue;
        }

        // Operators and punctuation
        parseOperator();
    }

    return Result::Success;
}
