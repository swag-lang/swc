#include "pch.h"

#include "Lexer/Lexer.h"
#include "Lexer/SourceFile.h"
#include "Main/CompilerContext.h"
#include "Main/CompilerInstance.h"
#include "Report/Logger.h"
#include "Report/Reporter.h"

Result Lexer::tokenize(CompilerInstance& ci, const CompilerContext& ctx)
{
    const auto  file   = ctx.sourceFile();
    const char* buffer = reinterpret_cast<const char*>(file->content_.data()) + file->offsetStartBuffer_;
    const char* start  = buffer;
    const char* end    = buffer + file->content_.size();

    tokens.reserve(file->content_.size() / 8);
    lines.reserve(file->content_.size() / 80);
    lines.push_back(0);

    while (buffer < end)
    {
        // End of line
        /////////////////////////////////////////
        if (buffer[0] == '\n')
        {
            buffer++;
            lines.push_back(static_cast<uint32_t>(buffer - start));
            continue;
        }

        // Line comment
        /////////////////////////////////////////
        if (buffer[0] == '/' && buffer[1] == '/')
        {
            while (buffer < end && buffer[0] != '\n')
                buffer++;
            continue;
        }

        // Multi-line comment
        /////////////////////////////////////////
        if (buffer[0] == '/' && buffer[1] == '*')
        {
            const auto startComment = buffer;
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
                const auto diag = Reporter::diagnostic();
                const auto elem = diag->addError(DiagnosticId::UnclosedComment);
                elem->setLocation(ctx.sourceFile(), static_cast<uint32_t>(startComment - start), 2);
                ci.diagReporter().report(ci, ctx, *diag);
                return Result::Error;
            }

            continue;
        }

        buffer++;
    }

    return Result::Success;
}
