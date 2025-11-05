#pragma once
#include "Lexer/Token.h"
#include "Parser/Ast.h"
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
    Context*     ctx_            = nullptr;
    SourceFile*  file_           = nullptr;
    Ast*         ast_            = nullptr;
    const Token* firstToken_     = nullptr;
    const Token* curToken_       = nullptr;
    const Token* lastToken_      = nullptr;
    uint32_t     depthParen_     = 0;
    uint32_t     depthBracket_   = 0;
    uint32_t     depthCurly_     = 0;
    TokenRef     lastErrorToken_ = INVALID_REF;

    TokenRef consume(TokenId id);
    TokenRef consume();
    bool     consumeIf(TokenId id, TokenRef* result = nullptr);

    template<typename... TokenIds>
    bool consumeIfAny(TokenIds... ids)
    {
        if (atEnd())
            return false;
        return ((consumeIf(ids)) || ...);
    }

    TokenRef expectAndConsumeClosingFor(TokenId openId, TokenRef openRef);
    void     expectEndStatement();

    TokenRef expectAndConsume(TokenId id, DiagnosticId diagId);

    const Token* tokPtr() const { return curToken_; }
    const Token& tok() const { return *curToken_; }
    TokenRef     ref() const { return static_cast<TokenRef>(curToken_ - firstToken_); }
    TokenId      id() const { return curToken_->id; }
    TokenId      nextId() const { return atEnd() ? TokenId::EndOfFile : curToken_[1].id; }
    bool         is(TokenId id0) const { return curToken_->id == id0; }
    bool         nextIs(TokenId id0) const { return atEnd() ? false : curToken_[1].id == id0; }
    bool         isNot(TokenId nid) const { return curToken_->id != nid; }
    bool         atEnd() const { return curToken_ >= lastToken_; }
    static bool  valid(TokenRef ref) { return ref != INVALID_REF; }
    static bool  invalid(TokenRef ref) { return ref == INVALID_REF; }

    template<typename... IDS>
    bool isAny(IDS... ids) const
    {
        return ((curToken_->id == ids) || ...);
    }

    AstNodeRef parseSingleType();
    AstNodeRef parseType();

    AstNodeRef parseCallArg1(AstNodeId callerNodeId);
    AstNodeRef parseCallArg2(AstNodeId callerNodeId);
    AstNodeRef parseCallArg3(AstNodeId callerNodeId);
    AstNodeRef parseBlockStmt(AstNodeId blockNodeId);
    AstNodeRef parseBlock(TokenId tokenStartId, AstNodeId blockNodeId);
    AstNodeRef parseCompilerIf(AstNodeId blockNodeId);
    AstNodeRef parseCompilerIfStmt(AstNodeId blockNodeId);
    AstNodeRef parseCompilerAttribute(AstNodeId blockNodeId);

    AstNodeRef       parseIdentifier();
    AstNodeRef       parseSuffixedIdentifier();
    AstNodeRef       parseAutoScopedIdentifier();
    AstNodeRef       parseUpIdentifier();
    AstNodeRef       parseScopedIdentifier();
    AstNodeRef       parseLiteral();
    AstNodeRef       parseLiteralExpression();
    AstNodeRef       parseLiteralArray();
    AstNodeRef       parseNamedArgument();
    AstNodeRef       parsePrimaryExpression();
    AstNodeRef       parsePostFixExpression();
    AstModifierFlags parseModifiers();
    AstNodeRef       parseCast();
    AstNodeRef       parseUnaryExpression();
    AstNodeRef       parseBinaryExpression();
    AstNodeRef       parseRelationalExpression();
    AstNodeRef       parseLogicalExpression();
    AstNodeRef       parseExpression();
    AstNodeRef       parseParenExpression();
    AstNodeRef       parseEnum();
    AstNodeRef       parseEnumImpl();
    AstNodeRef       parseEnumValue();
    AstNodeRef       parseCompilerFunc();
    AstNodeRef       parseCompilerFuncExpr();
    AstNodeRef       parseCompilerType();
    AstNodeRef       parseTopLevelStmt();
    AstNodeRef       parseEmbeddedStmt();
    AstNodeRef       parseNamespace();
    AstNodeRef       parseImpl();
    AstNodeRef       parseFile();
    AstNodeRef       parseAttribute();

    bool skipTo(std::initializer_list<TokenId> targets, SkipUntilFlags flags = SkipUntilFlags::Zero);
    bool skipAfter(std::initializer_list<TokenId> targets, SkipUntilFlags flags = SkipUntilFlags::Zero);
    bool skip(std::initializer_list<TokenId> targets, SkipUntilFlags flags);

    void        setReportArguments(Diagnostic& diag, TokenRef tokenRef) const;
    static void setReportExpected(Diagnostic& diag, TokenId expectedTknId);
    Diagnostic  reportError(DiagnosticId id, TokenRef tknRef);
    void        raiseError(DiagnosticId id, TokenRef tknRef);

public:
    Result parse(Context& ctx);
};

SWC_END_NAMESPACE()
