#pragma once
#include "Core/SmallVector.h"
#include "Lexer/Token.h"
#include "Parser/Ast.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

class SourceFile;
class Context;

enum class SkipUntilFlagsE : uint32_t
{
    Zero      = 0,
    Consume   = 1 << 0,
    EolBefore = 1 << 1,
};
using SkipUntilFlags = EnumFlags<SkipUntilFlagsE>;

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

    TokenRef consume(TokenId id);
    TokenRef consume();
    bool     consumeIf(TokenId id, TokenRef* result = nullptr);
    TokenRef expectAndConsumeClosingFor(TokenId openId, TokenRef openRef);
    TokenRef expectAndConsume(TokenId id, DiagnosticId diagId);
    void     expectEndStatement();

    AstNodeRef       parseInternalCallZero(AstNodeId callerNodeId);
    AstNodeRef       parseInternalCallUnary(AstNodeId callerNodeId);
    AstNodeRef       parseInternalCallBinary(AstNodeId callerNodeId);
    AstNodeRef       parseInternalCallTernary(AstNodeId callerNodeId);
    AstNodeRef       parseCompoundValue(AstNodeId blockNodeId);
    AstNodeRef       parseBlockCompilerDirective(AstNodeId blockNodeId);
    Result           parseCompoundSeparator(AstNodeId blockNodeId, TokenId tokenEndId);
    void             finalizeCompound(AstNodeId blockNodeId, TokenRef openTokRef, TokenRef closeTokenRef, TokenId tokenEndId, const SmallVector<AstNodeRef>& childrenRefs);
    AstNodeRef       parseCompound(AstNodeId blockNodeId, TokenId tokenStartId, bool endStmt = false);
    Ref              parseCompoundContent(AstNodeId blockNodeId, TokenId tokenStartId, bool endStmt = false);
    AstNodeRef       parseCompilerIf(AstNodeId blockNodeId);
    AstNodeRef       parseCompilerIfStmt(AstNodeId blockNodeId);
    AstNodeRef       parseCompilerAttribute(AstNodeId blockNodeId);
    AstNodeRef       parseAggregateDecl(AstNodeId nodeId);
    AstNodeRef       parseInitializerList(AstNodeRef nodeWhat);
    AstModifierFlags parseModifiers();
    AstNodeRef       parseDecompositionDecl(AstVarDecl::Flags flags);
    AstNodeRef       parseArraySlicingIndex(AstNodeRef nodeRef);

    AstNodeRef parseTryCatchAssume();
    AstNodeRef parseAggregateAccessModifier();
    AstNodeRef parseAggregateBody();
    AstNodeRef parseAggregateValue();
    AstNodeRef parseAlias();
    AstNodeRef parseAncestorIdentifier();
    AstNodeRef parseAttribute();
    AstNodeRef parseBinaryExpr();
    AstNodeRef parseCast();
    AstNodeRef parseDeRef();
    AstNodeRef parseClosureCaptureValue();
    AstNodeRef parseCompilerDependencies();
    AstNodeRef parseCompilerExpr();
    AstNodeRef parseCompilerFunc();
    AstNodeRef parseCompilerType();
    AstNodeRef parseConstraint();
    AstNodeRef parseEmbeddedStmt();
    AstNodeRef parseEnumDecl();
    AstNodeRef parseEnumValue();
    AstNodeRef parseExpression();
    AstNodeRef parseFile();
    AstNodeRef parseGenericParam();
    AstNodeRef parseGlobalAccessModifier();
    AstNodeRef parseIdentifier();
    AstNodeRef parseIdentifierType();
    AstNodeRef parseRetValType();
    AstNodeRef parseImpl();
    AstNodeRef parseImplEnum();
    AstNodeRef parseInitializerExpression();
    AstNodeRef parseIntrinsicValue();
    AstNodeRef parseLambdaParam();
    AstNodeRef parseLambdaType();
    AstNodeRef parseLiteral();
    AstNodeRef parseLiteralArray();
    AstNodeRef parseLiteralExpression();
    AstNodeRef parseLiteralStruct();
    AstNodeRef parseLogicalExpr();
    AstNodeRef parseNamedArgument();
    AstNodeRef parseNamespace();
    AstNodeRef parseParenExpr();
    AstNodeRef parsePostFixExpression();
    AstNodeRef parsePreQualifiedIdentifier();
    AstNodeRef parsePrimaryExpression();
    AstNodeRef parseQualifiedIdentifier();
    AstNodeRef parseRelationalExpr();
    AstNodeRef parseSingleType();
    AstNodeRef parseStructDecl();
    AstNodeRef parseTopLevelStmt();
    AstNodeRef parseType();
    AstNodeRef parseUnaryExpr();
    AstNodeRef parsePrefixExpr();
    AstNodeRef parseUnionDecl();
    AstNodeRef parseUsingDecl();
    AstNodeRef parseVarDecl();

    bool skipTo(std::initializer_list<TokenId> targets, SkipUntilFlags flags = SkipUntilFlagsE::Zero);
    bool skipAfter(std::initializer_list<TokenId> targets, SkipUntilFlags flags = SkipUntilFlagsE::Zero);
    bool skip(std::initializer_list<TokenId> targets, SkipUntilFlags flags);

    Utf8               tokenErrorString(TokenRef tokenRef) const;
    SourceCodeLocation tokenErrorLocation(TokenRef tokenRef) const;
    void               setReportArguments(Diagnostic& diag, TokenRef tokenRef) const;
    static void        setReportExpected(Diagnostic& diag, TokenId expectedTknId);
    Diagnostic         reportError(DiagnosticId id, TokenRef tknRef);
    void               raiseError(DiagnosticId id, TokenRef tknRef);
    void               raiseExpected(DiagnosticId id, TokenRef tknRef, TokenId tknExpected);

public:
    Result parse(Context& ctx);
};

SWC_END_NAMESPACE()
