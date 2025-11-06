#include "pch.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseImplDecl()
{
    if (nextIs(TokenId::KwdEnum))
        return parseEnumImplDecl();

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

AstNodeRef Parser::parseStructValue()
{
    static constexpr std::initializer_list ENUM_VALUE_SYNC = {TokenId::SymRightCurly, TokenId::SymComma, TokenId::Identifier};

    switch (id())
    {
    default:
        skipTo({TokenId::SymRightCurly, TokenId::SymComma}, SkipUntilFlags::EolBefore);
        return INVALID_REF;
    }
}

AstNodeRef Parser::parseStructDecl()
{
    consume(TokenId::KwdStruct);

    const auto tknName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);
    const auto nodeRef = parseBlock(TokenId::SymLeftCurly, AstNodeId::StructDecl);

    const auto nodePtr = ast_->node<AstNodeId::StructDecl>(nodeRef);
    nodePtr->tknName   = tknName;

    return nodeRef;
}

SWC_END_NAMESPACE()
