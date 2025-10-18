#include "pch.h"

#include "Lexer/Lexer.h"
#include "Lexer/SourceFile.h"
#include "Main/CompilerContext.h"

Result Lexer::tokenize(CompilerInstance& ci, const CompilerContext& ctx)
{
    const auto file = ctx.sourceFile();
    const char* buffer = reinterpret_cast<const char*>(file->content_.data()) + file->offsetStartBuffer_;
    const char* end    = buffer + file->content_.size();
    
    tokens_.reserve(file->content_.size() / 8); // Heuristic
    
    while (buffer < end)
    {
        buffer++;
    }

    return Result::Success;
}
