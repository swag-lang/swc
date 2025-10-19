#pragma once
#include "Lexer/Lexer.h"
#include "Report/Verifier.h"

class CompilerContext;
class CompilerInstance;

class SourceFile
{
    fs::path path_;

private:
    std::vector<uint8_t> content_;
    Verifier             verifier_;
    Lexer                lexer_;

public:
    explicit SourceFile(fs::path path);

    fs::path                    path() const { return path_; }
    const std::vector<uint8_t>& content() const { return content_; }
    Lexer&                      lexer() { return lexer_; }
    Verifier&                   verifier() { return verifier_; }
    const Lexer&                lexer() const { return lexer_; }
    const Verifier&             verifier() const { return verifier_; }
    const std::vector<Token>&   tokens() const { return lexer_.tokens(); }

    Result loadContent(const CompilerInstance& ci, const CompilerContext& ctx);
    Result tokenize(const CompilerInstance& ci, const CompilerContext& ctx);
    Utf8   codeLine(const CompilerInstance& ci, uint32_t line) const;
};
