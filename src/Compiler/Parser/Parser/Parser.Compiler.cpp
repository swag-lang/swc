#include "pch.h"
#include "Compiler/Parser/Parser/Parser.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseCompilerExpression()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerExpression>(ref());
    nodePtr->nodeExprRef    = parseExpression();
    return nodeRef;
}

AstNodeRef Parser::parseCompilerDiagnostic()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerDiagnostic>(consume());

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    nodePtr->nodeArgRef = parseCompilerExpression();
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);

    return nodeRef;
}

AstNodeRef Parser::parseCompilerTypeOf()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerCallOne>(consume());

    const auto              openRef = ref();
    SmallVector<AstNodeRef> nodeArgs;
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);

    while (isNot(TokenId::SymRightParen) && isNot(TokenId::EndOfFile))
    {
        if (!nodeArgs.empty())
        {
            if (expectAndConsume(TokenId::SymComma, DiagnosticId::parser_err_expected_token).isInvalid())
                skipTo({TokenId::SymComma, TokenId::SymRightParen});
            if (is(TokenId::SymRightParen))
                break;
        }

        if (nodeArgs.empty() && isAny(TokenId::KwdFunc, TokenId::KwdMtd))
            nodeArgs.push_back(parseType());
        else
            nodeArgs.push_back(parseExpression());
    }

    if (nodeArgs.empty())
    {
        auto diag = reportError(DiagnosticId::parser_err_too_few_arguments, ref());
        diag.addArgument(Diagnostic::ARG_COUNT, 1);
        diag.addArgument(Diagnostic::ARG_VALUE, static_cast<uint32_t>(nodeArgs.size()));
        diag.report(*ctx_);
    }
    else if (nodeArgs.size() > 1)
    {
        auto diag = reportError(DiagnosticId::parser_err_too_many_arguments, nodeArgs[1]);
        diag.addArgument(Diagnostic::ARG_COUNT, 1);
        diag.addArgument(Diagnostic::ARG_VALUE, static_cast<uint32_t>(nodeArgs.size()));
        diag.report(*ctx_);
    }

    nodePtr->nodeArgRef = nodeArgs.empty() ? AstNodeRef::invalid() : nodeArgs[0];
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);
    return nodeRef;
}

AstNodeRef Parser::parseCompilerCall(uint32_t numParams)
{
    if (numParams == 1)
        return parseCompilerCallOne();

    const auto token        = tok();
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerCall>(consume());

    const auto              openRef = ref();
    SmallVector<AstNodeRef> nodeArgs;
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);

    auto parseFlags = ParserContextFlagsE::Zero;
    if (token.id == TokenId::CompilerDefined)
        parseFlags = ParserContextFlagsE::InCompilerDefined;
    PushContextFlags context(this, parseFlags);

    while (isNot(TokenId::SymRightParen) && isNot(TokenId::EndOfFile))
    {
        if (!nodeArgs.empty())
        {
            if (expectAndConsume(TokenId::SymComma, DiagnosticId::parser_err_expected_token).isInvalid())
                skipTo({TokenId::SymComma, TokenId::SymRightParen});
            if (is(TokenId::SymRightParen))
                break;
        }

        nodeArgs.push_back(parseExpression());
    }

    if (nodeArgs.size() < numParams)
    {
        auto diag = reportError(DiagnosticId::parser_err_too_few_arguments, ref());
        diag.addArgument(Diagnostic::ARG_COUNT, numParams);
        diag.addArgument(Diagnostic::ARG_VALUE, static_cast<uint32_t>(nodeArgs.size()));
        diag.report(*ctx_);
    }
    else if (nodeArgs.size() > numParams)
    {
        auto diag = reportError(DiagnosticId::parser_err_too_many_arguments, nodeArgs[numParams]);
        diag.addArgument(Diagnostic::ARG_COUNT, numParams);
        diag.addArgument(Diagnostic::ARG_VALUE, static_cast<uint32_t>(nodeArgs.size()));
        diag.report(*ctx_);
    }

    nodePtr->spanChildrenRef = ast_->pushSpan(nodeArgs.span());
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);
    return nodeRef;
}

