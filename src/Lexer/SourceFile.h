#pragma once
#include "Lexer/Lexer.h"
#include "Report/UnitTest.h"

class CompilerContext;
class CompilerInstance;

class SourceFile
{
    static constexpr int TRAILING_0 = 4; // Number of '\0' forced at the end of the file

    fs::path             path_;
    std::vector<uint8_t> content_;
    UnitTest             verifier_;
    Lexer                lexer_;

public:
    explicit SourceFile(const fs::path& path);

    fs::path                    path() const { return path_; }
    const std::vector<uint8_t>& content() const { return content_; }
    size_t                      size() const { return content_.size() - TRAILING_0; }
    Lexer&                      lexer() { return lexer_; }
    UnitTest&                   verifier() { return verifier_; }
    const Lexer&                lexer() const { return lexer_; }
    const UnitTest&             verifier() const { return verifier_; }
    const std::vector<Token>&   tokens() const { return lexer_.tokens(); }

    Result           loadContent(CompilerContext& ctx);
    Result           tokenize(CompilerContext& ctx);
    Utf8             codeLine(uint32_t line) const;
    std::string_view codeView(uint32_t offset, uint32_t len) const;
};
