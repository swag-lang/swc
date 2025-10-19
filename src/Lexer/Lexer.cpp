#include "pch.h"

#include "LangSpec.h"
#include "Lexer/Lexer.h"
#include "Lexer/SourceFile.h"
#include "Main/CompilerContext.h"
#include "Main/CompilerInstance.h"
#include "Report/Reporter.h"

// Consume exactly one logical EOL (CRLF | CR | LF). Push the next line start.
void Lexer::consumeOneEol()
{
    SWAG_ASSERT(buffer_ < end_);

    if (buffer_[0] == '\r')
    {
        if (buffer_ + 1 < end_ && buffer_[1] == '\n')
            buffer_ += 2;
        else
            buffer_ += 1;
    }
    else if (buffer_[0] == '\n')
    {
        buffer_ += 1;
    }

    lines_.push_back(static_cast<uint32_t>(buffer_ - startBuffer_));
}

Result Lexer::parseEol()
{
    token_.id                 = TokenId::Eol;
    const uint8_t* startToken = buffer_;

    // Consume the first logical EOL.
    consumeOneEol();

    // Collapse subsequent EOLs (any mix of CR/LF/CRLF).
    while (buffer_ < end_ && langSpec_->isEol(buffer_[0]))
        consumeOneEol();

    token_.len = static_cast<uint32_t>(buffer_ - startToken);
    tokens_.push_back(token_);
    return Result::Success;
}

Result Lexer::parseBlank()
{
    token_.id                 = TokenId::Blank;
    const uint8_t* startToken = buffer_;

    buffer_++;

    while (buffer_ < end_ && langSpec_->isBlank(buffer_[0]))
        buffer_++;

    token_.len = static_cast<uint32_t>(buffer_ - startToken);
    tokens_.push_back(token_);
    return Result::Success;
}

Result Lexer::parseSingleLineStringLiteral()
{
    token_.id                 = TokenId::StringLiteral;
    token_.subTokenStringId   = SubTokenStringId::LineString;
    const uint8_t* startToken = buffer_;

    buffer_ += 1; // skip opening '"'

    while (buffer_ < end_)
    {
        const uint8_t c = buffer_[0];

        if (c == '"')
            break;

        if (c == '\n' || c == '\r')
        {
            Diagnostic diag;
            const auto elem = diag.addError(DiagnosticId::EolInStringLiteral);
            elem->setLocation(ctx_->sourceFile(), static_cast<uint32_t>(buffer_ - startBuffer_));
            ci_->diagReporter().report(*ci_, *ctx_, diag);
            return Result::Error;
        }

        if (c == '\\')
        {
            // Need one more char to escape
            if (buffer_ + 1 >= end_)
            {
                Diagnostic diag;
                const auto elem = diag.addError(DiagnosticId::UnclosedStringLiteral);
                elem->setLocation(ctx_->sourceFile(), static_cast<uint32_t>(startToken - startBuffer_));
                ci_->diagReporter().report(*ci_, *ctx_, diag);
                return Result::Error;
            }

            buffer_ += 2; // skip '\' and escaped char
            continue;
        }

        buffer_ += 1;
    }

    if (buffer_ == end_)
    {
        Diagnostic diag;
        const auto elem = diag.addError(DiagnosticId::UnclosedStringLiteral);
        elem->setLocation(ctx_->sourceFile(), static_cast<uint32_t>(startToken - startBuffer_));
        ci_->diagReporter().report(*ci_, *ctx_, diag);
        return Result::Error;
    }

    buffer_ += 1; // consume closing '"'
    token_.len = static_cast<uint32_t>(buffer_ - startToken);
    tokens_.push_back(token_);
    return Result::Success;
}

