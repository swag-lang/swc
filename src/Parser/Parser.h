#pragma once
#include "Core/SmallVector.h"
#include "Lexer/Lexer.h"
#include "Lexer/Token.h"
#include "Parser/Ast.h"
#include "Parser/AstNode.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

class SourceFile;
class TaskContext;

enum class SkipUntilFlagsE : uint32_t
{
    Zero      = 0,
    Consume   = 1 << 0,
    EolBefore = 1 << 1,
};
using SkipUntilFlags = EnumFlags<SkipUntilFlagsE>;

class Parser
{
    TaskContext* ctx_            = nullptr;
    Ast*         ast_            = nullptr;
    const Token* firstToken_     = nullptr;
    const Token* curToken_       = nullptr;
    const Token* lastToken_      = nullptr;
    uint32_t     depthParen_     = 0;
    uint32_t     depthBracket_   = 0;
    uint32_t     depthCurly_     = 0;
    TokenRef     lastErrorToken_ = TokenRef::invalid();

    const Token* tokPtr() const { return curToken_; }
    const Token& tok() const { return *curToken_; }
    TokenId      id() const { return curToken_->id; }
    TokenId      nextId() const { return atEnd() ? TokenId::EndOfFile : curToken_[1].id; }
    bool         is(TokenId id0) const { return curToken_->id == id0; }
    bool         nextIs(TokenId id0) const { return atEnd() ? false : curToken_[1].id == id0; }
    bool         isNot(TokenId nid) const { return curToken_->id != nid; }
    bool         atEnd() const { return curToken_ >= lastToken_; }

    TokenRef ref() const
    {
        auto result = static_cast<TokenRef>(static_cast<uint32_t>(curToken_ - firstToken_));
#if SWC_HAS_DEBUG_INFO
        result.setPtr(curToken_);
#endif
        return result;
    }

    template<typename... IDS>
    bool isAny(IDS... ids) const
    {
        return ((curToken_->id == ids) || ...);
    }

    template<typename... IDS>
    bool nextIsAny(IDS... ids) const
    {
        return ((curToken_[1].id == ids) || ...);
    }

    TokenRef consumeAssert(TokenId id);
    TokenRef consume();
    TokenRef consumeIf(TokenId id);
    TokenRef expectAndConsumeClosing(TokenId closeId, TokenRef openRef, const SmallVector<TokenId>& skipIds = {}, bool skipToEol = true);
    TokenRef expectAndConsume(TokenId id, DiagnosticId diagId);
    void     expectEndStatement();

    AstNodeRef parseCompoundValue(AstNodeId blockNodeId);
    Result     parseCompoundSeparator(AstNodeId blockNodeId, TokenId tokenEndId);
    SpanRef    parseCompoundContent(AstNodeId blockNodeId, TokenId tokenStartId);
    SpanRef    parseCompoundContentInside(AstNodeId blockNodeId, TokenRef openTokRef, TokenId tokenStartId);

    AstNodeRef       parseInitializerList(AstNodeRef nodeWhat);
    AstNodeRef       parseFunctionArguments(AstNodeRef nodeExpr);
    AstNodeRef       parseArraySlicingIndex(AstNodeRef nodeRef);
    AstModifierFlags parseModifiers();
    AstNodeRef       parseBinaryExpr(int minPrecedence);

    template<AstNodeId ID>
    AstNodeRef parseAttributeList();
    template<AstNodeId ID>
    AstNodeRef parseAggregateDecl();
    template<AstNodeId ID>
    AstNodeRef parseCompilerIfStmt();
    template<AstNodeId ID>
    AstNodeRef parseCompilerIf();

    template<AstNodeId ID>
    AstNodeRef parseCompound(TokenId tokenStartId)
    {
        auto [nodeRef, nodePtr]  = ast_->makeNode<ID>(ref());
        nodePtr->spanChildrenRef = parseCompoundContent(ID, tokenStartId);
        return nodeRef;
    }

