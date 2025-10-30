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
                p_->consume();
        }
    };

    TokenRef consumeOne()
    {
        if (atEnd())
            return INVALID_REF;
        const auto result = ref();
        curToken_++;
        return result;
    }

    TokenRef consume()
    {
        if (atEnd())
            return INVALID_REF;
        const auto result = consumeOne();
        skipTrivia();
        return result;
    }

    void skipTrivia()
    {
        while (is(TokenId::EndOfLine) || is(TokenId::Blank) || is(TokenId::CommentLine) || is(TokenId::CommentMultiLine))
            consumeAsTrivia();
    }

    void consumeAsTrivia()
    {
        consume();
    }

    TokenRef expect(TokenId expected, DiagnosticId diagId = DiagnosticId::None) const;
    TokenRef expectAndConsume(TokenId expected, DiagnosticId diagId = DiagnosticId::None);

    const Token* tokPtr() const { return curToken_; }
    const Token& tok() const { return *curToken_; }
    TokenRef     ref() const { return static_cast<TokenRef>(curToken_ - firstToken_) + 1; }
    TokenId      id() const { return curToken_->id; }
    bool         is(TokenId id0) const { return curToken_->id == id0; }
    bool         is(TokenId id0, TokenId id1) const { return curToken_->id == id0 || curToken_->id == id1; }
    bool         isNot(TokenId nid) const { return curToken_->id != nid; }
    bool         atEnd() const { return curToken_ >= lastToken_; }
    static bool  isInvalid(TokenRef ref) { return ref == INVALID_REF; }

    AstNodeRef parseExpression();
    AstNodeRef parseType();
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
    Diagnostic reportExpected(TokenId expected, DiagnosticId diagId) const;

public:
    Result parse(Context& ctx);
};

SWC_END_NAMESPACE()
