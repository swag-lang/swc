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

class ParserOutput
{
    Ast ast_;

public:
    Ast&       ast() noexcept { return ast_; }
    const Ast& ast() const noexcept { return ast_; }
};

class Parser
{
    TaskContext* ctx_            = nullptr;
    SourceFile*  file_           = nullptr;
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
    TokenRef     ref() const { return static_cast<TokenRef>(static_cast<uint32_t>(curToken_ - firstToken_)); }
    TokenId      id() const { return curToken_->id; }
    TokenId      nextId() const { return atEnd() ? TokenId::EndOfFile : curToken_[1].id; }
    bool         is(TokenId id0) const { return curToken_->id == id0; }
    bool         nextIs(TokenId id0) const { return atEnd() ? false : curToken_[1].id == id0; }
    bool         isNot(TokenId nid) const { return curToken_->id != nid; }
    bool         atEnd() const { return curToken_ >= lastToken_; }

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
    TokenRef expectAndConsumeClosing(TokenId closeId, TokenRef openRef, std::initializer_list<TokenId> skipIds = {}, bool skipToEol = true);
    TokenRef expectAndConsume(TokenId id, DiagnosticId diagId);
    void     expectEndStatement();

    AstNodeRef       parseCompoundValue(AstNodeId blockNodeId);
    Result           parseCompoundSeparator(AstNodeId blockNodeId, TokenId tokenEndId);
    void             finalizeCompound(AstNodeId blockNodeId, TokenRef openTokRef, TokenRef closeTokenRef, const SmallVector<AstNodeRef>& childrenRefs);
    AstNodeRef       parseCompound(AstNodeId blockNodeId, TokenId tokenStartId, bool endStmt = false);
    SpanRef          parseCompoundContent(AstNodeId blockNodeId, TokenId tokenStartId, bool endStmt = false);
    AstNodeRef       parseCompilerIf(AstNodeId blockNodeId);
    AstNodeRef       parseCompilerIfStmt(AstNodeId blockNodeId);
    AstNodeRef       parseAttributeList(AstNodeId blockNodeId);
    AstNodeRef       parseAggregateDecl(AstNodeId nodeId);
    AstNodeRef       parseInitializerList(AstNodeRef nodeWhat);
    AstModifierFlags parseModifiers();
    AstNodeRef       parseArraySlicingIndex(AstNodeRef nodeRef);

    AstNodeRef parseAffectStmt();
    AstNodeRef parseAggregateAccessModifier();
    AstNodeRef parseAggregateBody();
    AstNodeRef parseAggregateValue();
    AstNodeRef parseAlias();
    AstNodeRef parseAncestorIdentifier();
    AstNodeRef parseAttrDecl();
    AstNodeRef parseAttributeValue();
    AstNodeRef parseBinaryExpr();
    AstNodeRef parseBreak();
    AstNodeRef parseCast();
    AstNodeRef parseClosureCaptureValue();
    AstNodeRef parseCompilerCallUnary();
    AstNodeRef parseCompilerDependencies();
    AstNodeRef parseCompilerExpr();
    AstNodeRef parseCompilerFunc();
    AstNodeRef parseCompilerGlobal();
    AstNodeRef parseCompilerImport();
    AstNodeRef parseCompilerMacro();
    AstNodeRef parseCompilerMessageFunc();
    AstNodeRef parseCompilerScope();
    AstNodeRef parseCompilerTypeExpr();
    AstNodeRef parseCompilerTypeOf();
    AstNodeRef parseConstraint();
    AstNodeRef parseContinue();
    AstNodeRef parseDeRef();
    AstNodeRef parseDecompositionDecl();
    AstNodeRef parseDefer();
    AstNodeRef parseDiscard();
    AstNodeRef parseDoCurlyBlock();
    AstNodeRef parseEmbeddedStmt();
    AstNodeRef parseEnumDecl();
    AstNodeRef parseEnumValue();
    AstNodeRef parseExpression();
    AstNodeRef parseFallThrough();
    AstNodeRef parseFile();
    AstNodeRef parseForeach();
    AstNodeRef parseFuncDecl();
    AstNodeRef parseFunctionParam();
    AstNodeRef parseFunctionParamList();
    AstNodeRef parseGenericParam();
    AstNodeRef parseGlobalAccessModifier();
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
    AstNodeRef parseLambdaExpression();
    AstNodeRef parseLambdaType();
    AstNodeRef parseLambdaTypeParam();
    AstNodeRef parseLiteral();
    AstNodeRef parseLiteralArray();
    AstNodeRef parseLiteralExpression();
    AstNodeRef parseLiteralStruct();
    AstNodeRef parseLogicalExpr();
    AstNodeRef parseMoveRef();
    AstNodeRef parseNamedArgument();
    AstNodeRef parseNamespace();
    AstNodeRef parseParenExpr();
    AstNodeRef parsePostFixExpression();
    AstNodeRef parsePostfixIdentifierValue();
    AstNodeRef parsePreQualifiedIdentifier();
    AstNodeRef parsePrefixExpr();
    AstNodeRef parsePrimaryExpression();
    AstNodeRef parseQualifiedIdentifier();
    AstNodeRef parseRelationalExpr();
    AstNodeRef parseRetValType();
    AstNodeRef parseReturn();
    AstNodeRef parseSingleType();
    AstNodeRef parseStructDecl();
    AstNodeRef parseSubType();
    AstNodeRef parseSwitch();
    AstNodeRef parseSwitchCaseDefault();
    AstNodeRef parseSwitchCaseExpression();
    AstNodeRef parseThrow();
    AstNodeRef parseTopLevelCall();
    AstNodeRef parseTopLevelStmt();
    AstNodeRef parseTryCatch();
    AstNodeRef parseTryCatchAssume();
    AstNodeRef parseType();
    AstNodeRef parseUnionDecl();
    AstNodeRef parseUnreachable();
    AstNodeRef parseUsing();
    AstNodeRef parseVarDecl();
    AstNodeRef parseWhile();
    AstNodeRef parseWith();

    template<AstNodeId ID>
    AstNodeRef parseCompound(TokenId tokenStartId, bool endStmt = false)
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<ID>();
        nodePtr->spanChildren   = parseCompoundContent(ID, tokenStartId, endStmt);
        return nodeRef;
    }

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
    Result parse(TaskContext& ctx, LexerFlags lexerFlags = LexerFlagsE::Default);
};

SWC_END_NAMESPACE()
