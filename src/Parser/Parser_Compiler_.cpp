#include "pch.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseCompilerFunc()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerFunc>();
    nodePtr->tknName        = consume();
    nodePtr->nodeBody       = parseBlock(AstNodeId::FuncBody, TokenId::SymLeftCurly);
    return nodeRef;
}

SWC_END_NAMESPACE()