Result Lexer::parseMultiLineStringLiteral()
{
    token_.id                 = TokenId::StringLiteral;
    token_.subTokenStringId   = SubTokenStringId::MultiLineString;
    const uint8_t* startToken = buffer_;

    // Precondition: tokenizer checked for starting '"""'
    buffer_ += 3;

    while (buffer_ < end_)
    {
        // Track line starts for accurate diagnostics later
        if (langSpec_->isEol(buffer_[0]))
        {
            consumeOneEol();
            continue;
        }

        // Support escaping inside multi-line strings
        if (*buffer_ == '\\')
        {
            if (buffer_ + 1 >= end_)
                break; // will report unclosed below
            buffer_ += 2;
            continue;
        }

        // Closing delimiter
        if (buffer_ + 2 < end_ && buffer_[0] == '"' && buffer_[1] == '"' && buffer_[2] == '"')
        {
            buffer_ += 3;
            token_.len = static_cast<uint32_t>(buffer_ - startToken);
            tokens_.push_back(token_);
            return Result::Success;
        }

        buffer_++;
    }

    // EOF before closing delimiter
    Diagnostic diag;
    const auto elem = diag.addError(DiagnosticId::UnclosedStringLiteral);
    elem->setLocation(ctx_->sourceFile(), static_cast<uint32_t>(startToken - startBuffer_));
    ci_->diagReporter().report(*ci_, *ctx_, diag);

    return Result::Error;
}

Result Lexer::parseRawStringLiteral()
{
    token_.id                 = TokenId::StringLiteral;
    token_.subTokenStringId   = SubTokenStringId::RawString;
    const uint8_t* startToken = buffer_;

    // Opening is #"
    buffer_ += 2;

    while (buffer_ < end_ - 1 && (buffer_[0] != '"' || buffer_[1] != '#'))
    {
        if (langSpec_->isEol(buffer_[0]))
        {
            consumeOneEol();
            continue;
        }

        buffer_++;
    }

    if (buffer_ >= end_ - 1)
    {
        Diagnostic diag;
        const auto elem = diag.addError(DiagnosticId::UnclosedStringLiteral);
        elem->setLocation(ctx_->sourceFile(), static_cast<uint32_t>(startToken - startBuffer_));
        ci_->diagReporter().report(*ci_, *ctx_, diag);
        return Result::Error;
    }

    // Consume closing "#"
    buffer_ += 2;
    token_.len = static_cast<uint32_t>(buffer_ - startToken);
    tokens_.push_back(token_);

    return Result::Success;
}

