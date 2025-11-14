#include "pch.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseClosureCaptureArg()
{
    AstClosureCapture::Flags flags = AstClosureCapture::FlagsE::Zero;

    if (consumeIf(TokenId::SymAmpersand).isValid())
        flags.add(AstClosureCapture::FlagsE::Address);

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ClosureCapture>();
    nodePtr->addFlag(flags);
    nodePtr->nodeIdentifier = parseQualifiedIdentifier();

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
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::LambdaTypeParam>();
    nodePtr->tokName        = tokName;
    nodePtr->nodeType       = nodeType;

    if (consumeIf(TokenId::SymEqual).isValid())
        nodePtr->nodeDefaultValue = parseInitializerExpression();
    else
        nodePtr->nodeDefaultValue = AstNodeRef::invalid();

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
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::LambdaTypeParam>();
    nodePtr->tokName        = tokName;
    nodePtr->nodeType       = nodeType;

    if (consumeIf(TokenId::SymEqual).isValid())
        nodePtr->nodeDefaultValue = parseInitializerExpression();
    else
        nodePtr->nodeDefaultValue = AstNodeRef::invalid();

    return nodeRef;
}

AstNodeRef Parser::parseLambdaType()
{
    AstLambdaType::Flags flags    = AstLambdaType::FlagsE::Zero;
    const auto           tokStart = ref();

    if (consumeIf(TokenId::KwdMtd).isValid())
        flags.add(AstLambdaType::FlagsE::Mtd);
    else
        consumeAssert(TokenId::KwdFunc);

    if (consumeIf(TokenId::SymVerticalVertical).isValid())
        flags.add(AstLambdaType::FlagsE::Closure);
    else if (flags.has(AstLambdaType::FlagsE::Mtd))
    {
        raiseError(DiagnosticId::parser_err_mtd_missing_capture, tokStart);
        flags.add(AstLambdaType::FlagsE::Closure);
    }

    const SpanRef params = parseCompoundContent(AstNodeId::LambdaType, TokenId::SymLeftParen);

    // Return type
    AstNodeRef returnType = AstNodeRef::invalid();
    if (consumeIf(TokenId::SymMinusGreater).isValid())
        returnType = parseType();

    // Can raise errors
    if (consumeIf(TokenId::KwdThrow).isValid())
        flags.add(AstLambdaType::FlagsE::Throw);

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::LambdaType>();
    nodePtr->addFlag(flags);
    nodePtr->spanParams     = params;
    nodePtr->nodeReturnType = returnType;
    return nodeRef;
}

AstNodeRef Parser::parseLambdaExpression()
{
    AstLambdaType::Flags flags    = AstLambdaType::FlagsE::Zero;
    const auto           tokStart = ref();

    if (consumeIf(TokenId::KwdMtd).isValid())
        flags.add(AstLambdaType::FlagsE::Mtd);
    else
        consumeAssert(TokenId::KwdFunc);

    // Capture
    SpanRef captureArgs = SpanRef::invalid();
    if (is(TokenId::SymVertical))
    {
        flags.add(AstLambdaType::FlagsE::Closure);
        captureArgs = parseCompoundContent(AstNodeId::ClosureExpr, TokenId::SymVertical);
    }
    else if (consumeIf(TokenId::SymVerticalVertical).isValid())
    {
        flags.add(AstLambdaType::FlagsE::Closure);
    }
    else if (flags.has(AstLambdaType::FlagsE::Mtd))
    {
        raiseError(DiagnosticId::parser_err_mtd_missing_capture, tokStart);
        flags.add(AstLambdaType::FlagsE::Closure);
    }

    // Arguments
    const SpanRef args = parseCompoundContent(AstNodeId::FunctionExpr, TokenId::SymLeftParen);

    // Return type
    AstNodeRef returnType = AstNodeRef::invalid();
    if (consumeIf(TokenId::SymMinusGreater).isValid())
        returnType = parseType();

    // Can raise errors
    if (consumeIf(TokenId::KwdThrow).isValid())
        flags.add(AstLambdaType::FlagsE::Throw);

    // Body
    AstNodeRef body = AstNodeRef::invalid();
    if (is(TokenId::SymLeftCurly))
        body = parseFunctionBody();
    else
    {
        expectAndConsume(TokenId::SymEqualGreater, DiagnosticId::parser_err_expected_token_before);
        body = parseExpression();
    }

    if (flags.has(AstLambdaType::FlagsE::Closure))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ClosureExpr>();
        nodePtr->addFlag(flags);
        nodePtr->nodeCaptureArgs = captureArgs;
        nodePtr->spanArgs        = args;
        nodePtr->nodeReturnType  = returnType;
        nodePtr->nodeBody        = body;
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::FunctionExpr>();
    nodePtr->addFlag(flags);
    nodePtr->spanArgs       = args;
    nodePtr->nodeReturnType = returnType;
    nodePtr->nodeBody       = body;
    return nodeRef;
}

