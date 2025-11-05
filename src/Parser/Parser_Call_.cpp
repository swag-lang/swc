#include "pch.h"
#include "Core/SmallVector.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseCallArg1(AstNodeId callerNodeId)
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeCall1>(callerNodeId);
    nodePtr->tokRef         = consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::ParserExpectedTokenBefore, ref());
    nodePtr->nodeParam1 = parseExpression();
    if (invalid(nodePtr->nodeParam1))
        skipTo({TokenId::SymRightParen});
    expectAndConsumeClosingFor(TokenId::SymLeftParen, openRef);

    return nodeRef;
}

AstNodeRef Parser::parseCallArg2(AstNodeId callerNodeId)
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeCall2>(callerNodeId);
    nodePtr->tokRef         = consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::ParserExpectedTokenBefore, ref());

    nodePtr->nodeParam1 = parseExpression();
    if (invalid(nodePtr->nodeParam1))
        skipTo({TokenId::SymComma, TokenId::SymRightParen});
    expectAndConsume(TokenId::SymComma, DiagnosticId::ParserExpectedToken);

    nodePtr->nodeParam2 = parseExpression();
    if (invalid(nodePtr->nodeParam2))
        skipTo({TokenId::SymComma, TokenId::SymRightParen});

    expectAndConsumeClosingFor(TokenId::SymLeftParen, openRef);
    return nodeRef;
}

AstNodeRef Parser::parseCallArg3(AstNodeId callerNodeId)
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeCall3>(callerNodeId);
    nodePtr->tokRef         = consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::ParserExpectedTokenBefore, ref());

    nodePtr->nodeParam1 = parseExpression();
    if (invalid(nodePtr->nodeParam1))
        skipTo({TokenId::SymRightParen});
    expectAndConsume(TokenId::SymComma, DiagnosticId::ParserExpectedToken);

    nodePtr->nodeParam2 = parseExpression();
    if (invalid(nodePtr->nodeParam2))
        skipTo({TokenId::SymComma, TokenId::SymRightParen});
    expectAndConsume(TokenId::SymComma, DiagnosticId::ParserExpectedToken);

    nodePtr->nodeParam3 = parseExpression();
    if (invalid(nodePtr->nodeParam2))
        skipTo({TokenId::SymComma, TokenId::SymRightParen});

    expectAndConsumeClosingFor(TokenId::SymLeftParen, openRef);
    return nodeRef;
}

AstNodeRef Parser::parseAttribute()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Attribute>();
    nodePtr->nodeIdentifier = parseScopedIdentifier();
    if (is(TokenId::SymLeftParen))
        nodePtr->nodeArgs = parseBlock(TokenId::SymLeftParen, AstNodeId::NamedArgumentBlock);
    return nodeRef;
}

AstNodeRef Parser::parseCompilerAttribute(AstNodeId blockNodeId)
{
    const auto nodeRef = parseBlock(TokenId::SymAttrStart, AstNodeId::AttributeBlock);
    if (invalid(nodeRef))
        return INVALID_REF;

    const auto nodePtr = ast_->node<AstNodeId::AttributeBlock>(nodeRef);
    if (is(TokenId::SymLeftCurly))
        nodePtr->nodeBody = parseBlock(TokenId::SymLeftCurly, blockNodeId);
    else
        nodePtr->nodeBody = parseBlockStmt(blockNodeId);
    return nodeRef;
}

SWC_END_NAMESPACE()
