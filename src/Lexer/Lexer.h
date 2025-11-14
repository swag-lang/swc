#pragma once
#include "Lexer/Token.h"

SWC_BEGIN_NAMESPACE()

enum class DiagnosticId;
class Diagnostic;
class TaskContext;
class Global;
class SourceFile;
class LangSpec;

enum class LexerFlagsE : uint32_t
{
    Default,
};
using LexerFlags = EnumFlags<LexerFlagsE>;

struct LexTrivia
{
    TokenRef tokenRef;
    Token    token;
};

struct LexIdentifier
{
    uint64_t hash      = 0;
    uint32_t byteStart = 0; // Byte offset in the source file buffer
};

class LexerOutput
{
protected:
    friend class Lexer;
    const SourceFile*          file_ = nullptr;
    std::string_view           sourceView_;
    std::vector<Token>         tokens_;
    std::vector<LexTrivia>     trivia_;
    std::vector<uint32_t>      lines_;
    std::vector<LexIdentifier> identifiers_;

public:
    const SourceFile*                 file() const { return file_; }
    void                              setFile(const SourceFile* file);
    std::string_view                  sourceView() const { return sourceView_; }
    const std::vector<LexTrivia>&     trivia() const { return trivia_; }
    const std::vector<Token>&         tokens() const { return tokens_; }
    const std::vector<uint32_t>&      lines() const { return lines_; }
    const std::vector<LexIdentifier>& identifiers() const { return identifiers_; }
    const Token&                      token(TokenRef tok) const { return tokens_[tok.get()]; }

    Utf8             codeLine(const TaskContext& ctx, uint32_t line) const;
    std::string_view codeView(uint32_t offset, uint32_t len) const;
};

// Main lexer class - converts source text into tokens
class Lexer
{
    Token token_     = {};
    Token prevToken_ = {};

    LexerOutput*    lexOut_           = nullptr;
    const char8_t*  buffer_           = nullptr;
    const char8_t*  startBuffer_      = nullptr;
    const char8_t*  endBuffer_        = nullptr;
    const char8_t*  startToken_       = nullptr;
    TaskContext*    ctx_              = nullptr;
    const LangSpec* langSpec_         = nullptr;
    LexerFlags      lexerFlags_       = LexerFlagsE::Default;
    uint32_t        startTokenOffset_ = 0;
    bool            hasTokenError_    = false;
    bool            hasUtf8Error_     = false;
    bool            rawMode_          = false;

    static bool isTerminatorAfterEscapeChar(uint8_t c, TokenId container);

    void       eatOne();
    void       eatOneEol();
    void       eatUtf8Char();
    void       pushToken();
    void       raiseUtf8Error(DiagnosticId id, uint32_t offset, uint32_t len = 1);
    Diagnostic reportTokenError(DiagnosticId id, uint32_t offset, uint32_t len = 1);
    void       raiseTokenError(DiagnosticId id, uint32_t offset, uint32_t len = 1);
    void       checkFormat(uint32_t& startOffset);
    void       lexEscape(TokenId containerToken, bool eatEol);

    void lexWhitespace();
    void lexSingleLineStringLiteral();
    void lexMultiLineStringLiteral();
    void lexRawStringLiteral();
    void lexCharacterLiteral();
    void lexHexNumber();
    void lexBinNumber();
    void lexDecimalNumber();
    void lexNumber();
    void lexSymbol();
    void lexIdentifier();
    void lexSingleLineComment();
    void lexMultiLineComment();

public:
    void tokenizeRaw(TaskContext& ctx, LexerOutput& lexOut);
    void tokenize(TaskContext& ctx, LexerOutput& lexOut, LexerFlags flags);
};

SWC_END_NAMESPACE()
