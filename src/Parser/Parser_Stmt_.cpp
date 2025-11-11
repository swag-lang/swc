#include "pch.h"
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
        return AstNodeRef::invalid();

    case TokenId::SymSemiColon:
        consume();
        return AstNodeRef::invalid();

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

    case TokenId::CompilerFuncMessage:
        return parseCompilerMessageFunc();

    case TokenId::KwdNamespace:
        return parseNamespace();
    case TokenId::CompilerDependencies:
        return parseCompilerDependencies();

    case TokenId::SymAttrStart:
        return parseAttributeList(AstNodeId::TopLevelBlock);

    case TokenId::KwdPublic:
    case TokenId::KwdInternal:
    case TokenId::KwdPrivate:
        return parseGlobalAccessModifier();

    case TokenId::KwdUsing:
        return parseUsing();

    case TokenId::KwdConst:
    case TokenId::KwdVar:
    {
        const AstNodeRef nodeRef = parseVarDecl();
        expectEndStatement();
        return nodeRef;
    }

    case TokenId::CompilerLoad:
    case TokenId::CompilerForeignLib:
        return parseInternalCallUnary(AstNodeId::CompilerCallUnary);

    case TokenId::KwdFunc:
    case TokenId::KwdMtd:
        return parseFuncDecl();

    case TokenId::KwdAttr:
        return parseAttrDecl();

    case TokenId::KwdAlias:
        return parseAlias();

    case TokenId::CompilerImport:
        return parseCompilerImport();

    case TokenId::CompilerGlobal:
        raiseError(DiagnosticId::parser_err_misplaced_global, ref());
        return parseCompilerGlobal();

    case TokenId::KwdInterface:
        return parseInterfaceDecl();

    case TokenId::Identifier:
        return parseTopLevelCall();

    case TokenId::EndOfFile:
        return AstNodeRef::invalid();

    default:
        raiseError(DiagnosticId::parser_err_unexpected_token, ref());
        return AstNodeRef::invalid();
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
        return AstNodeRef::invalid();

    case TokenId::SymSemiColon:
        consume();
        return AstNodeRef::invalid();

    case TokenId::KwdEnum:
        return parseEnumDecl();
    case TokenId::KwdUnion:
        return parseUnionDecl();
    case TokenId::KwdStruct:
        return parseStructDecl();

    case TokenId::IntrinsicBcBreakpoint:
        return parseInternalCallZero(AstNodeId::IntrinsicCallZero);

    case TokenId::IntrinsicAssert:
    case TokenId::IntrinsicFree:
        return parseInternalCallUnary(AstNodeId::IntrinsicCallUnary);

    case TokenId::IntrinsicCompilerError:
    case TokenId::IntrinsicCompilerWarning:
    case TokenId::IntrinsicPanic:
        return parseInternalCallBinary(AstNodeId::IntrinsicCallBinary);

    case TokenId::IntrinsicMemCpy:
    case TokenId::IntrinsicMemMove:
    case TokenId::IntrinsicMemSet:
        return parseInternalCallTernary(AstNodeId::IntrinsicCallTernary);

    case TokenId::SymAttrStart:
        return parseAttributeList(AstNodeId::EmbeddedBlock);

    case TokenId::KwdFunc:
    case TokenId::KwdMtd:
        return parseFuncDecl();

    case TokenId::KwdConst:
    case TokenId::KwdVar:
    case TokenId::KwdLet:
    {
        const AstNodeRef nodeRef = parseVarDecl();
        expectEndStatement();
        return nodeRef;
    }

    default:
        // @skip
        skipTo({TokenId::SymSemiColon, TokenId::SymRightCurly}, SkipUntilFlagsE::EolBefore);
        return AstNodeRef::invalid();
    }
}

AstNodeRef Parser::parseTopLevelCall()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::TopLevelCall>();
    nodePtr->nodeIdentifier = parseQualifiedIdentifier();
    nodePtr->nodeArgs       = parseCompound(AstNodeId::NamedArgList, TokenId::SymLeftParen);
    expectEndStatement();
    return nodeRef;
}

AstNodeRef Parser::parseGlobalAccessModifier()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AccessModifier>();
    nodePtr->tokAccess      = consume();
    nodePtr->nodeWhat       = parseTopLevelStmt();
    return nodeRef;
}

AstNodeRef Parser::parseUsing()
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
    else if (Token::isType(id()))
        nodePtr->nodeExpr = parseType();
    else if (is(TokenId::Identifier))
        nodePtr->nodeExpr = parseQualifiedIdentifier();
    else
        nodePtr->nodeExpr = parsePrimaryExpression();

    return nodeRef;
}

SWC_END_NAMESPACE()
