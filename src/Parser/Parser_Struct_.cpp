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
    case TokenId::SymAttrStart:
        return parseCompilerAttribute(AstNodeId::StructDecl);

    case TokenId::SymLeftCurly:
        // @skip
        consume();
        skipTo({TokenId::SymRightCurly}, SkipUntilFlags::Consume);
        return INVALID_REF;

    default:
        // @skip
        skipTo({TokenId::SymRightCurly, TokenId::SymComma}, SkipUntilFlags::EolBefore);
        return INVALID_REF;
    }
}

AstNodeRef Parser::parseStructDecl()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::StructDecl>();
    consume(TokenId::KwdStruct);

    // Generic types
    if (is(TokenId::SymLeftParen))
    {
        // @skip
        consume();
        skipTo({TokenId::SymRightParen}, SkipUntilFlags::Consume);
    }

    // Name
    nodePtr->tknName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);
    if (invalid(nodePtr->tknName))
        skipTo({TokenId::SymLeftCurly});

    // Where
    if (is(TokenId::KwdWhere))
    {
        // @skip
        consume();
        parseExpression();
    }

    // Content
    nodePtr->spanChildren = parseBlockContent(TokenId::SymLeftCurly, AstNodeId::StructDecl);

    return nodeRef;
}

SWC_END_NAMESPACE()
