#include "pch.h"

#include "LangSpec.h"
#include "Lexer/Lexer.h"
#include "Lexer/SourceFile.h"
#include "Main/CompilerContext.h"
#include "Main/CompilerInstance.h"
#include "Report/Reporter.h"

Result Lexer::parseEol()
{
    token_.id                 = TokenId::Eol;
    const uint8_t* startToken = buffer_;

    // First EOL (handle CRLF and lone CR/LF)
    if (buffer_[0] == '\r' && buffer_ + 1 < end_ && buffer_[1] == '\n')
    {
        buffer_ += 2;
        lines_.push_back(static_cast<uint32_t>(buffer_ - startBuffer_));
    }
    else if (buffer_[0] == '\r' || buffer_[0] == '\n')
    {
        buffer_ += 1;
        lines_.push_back(static_cast<uint32_t>(buffer_ - startBuffer_));
    }

    // Collapse subsequent EOLs (any mix of CR/LF/CRLF)
    while (buffer_ < end_)
    {
        if (buffer_[0] == '\r' && buffer_ + 1 < end_ && buffer_[1] == '\n')
        {
            buffer_ += 2;
            lines_.push_back(static_cast<uint32_t>(buffer_ - startBuffer_));
        }
        else if (buffer_[0] == '\r' || buffer_[0] == '\n')
        {
            buffer_ += 1;
            lines_.push_back(static_cast<uint32_t>(buffer_ - startBuffer_));
        }
        else
        {
            break;
        }
    }

    token_.len = static_cast<uint32_t>(buffer_ - startToken);
    tokens_.push_back(token_);
    return Result::Success;
}

Result Lexer::parseBlank(const LangSpec& langSpec)
{
    token_.id                 = TokenId::Blank;
    const uint8_t* startToken = buffer_;

    buffer_++;

    while (buffer_ < end_ && langSpec.isBlank(buffer_[0]))
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
        if (*buffer_ == '\n')
        {
            buffer_++;
            lines_.push_back(static_cast<uint32_t>(buffer_ - startBuffer_));
            continue;
        }

        // Optional: support escaping inside multi-line strings
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

    buffer_ += 2;

    while (buffer_ < end_ - 1 && (buffer_[0] != '"' || buffer_[1] != '#'))
    {
        if (*buffer_ == '\n')
        {
            buffer_++;
            lines_.push_back(static_cast<uint32_t>(buffer_ - startBuffer_));
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

    buffer_ += 2;
    token_.len = static_cast<uint32_t>(buffer_ - startToken);
    tokens_.push_back(token_);

    return Result::Success;
}

Result Lexer::parseSingleLineComment()
{
    token_.id                 = TokenId::LineComment;
    const uint8_t* startToken = buffer_;

    while (buffer_ < end_ && buffer_[0] != '\n')
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
        if (*buffer_ == '\n')
        {
            buffer_++;
            lines_.push_back(static_cast<uint32_t>(buffer_ - startBuffer_));
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
    const auto  file     = ctx.sourceFile();
    const auto& langSpec = ci.langSpec();
    ci_                  = &ci;
    ctx_                 = &ctx;

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

        // End of line
        if (buffer_[0] == '\n')
        {
            SWAG_CHECK(parseEol());
            continue;
        }

        // Blanks
        if (langSpec.isBlank(buffer_[0]))
        {
            SWAG_CHECK(parseBlank(langSpec));
            continue;
        }

        // String
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
        if (buffer_  + 1 < end_ && buffer_[0] == '/' && buffer_[1] == '*')
        {
            SWAG_CHECK(parseMultiLineComment());
            continue;
        }

        buffer_++;
    }

    return Result::Success;
}