Result Lexer::parseHexNumber()
{
    token_.subTokenNumberId   = SubTokenNumberId::Hexadecimal;
    const uint8_t* startToken = buffer_;

    buffer_ += 2;

    bool     lastWasSep = true;
    uint32_t digits     = 0;
    while (langSpec_->isHexNumber(buffer_[0]))
    {
        if (langSpec_->isNumberSep(buffer_[0]))
        {
            if (lastWasSep)
            {
                Diagnostic diag;
                const auto elem = diag.addError(DiagnosticId::SyntaxNumberSepMulti);
                elem->setLocation(ctx_->sourceFile(), static_cast<uint32_t>(buffer_ - startBuffer_));
                ci_->diagReporter().report(*ci_, *ctx_, diag);
                return Result::Error;
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
    if (digits == 0)
    {
        Diagnostic diag;
        const auto elem = diag.addError(DiagnosticId::SyntaxMissingHexDigits);
        elem->setLocation(ctx_->sourceFile(), static_cast<uint32_t>(startToken - startBuffer_));
        ci_->diagReporter().report(*ci_, *ctx_, diag);
        return Result::Error;
    }    

    // No trailing separator
    if (lastWasSep)
    {
        Diagnostic diag;
        const auto elem = diag.addError(DiagnosticId::SyntaxNumberSepAtEnd);
        elem->setLocation(ctx_->sourceFile(), static_cast<uint32_t>(buffer_ - startBuffer_ - 1));
        ci_->diagReporter().report(*ci_, *ctx_, diag);
        return Result::Error;
    }

    // Letters immediately following the literal
    if (buffer_ < end_ && langSpec_->isLetter(buffer_[0]))
    {
        Diagnostic diag;
        const auto elem = diag.addError(DiagnosticId::SyntaxMalformedHexNumber);
        elem->setLocation(ctx_->sourceFile(), static_cast<uint32_t>(buffer_ - startBuffer_));
        ci_->diagReporter().report(*ci_, *ctx_, diag);
        return Result::Error;
    }

    token_.len = static_cast<uint32_t>(buffer_ - startToken);
    tokens_.push_back(token_);
    return Result::Success;
}

Result Lexer::parseBinNumber()
{
    token_.subTokenNumberId = SubTokenNumberId::Binary;
    buffer_ += 2;

    return Result::Success;
}

Result Lexer::parseNumber()
{
    token_.id = TokenId::NumberLiteral;

    if (buffer_[0] == '0' && buffer_ + 1 < end_ && (buffer_[1] == 'x' || buffer_[1] == 'X'))
    {
        SWAG_CHECK(parseHexNumber());
        return Result::Success;
    }

    if (buffer_[0] == '0' && buffer_ + 1 < end_ && (buffer_[1] == 'b' || buffer_[1] == 'B'))
    {
        SWAG_CHECK(parseBinNumber());
        return Result::Success;
    }

    buffer_++;
    return Result::Success;
}

Result Lexer::parseSingleLineComment()
{
    token_.id                 = TokenId::LineComment;
    const uint8_t* startToken = buffer_;

    // Stop before EOL (LF or CR), do not consume it here.
    while (buffer_ < end_ && buffer_[0] != '\n' && buffer_[0] != '\r')
        buffer_++;

    token_.len = static_cast<uint32_t>(buffer_ - startToken);
    tokens_.push_back(token_);
    return Result::Success;
}

Result Lexer::parseMultiLineComment()
{
    token_.id                 = TokenId::MultiLineComment;
    const uint8_t* startToken = buffer_;

    buffer_ += 2;
    uint32_t depth = 1;

    while (buffer_ < end_ && depth > 0)
    {
        if (langSpec_->isEol(buffer_[0]))
        {
            consumeOneEol();
            continue;
        }

        // Need two chars to check either "/*" or "*/"
        if (buffer_ + 1 >= end_)
            break;

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
        Diagnostic diag;
        const auto elem = diag.addError(DiagnosticId::UnclosedComment);
        elem->setLocation(ctx_->sourceFile(), static_cast<uint32_t>(startToken - startBuffer_), 2);
        ci_->diagReporter().report(*ci_, *ctx_, diag);
        return Result::Error;
    }

    token_.len = static_cast<uint32_t>(buffer_ - startToken);
    tokens_.push_back(token_);
    return Result::Success;
}

Result Lexer::tokenize(const CompilerInstance& ci, const CompilerContext& ctx)
{
    const auto file = ctx.sourceFile();
    langSpec_       = &ci.langSpec();
    ci_             = &ci;
    ctx_            = &ctx;

    const auto base = reinterpret_cast<const uint8_t*>(file->content_.data());
    buffer_         = base + file->offsetStartBuffer_;
    end_            = base + file->content_.size();
    startBuffer_    = buffer_;

    tokens_.reserve(file->content_.size() / 8);
    lines_.reserve(file->content_.size() / 80);
    lines_.push_back(0);

    while (buffer_ < end_)
    {
        const auto startToken = buffer_;
        token_.start          = static_cast<uint32_t>(startToken - startBuffer_);
        token_.len            = 1;

        // End of line (LF, CRLF, or CR)
        if (langSpec_->isEol(buffer_[0]))
        {
            SWAG_CHECK(parseEol());
            continue;
        }

        // Blanks
        if (langSpec_->isBlank(buffer_[0]))
        {
            SWAG_CHECK(parseBlank());
            continue;
        }

        // Number literal
        if (langSpec_->isDigit(buffer_[0]))
        {
            SWAG_CHECK(parseNumber());
            continue;
        }

        // String literal
        if (buffer_ + 1 < end_ && buffer_[0] == '#' && buffer_[1] == '"')
        {
            SWAG_CHECK(parseRawStringLiteral());
            continue;
        }

        if (buffer_ + 2 < end_ && buffer_[0] == '"' && buffer_[1] == '"' && buffer_[2] == '"')
        {
            SWAG_CHECK(parseMultiLineStringLiteral());
            continue;
        }

        if (buffer_[0] == '"')
        {
            SWAG_CHECK(parseSingleLineStringLiteral());
            continue;
        }

        // Line comment
        if (buffer_ + 1 < end_ && buffer_[0] == '/' && buffer_[1] == '/')
        {
            SWAG_CHECK(parseSingleLineComment());
            continue;
        }

        // Multi-line comment
        if (buffer_ + 1 < end_ && buffer_[0] == '/' && buffer_[1] == '*')
        {
            SWAG_CHECK(parseMultiLineComment());
            continue;
        }

        buffer_++;
    }

    return Result::Success;
}
