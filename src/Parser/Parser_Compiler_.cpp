#include "pch.h"

#include "Lexer/SourceFile.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseCompilerFunc()
{
    if (nextIs(TokenId::SymLeftCurly))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerFunc>();
        nodePtr->tknName        = consume();
        nodePtr->nodeBody       = parseBlock(TokenId::SymLeftCurly, AstNodeId::FuncBody);
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerShortFunc>();
    nodePtr->tknName        = consume();
    nodePtr->nodeExpression = parseExpression();
    return nodeRef;
}

AstNodeRef Parser::parseCompilerFuncExpr()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerFuncExpr>();
    nodePtr->tknName        = consume();
    nodePtr->nodeExpression = parseExpression();
    return nodeRef;
}

AstNodeRef Parser::parseCompilerType()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerType>();
    consume();
    nodePtr->nodeType = parseType();
    return nodeRef;
}

AstNodeRef Parser::parseCompilerIfStmt(AstNodeId blockNodeId)
{
    if (consumeIf(TokenId::KwdDo))
    {
        if (is(TokenId::SymLeftCurly))
        {
            raiseError(DiagnosticId::parser_err_unexpected_do_block, ref() - 1);
            return parseBlock(TokenId::SymLeftCurly, blockNodeId);
        }

        return parseBlockStmt(blockNodeId);
    }

    if (is(TokenId::SymLeftCurly))
    {
        return parseBlock(TokenId::SymLeftCurly, blockNodeId);
    }

    const auto diag = reportError(DiagnosticId::parser_err_expected_do_block, ref() - 1);
    diag.report(*ctx_);
    return INVALID_REF;
}

AstNodeRef Parser::parseCompilerIf(AstNodeId blockNodeId)
{
    SWC_ASSERT(isAny(TokenId::CompilerIf, TokenId::CompilerElseIf));
    const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerIf>();
    nodePtr->tknIf                = consume();

    // Parse the condition expression
    nodePtr->nodeCondition = parseExpression();
    if (invalid(nodePtr->nodeCondition))
        skipTo({TokenId::KwdDo, TokenId::SymLeftCurly});

    nodePtr->nodeIfBlock = parseCompilerIfStmt(blockNodeId);

    // Parse optional 'else' or 'elif' block
    if (is(TokenId::CompilerElseIf))
        nodePtr->nodeElseBlock = parseCompilerIf(blockNodeId);
    else if (consumeIf(TokenId::CompilerElse))
        nodePtr->nodeElseBlock = parseCompilerIfStmt(blockNodeId);

    return nodeRef;
}

SWC_END_NAMESPACE()
