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
        return parseBlock(TokenId::SymLeftCurly, AstNodeId::TopLevelBlock);
    case TokenId::SymRightCurly:
        raiseError(DiagnosticId::parser_err_unexpected_token, ref());
        return INVALID_REF;

    case TokenId::SymSemiColon:
        consume();
        return INVALID_REF;

    case TokenId::KwdEnum:
        return parseEnum();

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

    default:
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Invalid>();
        skipTo({TokenId::SymSemiColon, TokenId::SymRightCurly}, SkipUntilFlags::EolBefore);
        return nodeRef;
    }
    }
}

AstNodeRef Parser::parseEmbeddedStmt()
{
    switch (id())
    {
    case TokenId::SymLeftCurly:
        return parseBlock(TokenId::SymLeftCurly, AstNodeId::EmbeddedBlock);
    case TokenId::SymRightCurly:
        raiseError(DiagnosticId::parser_err_unexpected_token, ref());
        return INVALID_REF;

    case TokenId::SymSemiColon:
        consume();
        return INVALID_REF;

    case TokenId::SymAttrStart:
        return parseCompilerAttribute(AstNodeId::EmbeddedBlock);

    default:
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Invalid>();
        skipTo({TokenId::SymSemiColon, TokenId::SymRightCurly}, SkipUntilFlags::EolBefore);
        return nodeRef;
    }
    }
}

AstNodeRef Parser::parseUsing()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Using>();
    consume();
    nodePtr->nodeBody = parseBlock(TokenId::Invalid, AstNodeId::UsingBlock);
    expectEndStatement();
    return nodeRef;
}

SWC_END_NAMESPACE()
