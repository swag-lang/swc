#pragma once
#include "Lexer/Lexer.h"
#include "Report/Verifier.h"

class CompilerContext;
class CompilerInstance;

class SourceFile
{
    friend class Lexer;

protected:
    fs::path             path_;
    std::vector<uint8_t> content_;
    Verifier             verifier_;
    Lexer                lexer_;

public:
    explicit SourceFile(fs::path path);

    fs::path                    fullName() const { return path_; }
    const std::vector<uint8_t>& content() const { return content_; }
    const Lexer&                lexer() const { return lexer_; }
    const std::vector<Token>&   tokens() const { return lexer_.tokens(); }

    Result      loadContent(const CompilerInstance& ci, const CompilerContext& ctx);
    Result      tokenize(const CompilerInstance& ci, const CompilerContext& ctx);
    std::string codeLine(const CompilerInstance& ci, uint32_t line) const;
};
