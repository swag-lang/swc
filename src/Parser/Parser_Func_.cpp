#include "pch.h"
#include "Lexer/SourceFile.h"
#include "Os/Os.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseClosureCaptureValue()
{
    AstClosureCapture::Flags flags = AstClosureCapture::FlagsE::Zero;

    if (consumeIf(TokenId::SymAmpersand) != INVALID_REF)
        flags.add(AstClosureCapture::FlagsE::Address);

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ClosureCapture>();
    nodePtr->addFlag(flags);
    nodePtr->tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_before);

    return nodeRef;
}

AstNodeRef Parser::parseLambdaTypeParam()
{
    AstNodeRef nodeType;
    TokenRef   tokName = INVALID_REF;

    if (is(TokenId::CompilerType))
        nodeType = parseCompilerTypeExpr();
    else
    {
        // Optional name
        if (is(TokenId::Identifier) && nextIs(TokenId::SymColon))
        {
            tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_before);
            consume(TokenId::SymColon);
        }

        // Untyped variadic parameter
        if (consumeIf(TokenId::SymDotDotDot) != INVALID_REF)
        {
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::VariadicParam>();
            nodePtr->tokName        = tokName;
            return nodeRef;
        }

        nodeType = parseType();
    }

    // Typed variadic parameter
    if (consumeIf(TokenId::SymDotDotDot) != INVALID_REF)
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::TypedVariadicParam>();
        nodePtr->tokName        = tokName;
        nodePtr->nodeType       = nodeType;
        return nodeRef;
    }

    // Normal parameter
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::LambdaTypeParam>();
    nodePtr->tokName        = tokName;
    nodePtr->nodeType       = nodeType;

    if (consumeIf(TokenId::SymEqual) != INVALID_REF)
        nodePtr->nodeDefaultValue = parseInitializerExpression();
    else
        nodePtr->nodeDefaultValue = INVALID_REF;

    return nodeRef;
}

AstNodeRef Parser::parseLambdaType()
{
    AstLambdaType::Flags flags    = AstLambdaType::FlagsE::Zero;
    const auto           tokStart = ref();

    if (consumeIf(TokenId::KwdMtd) != INVALID_REF)
        flags.add(AstLambdaType::FlagsE::Mtd);
    else
        consume(TokenId::KwdFunc);

    if (consumeIf(TokenId::SymVerticalVertical) != INVALID_REF)
        flags.add(AstLambdaType::FlagsE::Closure);
    else if (flags.has(AstLambdaType::FlagsE::Mtd))
    {
        raiseError(DiagnosticId::parser_err_mtd_missing_capture, tokStart);
        flags.add(AstLambdaType::FlagsE::Closure);
    }

    const SpanRef params = parseCompound(AstNodeId::LambdaTypeParamList, TokenId::SymLeftParen);

    // Return type
    AstNodeRef returnType = INVALID_REF;
    if (consumeIf(TokenId::SymMinusGreater) != INVALID_REF)
        returnType = parseType();

    // Can raise errors
    if (consumeIf(TokenId::KwdThrow) != INVALID_REF)
        flags.add(AstLambdaType::FlagsE::Throw);

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::LambdaType>();
    nodePtr->addFlag(flags);
    nodePtr->nodeParams     = params;
    nodePtr->nodeReturnType = returnType;
    return nodeRef;
}