AstNodeRef Parser::parseCompilerCallOne()
{
    const auto token        = tok();
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerCallOne>(consume());

    const auto              openRef = ref();
    SmallVector<AstNodeRef> nodeArgs;
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);

    auto parseFlags = ParserContextFlagsE::Zero;
    if (token.id == TokenId::CompilerDefined)
        parseFlags = ParserContextFlagsE::InCompilerDefined;
    PushContextFlags context(this, parseFlags);

    while (isNot(TokenId::SymRightParen) && isNot(TokenId::EndOfFile))
    {
        if (!nodeArgs.empty())
        {
            if (expectAndConsume(TokenId::SymComma, DiagnosticId::parser_err_expected_token).isInvalid())
                skipTo({TokenId::SymComma, TokenId::SymRightParen});
            if (is(TokenId::SymRightParen))
                break;
        }

        nodeArgs.push_back(parseExpression());
    }

    if (nodeArgs.empty())
    {
        auto diag = reportError(DiagnosticId::parser_err_too_few_arguments, ref());
        diag.addArgument(Diagnostic::ARG_COUNT, 1);
        diag.addArgument(Diagnostic::ARG_VALUE, static_cast<uint32_t>(nodeArgs.size()));
        diag.report(*ctx_);
    }
    else if (nodeArgs.size() > 1)
    {
        auto diag = reportError(DiagnosticId::parser_err_too_many_arguments, nodeArgs[1]);
        diag.addArgument(Diagnostic::ARG_COUNT, 1);
        diag.addArgument(Diagnostic::ARG_VALUE, static_cast<uint32_t>(nodeArgs.size()));
        diag.report(*ctx_);
    }

    nodePtr->nodeArgRef = nodeArgs.empty() ? AstNodeRef::invalid() : nodeArgs[0];
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);
    return nodeRef;
}

AstNodeRef Parser::parseCompilerFunc()
{
    const auto what = id();

    if (nextIs(TokenId::SymLeftCurly))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerFunc>(consume());
        nodePtr->nodeBodyRef    = parseFunctionBody();
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerShortFunc>(consume());
    if (what == TokenId::CompilerAst)
        nodePtr->nodeBodyRef = parseExpression();
    else
        nodePtr->nodeBodyRef = parseEmbeddedStmt();
    return nodeRef;
}

AstNodeRef Parser::parseCompilerMessageFunc()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerMessageFunc>(consume());
    const auto openRef      = ref();

    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    nodePtr->nodeParamRef = parseExpression();
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);

    nodePtr->nodeBodyRef = parseFunctionBody();
    return nodeRef;
}

AstNodeRef Parser::parseCompilerRun()
{
    if (nextIs(TokenId::SymLeftCurly))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerRunBlock>(consume());
        nodePtr->nodeBodyRef    = parseFunctionBody();
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerRunExpr>(consume());
    nodePtr->nodeExprRef    = parseExpression();
    return nodeRef;
}

AstNodeRef Parser::parseCompilerCode()
{
    if (nextIs(TokenId::SymLeftCurly))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerCodeBlock>(consume());
        nodePtr->nodeBodyRef    = parseFunctionBody();
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerCodeExpr>(consume());
    nodePtr->nodeExprRef    = parseExpression();
    return nodeRef;
}

AstNodeRef Parser::parseCompilerTypeExpr()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerTypeExpr>(consume());
    nodePtr->nodeTypeRef    = parseType();
    return nodeRef;
}

template<AstNodeId ID>
AstNodeRef Parser::parseCompilerIfStmt()
{
    if (consumeIf(TokenId::KwdDo).isValid())
    {
        if (is(TokenId::SymLeftCurly))
        {
            raiseError(DiagnosticId::parser_err_unexpected_do_block, ref().offset(-1));
            return parseCompound<ID>(TokenId::SymLeftCurly);
        }

        return parseCompoundValue(ID);
    }

    if (is(TokenId::SymLeftCurly))
        return parseCompound<ID>(TokenId::SymLeftCurly);

    const auto diag = reportError(DiagnosticId::parser_err_expected_do_block, ref().offset(-1));
    diag.report(*ctx_);
    return AstNodeRef::invalid();
}

template AstNodeRef Parser::parseCompilerIf<AstNodeId::AggregateBody>();
template AstNodeRef Parser::parseCompilerIf<AstNodeId::InterfaceBody>();
template AstNodeRef Parser::parseCompilerIf<AstNodeId::EnumBody>();
template AstNodeRef Parser::parseCompilerIf<AstNodeId::TopLevelBlock>();
template AstNodeRef Parser::parseCompilerIf<AstNodeId::EmbeddedBlock>();

