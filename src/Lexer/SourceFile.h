#pragma once
#include "Lexer.h"

class CompilerContext;
class CompilerInstance;

class SourceFile
{
    friend class Lexer;
    
protected:
    Fs::path             path_;
    std::vector<uint8_t> content_;
    uint32_t             offsetStartBuffer_ = 0;
    Lexer                lexer_;

    Result checkFormat(CompilerInstance& ci, CompilerContext& ctx);

public:
    explicit SourceFile(Fs::path path);
    Result loadContent(CompilerInstance& ci, CompilerContext& ctx);
    Result tokenize(CompilerInstance& ci, CompilerContext& ctx);
};
