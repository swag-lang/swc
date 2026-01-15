#include "pch.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseAttributeValue()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Attribute>(ref());
    nodePtr->nodeIdentRef   = parseQualifiedIdentifier();
    if (is(TokenId::SymLeftParen))
        nodePtr->nodeArgsRef = parseCompound<AstNodeId::NamedArgumentList>(TokenId::SymLeftParen);
    else
        nodePtr->nodeArgsRef.setInvalid();
    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicCall(uint32_t numParams)
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicCall>(consume());

    const auto              openRef = ref();
    SmallVector<AstNodeRef> nodeArgs;
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    for (uint32_t i = 0; i < numParams; i++)
    {
        if (i != 0)
        {
            if (expectAndConsume(TokenId::SymComma, DiagnosticId::parser_err_expected_token).isInvalid())
                skipTo({TokenId::SymComma, TokenId::SymRightParen});
        }

        nodeArgs.push_back(parseExpression());
    }
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);

    nodePtr->spanChildrenRef = ast_->pushSpan(nodeArgs.span());
    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicCallVariadic()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicCallVariadic>(consume());

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);

    SmallVector<AstNodeRef> nodeArgs;
    while (isNot(TokenId::SymRightParen) && isNot(TokenId::EndOfFile))
    {
        if (!nodeArgs.empty())
        {
            if (expectAndConsume(TokenId::SymComma, DiagnosticId::parser_err_expected_token).isInvalid())
                skipTo({TokenId::SymComma, TokenId::SymRightParen});
            if (is(TokenId::SymRightParen))
                break;
        }

        nodeArgs.push_back(parseExpression());
    }

    nodePtr->spanChildrenRef = ast_->pushSpan(nodeArgs.span());
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);
    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicCallExpr(uint32_t numParams)
{
    const auto tokRef       = consume();
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CallExpr>(tokRef);
    auto [idRef, idPtr]     = ast_->makeNode<AstNodeId::Identifier>(tokRef);
    nodePtr->nodeExprRef    = idRef;

    const auto              openRef = ref();
    SmallVector<AstNodeRef> nodeArgs;
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    for (uint32_t i = 0; i < numParams; i++)
    {
        if (i != 0)
        {
            if (expectAndConsume(TokenId::SymComma, DiagnosticId::parser_err_expected_token).isInvalid())
                skipTo({TokenId::SymComma, TokenId::SymRightParen});
        }

        nodeArgs.push_back(parseExpression());
    }
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);

    nodePtr->spanChildrenRef = ast_->pushSpan(nodeArgs.span());
    return nodeRef;
}

template AstNodeRef Parser::parseAttributeList<AstNodeId::AggregateBody>();
template AstNodeRef Parser::parseAttributeList<AstNodeId::InterfaceBody>();
template AstNodeRef Parser::parseAttributeList<AstNodeId::EnumBody>();
template AstNodeRef Parser::parseAttributeList<AstNodeId::TopLevelBlock>();
template AstNodeRef Parser::parseAttributeList<AstNodeId::EmbeddedBlock>();

template<AstNodeId ID>
AstNodeRef Parser::parseAttributeList()
{
    const auto nodeRef = parseCompound<AstNodeId::AttributeList>(TokenId::SymAttrStart);
    if (nodeRef.isInvalid())
        return AstNodeRef::invalid();

    const auto nodePtr = ast_->node<AstNodeId::AttributeList>(nodeRef);
    if (is(TokenId::SymLeftCurly))
        nodePtr->nodeBodyRef = parseCompound<ID>(TokenId::SymLeftCurly);
    else
        nodePtr->nodeBodyRef = parseCompoundValue(ID);
    return nodeRef;
}

SWC_END_NAMESPACE();