AstNodeRef Parser::parseLambdaExpression()
{
    AstLambdaType::Flags flags    = AstLambdaType::FlagsE::Zero;
    const auto           tokStart = ref();

    if (consumeIf(TokenId::KwdMtd) != INVALID_REF)
        flags.add(AstLambdaType::FlagsE::Mtd);
    else
        consume(TokenId::KwdFunc);

    AstNodeRef captureArgs = INVALID_REF;
    if (is(TokenId::SymVertical))
    {
        flags.add(AstLambdaType::FlagsE::Closure);
        captureArgs = parseCompound(AstNodeId::ClosureCaptureList, TokenId::SymVertical);
    }
    else if (consumeIf(TokenId::SymVerticalVertical) != INVALID_REF)
    {
        flags.add(AstLambdaType::FlagsE::Closure);
    }
    else if (flags.has(AstLambdaType::FlagsE::Mtd))
    {
        raiseError(DiagnosticId::parser_err_mtd_missing_capture, tokStart);
        flags.add(AstLambdaType::FlagsE::Closure);
    }

    const SpanRef params = parseCompound(AstNodeId::LambdaTypeParamList, TokenId::SymLeftParen);

    // Return type
    AstNodeRef returnType = INVALID_REF;
    if (consumeIf(TokenId::SymMinusGreater) != INVALID_REF)
        returnType = parseType();

    // Can raise errors
    if (consumeIf(TokenId::KwdThrow) != INVALID_REF)
        flags.add(AstLambdaType::FlagsE::Throw);

    // Body
    AstNodeRef body = INVALID_REF;
    if (is(TokenId::SymLeftCurly))
        body = parseCompound(AstNodeId::FunctionBody, TokenId::SymLeftCurly);
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
        nodePtr->nodeParams      = params;
        nodePtr->nodeReturnType  = returnType;
        nodePtr->nodeBody        = body;
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::FunctionExpr>();
    nodePtr->addFlag(flags);
    nodePtr->nodeParams     = params;
    nodePtr->nodeReturnType = returnType;
    nodePtr->nodeBody       = body;
    return nodeRef;
}

AstNodeRef Parser::parseFuncDecl()
{
    AstLambdaType::Flags flags = AstLambdaType::FlagsE::Zero;
    if (consumeIf(TokenId::KwdMtd) != INVALID_REF)
        flags.add(AstLambdaType::FlagsE::Mtd);
    else
        consume(TokenId::KwdFunc);

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::FunctionDecl>();
    nodePtr->addFlag(flags);

    // Generic parameters
    if (is(TokenId::SymLeftParen))
        nodePtr->spanGenericParams = parseCompoundContent(AstNodeId::GenericParamList, TokenId::SymLeftParen);
    else
        nodePtr->spanGenericParams = INVALID_REF;

    // Modifiers
    if (consumeIf(TokenId::KwdConst) != INVALID_REF)
        flags.add(AstLambdaType::FlagsE::Const);
    if (consumeIf(TokenId::KwdImpl) != INVALID_REF)
        flags.add(AstLambdaType::FlagsE::Impl);

    // Name
    if (Token::isIntrinsic(id()))
        nodePtr->tokName = consume();
    else
        nodePtr->tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);

    // @skip
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_fam_before);
    skipTo({TokenId::SymRightParen}, SkipUntilFlagsE::Consume);

    // Return type
    if (consumeIf(TokenId::SymMinusGreater) != INVALID_REF)
        nodePtr->nodeReturnType = parseType();
    else
        nodePtr->nodeReturnType = INVALID_REF;

    // Throw
    if (consumeIf(TokenId::KwdThrow) != INVALID_REF)
        flags.add(AstLambdaType::FlagsE::Throw);

    // Constraints
    SmallVector<AstNodeRef> whereRefs;
    while (is(TokenId::KwdWhere) || is(TokenId::KwdVerify))
    {
        const auto loopStartToken = curToken_;
        auto       whereRef       = parseConstraint();
        if (valid(whereRef))
            whereRefs.push_back(whereRef);
        if (loopStartToken == curToken_)
            consume();
    }

    nodePtr->spanConstraints = ast_->store_.push_span(whereRefs.span());

    // Body
    if (consumeIf(TokenId::SymSemiColon) != INVALID_REF)
        nodePtr->nodeBody = INVALID_REF;
    else if (consumeIf(TokenId::SymEqualGreater) != INVALID_REF)
        nodePtr->nodeBody = parseExpression();
    else
        nodePtr->nodeBody = parseCompound(AstNodeId::FunctionBody, TokenId::SymLeftCurly);

    return nodeRef;
}

SWC_END_NAMESPACE()
