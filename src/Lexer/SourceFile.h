#pragma once
#include "Lexer/Lexer.h"
#include "Report/UnitTest.h"

class CompilerContext;
class CompilerInstance;

class SourceFile
{
    fs::path path_;

private:
    std::vector<uint8_t> content_;
    UnitTest             verifier_;
    Lexer                lexer_;

public:
    explicit SourceFile(const fs::path& path);

    fs::path                    path() const { return path_; }
    const std::vector<uint8_t>& content() const { return content_; }
    Lexer&                      lexer() { return lexer_; }
    UnitTest&                   verifier() { return verifier_; }
    const Lexer&                lexer() const { return lexer_; }
    const UnitTest&             verifier() const { return verifier_; }
    const std::vector<Token>&   tokens() const { return lexer_.tokens(); }

    Result loadContent(CompilerContext& ctx);
    Result tokenize(CompilerContext& ctx);
    Utf8   codeLine(CompilerContext& ctx, uint32_t line) const;
};
