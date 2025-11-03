#include "pch.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseImpl()
{
    if (nextIs(TokenId::KwdEnum))
        return parseEnumImpl();

    const auto tknOp = consume();

    // Name
    const AstNodeRef nodeIdentifier = parseScopedIdentifier();
    if (isInvalid(nodeIdentifier))
        skipTo({TokenId::SymLeftCurly, TokenId::KwdFor});

    // For
    AstNodeRef nodeFor = INVALID_REF;
    if (consumeIf(TokenId::KwdFor))
    {
        nodeFor = parseScopedIdentifier();
        if (isInvalid(nodeIdentifier))
            skipTo({TokenId::SymLeftCurly});
    }

    if (isInvalid(nodeFor))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ImplDecl>();
        nodePtr->tknOp          = tknOp;
        nodePtr->nodeIdentifier = nodeIdentifier;
        nodePtr->nodeContent    = parseBlock(AstNodeId::TopLevelBlock, TokenId::SymLeftCurly);
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ImplDeclFor>();
    nodePtr->tknOp          = tknOp;
    nodePtr->nodeIdentifier = nodeIdentifier;
    nodePtr->nodeFor        = nodeFor;
    nodePtr->nodeContent    = parseBlock(AstNodeId::ImplBlock, TokenId::SymLeftCurly);
    return nodeRef;
}

SWC_END_NAMESPACE()
