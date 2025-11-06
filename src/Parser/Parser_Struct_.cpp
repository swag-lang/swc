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
    if (invalid(nodeIdentifier))
        skipTo({TokenId::SymLeftCurly, TokenId::KwdFor});

    // For
    AstNodeRef nodeFor = INVALID_REF;
    if (consumeIf(TokenId::KwdFor))
    {
        nodeFor = parseScopedIdentifier();
        if (invalid(nodeIdentifier))
            skipTo({TokenId::SymLeftCurly});
    }

    if (invalid(nodeFor))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ImplDecl>();
        nodePtr->tknOp          = tknOp;
        nodePtr->nodeIdentifier = nodeIdentifier;
        nodePtr->nodeContent    = parseBlock(TokenId::SymLeftCurly, AstNodeId::TopLevelBlock);
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ImplDeclFor>();
    nodePtr->tknOp          = tknOp;
    nodePtr->nodeIdentifier = nodeIdentifier;
    nodePtr->nodeFor        = nodeFor;
    nodePtr->nodeContent    = parseBlock(TokenId::SymLeftCurly, AstNodeId::ImplBlock);
    return nodeRef;
}

AstNodeRef Parser::parseStruct()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::StructDecl>();
    consume(TokenId::KwdStruct);

    // Name
    nodePtr->tknName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);
    if (invalid(nodePtr->tknName))
        skipTo({TokenId::SymLeftCurly});

    return nodeRef;
}

SWC_END_NAMESPACE()
