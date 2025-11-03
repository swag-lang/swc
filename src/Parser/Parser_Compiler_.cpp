#include "pch.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseCompilerFunc()
{
    if (nextIs(TokenId::SymLeftCurly))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerFunc>();
        nodePtr->tknName        = consume();
        nodePtr->nodeBody       = parseBlock(AstNodeId::FuncBody, TokenId::SymLeftCurly);
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerShortFunc>();
    nodePtr->tknName        = consume();
    nodePtr->nodeExpression = parseExpression();
    return nodeRef;
}

SWC_END_NAMESPACE()
