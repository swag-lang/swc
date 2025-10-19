#pragma once
#include "Lexer.h"

class CompilerContext;
class CompilerInstance;

class SourceFile
{
    friend struct Lexer;

protected:
    fs::path             path_;
    std::vector<uint8_t> content_;
    uint32_t             offsetStartBuffer_ = 0;
    Lexer                lexer_;

    Result checkFormat(CompilerInstance& ci, CompilerContext& ctx);

public:
    explicit SourceFile(fs::path path);
    fs::path                    fullName() const { return path_; }
    const std::vector<uint8_t>& content() const { return content_; }
    const Lexer&                lexer() const { return lexer_; }
    const std::vector<Token>&   tokens() const { return lexer_.tokens; }

    Result loadContent(CompilerInstance& ci, CompilerContext& ctx);
    Result tokenize(CompilerInstance& ci, const CompilerContext& ctx);
};
