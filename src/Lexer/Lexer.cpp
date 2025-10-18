#include "pch.h"

#include "Lexer/Lexer.h"
#include "SourceFile.h"

Result Lexer::tokenize(CompilerInstance& ci, CompilerContext& ctx, const SourceFile& file)
{
    const char* buffer = reinterpret_cast<const char*>(file.content_.data()) + file.offsetStartBuffer_;
    const char* end    = buffer + file.content_.size();
    
    tokens_.reserve(file.content_.size() / 8); // Heuristic
    
    while (buffer < end)
    {
        buffer++;
    }

    return Result::Success;
}
