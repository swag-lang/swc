#include "pch.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseCallArg1(AstNodeId callerNodeId)
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstSysCallUnaryBase>(callerNodeId);
    nodePtr->tokName         = consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    nodePtr->nodeArg1 = parseExpression();
    expectAndConsumeClosingFor(TokenId::SymLeftParen, openRef);

    return nodeRef;
}

AstNodeRef Parser::parseCallArg2(AstNodeId callerNodeId)
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstSysCallBinaryBase>(callerNodeId);
    nodePtr->tokName         = consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);

    nodePtr->nodeArg1 = parseExpression();
    if (invalid(expectAndConsume(TokenId::SymComma, DiagnosticId::parser_err_expected_token)))
        skipTo({TokenId::SymComma, TokenId::SymRightParen});

    nodePtr->nodeArg2 = parseExpression();

    expectAndConsumeClosingFor(TokenId::SymLeftParen, openRef);
    return nodeRef;
}

AstNodeRef Parser::parseCallArg3(AstNodeId callerNodeId)
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstSysCallTernaryBase>(callerNodeId);
    nodePtr->tokName         = consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);

    nodePtr->nodeArg1 = parseExpression();
    if (invalid(expectAndConsume(TokenId::SymComma, DiagnosticId::parser_err_expected_token)))
        skipTo({TokenId::SymComma, TokenId::SymRightParen});

    nodePtr->nodeArg2 = parseExpression();
    if (invalid(expectAndConsume(TokenId::SymComma, DiagnosticId::parser_err_expected_token)))
        skipTo({TokenId::SymComma, TokenId::SymRightParen});

    nodePtr->nodeArg3 = parseExpression();

    expectAndConsumeClosingFor(TokenId::SymLeftParen, openRef);
    return nodeRef;
}

AstNodeRef Parser::parseAttribute()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Attribute>();
    nodePtr->nodeIdent = parseQualifiedIdentifier();
    if (is(TokenId::SymLeftParen))
        nodePtr->nodeArgs = parseBlock(AstNodeId::NamedArgList, TokenId::SymLeftParen);
    return nodeRef;
}

AstNodeRef Parser::parseCompilerAttribute(AstNodeId blockNodeId)
{
    const auto nodeRef = parseBlock(AstNodeId::AttributeList, TokenId::SymAttrStart);
    if (invalid(nodeRef))
        return INVALID_REF;

    const auto nodePtr = ast_->node<AstNodeId::AttributeList>(nodeRef);
    if (is(TokenId::SymLeftCurly))
        nodePtr->nodeBody = parseBlock(blockNodeId, TokenId::SymLeftCurly);
    else
        nodePtr->nodeBody = parseBlockStmt(blockNodeId);
    return nodeRef;
}

SWC_END_NAMESPACE()
