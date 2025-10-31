#include "pch.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseExpression()
{
    if (is(TokenId::NumberInteger))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNode>();
        consume();
        return nodeRef;
    }

    return INVALID_REF;
}

SWC_END_NAMESPACE()