AstNodeRef Parser::parseFunctionDecl()
{
    AstLambdaType::Flags flags = AstLambdaType::FlagsE::Zero;
    if (consumeIf(TokenId::KwdMtd).isValid())
        flags.add(AstLambdaType::FlagsE::Mtd);
    else
        consumeAssert(TokenId::KwdFunc);

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::FunctionDecl>();
    nodePtr->addFlag(flags);

    // Generic parameters
    if (is(TokenId::SymLeftParen))
        nodePtr->spanGenericParams = parseCompoundContent(AstNodeId::GenericParamList, TokenId::SymLeftParen);
    else
        nodePtr->spanGenericParams = SpanRef::invalid();

    // Modifiers
    if (consumeIf(TokenId::KwdConst).isValid())
        flags.add(AstLambdaType::FlagsE::Const);
    if (consumeIf(TokenId::KwdImpl).isValid())
        flags.add(AstLambdaType::FlagsE::Impl);

    // Name
    if (Token::isIntrinsic(id()))
        nodePtr->tokName = consume();
    else
        nodePtr->tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);

    // Parameters
    nodePtr->nodeParams = parseFunctionParamList();

    // Return type
    if (consumeIf(TokenId::SymMinusGreater).isValid())
        nodePtr->nodeReturnType = parseType();
    else
        nodePtr->nodeReturnType = AstNodeRef::invalid();

    // Throw
    if (consumeIf(TokenId::KwdThrow).isValid())
        flags.add(AstLambdaType::FlagsE::Throw);

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

    nodePtr->spanConstraints = ast_->store_.push_span(whereRefs.span());

    // Body
    if (consumeIf(TokenId::SymSemiColon).isValid())
        nodePtr->nodeBody = AstNodeRef::invalid();
    else if (consumeIf(TokenId::SymEqualGreater).isValid())
        nodePtr->nodeBody = parseExpression();
    else
        nodePtr->nodeBody = parseFunctionBody();

    return nodeRef;
}

AstNodeRef Parser::parseAttrDecl()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AttrDecl>();
    consume();
    nodePtr->tokName    = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);
    nodePtr->nodeParams = parseFunctionParamList();

    return nodeRef;
}

AstNodeRef Parser::parseFunctionParam()
{
    if (is(TokenId::SymAttrStart))
    {
        const auto nodeRef = parseCompound<AstNodeId::AttributeList>(TokenId::SymAttrStart);
        const auto nodePtr = ast_->node<AstNodeId::AttributeList>(nodeRef);
        nodePtr->nodeBody  = parseFunctionParam();
        return nodeRef;
    }

    if (consumeIf(TokenId::KwdConst).isValid())
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::FuncParamMe>();
        nodePtr->addFlag(AstFuncParamMe::FlagsE::Const);
        expectAndConsume(TokenId::KwdMe, DiagnosticId::parser_err_expected_token_before);
        return nodeRef;
    }

    if (consumeIf(TokenId::KwdMe).isValid())
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::FuncParamMe>();
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

AstNodeRef Parser::parseFunctionArguments()
{
    if (nextIs(TokenId::SymVertical))
    {
        const auto openRef = consume();

        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AliasCall>();
        nodePtr->nodeExpr             = nodeRef;
        nodePtr->spanAliases          = parseCompoundContent(AstNodeId::AliasCall, TokenId::SymVertical);
        nodePtr->spanChildren         = parseCompoundContentInside(AstNodeId::NamedArgList, openRef, TokenId::SymLeftParen);
        return nodeRef;
    }

    const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Call>();
    nodePtr->nodeExpr             = nodeRef;
    nodePtr->spanChildren         = parseCompoundContent(AstNodeId::NamedArgList, TokenId::SymLeftParen);
    return nodeRef;
}

SWC_END_NAMESPACE()