template<AstNodeId ID>
AstNodeRef Parser::parseCompilerIf()
{
    SWC_ASSERT(isAny(TokenId::CompilerIf, TokenId::CompilerElseIf));
    const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerIf>(consume());

    // Parse the condition expression
    nodePtr->nodeConditionRef = parseCompilerExpression();
    if (nodePtr->nodeConditionRef.isInvalid())
        skipTo({TokenId::KwdDo, TokenId::SymLeftCurly});

    nodePtr->nodeIfBlockRef = parseCompilerIfStmt<ID>();

    // Parse optional 'else' or 'elif' block
    if (is(TokenId::CompilerElseIf))
        nodePtr->nodeElseBlockRef = parseCompilerIf<ID>();
    else if (consumeIf(TokenId::CompilerElse).isValid())
        nodePtr->nodeElseBlockRef = parseCompilerIfStmt<ID>();
    else
        nodePtr->nodeElseBlockRef.setInvalid();

    return nodeRef;
}

AstNodeRef Parser::parseCompilerDependencies()
{
    auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::DependenciesBlock>(consume());
    nodePtr->spanChildrenRef = parseCompoundContent(AstNodeId::TopLevelBlock, TokenId::SymLeftCurly);
    return nodeRef;
}

AstNodeRef Parser::parseCompilerGlobal()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerGlobal>(consume());
    const auto tokStr       = tok().string(ast_->srcView());

    nodePtr->spanNameRef.setInvalid();
    nodePtr->nodeModeRef.setInvalid();

    if (tokStr == Token::toName(TokenId::KwdSkipFmt))
    {
        nodePtr->mode        = AstCompilerGlobal::Mode::SkipFmt;
        nodePtr->nodeModeRef = AstNodeRef::invalid();
        consume();
    }
    else if (tokStr == Token::toName(TokenId::KwdGenerated))
    {
        nodePtr->mode        = AstCompilerGlobal::Mode::Generated;
        nodePtr->nodeModeRef = AstNodeRef::invalid();
        consume();
    }
    else if (tokStr == Token::toName(TokenId::KwdExport))
    {
        nodePtr->mode        = AstCompilerGlobal::Mode::Export;
        nodePtr->nodeModeRef = AstNodeRef::invalid();
        consume();
    }
    else if (is(TokenId::SymAttrStart))
    {
        nodePtr->mode        = AstCompilerGlobal::Mode::AttributeList;
        nodePtr->nodeModeRef = parseCompound<AstNodeId::AttributeList>(TokenId::SymAttrStart);
        const auto attrPtr   = ast_->node<AstNodeId::AttributeList>(nodePtr->nodeModeRef);
        attrPtr->nodeBodyRef.setInvalid();
    }
    else if (is(TokenId::KwdPublic))
    {
        nodePtr->mode        = AstCompilerGlobal::Mode::AccessPublic;
        nodePtr->nodeModeRef = AstNodeRef::invalid();
        consume();
    }
    else if (is(TokenId::KwdInternal))
    {
        nodePtr->mode        = AstCompilerGlobal::Mode::AccessInternal;
        nodePtr->nodeModeRef = AstNodeRef::invalid();
        consume();
    }
    else if (is(TokenId::KwdPrivate))
    {
        nodePtr->mode        = AstCompilerGlobal::Mode::AccessPrivate;
        nodePtr->nodeModeRef = AstNodeRef::invalid();
        consume();
    }
    else if (is(TokenId::KwdNamespace))
    {
        nodePtr->mode = AstCompilerGlobal::Mode::Namespace;
        consume();
        nodePtr->spanNameRef = parseQualifiedName();
    }
    else if (is(TokenId::CompilerIf))
    {
        nodePtr->mode = AstCompilerGlobal::Mode::CompilerIf;
        consume();
        nodePtr->nodeModeRef = parseExpression();
    }
    else if (is(TokenId::KwdUsing))
    {
        nodePtr->mode        = AstCompilerGlobal::Mode::Using;
        nodePtr->nodeModeRef = parseUsing();
    }
    else
    {
        raiseError(DiagnosticId::parser_err_unexpected_token, ref());
        skipTo({TokenId::SymSemiColon, TokenId::SymRightCurly}, SkipUntilFlagsE::EolBefore);
    }

    return nodeRef;
}

