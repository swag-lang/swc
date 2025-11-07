#include "pch.h"
#include "Parser/AstNodeBase.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseImplDecl()
{
    if (nextIs(TokenId::KwdEnum))
        return parseEnumImplDecl();

    consume();

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
        nodePtr->nodeIdentifier = nodeIdentifier;
        nodePtr->spanChildren   = parseBlockContent(AstNodeId::ImplDecl, TokenId::SymLeftCurly);
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ImplDeclFor>();
    nodePtr->nodeIdentifier = nodeIdentifier;
    nodePtr->nodeFor        = nodeFor;
    nodePtr->spanChildren   = parseBlockContent(AstNodeId::ImplDeclFor, TokenId::SymLeftCurly);
    return nodeRef;
}

AstNodeRef Parser::parseStructValue()
{
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

AstNodeRef Parser::parseUnionDecl()
{
    return parseStructUnionDecl(AstNodeId::UnionDecl);
}

AstNodeRef Parser::parseStructDecl()
{
    return parseStructUnionDecl(AstNodeId::StructDecl);
}

AstNodeRef Parser::parseStructUnionDecl(AstNodeId nodeId)
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeStructDeclBase>(nodeId);
    consume();

    // Generic types
    if (is(TokenId::SymLeftParen))
    {
        nodePtr->spanGenericParams = parseBlockContent(AstNodeId::GenericParamsList, TokenId::SymLeftParen);
        if (invalid(nodePtr->spanGenericParams))
            skipTo({TokenId::SymLeftCurly});
    }

    // Name
    nodePtr->tknName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);
    if (invalid(nodePtr->tknName))
        skipTo({TokenId::SymLeftCurly});

    // Where
    SmallVector<AstNodeRef> whereRefs;
    while (is(TokenId::KwdWhere))
    {
        const auto loopStartToken = curToken_;
        auto       whereRef       = parseConstraint();
        if (valid(whereRef))
            whereRefs.push_back(whereRef);

        if (loopStartToken == curToken_)
            consume();
    }

    nodePtr->spanWhere = whereRefs.empty() ? INVALID_REF : ast_->store_.push_span(whereRefs.span());

    // Content
    nodePtr->spanChildren = parseBlockContent(AstNodeId::StructDecl, TokenId::SymLeftCurly);

    return nodeRef;
}

SWC_END_NAMESPACE()
