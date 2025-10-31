#pragma once
#include "Lexer/Token.h"
#include "Parser/Ast.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

class SourceFile;
class Context;

enum class SkipUntilFlags : uint32_t
{
    Zero    = 0,
    Consume = 1 << 0,
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
                p_->consumeOne();
        }
    };

    const Token* lastNonTrivia() const;
    TokenRef     consumeOne();
    TokenRef     consume();
    bool         consumeIf(TokenId id, TokenRef* result = nullptr);
    void         skipTrivia();
    void         skipTriviaAndEol();
    void         consumeTrivia();

    template<typename... TokenIds>
    bool consumeIfAny(TokenIds... ids)
    {
        if (atEnd())
            return false;
        return ((consumeIf(ids)) || ...);
    }

    struct Expect
    {
        TokenId              oneTok     = TokenId::Invalid;
        SmallVector<TokenId> manyTok    = {};
        DiagnosticId         diag       = DiagnosticId::ParserExpectedToken;
        DiagnosticId         becauseCtx = DiagnosticId::None;

        bool valid(TokenId id) const
        {
            const bool ok = manyTok.empty() ? (id == oneTok) : std::ranges::find(manyTok, id) != manyTok.end();
            return ok;
        }

        static Expect one(TokenId tok, DiagnosticId d = DiagnosticId::ParserExpectedToken)
        {
            Expect s;
            s.oneTok = tok;
            s.diag   = d;
            return s;
        }

        static Expect oneOf(std::initializer_list<TokenId> set, DiagnosticId d = DiagnosticId::ParserExpectedToken)
        {
            Expect s;
            s.manyTok = set;
            s.diag    = d;
            return s;
        }

        Expect& because(DiagnosticId b)
        {
            becauseCtx = b;
            return *this;
        }
    };

    TokenRef expect(const Expect& expect) const;
    TokenRef expectAndConsume(const Expect& expect);
    TokenRef expectAndConsumeSingle(const Expect& expect);

    TokenRef expect(TokenId id, DiagnosticId d) const { return expect(Expect::one(id, d)); }
    TokenRef expectAndConsume(TokenId id, DiagnosticId d) { return expectAndConsume(Expect::one(id, d)); }
    TokenRef expectAndConsumeSingle(TokenId id, DiagnosticId d) { return expectAndConsumeSingle(Expect::one(id, d)); }
    TokenRef expectAndConsumeOneOf(std::initializer_list<TokenId> set, DiagnosticId d) { return expectAndConsume(Expect::oneOf(set, d)); }

    const Token* tokPtr() const { return curToken_; }
    const Token& tok() const { return *curToken_; }
    TokenRef     ref() const { return static_cast<TokenRef>(curToken_ - firstToken_) + 1; }
    TokenId      id() const { return curToken_->id; }
    bool         is(TokenId id0) const { return curToken_->id == id0; }
    bool         isNot(TokenId nid) const { return curToken_->id != nid; }
    bool         atEnd() const { return curToken_ >= lastToken_; }
    static bool  isInvalid(TokenRef ref) { return ref == INVALID_REF; }

    template<typename... TokenIds>
    bool isAny(TokenIds... ids) const
    {
        return ((curToken_->id == ids) || ...);
    }

    AstNodeRef parseSingleType();
    AstNodeRef parseType();

    AstNodeRef parseExpression();
    AstNodeRef parseEnum();
    AstNodeRef parseEnumValue();
    AstNodeRef parseTopLevelInstruction();
    AstNodeRef parseBlock(AstNodeId blockId, TokenId blockTokenEnd);
    AstNodeRef parseFile();

    bool skipTo(std::initializer_list<TokenId> targets, SkipUntilFlags flags = SkipUntilFlags::Zero);
    bool skipAfter(std::initializer_list<TokenId> targets, SkipUntilFlags flags = SkipUntilFlags::Zero);
    bool skip(std::initializer_list<TokenId> targets, SkipUntilFlags flags);

    void       reportArguments(Diagnostic& diag, const Token& myToken) const;
    Diagnostic reportError(DiagnosticId id, const Token& myToken) const;
    Diagnostic reportExpected(const Expect& expect) const;

public:
    Result parse(Context& ctx);
};

SWC_END_NAMESPACE()