AstNodeRef Parser::parseCompilerImport()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerImport>(consume());
    const auto openRef      = ref();

    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    nodePtr->tokModuleNameRef = expectAndConsume(TokenId::StringLine, DiagnosticId::parser_err_expected_token_before);
    nodePtr->tokLocationRef   = TokenRef::invalid();
    nodePtr->tokVersionRef    = TokenRef::invalid();

    if (consumeIf(TokenId::SymComma).isValid())
    {
        auto tokStr = tok().string(ast_->srcView());
        if (tokStr == Token::toName(TokenId::KwdLocation))
        {
            consume();
            expectAndConsume(TokenId::SymColon, DiagnosticId::parser_err_expected_token_before);
            nodePtr->tokLocationRef = expectAndConsume(TokenId::StringLine, DiagnosticId::parser_err_expected_token_before);
            if (consumeIf(TokenId::SymComma).isValid())
            {
                tokStr = tok().string(ast_->srcView());
                if (tokStr == Token::toName(TokenId::KwdVersion))
                {
                    consume();
                    expectAndConsume(TokenId::SymColon, DiagnosticId::parser_err_expected_token_before);
                    nodePtr->tokVersionRef = expectAndConsume(TokenId::StringLine, DiagnosticId::parser_err_expected_token_before);
                }
            }
        }
    }

    expectAndConsumeClosing(TokenId::SymRightParen, openRef);

    return nodeRef;
}

AstNodeRef Parser::parseCompilerScope()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerScope>(consume());

    const auto openRef = ref();
    if (consumeIf(TokenId::SymLeftParen).isValid())
    {
        nodePtr->tokNameRef = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_before);
        expectAndConsumeClosing(TokenId::SymRightParen, openRef);
    }

    nodePtr->nodeBodyRef = parseEmbeddedStmt();
    return nodeRef;
}

AstNodeRef Parser::parseCompilerMacro()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerMacro>(consume());
    nodePtr->nodeBodyRef    = parseCompound<AstNodeId::EmbeddedBlock>(TokenId::SymLeftCurly);
    return nodeRef;
}

AstNodeRef Parser::parseCompilerInject()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerInject>(consume());
    const auto openRef      = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);

    nodePtr->nodeExprRef = parseExpression();
    nodePtr->nodeReplaceBreakRef.setInvalid();
    nodePtr->nodeReplaceContinueRef.setInvalid();

    while (consumeIf(TokenId::SymComma).isValid())
    {
        // Replacement for 'break'
        if (consumeIf(TokenId::KwdBreak).isValid())
        {
            if (nodePtr->nodeReplaceBreakRef.isValid())
            {
                raiseError(DiagnosticId::parser_err_inject_instruction_done, ref());
                skipTo({TokenId::SymRightParen, TokenId::SymLeftParen});
                continue;
            }

            expectAndConsume(TokenId::SymEqual, DiagnosticId::parser_err_expected_token_before);
            nodePtr->nodeReplaceBreakRef = parseEmbeddedStmt();
            continue;
        }

        // Replacement for 'continue'
        if (consumeIf(TokenId::KwdContinue).isValid())
        {
            if (nodePtr->nodeReplaceContinueRef.isValid())
            {
                raiseError(DiagnosticId::parser_err_inject_instruction_done, ref());
                skipTo({TokenId::SymRightParen, TokenId::SymLeftParen});
                continue;
            }

            expectAndConsume(TokenId::SymEqual, DiagnosticId::parser_err_expected_token_before);
            nodePtr->nodeReplaceContinueRef = parseEmbeddedStmt();
            continue;
        }

        raiseError(DiagnosticId::parser_err_inject_invalid_instruction, ref());
        skipTo({TokenId::SymRightParen});
        break;
    }

    expectAndConsumeClosing(TokenId::SymRightParen, openRef);

    return nodeRef;
}

AstNodeRef Parser::parseCompilerUp()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AncestorIdentifier>(consume());
    const auto openRef      = ref();
    if (consumeIf(TokenId::SymLeftParen).isValid())
    {
        nodePtr->nodeValueRef = parseExpression();
        expectAndConsumeClosing(TokenId::SymRightParen, openRef);
    }
    else
        nodePtr->nodeValueRef.setInvalid();

    nodePtr->nodeIdentRef = parseQualifiedIdentifier();
    return nodeRef;
}

SWC_END_NAMESPACE();
