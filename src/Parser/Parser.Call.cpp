#include "pch.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseIntrinsicCallZero()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicCallZero>(consume());

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);

    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicCallUnary()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicCallUnary>(consume());

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    nodePtr->nodeArgRef = parseExpression();
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);

    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicCallBinary()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicCallBinary>(consume());

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);

    nodePtr->nodeArg1Ref = parseExpression();
    if (expectAndConsume(TokenId::SymComma, DiagnosticId::parser_err_expected_token).isInvalid())
        skipTo({TokenId::SymComma, TokenId::SymRightParen});

    nodePtr->nodeArg2Ref = parseExpression();

    expectAndConsumeClosing(TokenId::SymRightParen, openRef);
    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicCallTernary()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicCallTernary>(consume());

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);

    nodePtr->nodeArg1Ref = parseExpression();
    if (expectAndConsume(TokenId::SymComma, DiagnosticId::parser_err_expected_token).isInvalid())
        skipTo({TokenId::SymComma, TokenId::SymRightParen});

    nodePtr->nodeArg2Ref = parseExpression();
    if (expectAndConsume(TokenId::SymComma, DiagnosticId::parser_err_expected_token).isInvalid())
        skipTo({TokenId::SymComma, TokenId::SymRightParen});

    nodePtr->nodeArg3Ref = parseExpression();

    expectAndConsumeClosing(TokenId::SymRightParen, openRef);
    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicCallVariadic()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicCallVariadic>(consume());

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);

    SmallVector<AstNodeRef> nodeArgs;
    auto                    nodeArg = parseExpression();
    nodeArgs.push_back(nodeArg);

    while (consumeIf(TokenId::SymComma).isValid())
    {
        nodeArg = parseExpression();
        nodeArgs.push_back(nodeArg);
    }

    nodePtr->spanChildrenRef = ast_->pushSpan(nodeArgs.span());
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);
    return nodeRef;
}

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
