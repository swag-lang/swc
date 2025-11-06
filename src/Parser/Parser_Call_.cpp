#include "pch.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseCallArg1(AstNodeId callerNodeId)
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeCall1>(callerNodeId);
    nodePtr->tokRef         = consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    nodePtr->nodeParam1 = parseExpression();
    expectAndConsumeClosingFor(TokenId::SymLeftParen, openRef);

    return nodeRef;
}

AstNodeRef Parser::parseCallArg2(AstNodeId callerNodeId)
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeCall2>(callerNodeId);
    nodePtr->tokRef         = consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);

    nodePtr->nodeParam1 = parseExpression();
    if (invalid(expectAndConsume(TokenId::SymComma, DiagnosticId::parser_err_expected_token)))
        skipTo({TokenId::SymComma, TokenId::SymRightParen});

    nodePtr->nodeParam2 = parseExpression();

    expectAndConsumeClosingFor(TokenId::SymLeftParen, openRef);
    return nodeRef;
}

AstNodeRef Parser::parseCallArg3(AstNodeId callerNodeId)
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeCall3>(callerNodeId);
    nodePtr->tokRef         = consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);

    nodePtr->nodeParam1 = parseExpression();
    if (invalid(expectAndConsume(TokenId::SymComma, DiagnosticId::parser_err_expected_token)))
        skipTo({TokenId::SymComma, TokenId::SymRightParen});

    nodePtr->nodeParam2 = parseExpression();
    if (invalid(expectAndConsume(TokenId::SymComma, DiagnosticId::parser_err_expected_token)))
        skipTo({TokenId::SymComma, TokenId::SymRightParen});

    nodePtr->nodeParam3 = parseExpression();

    expectAndConsumeClosingFor(TokenId::SymLeftParen, openRef);
    return nodeRef;
}

AstNodeRef Parser::parseAttribute()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Attribute>();
    nodePtr->nodeIdentifier = parseScopedIdentifier();
    if (is(TokenId::SymLeftParen))
        nodePtr->nodeArgs = parseBlock(AstNodeId::NamedArgumentBlock, TokenId::SymLeftParen);
    return nodeRef;
}

AstNodeRef Parser::parseCompilerAttribute(AstNodeId blockNodeId)
{
    const auto nodeRef = parseBlock(AstNodeId::AttributeBlock, TokenId::SymAttrStart);
    if (invalid(nodeRef))
        return INVALID_REF;

    const auto nodePtr = ast_->node<AstNodeId::AttributeBlock>(nodeRef);
    if (is(TokenId::SymLeftCurly))
        nodePtr->nodeBody = parseBlock(blockNodeId, TokenId::SymLeftCurly);
    else
        nodePtr->nodeBody = parseBlockStmt(blockNodeId);
    return nodeRef;
}

SWC_END_NAMESPACE()