    AstNodeRef parseAssignStmt();
    AstNodeRef parseAggregateAccessModifier();
    AstNodeRef parseAggregateBody();
    AstNodeRef parseAggregateValue();
    AstNodeRef parseAlias();
    AstNodeRef parseCompilerUp();
    AstNodeRef parseAttrDecl();
    AstNodeRef parseAttributeValue();
    AstNodeRef parseBinaryExpr();
    AstNodeRef parseBreak();
    AstNodeRef parseCast();
    AstNodeRef parseClosureArg();
    AstNodeRef parseCompilerExpression();
    AstNodeRef parseCompilerDiagnostic();
    AstNodeRef parseCompilerCallUnary();
    AstNodeRef parseCompilerDependencies();
    AstNodeRef parseCompilerRun();
    AstNodeRef parseCompilerCode();
    AstNodeRef parseCompilerFunc();
    AstNodeRef parseCompilerGlobal();
    AstNodeRef parseCompilerImport();
    AstNodeRef parseCompilerInject();
    AstNodeRef parseCompilerMacro();
    AstNodeRef parseCompilerMessageFunc();
    AstNodeRef parseCompilerScope();
    AstNodeRef parseCompilerTypeExpr();
    AstNodeRef parseCompilerTypeOf();
    AstNodeRef parseConstraint();
    AstNodeRef parseContinue();
    AstNodeRef parseVarDeclDecomposition();
    AstNodeRef parseDefer();
    AstNodeRef parseDiscard();
    AstNodeRef parseDoCurlyBlock();
    AstNodeRef parseEmbeddedStmt();
    AstNodeRef parseEnumDecl();
    AstNodeRef parseEnumValue();
    AstNodeRef parseExpression();
    AstNodeRef parseRangeExpression();
    AstNodeRef parseFallThrough();
    AstNodeRef parseFile();
    AstNodeRef parseFor();
    AstNodeRef parseForLoop();
    AstNodeRef parseForCpp();
    AstNodeRef parseForInfinite();
    AstNodeRef parseForeach();
    AstNodeRef parseFunctionDecl();
    AstNodeRef parseFunctionBody();
    AstNodeRef parseFunctionParam();
    AstNodeRef parseFunctionParamList();
    AstNodeRef parseGenericParam();
    AstNodeRef parseAccessModifier();
    AstNodeRef parseIdentifier();
    AstNodeRef parseIdentifierType();
    AstNodeRef parseIf();
    AstNodeRef parseImpl();
    AstNodeRef parseImplEnum();
    AstNodeRef parseInitializerExpression();
    AstNodeRef parseInterfaceDecl();
    AstNodeRef parseInterfaceValue();
    AstNodeRef parseIntrinsicCallBinary();
    AstNodeRef parseIntrinsicCallTernary();
    AstNodeRef parseIntrinsicCallVariadic();
    AstNodeRef parseIntrinsicCallUnary();
    AstNodeRef parseIntrinsicCallZero();
    AstNodeRef parseIntrinsicDrop();
    AstNodeRef parseIntrinsicInit();
    AstNodeRef parseIntrinsicPostCopy();
    AstNodeRef parseIntrinsicPostMove();
    AstNodeRef parseIntrinsicValue();
    AstNodeRef parseLogicalExpr(int minPrecedence);
    AstNodeRef parseLambdaExpression();
    AstNodeRef parseLambdaType();
    AstNodeRef parseLambdaTypeParam();
    AstNodeRef parseLambdaExprArg();
    AstNodeRef parseLiteral();
    AstNodeRef parseLiteralArray();
    AstNodeRef parseLiteralExpression();
    AstNodeRef parseLiteralStruct();
    AstNodeRef parseLogicalExpr();
    AstNodeRef parseNamedArg();
    AstNodeRef parseNamespace();
    AstNodeRef parseParenExpr();
    AstNodeRef parsePostFixExpression();
    AstNodeRef parseIdentifierSuffixValue();
    AstNodeRef parseScopedIdentifier();
    AstNodeRef parsePrefixExpr();
    AstNodeRef parsePrimaryExpression();
    AstNodeRef parseQualifiedIdentifier();
    AstNodeRef parseRelationalExpr(int minPrecedence);
    AstNodeRef parseRelationalExpr();
    AstNodeRef parseRetValType();
    AstNodeRef parseReturn();
    AstNodeRef parseSingleType();
    AstNodeRef parseStructDecl();
    AstNodeRef parseSubType();
    AstNodeRef parseSwitch();
    AstNodeRef parseSwitchCaseDefault();
    AstNodeRef parseThrow();
    AstNodeRef parseTopLevelCall();
    AstNodeRef parseTopLevelDeclOrBlock();
    AstNodeRef parseTopLevelStmt();
    AstNodeRef parseTryCatch();
    AstNodeRef parseTryCatchAssume();
    AstNodeRef parseType();
    AstNodeRef parseTypeValue();
    AstNodeRef parseUnionDecl();
    AstNodeRef parseUnreachable();
    AstNodeRef parseUsing();
    AstNodeRef parseVarDecl();
    AstNodeRef parseWhile();
    AstNodeRef parseWith();

    bool skipTo(const SmallVector<TokenId>& targets, SkipUntilFlags flags = SkipUntilFlagsE::Zero);
    bool skipAfter(const SmallVector<TokenId>& targets, SkipUntilFlags flags = SkipUntilFlagsE::Zero);
    bool skip(const SmallVector<TokenId>& targets, SkipUntilFlags flags);

    void        setReportArguments(Diagnostic& diag, TokenRef tokRef) const;
    static void setReportExpected(Diagnostic& diag, TokenId expectedTknId);
    Diagnostic  reportError(DiagnosticId id, TokenRef tknRef);
    void        raiseError(DiagnosticId id, TokenRef tknRef);
    void        raiseExpected(DiagnosticId id, TokenRef tknRef, TokenId tknExpected);

public:
    void parse(TaskContext& ctx, Ast& ast);
};

SWC_END_NAMESPACE()
