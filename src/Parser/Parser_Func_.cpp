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

    if (consumeIf(TokenId::SymEqual))
        nodePtr->nodeDefaultValue = parseInitializationExpression();
    else
        nodePtr->nodeDefaultValue = INVALID_REF;

    return nodeRef;
}

AstNodeRef Parser::parseLambdaType()
{
    AstLambdaType::Flags flags    = AstLambdaType::FlagsE::Zero;
    const auto           tokStart = ref();

    if (consumeIf(TokenId::KwdMtd))
        flags.add(AstLambdaType::FlagsE::Mtd);
    else
        consume(TokenId::KwdFunc);

    bool       isCapture     = false;
    AstNodeRef captureParams = INVALID_REF;
    if (is(TokenId::SymVertical))
    {
        isCapture     = true;
        captureParams = parseCompound(AstNodeId::ClosureCaptureList, TokenId::SymVertical);
    }
    else if (consumeIf(TokenId::SymVerticalVertical))
    {
        isCapture = true;
    }
    else if (flags.has(AstLambdaType::FlagsE::Mtd))
    {
        raiseError(DiagnosticId::parser_err_mtd_missing_capture, tokStart);
        isCapture = true;
    }

    const SpanRef params = parseCompound(AstNodeId::LambdaParameterList, TokenId::SymLeftParen);

    // Return type
    AstNodeRef returnType = INVALID_REF;
    if (consumeIf(TokenId::SymMinusGreater))
        returnType = parseType();

    // Can raise errors
    if (consumeIf(TokenId::KwdThrow))
        flags.add(AstLambdaType::FlagsE::Throw);

    if (isCapture)
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ClosureType>();
        nodePtr->addFlag(flags);
        nodePtr->nodeCaptureParams = captureParams;
        nodePtr->nodeParams        = params;
        nodePtr->nodeReturnType    = returnType;
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::FunctionType>();
    nodePtr->addFlag(flags);
    nodePtr->nodeParams     = params;
    nodePtr->nodeReturnType = returnType;
    return nodeRef;
}

SWC_END_NAMESPACE()
