#include "pch.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseClosureArg()
{
    AstClosureArgument::Flags flags = AstClosureArgument::Zero;

    const auto tokStart = ref();
    if (consumeIf(TokenId::SymAmpersand).isValid())
        flags.add(AstClosureArgument::Address);

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ClosureArgument>(tokStart);
    nodePtr->addParserFlag(flags);
    nodePtr->nodeIdentifierRef = parseQualifiedIdentifier();

    return nodeRef;
}

AstNodeRef Parser::parseLambdaTypeParam()
{
    AstNodeRef nodeType;
    TokenRef   tokName = TokenRef::invalid();

    if (is(TokenId::CompilerType))
        nodeType = parseCompilerTypeExpr();
    else
    {
        // Optional name
        if (is(TokenId::Identifier) && nextIs(TokenId::SymColon))
        {
            tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_before);
            consumeAssert(TokenId::SymColon);
        }

        nodeType = parseType();
    }

    // Normal parameter
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::LambdaTypeParam>(tokName);
    nodePtr->nodeTypeRef    = nodeType;

    if (consumeIf(TokenId::SymEqual).isValid())
        nodePtr->nodeDefaultValueRef = parseInitializerExpression();
    else
        nodePtr->nodeDefaultValueRef = AstNodeRef::invalid();

    return nodeRef;
}

AstNodeRef Parser::parseLambdaExprArg()
{
    AstNodeRef nodeType;
    TokenRef   tokName = TokenRef::invalid();

    if (is(TokenId::CompilerType))
        nodeType = parseCompilerTypeExpr();
    else if (is(TokenId::Identifier) && nextIs(TokenId::SymColon))
    {
        tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_before);
        consumeAssert(TokenId::SymColon);
        nodeType = parseType();
    }
    else
    {
        nodeType = AstNodeRef::invalid();
        if (is(TokenId::Identifier))
            tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_before);
        else if (is(TokenId::SymQuestion))
            tokName = consume();
        else
            raiseError(DiagnosticId::parser_err_unexpected_token, ref());
    }

    // Normal parameter
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::LambdaTypeParam>(tokName);
    nodePtr->nodeTypeRef    = nodeType;

    if (consumeIf(TokenId::SymEqual).isValid())
        nodePtr->nodeDefaultValueRef = parseInitializerExpression();
    else
        nodePtr->nodeDefaultValueRef = AstNodeRef::invalid();

    return nodeRef;
}

AstNodeRef Parser::parseLambdaType()
{
    AstLambdaType::Flags flags    = AstLambdaType::Zero;
    const auto           tokStart = ref();

    if (consumeIf(TokenId::KwdMtd).isValid())
        flags.add(AstLambdaType::Mtd);
    else
        consumeAssert(TokenId::KwdFunc);

    if (consumeIf(TokenId::SymPipePipe).isValid())
        flags.add(AstLambdaType::Closure);
    else if (flags.has(AstLambdaType::Mtd))
    {
        raiseError(DiagnosticId::parser_err_mtd_missing_capture, tokStart);
        flags.add(AstLambdaType::Closure);
    }

    const SpanRef params = parseCompoundContent(AstNodeId::LambdaType, TokenId::SymLeftParen);

    // Return type
    AstNodeRef returnType = AstNodeRef::invalid();
    if (consumeIf(TokenId::SymMinusGreater).isValid())
        returnType = parseType();

    // Can raise errors
    if (consumeIf(TokenId::KwdThrow).isValid())
        flags.add(AstLambdaType::Throw);

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::LambdaType>(ref());
    nodePtr->addParserFlag(flags);
    nodePtr->spanParamsRef     = params;
    nodePtr->nodeReturnTypeRef = returnType;
    return nodeRef;
}

AstNodeRef Parser::parseLambdaExpression()
{
    AstLambdaType::Flags flags    = AstLambdaType::Zero;
    const auto           tokStart = ref();

    if (consumeIf(TokenId::KwdMtd).isValid())
        flags.add(AstLambdaType::Mtd);
    else
        consumeAssert(TokenId::KwdFunc);

    // Capture
    SpanRef captureArgs = SpanRef::invalid();
    if (is(TokenId::SymPipe))
    {
        flags.add(AstLambdaType::Closure);
        captureArgs = parseCompoundContent(AstNodeId::ClosureExpr, TokenId::SymPipe);
    }
    else if (consumeIf(TokenId::SymPipePipe).isValid())
    {
        flags.add(AstLambdaType::Closure);
    }
    else if (flags.has(AstLambdaType::Mtd))
    {
        raiseError(DiagnosticId::parser_err_mtd_missing_capture, tokStart);
        flags.add(AstLambdaType::Closure);
    }

    // Arguments
    const SpanRef args = parseCompoundContent(AstNodeId::FunctionExpr, TokenId::SymLeftParen);

    // Return type
    AstNodeRef returnType = AstNodeRef::invalid();
    if (consumeIf(TokenId::SymMinusGreater).isValid())
        returnType = parseType();

    // Can raise errors
    if (consumeIf(TokenId::KwdThrow).isValid())
        flags.add(AstLambdaType::Throw);

    // Body
    AstNodeRef body = AstNodeRef::invalid();
    if (is(TokenId::SymLeftCurly))
        body = parseFunctionBody();
    else
    {
        expectAndConsume(TokenId::SymEqualGreater, DiagnosticId::parser_err_expected_token_before);
        body = parseExpression();
    }

    if (flags.has(AstLambdaType::Closure))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ClosureExpr>(ref());
        nodePtr->addParserFlag(flags);
        nodePtr->nodeCaptureArgsRef = captureArgs;
        nodePtr->spanArgsRef        = args;
        nodePtr->nodeReturnTypeRef  = returnType;
        nodePtr->nodeBodyRef        = body;
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::FunctionExpr>(ref());
    nodePtr->addParserFlag(flags);
    nodePtr->spanArgsRef       = args;
    nodePtr->nodeReturnTypeRef = returnType;
    nodePtr->nodeBodyRef       = body;
    return nodeRef;
}

