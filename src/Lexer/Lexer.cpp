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

    buffer_++;
    lines_.push_back(static_cast<uint32_t>(buffer_ - startBuffer_));

    while (buffer_ < end_ && buffer_[0] == '\n')
    {
        buffer_++;
        lines_.push_back(static_cast<uint32_t>(buffer_ - startBuffer_));
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

    buffer_ += 1;

    while (buffer_ < end_ && buffer_[0] != '"')
    {
        if (buffer_[0] == '\n' || buffer_[0] == '\r')
        {
            Diagnostic diag;
            const auto elem = diag.addError(DiagnosticId::EolInStringLiteral);
            elem->setLocation(ctx_->sourceFile(), static_cast<uint32_t>(buffer_ - startBuffer_));
            ci_->diagReporter().report(*ci_, *ctx_, diag);
            return Result::Error;
        }

        // Escape sequence
        if (buffer_ < end_ + 1 && buffer_[0] == '\\')
            buffer_++;

        buffer_++;
    }

    if (buffer_ == end_)
    {
        Diagnostic diag;
        const auto elem = diag.addError(DiagnosticId::UnclosedStringLiteral);
        elem->setLocation(ctx_->sourceFile(), static_cast<uint32_t>(startToken - startBuffer_));
        ci_->diagReporter().report(*ci_, *ctx_, diag);
        return Result::Error;
    }

    buffer_++;
    token_.len = static_cast<uint32_t>(buffer_ - startToken);
    tokens_.push_back(token_);

    return Result::Success;
}

Result Lexer::parseMultiLineStringLiteral()
{
    token_.id                 = TokenId::StringLiteral;
    token_.subTokenStringId   = SubTokenStringId::MultiLineString;
    const uint8_t* startToken = buffer_;

    return Result::Success;
}

Result Lexer::parseRawStringLiteral()
{
    token_.id                 = TokenId::StringLiteral;
    token_.subTokenStringId   = SubTokenStringId::RawString;
    const uint8_t* startToken = buffer_;

    buffer_ += 2;

    while (buffer_ < end_ - 1 && (buffer_[0] != '"' || buffer_[1] != '#'))
    {
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
            if (!buffer_)
                return Result::Error;
            continue;
        }

        // Blanks
        if (langSpec.isBlank(buffer_[0]))
        {
            SWAG_CHECK(parseBlank(langSpec));
            if (!buffer_)
                return Result::Error;
            continue;
        }

        // String
        if (buffer_ < end_ - 1 && buffer_[0] == '#' && buffer_[1] == '"')
        {
            SWAG_CHECK(parseRawStringLiteral());
            continue;
        }

        if (buffer_ < end_ - 2 && buffer_[0] == '"' && buffer_[1] == '"' && buffer_[2] == '"')
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
        if (buffer_ < end_ - 1 && buffer_[0] == '/' && buffer_[1] == '/')
        {
            SWAG_CHECK(parseSingleLineComment());
            continue;
        }

        // Multi-line comment
        if (buffer_ < end_ - 1 && buffer_[0] == '/' && buffer_[1] == '*')
        {
            SWAG_CHECK(parseMultiLineComment());
            continue;
        }

        buffer_++;
    }

    return Result::Success;
}
