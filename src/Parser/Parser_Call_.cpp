#include "pch.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseCallArg1(AstNodeId callerNodeId)
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeCallerArg1>(callerNodeId);
    nodePtr->tokRef         = consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::ParserExpectedTokenAfter);
    nodePtr->nodeParam1 = parseExpression();
    if (isInvalid(nodePtr->nodeParam1))
        skipTo({TokenId::SymRightParen});
    expectAndConsumeClosingFor(TokenId::SymLeftParen, openRef);

    return nodeRef;
}

AstNodeRef Parser::parseCallArg2(AstNodeId callerNodeId)
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeCallerArg2>(callerNodeId);
    nodePtr->tokRef         = consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::ParserExpectedTokenAfter);

    nodePtr->nodeParam1 = parseExpression();
    if (isInvalid(nodePtr->nodeParam1))
        skipTo({TokenId::SymComma, TokenId::SymRightParen});
    expectAndConsume(TokenId::SymComma, DiagnosticId::ParserExpectedToken);

    nodePtr->nodeParam2 = parseExpression();
    if (isInvalid(nodePtr->nodeParam2))
        skipTo({TokenId::SymComma, TokenId::SymRightParen});

    expectAndConsumeClosingFor(TokenId::SymLeftParen, openRef);
    return nodeRef;
}

AstNodeRef Parser::parseCallArg3(AstNodeId callerNodeId)
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeCallerArg3>(callerNodeId);
    nodePtr->tokRef         = consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::ParserExpectedTokenAfter);

    nodePtr->nodeParam1 = parseExpression();
    if (isInvalid(nodePtr->nodeParam1))
        skipTo({TokenId::SymRightParen});
    expectAndConsume(TokenId::SymComma, DiagnosticId::ParserExpectedToken);

    nodePtr->nodeParam2 = parseExpression();
    if (isInvalid(nodePtr->nodeParam2))
        skipTo({TokenId::SymComma, TokenId::SymRightParen});
    expectAndConsume(TokenId::SymComma, DiagnosticId::ParserExpectedToken);

    nodePtr->nodeParam3 = parseExpression();
    if (isInvalid(nodePtr->nodeParam2))
        skipTo({TokenId::SymComma, TokenId::SymRightParen});

    expectAndConsumeClosingFor(TokenId::SymLeftParen, openRef);
    return nodeRef;
}

SWC_END_NAMESPACE()
