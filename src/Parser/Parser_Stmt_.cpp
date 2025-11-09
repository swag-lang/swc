#include "pch.h"
#include "Core/Types.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseTopLevelStmt()
{
    switch (id())
    {
    case TokenId::SymLeftCurly:
        return parseCompound(AstNodeId::TopLevelBlock, TokenId::SymLeftCurly);
    case TokenId::SymRightCurly:
        raiseError(DiagnosticId::parser_err_unexpected_token, ref());
        return INVALID_REF;

    case TokenId::SymSemiColon:
        consume();
        return INVALID_REF;

    case TokenId::KwdEnum:
        return parseEnumDecl();
    case TokenId::KwdUnion:
        return parseUnionDecl();
    case TokenId::KwdStruct:
        return parseStructDecl();

    case TokenId::KwdImpl:
        return parseImpl();

    case TokenId::CompilerFuncTest:
    case TokenId::CompilerFuncMain:
    case TokenId::CompilerFuncPreMain:
    case TokenId::CompilerFuncInit:
    case TokenId::CompilerFuncDrop:
    case TokenId::CompilerAst:
    case TokenId::CompilerRun:
        return parseCompilerFunc();

    case TokenId::KwdNamespace:
        return parseNamespace();
    case TokenId::CompilerDependencies:
        return parseCompilerDependencies();

    case TokenId::SymAttrStart:
        return parseCompilerAttribute(AstNodeId::TopLevelBlock);

    case TokenId::KwdPublic:
    case TokenId::KwdInternal:
    case TokenId::KwdPrivate:
        return parseGlobalAccessModifier();

    case TokenId::KwdUsing:
        return parseUsingDecl();

    case TokenId::KwdConst:
        return parseVarDecl();

    default:
    {
        // @skip
        skipTo({TokenId::SymSemiColon, TokenId::SymRightCurly}, SkipUntilFlagsE::EolBefore);
        return INVALID_REF;
    }
    }
}

AstNodeRef Parser::parseEmbeddedStmt()
{
    switch (id())
    {
    case TokenId::SymLeftCurly:
        return parseCompound(AstNodeId::EmbeddedBlock, TokenId::SymLeftCurly);
    case TokenId::SymRightCurly:
        raiseError(DiagnosticId::parser_err_unexpected_token, ref());
        return INVALID_REF;

    case TokenId::SymSemiColon:
        consume();
        return INVALID_REF;

    case TokenId::KwdEnum:
        return parseEnumDecl();
    case TokenId::KwdUnion:
        return parseUnionDecl();
    case TokenId::KwdStruct:
        return parseStructDecl();

    case TokenId::IntrinsicPrint:
        return parseInternalCallUnary(AstNodeId::IntrinsicCallUnary);

    case TokenId::SymAttrStart:
        return parseCompilerAttribute(AstNodeId::EmbeddedBlock);

    default:
    {
        // @skip
        skipTo({TokenId::SymSemiColon, TokenId::SymRightCurly}, SkipUntilFlagsE::EolBefore);
        return INVALID_REF;
    }
    }
}

AstNodeRef Parser::parseGlobalAccessModifier()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AccessModifier>();
    nodePtr->tokAccess      = consume();
    nodePtr->nodeWhat       = parseTopLevelStmt();
    return nodeRef;
}

AstNodeRef Parser::parseUsingDecl()
{
    if (nextIs(TokenId::KwdNamespace))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::UsingNamespace>();
        consume();
        nodePtr->nodeNamespace = parseNamespace();
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::UsingDecl>();
    consume();
    nodePtr->spanChildren = parseCompoundContent(AstNodeId::UsingDecl, TokenId::Invalid, true);
    expectEndStatement();
    return nodeRef;
}

AstNodeRef Parser::parseConstraint()
{
    if (nextIs(TokenId::SymLeftCurly))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ConstraintBlock>();
        nodePtr->tokConstraint  = consume();
        nodePtr->spanChildren   = parseCompoundContent(AstNodeId::EmbeddedBlock, TokenId::SymLeftCurly);
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ConstraintExpr>();
    nodePtr->tokConstraint  = consume();
    nodePtr->nodeExpr       = parseExpression();
    return nodeRef;
}

AstNodeRef Parser::parseAlias()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Alias>();
    consume();
    nodePtr->tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam);
    expectAndConsume(TokenId::SymEqual, DiagnosticId::parser_err_expected_token_fam);

    if (isAny(TokenId::CompilerDeclType, TokenId::SymLeftBracket, TokenId::SymLeftCurly, TokenId::KwdFunc, TokenId::KwdMtd))
        nodePtr->nodeExpr = parseType();
    else
        nodePtr->nodeExpr = parsePrimaryExpression();

    return nodeRef;
}

SWC_END_NAMESPACE()