AstNodeRef Parser::parseFunctionDecl()
{
    AstLambdaType::Flags flags = AstLambdaType::Zero;
    if (consumeIf(TokenId::KwdMtd).isValid())
        flags.add(AstLambdaType::Mtd);
    else
        consumeAssert(TokenId::KwdFunc);

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::FunctionDecl>(ref());
    nodePtr->addParserFlag(flags);

    // Generic parameters
    if (is(TokenId::SymLeftParen))
        nodePtr->spanGenericParamsRef = parseCompoundContent(AstNodeId::GenericParamList, TokenId::SymLeftParen);
    else
        nodePtr->spanGenericParamsRef = SpanRef::invalid();

    // Modifiers
    if (consumeIf(TokenId::KwdConst).isValid())
        flags.add(AstLambdaType::Const);
    if (consumeIf(TokenId::KwdImpl).isValid())
        flags.add(AstLambdaType::Impl);

    // Name
    if (Token::isIntrinsic(id()))
        nodePtr->tokNameRef = consume();
    else
        nodePtr->tokNameRef = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);

    // Parameters
    nodePtr->nodeParamsRef = parseFunctionParamList();

    // Return type
    if (consumeIf(TokenId::SymMinusGreater).isValid())
        nodePtr->nodeReturnTypeRef = parseType();
    else
        nodePtr->nodeReturnTypeRef = AstNodeRef::invalid();

    // Throw
    if (consumeIf(TokenId::KwdThrow).isValid())
        flags.add(AstLambdaType::Throw);

    // Constraints
    SmallVector<AstNodeRef> whereRefs;
    while (is(TokenId::KwdWhere) || is(TokenId::KwdVerify))
    {
        const auto loopStartToken = curToken_;
        auto       whereRef       = parseConstraint();
        if (whereRef.isValid())
            whereRefs.push_back(whereRef);
        if (loopStartToken == curToken_)
            consume();
    }

    nodePtr->spanConstraintsRef = ast_->pushSpan(whereRefs.span());

    // Body
    if (consumeIf(TokenId::SymSemiColon).isValid())
        nodePtr->nodeBodyRef = AstNodeRef::invalid();
    else if (consumeIf(TokenId::SymEqualGreater).isValid())
        nodePtr->nodeBodyRef = parseExpression();
    else
        nodePtr->nodeBodyRef = parseFunctionBody();

    return nodeRef;
}

AstNodeRef Parser::parseAttrDecl()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AttrDecl>(consume());
    nodePtr->tokNameRef     = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);
    nodePtr->nodeParamsRef  = parseFunctionParamList();

    return nodeRef;
}

AstNodeRef Parser::parseFunctionParam()
{
    if (is(TokenId::SymAttrStart))
    {
        const auto nodeRef   = parseCompound<AstNodeId::AttributeList>(TokenId::SymAttrStart);
        const auto nodePtr   = ast_->node<AstNodeId::AttributeList>(nodeRef);
        nodePtr->nodeBodyRef = parseFunctionParam();
        return nodeRef;
    }

    if (is(TokenId::KwdConst))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::FunctionParamMe>(consume());
        nodePtr->addParserFlag(AstFunctionParamMe::Const);
        expectAndConsume(TokenId::KwdMe, DiagnosticId::parser_err_expected_token_before);
        return nodeRef;
    }

    if (is(TokenId::KwdMe))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::FunctionParamMe>(consume());
        return nodeRef;
    }

    return parseVarDecl();
}

AstNodeRef Parser::parseFunctionParamList()
{
    return parseCompound<AstNodeId::FunctionParamList>(TokenId::SymLeftParen);
}

AstNodeRef Parser::parseFunctionBody()
{
    return parseCompound<AstNodeId::EmbeddedBlock>(TokenId::SymLeftCurly);
}

AstNodeRef Parser::parseFunctionArguments(AstNodeRef nodeExpr)
{
    if (nextIs(TokenId::SymPipe))
    {
        const auto openRef            = ref();
        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AliasCallExpr>(consume());
        nodePtr->nodeExprRef          = nodeExpr;
        nodePtr->spanAliasesRef       = parseCompoundContent(AstNodeId::AliasCallExpr, TokenId::SymPipe);
        nodePtr->spanChildrenRef      = parseCompoundContentInside(AstNodeId::NamedArgumentList, openRef, TokenId::SymLeftParen);
        return nodeRef;
    }

    const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CallExpr>(ref());
    nodePtr->nodeExprRef          = nodeExpr;
    nodePtr->spanChildrenRef      = parseCompoundContent(AstNodeId::NamedArgumentList, TokenId::SymLeftParen);
    return nodeRef;
}

SWC_END_NAMESPACE()
