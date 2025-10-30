#pragma once
#include "Lexer/Token.h"
#include "Parser/Ast.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

class SourceFile;
class Context;

enum class SkipUntilFlags : uint32_t
{
    Zero          = 0,
    StopAfterEol  = 1 << 0,
    StopBeforeEol = 1 << 1,
    Consume       = 1 << 2,
};
SWC_ENABLE_BITMASK(SkipUntilFlags);

class ParserOutput
{
protected:
    friend class Parser;
    Ast ast_;
};

class Parser
{
    Context*     ctx_        = nullptr;
    SourceFile*  file_       = nullptr;
    Ast*         ast_        = nullptr;
    const Token* firstToken_ = nullptr;
    const Token* curToken_   = nullptr;
    const Token* lastToken_  = nullptr;

    TokenRef consume()
    {
        if (atEnd())
            return INVALID_REF;
        const auto result = ref();
        curToken_++;
        return result;
    }

    void consumeTrivia()
    {
        consume();
    }

    TokenRef expect(TokenId expected, DiagnosticId diagId = DiagnosticId::None) const;
    TokenRef expectAndConsume(TokenId expected, DiagnosticId diagId = DiagnosticId::None);

    const Token& tok() const { return *curToken_; }
    TokenRef     ref() const { return static_cast<TokenRef>(curToken_ - firstToken_) + 1; }
    TokenId      id() const { return curToken_->id; }
    bool         is(TokenId id0) const { return curToken_->id == id0; }
    bool         is(TokenId id0, TokenId id1) const { return curToken_->id == id0 || curToken_->id == id1; }
    bool         isNot(TokenId nid) const { return curToken_->id != nid; }
    bool         atEnd() const { return curToken_ >= lastToken_; }

    AstNodeRef parseType();
    AstNodeRef parseEnum();
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
