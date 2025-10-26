#pragma once
#include "Core/Types.h"
#include "Lexer/Lexer.h"
#include "Parser/Parser.h"
#include "Report/UnitTest.h"

SWC_BEGIN_NAMESPACE();

class Context;
class Global;

class SourceFile
{
    // Number of '\0' forced at the end of the file
    static constexpr int TRAILING_0 = 4;

    FileRef              ref_ = INVALID_REF;
    fs::path             path_;
    std::vector<uint8_t> content_;
    UnitTest             verifier_;

    bool hasError_   = false;
    bool hasWarning_ = false;

protected:
    friend class Lexer;
    friend class Parser;
    LexerOutput  lexOut_;
    ParserOutput parserOut_;

public:
    explicit SourceFile(fs::path path);

    fs::path                    path() const { return path_; }
    const std::vector<uint8_t>& content() const { return content_; }
    size_t                      size() const { return content_.size() - TRAILING_0; }
    const LexerOutput&          lexOut() const { return lexOut_; }
    const ParserOutput&         parserOut() const { return parserOut_; }
    UnitTest&                   verifier() { return verifier_; }
    const UnitTest&             verifier() const { return verifier_; }
    bool                        hasError() const { return hasError_; }
    void                        setHasError() { hasError_ = true; }
    void                        setHasWarning() { hasWarning_ = true; }
    FileRef                     ref() const { return ref_; }

    Result           loadContent(const Context& ctx);
    Result           tokenize(Context& ctx);
    Utf8             codeLine(const Context& ctx, uint32_t line) const;
    std::string_view codeView(uint32_t offset, uint32_t len) const;
};

SWC_END_NAMESPACE();
