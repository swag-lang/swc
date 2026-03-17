#pragma once
#include "Compiler/Lexer/Token.h"
#include "Compiler/SourceFile.h"

SWC_BEGIN_NAMESPACE();

namespace Runtime
{
    struct SourceCodeLocation;
}

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

enum class SourceViewFlagsE : uint32_t
{
    Zero       = 0,
    MustSkip   = 1 << 0,
    LexOnly    = 1 << 1,
    SyntaxOnly = 1 << 2,
    SemaOnly   = 1 << 3,
};
using SourceViewFlags = EnumFlags<SourceViewFlagsE>;

class SourceView
{
public:
    SourceView(SourceViewRef ref, const SourceFile* file);
    SourceView(const SourceView&)            = delete;
    SourceView& operator=(const SourceView&) = delete;

    SourceViewRef                        ref() const { return ref_; }
    const SourceFile*                    file() const { return file_; }
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
    bool                                 hasParseFlag(SourceViewFlagsE flag) const { return parseFlags_.has(flag); }
    void                                 addParseFlag(SourceViewFlagsE flag) { parseFlags_.add(flag); }
    void                                 clearParseFlags() { parseFlags_.clear(); }
    bool                                 mustSkip() const { return parseFlags_.has(SourceViewFlagsE::MustSkip); }
    void                                 setMustSkip() { parseFlags_.add(SourceViewFlagsE::MustSkip); }
    bool                                 isLexOnly() const { return parseFlags_.has(SourceViewFlagsE::LexOnly); }
    void                                 setLexOnly() { parseFlags_.add(SourceViewFlagsE::LexOnly); }
    bool                                 isSyntaxOnly() const { return parseFlags_.has(SourceViewFlagsE::SyntaxOnly); }
    void                                 setSyntaxOnly() { parseFlags_.add(SourceViewFlagsE::SyntaxOnly); }
    bool                                 isSemaOnly() const { return parseFlags_.has(SourceViewFlagsE::SemaOnly); }
    void                                 setSemaOnly() { parseFlags_.add(SourceViewFlagsE::SemaOnly); }
    bool                                 runsParser() const { return parseFlags_.hasNot(SourceViewFlagsE::LexOnly); }
    bool                                 runsSema() const { return runsParser() && parseFlags_.hasNot(SourceViewFlagsE::SyntaxOnly); }
    bool                                 runsJit() const { return runsSema() && parseFlags_.hasNot(SourceViewFlagsE::SemaOnly); }
    bool                                 runsNativeArtifact() const { return runsJit(); }
    bool                                 isRuntimeFile() const { return file_ && file_->isRuntime(); }

    SourceCodeRange               tokenCodeRange(const TaskContext& ctx, TokenRef tokRef) const;
    void                          codeRangeFromRuntimeLocation(const TaskContext& ctx, const Runtime::SourceCodeLocation& location, SourceCodeRange& outCodeRange) const;
    std::string_view              tokenString(TokenRef tokRef) const;
    Utf8                          codeLine(const TaskContext& ctx, uint32_t line) const;
    std::string_view              codeView(uint32_t offset, uint32_t len) const;
    std::pair<uint32_t, uint32_t> triviaRangeForToken(TokenRef tok) const;
    TokenRef                      findRightFrom(TokenRef startRef, std::initializer_list<TokenId> ids) const;
    TokenRef                      findLeftFrom(TokenRef startRef, std::initializer_list<TokenId> ids) const;

private:
    SourceViewRef                 ref_     = SourceViewRef::invalid();
    const SourceFile*             file_    = nullptr;
    FileRef                       fileRef_ = FileRef::invalid();
    std::string_view              stringView_;
    std::vector<Token>            tokens_;
    std::vector<uint32_t>         lines_;
    std::vector<SourceTrivia>     trivia_;
    std::vector<uint32_t>         triviaStart_;
    std::vector<SourceIdentifier> identifiers_;
    SourceViewFlags               parseFlags_ = SourceViewFlagsE::Zero;
};

SWC_END_NAMESPACE();
