#include "pch.h"

#include "Lexer/Lexer.h"
#include "Lexer/SourceFile.h"
#include "Main/CompilerContext.h"
#include "Main/CompilerInstance.h"
#include "Report/Reporter.h"

Result Lexer::tokenize(const CompilerInstance& ci, const CompilerContext& ctx)
{
    const auto  file        = ctx.sourceFile();
    const char* buffer      = reinterpret_cast<const char*>(file->content_.data()) + file->offsetStartBuffer_;
    const char* startBuffer = buffer;
    const char* end         = buffer + file->content_.size();

    tokens_.reserve(file->content_.size() / 8);
    lines_.reserve(file->content_.size() / 80);
    lines_.push_back(0);

    while (buffer < end)
    {
        const auto startToken = buffer;
        token_.start          = static_cast<uint32_t>(startToken - startBuffer);
        token_.len            = 1;

        // End of line
        /////////////////////////////////////////
        if (buffer[0] == '\n')
        {
            token_.id = TokenId::Eol;
            buffer++;
            lines_.push_back(static_cast<uint32_t>(buffer - startBuffer));

            while (buffer < end && buffer[0] == '\n')
            {
                buffer++;
                lines_.push_back(static_cast<uint32_t>(buffer - startBuffer));
            }

            token_.len = static_cast<uint32_t>(buffer - startToken);
            tokens_.push_back(token_);
            continue;
        }

        // Line comment
        /////////////////////////////////////////
        if (buffer[0] == '/' && buffer[1] == '/')
        {
            token_.id = TokenId::LineComment;

            while (buffer < end && buffer[0] != '\n')
            {
                token_.len++;
                buffer++;
            }

            token_.len = static_cast<uint32_t>(buffer - startToken);
            tokens_.push_back(token_);
            continue;
        }

        // Multi-line comment
        /////////////////////////////////////////
        if (buffer[0] == '/' && buffer[1] == '*')
        {
            token_.id = TokenId::MultiLineComment;

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

                while (buffer[0] == '*' && buffer[1] == '/')
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
                return Result::Error;
            }

            token_.len = static_cast<uint32_t>(buffer - startToken);
            tokens_.push_back(token_);
            continue;
        }

        // Blanks
        /////////////////////////////////////////
        if (std::isblank(buffer[0]))
        {
            token_.id = TokenId::Blank;
            buffer++;

            while (buffer < end && std::isblank(buffer[0]))
                buffer++;

            token_.len = static_cast<uint32_t>(buffer - startToken);
            tokens_.push_back(token_);
            continue;
        }        

        buffer++;
    }

    return Result::Success;
}
