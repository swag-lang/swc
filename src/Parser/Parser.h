#pragma once
#include "Lexer/Token.h"
#include "Parser/Ast.h"
#include "Parser/ParserExpect.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

class SourceFile;
class Context;

enum class SkipUntilFlags : uint32_t
{
    Zero      = 0,
    Consume   = 1 << 0,
    EolBefore = 1 << 1,
};
SWC_ENABLE_BITMASK(SkipUntilFlags);

class ParserOutput
{
    Ast ast_;

public:
    Ast&       ast() noexcept { return ast_; }
    const Ast& ast() const noexcept { return ast_; }
};

class Parser
{
    Context*     ctx_        = nullptr;
    SourceFile*  file_       = nullptr;
    Ast*         ast_        = nullptr;
    const Token* firstToken_ = nullptr;
    const Token* curToken_   = nullptr;
    const Token* lastToken_  = nullptr;

    // Be sure that we consume something
    class EnsureConsume
    {
        Parser*      p_;
        const Token* start_;

    public:
        explicit EnsureConsume(Parser& p) :
            p_(&p),
            start_(p.tokPtr())
        {
        }
        ~EnsureConsume()
        {
            if (start_ == p_->tokPtr())
                p_->consume();
        }
    };

    TokenRef consume(TokenId id);
    TokenRef consume();
    bool     consumeIf(TokenId id, TokenRef* result = nullptr);
    TokenRef skip(TokenId id);
    TokenRef skip();

    template<typename... TokenIds>
    bool consumeIfAny(TokenIds... ids)
    {
        if (atEnd())
            return false;
        return ((consumeIf(ids)) || ...);
    }

    TokenRef expect(const ParserExpect& expect) const;
    TokenRef expectAndConsume(const ParserExpect& expect);
    TokenRef expectAndSkip(const ParserExpect& expect);
    TokenRef expectAndConsumeClosing(TokenId openId, TokenRef openRef);
    TokenRef expectAndSkipClosing(TokenId openId, TokenRef openRef);
    void     expectEndStatement();

    TokenRef expect(TokenId id, DiagnosticId d) const { return expect(ParserExpect::one(id, d)); }
    TokenRef expectAndSkip(TokenId id, DiagnosticId d) { return expectAndSkip(ParserExpect::one(id, d)); }
    TokenRef expectAndConsume(TokenId id, DiagnosticId d) { return expectAndConsume(ParserExpect::one(id, d)); }
    TokenRef expectAndConsumeOneOf(std::initializer_list<TokenId> set, DiagnosticId d) { return expectAndConsume(ParserExpect::oneOf(set, d)); }

    const Token* tokPtr() const { return curToken_; }
    const Token& tok() const { return *curToken_; }
    TokenRef     ref() const { return static_cast<TokenRef>(curToken_ - firstToken_); }
    TokenId      id() const { return curToken_->id; }
    bool         is(TokenId id0) const { return curToken_->id == id0; }
    bool         nextIs(TokenId id0) const { return atEnd() ? false : curToken_[1].id == id0; }
    bool         isNot(TokenId nid) const { return curToken_->id != nid; }
    bool         atEnd() const { return curToken_ >= lastToken_; }
    static bool  isValid(TokenRef ref) { return ref != INVALID_REF; }
    static bool  isInvalid(TokenRef ref) { return ref == INVALID_REF; }

    template<typename... TokenIds>
    bool isAny(TokenIds... ids) const
    {
        return ((curToken_->id == ids) || ...);
    }

    AstNodeRef parseSingleType();
    AstNodeRef parseType();

    AstNodeRef parseCallerSingleArg(AstNodeId callerNodeId);
    AstNodeRef parseBlock(AstNodeId blockNodeId, TokenId tokenStartId);

    AstNodeRef parseIdentifier();
    AstNodeRef parseExpression();
    AstNodeRef parseEnum();
    AstNodeRef parseEnumImpl();
    AstNodeRef parseEnumValue();
    AstNodeRef parseTopLevelInstruction();
    AstNodeRef parseImpl();
    AstNodeRef parseFile();

    bool skipTo(std::initializer_list<TokenId> targets, SkipUntilFlags flags = SkipUntilFlags::Zero);
    bool skipAfter(std::initializer_list<TokenId> targets, SkipUntilFlags flags = SkipUntilFlags::Zero);
    bool skip(std::initializer_list<TokenId> targets, SkipUntilFlags flags);

    void       setReportArguments(Diagnostic& diag, const Token& token) const;
    void       setReportExpected(Diagnostic& diag, TokenId expectedTknId) const;
    Diagnostic reportError(DiagnosticId id, const Token& token) const;
    Diagnostic reportExpected(const ParserExpect& expect) const;

public:
    Result parse(Context& ctx);
};

SWC_END_NAMESPACE()
