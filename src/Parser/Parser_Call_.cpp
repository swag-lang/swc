#include "pch.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseCompilerCallUnary()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerCallUnary>();
    nodePtr->tokName        = consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    nodePtr->nodeArg1 = parseExpression();
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);

    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicCallZero()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicCallZero>();
    nodePtr->tokName        = consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);

    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicCallUnary()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicCallUnary>();
    nodePtr->tokName        = consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    nodePtr->nodeArg1 = parseExpression();
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);

    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicCallBinary()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicCallBinary>();
    nodePtr->tokName        = consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);

    nodePtr->nodeArg1 = parseExpression();
    if (expectAndConsume(TokenId::SymComma, DiagnosticId::parser_err_expected_token).isInvalid())
        skipTo({TokenId::SymComma, TokenId::SymRightParen});

    nodePtr->nodeArg2 = parseExpression();

    expectAndConsumeClosing(TokenId::SymRightParen, openRef);
    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicCallTernary()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicCallTernary>();
    nodePtr->tokName        = consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);

    nodePtr->nodeArg1 = parseExpression();
    if (expectAndConsume(TokenId::SymComma, DiagnosticId::parser_err_expected_token).isInvalid())
        skipTo({TokenId::SymComma, TokenId::SymRightParen});

    nodePtr->nodeArg2 = parseExpression();
    if (expectAndConsume(TokenId::SymComma, DiagnosticId::parser_err_expected_token).isInvalid())
        skipTo({TokenId::SymComma, TokenId::SymRightParen});

    nodePtr->nodeArg3 = parseExpression();

    expectAndConsumeClosing(TokenId::SymRightParen, openRef);
    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicCallVariadic()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicCallVariadic>();
    nodePtr->tokName        = consume();

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

    nodePtr->spanChildren = ast_->store_.push_span(nodeArgs.span());
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);
    return nodeRef;
}

AstNodeRef Parser::parseAttributeValue()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Attribute>();
    nodePtr->nodeIdent      = parseQualifiedIdentifier();
    if (is(TokenId::SymLeftParen))
        nodePtr->nodeArgs = parseCompound<AstNodeId::NamedArgList>(TokenId::SymLeftParen);
    return nodeRef;
}

AstNodeRef Parser::parseAttributeList(AstNodeId blockNodeId)
{
    const auto nodeRef = parseCompound<AstNodeId::AttributeList>(TokenId::SymAttrStart);
    if (nodeRef.isInvalid())
        return AstNodeRef::invalid();

    const auto nodePtr = ast_->node<AstNodeId::AttributeList>(nodeRef);
    if (is(TokenId::SymLeftCurly))
        nodePtr->nodeBody = parseCompound(blockNodeId, TokenId::SymLeftCurly);
    else
        nodePtr->nodeBody = parseCompoundValue(blockNodeId);
    return nodeRef;
}

SWC_END_NAMESPACE()
