#include "pch.h"
#include "Lexer/SourceFile.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseClosureCaptureValue()
{
    return parseExpression();
}

AstNodeRef Parser::parseLambdaParam()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::FuncParam>();

    // Optional name
    if (is(TokenId::Identifier) && nextIs(TokenId::SymColon))
    {
        nodePtr->tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_before);
        consume(TokenId::SymColon);
    }
    else
        nodePtr->tokName = INVALID_REF;

    nodePtr->nodeType = parseType();
    return nodeRef;
}

AstNodeRef Parser::parseLambdaType()
{
    const auto tokKwd = consume();

    bool       emptyCapture  = false;
    AstNodeRef captureParams = INVALID_REF;
    if (is(TokenId::SymVertical))
        captureParams = parseBlock(AstNodeId::ClosureCaptureList, TokenId::SymVertical);
    else if (consumeIf(TokenId::SymVerticalVertical))
        emptyCapture = true;

    const SpanRef params = parseBlock(AstNodeId::LambdaParameterList, TokenId::SymLeftParen);

    // Return type
    AstNodeRef returnType = INVALID_REF;
    if (consumeIf(TokenId::SymMinusGreater))
        returnType = parseType();

    if (valid(captureParams) || emptyCapture)
    {
        auto [nodeRef, nodePtr]    = ast_->makeNode<AstNodeId::ClosureType>();
        nodePtr->nodeCaptureParams = captureParams;
        nodePtr->nodeParams        = params;
        nodePtr->nodeReturnType    = returnType;
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::FunctionType>();
    nodePtr->nodeParams     = params;
    nodePtr->nodeReturnType = returnType;
    return nodeRef;
}

SWC_END_NAMESPACE()
