#pragma once
#include "Lexer/Token.h"

SWC_BEGIN_NAMESPACE()

struct SourceTrivia
{
    TokenRef tokRef; // The last pushed token when the trivia was found
    Token    tok;    // Trivia definition
};

struct SourceIdentifier
{
    uint32_t crc       = 0;
    uint32_t byteStart = 0; // Byte offset in the source file buffer
};

class SourceView
{
    SourceViewRef                 ref_     = SourceViewRef::invalid();
    FileRef                       fileRef_ = FileRef::invalid();
    std::string_view              stringView_;
    std::vector<Token>            tokens_;
    std::vector<uint32_t>         lines_;
    std::vector<SourceTrivia>     trivia_;
    std::vector<uint32_t>         triviaStart_;
    std::vector<SourceIdentifier> identifiers_;
    bool                          mustSkip_ = false;

public:
    SourceView(SourceViewRef ref, const SourceFile* file);

    SourceViewRef                        ref() const { return ref_; }
    FileRef                              fileRef() const { return fileRef_; }
    std::string_view                     stringView() const { return stringView_; }
    const std::vector<SourceTrivia>&     trivia() const { return trivia_; }
    std::vector<SourceTrivia>&           trivia() { return trivia_; }
    const std::vector<Token>&            tokens() const { return tokens_; }
    std::vector<Token>&                  tokens() { return tokens_; }
    const std::vector<uint32_t>&         lines() const { return lines_; }
    std::vector<uint32_t>&               lines() { return lines_; }
    const std::vector<SourceIdentifier>& identifiers() const { return identifiers_; }
    std::vector<SourceIdentifier>&       identifiers() { return identifiers_; }
    const Token&                         token(TokenRef tok) const { return tokens_[tok.get()]; }
    uint32_t                             numTokens() const { return static_cast<uint32_t>(tokens_.size()); }
    const std::vector<uint32_t>&         triviaStart() const { return triviaStart_; }
    std::vector<uint32_t>&               triviaStart() { return triviaStart_; }
    bool                                 mustSkip() const { return mustSkip_; }
    void                                 setMustSkip(bool mustSkip) { mustSkip_ = mustSkip; }

    Utf8                          codeLine(const TaskContext& ctx, uint32_t line) const;
    std::string_view              codeView(uint32_t offset, uint32_t len) const;
    std::pair<uint32_t, uint32_t> triviaRangeForToken(TokenRef tok) const;
    TokenRef                      findRightFrom(TokenRef startRef, std::initializer_list<TokenId> ids) const;
    TokenRef                      findLeftFrom(TokenRef startRef, std::initializer_list<TokenId> ids) const;
};

SWC_END_NAMESPACE()
