#include "pch.h"

#include "LangSpec.h"
#include "Lexer/Lexer.h"
#include "Lexer/SourceFile.h"
#include "Main/CompilerContext.h"
#include "Main/CompilerInstance.h"
#include "Report/Reporter.h"

const uint8_t* Lexer::parseEol(const uint8_t* buffer, const uint8_t* startBuffer, const uint8_t* end)
{
    token_.id                 = TokenId::Eol;
    const uint8_t* startToken = buffer;

    buffer++;
    lines_.push_back(static_cast<uint32_t>(buffer - startBuffer));

    while (buffer < end && buffer[0] == '\n')
    {
        buffer++;
        lines_.push_back(static_cast<uint32_t>(buffer - startBuffer));
    }

    token_.len = static_cast<uint32_t>(buffer - startToken);
    tokens_.push_back(token_);

    return buffer;
}

const uint8_t* Lexer::parseBlank(const LangSpec& langSpec, const uint8_t* buffer, const uint8_t* startBuffer, const uint8_t* end)
{
    token_.id                 = TokenId::Blank;
    const uint8_t* startToken = buffer;

    buffer++;

    while (buffer < end && langSpec.isBlank(buffer[0]))
        buffer++;

    token_.len = static_cast<uint32_t>(buffer - startToken);
    tokens_.push_back(token_);

    return buffer;
}

const uint8_t* Lexer::parseSingleLineString(const CompilerInstance& ci, const CompilerContext& ctx, const uint8_t* buffer, const uint8_t* startBuffer, const uint8_t* end)
{
    token_.id                 = TokenId::StringLiteral;
    const uint8_t* startToken = buffer;

    buffer++;

    while (buffer < end && buffer[0] != '"')
    {
        if (buffer[0] == '\n' || buffer[0] == '\r')
        {
            Diagnostic diag;
            const auto elem = diag.addError(DiagnosticId::EolInStringLiteral);
            elem->setLocation(ctx.sourceFile(), static_cast<uint32_t>(buffer - startBuffer));
            ci.diagReporter().report(ci, ctx, diag);
            return nullptr;
        }

        // Escape sequence
        if (buffer < end + 1 && buffer[0] == '\\')
            buffer++;
        
        buffer++;
    }

    if (buffer == end)
    {
        Diagnostic diag;
        const auto elem = diag.addError(DiagnosticId::UnclosedStringLiteral);
        elem->setLocation(ctx.sourceFile(), static_cast<uint32_t>(startToken - startBuffer));
        ci.diagReporter().report(ci, ctx, diag);
        return nullptr;
    }

    buffer++;
    token_.len = static_cast<uint32_t>(buffer - startToken);
    tokens_.push_back(token_);

    return buffer;
}

const uint8_t* Lexer::parseSingleLineComment(const uint8_t* buffer, const uint8_t* startBuffer, const uint8_t* end)
{
    token_.id                 = TokenId::LineComment;
    const uint8_t* startToken = buffer;

    while (buffer < end && buffer[0] != '\n')
        buffer++;

    token_.len = static_cast<uint32_t>(buffer - startToken);
    tokens_.push_back(token_);
    return buffer;
}

const uint8_t* Lexer::parseMultiLineComment(const CompilerInstance& ci, const CompilerContext& ctx, const uint8_t* buffer, const uint8_t* startBuffer, const uint8_t* end)
{
    token_.id                 = TokenId::MultiLineComment;
    const uint8_t* startToken = buffer;

    buffer += 2;
    uint32_t depth = 1;

    while (buffer < end && depth > 0)
    {
        // Need two chars to check either "/*" or "*/"
        if (buffer + 1 >= end)
            break;

        if (buffer[0] == '/' && buffer[1] == '*')
        {
            depth++;
            buffer += 2;
            continue;
        }

        if (buffer[0] == '*' && buffer[1] == '/')
        {
            depth--;
            buffer += 2;
            continue;
        }

        buffer++;
    }

    if (depth > 0)
    {
        Diagnostic diag;
        const auto elem = diag.addError(DiagnosticId::UnclosedComment);
        elem->setLocation(ctx.sourceFile(), static_cast<uint32_t>(startToken - startBuffer), 2);
        ci.diagReporter().report(ci, ctx, diag);
        return nullptr;
    }

    token_.len = static_cast<uint32_t>(buffer - startToken);
    tokens_.push_back(token_);
    return buffer;
}

Result Lexer::tokenize(const CompilerInstance& ci, const CompilerContext& ctx)
{
    const auto     file        = ctx.sourceFile();
    const auto     base        = reinterpret_cast<const uint8_t*>(file->content_.data());
    const uint8_t* buffer      = base + file->offsetStartBuffer_;
    const uint8_t* end         = base + file->content_.size();
    const uint8_t* startBuffer = buffer;
    const auto&    langSpec    = ci.langSpec();

    tokens_.reserve(file->content_.size() / 8);
    lines_.reserve(file->content_.size() / 80);
    lines_.push_back(0);

    while (buffer < end)
    {
        const auto startToken = buffer;
        token_.start          = static_cast<uint32_t>(startToken - startBuffer);
        token_.len            = 1;

        // End of line
        if (buffer[0] == '\n')
        {
            buffer = parseEol(buffer, startBuffer, end);
            if (!buffer)
                return Result::Error;
            continue;
        }

        // Blanks
        if (langSpec.isBlank(buffer[0]))
        {
            buffer = parseBlank(langSpec, buffer, startBuffer, end);
            if (!buffer)
                return Result::Error;
            continue;
        }

        // String
        if (buffer[0] == '"')
        {
            buffer = parseSingleLineString(ci, ctx, buffer, startBuffer, end);
            if (!buffer)
                return Result::Error;
            continue;
        }

        // Line comment
        if (buffer[0] == '/' && buffer[1] == '/')
        {
            buffer = parseSingleLineComment(buffer, startBuffer, end);
            if (!buffer)
                return Result::Error;
            continue;
        }

        // Multi-line comment
        if (buffer[0] == '/' && buffer[1] == '*')
        {
            buffer = parseMultiLineComment(ci, ctx, buffer, startBuffer, end);
            if (!buffer)
                return Result::Error;
            continue;
        }

        buffer++;
    }

    return Result::Success;
}
