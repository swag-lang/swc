#include "pch.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseInternalCallZero(AstNodeId callerNodeId)
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstInternalCallUnaryBase>(callerNodeId);
    nodePtr->tokName        = consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    expectAndConsumeClosingFor(TokenId::SymLeftParen, openRef);

    return nodeRef;
}

AstNodeRef Parser::parseInternalCallUnary(AstNodeId callerNodeId)
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstInternalCallUnaryBase>(callerNodeId);
    nodePtr->tokName        = consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    nodePtr->nodeArg1 = parseExpression();
    expectAndConsumeClosingFor(TokenId::SymLeftParen, openRef);

    return nodeRef;
}

AstNodeRef Parser::parseInternalCallBinary(AstNodeId callerNodeId)
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstInternalCallBinaryBase>(callerNodeId);
    nodePtr->tokName        = consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);

    nodePtr->nodeArg1 = parseExpression();
    if (expectAndConsume(TokenId::SymComma, DiagnosticId::parser_err_expected_token).isInvalid())
        skipTo({TokenId::SymComma, TokenId::SymRightParen});

    nodePtr->nodeArg2 = parseExpression();

    expectAndConsumeClosingFor(TokenId::SymLeftParen, openRef);
    return nodeRef;
}

AstNodeRef Parser::parseInternalCallTernary(AstNodeId callerNodeId)
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstInternalCallTernaryBase>(callerNodeId);
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

    expectAndConsumeClosingFor(TokenId::SymLeftParen, openRef);
    return nodeRef;
}

AstNodeRef Parser::parseCompilerAttributeValue()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Attribute>();
    nodePtr->nodeIdent      = parseQualifiedIdentifier();
    if (is(TokenId::SymLeftParen))
        nodePtr->nodeArgs = parseCompound(AstNodeId::NamedArgList, TokenId::SymLeftParen);
    return nodeRef;
}

AstNodeRef Parser::parseCompilerAttribute(AstNodeId blockNodeId)
{
    const auto nodeRef = parseCompound(AstNodeId::AttributeList, TokenId::SymAttrStart);
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
