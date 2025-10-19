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
    const char* end    = buffer + file->content_.size();

    tokens_.reserve(file->content_.size() / 8); // Heuristic

    while (buffer < end)
    {
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
                const auto elem = diag->addElement(DiagnosticKind::Error, DiagnosticId::UnclosedComment);
                ci.diagReporter().report(ci, ctx, *diag);
                return Result::Error;           
            }
            
            continue;
        }

        buffer++;
    }

    return Result::Success;
}
