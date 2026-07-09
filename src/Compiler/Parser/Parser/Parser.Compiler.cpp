#include "pch.h"
#include "Compiler/Parser/Parser/Parser.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    TokenRef findInjectReplacement(const SourceView& srcView, const std::span<const TokenRef>& replacementInstructionRefs, TokenId tokenId)
    {
        for (const TokenRef instructionRef : replacementInstructionRefs)
        {
            if (srcView.token(instructionRef).id == tokenId)
                return instructionRef;
        }

        return TokenRef::invalid();
    }
}

AstNodeRef Parser::parseCompilerExpression()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerExpression>(ref());
    nodePtr->nodeExprRef    = parseExpression();
    return nodeRef;
}

AstNodeRef Parser::parseCompilerDiagnostic()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerDiagnostic>(consume());

    const TokenRef openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    nodePtr->nodeArgRef = parseCompilerExpression();
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);

    return nodeRef;
}

AstNodeRef Parser::parseCompilerTypeOf()
{
    const TokenRef tokRef   = consume();
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerCallOne>(tokRef);

    const TokenRef          openRef = ref();
    SmallVector<AstNodeRef> nodeArgs;
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);

    while (isNot(TokenId::SymRightParen) && isNot(TokenId::EndOfFile))
    {
        if (!nodeArgs.empty())
        {
            // Error recovery can land on a container closer from the surrounding
            // syntax. Stop there and let expectAndConsumeClosing handle the final
            // diagnostic instead of eating tokens from the parent construct.
            if (isAny(TokenId::SymRightCurly, TokenId::SymRightBracket))
                break;
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
        const Diagnostic diag = reportArgumentCountError(DiagnosticId::parser_err_too_few_arguments, tokRef, ref(), 1, static_cast<uint32_t>(nodeArgs.size()));
        diag.report(*ctx_);
    }
    else if (nodeArgs.size() > 1)
    {
        const Diagnostic diag = reportArgumentCountError(DiagnosticId::parser_err_too_many_arguments, tokRef, nodeArgs[1], 1, static_cast<uint32_t>(nodeArgs.size()));
        diag.report(*ctx_);
    }

    nodePtr->nodeArgRef = nodeArgs.empty() ? AstNodeRef::invalid() : nodeArgs[0];
    expectAndConsumeClosing(TokenId::SymRightParen, openRef, {TokenId::SymRightCurly, TokenId::SymRightBracket});
    return nodeRef;
}

AstNodeRef Parser::parseCompilerCall(uint32_t numParams)
{
    if (numParams == 1)
        return parseCompilerCallOne();

    const TokenRef tokRef   = consume();
    const TokenId  tokenId  = ast_->srcView().token(tokRef).id;
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerCall>(tokRef);

    const TokenRef          openRef = ref();
    SmallVector<AstNodeRef> nodeArgs;
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);

    ParserContextFlags parseFlags = ParserContextFlagsE::Zero;
    if (tokenId == TokenId::CompilerDefined)
        parseFlags = ParserContextFlagsE::InCompilerDefined;
    const PushContextFlags context(this, parseFlags);

    while (isNot(TokenId::SymRightParen) && isNot(TokenId::EndOfFile))
    {
        if (!nodeArgs.empty())
        {
            if (isAny(TokenId::SymRightCurly, TokenId::SymRightBracket))
                break;
            if (expectAndConsume(TokenId::SymComma, DiagnosticId::parser_err_expected_token).isInvalid())
                skipTo({TokenId::SymComma, TokenId::SymRightParen});
            if (is(TokenId::SymRightParen))
                break;
        }

        nodeArgs.push_back(parseExpression());
    }

    if (nodeArgs.size() < numParams)
    {
        const Diagnostic diag = reportArgumentCountError(DiagnosticId::parser_err_too_few_arguments, tokRef, ref(), numParams, static_cast<uint32_t>(nodeArgs.size()));
        diag.report(*ctx_);
    }
    else if (nodeArgs.size() > numParams)
    {
        const Diagnostic diag = reportArgumentCountError(DiagnosticId::parser_err_too_many_arguments, tokRef, nodeArgs[numParams], numParams, static_cast<uint32_t>(nodeArgs.size()));
        diag.report(*ctx_);
    }

    nodePtr->spanChildrenRef = ast_->pushSpan(nodeArgs.span());
    expectAndConsumeClosing(TokenId::SymRightParen, openRef, {TokenId::SymRightCurly, TokenId::SymRightBracket});
    return nodeRef;
}

AstNodeRef Parser::parseCompilerCallOne()
{
    const TokenRef tokRef   = consume();
    const TokenId  tokenId  = ast_->srcView().token(tokRef).id;
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerCallOne>(tokRef);

    const TokenRef          openRef = ref();
    SmallVector<AstNodeRef> nodeArgs;
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);

    ParserContextFlags parseFlags = ParserContextFlagsE::Zero;
    if (tokenId == TokenId::CompilerDefined)
        parseFlags = ParserContextFlagsE::InCompilerDefined;
    const PushContextFlags context(this, parseFlags);

    while (isNot(TokenId::SymRightParen) && isNot(TokenId::EndOfFile))
    {
        if (!nodeArgs.empty())
        {
            if (isAny(TokenId::SymRightCurly, TokenId::SymRightBracket))
                break;
            if (expectAndConsume(TokenId::SymComma, DiagnosticId::parser_err_expected_token).isInvalid())
                skipTo({TokenId::SymComma, TokenId::SymRightParen});
            if (is(TokenId::SymRightParen))
                break;
        }

        nodeArgs.push_back(parseExpression());
    }

    if (nodeArgs.empty())
    {
        const Diagnostic diag = reportArgumentCountError(DiagnosticId::parser_err_too_few_arguments, tokRef, ref(), 1, static_cast<uint32_t>(nodeArgs.size()));
        diag.report(*ctx_);
    }
    else if (nodeArgs.size() > 1)
    {
        const Diagnostic diag = reportArgumentCountError(DiagnosticId::parser_err_too_many_arguments, tokRef, nodeArgs[1], 1, static_cast<uint32_t>(nodeArgs.size()));
        diag.report(*ctx_);
    }

    nodePtr->nodeArgRef = nodeArgs.empty() ? AstNodeRef::invalid() : nodeArgs[0];
    expectAndConsumeClosing(TokenId::SymRightParen, openRef, {TokenId::SymRightCurly, TokenId::SymRightBracket});
    return nodeRef;
}

AstNodeRef Parser::parseCompilerFunc()
{
    const TokenId what = id();

    if (what == TokenId::CompilerRun || nextIs(TokenId::SymLeftCurly))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerFunc>(consume());
        if (is(TokenId::SymLeftCurly))
            nodePtr->nodeBodyRef = parseFunctionBody();
        else if (what == TokenId::CompilerAst)
            nodePtr->nodeBodyRef = parseExpression();
        else
            nodePtr->nodeBodyRef = parseEmbeddedStmt();
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
    const TokenRef openRef  = ref();

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

    // '#code => expr': explicit expression literal, mirroring 'func() => expr'
    if (nextIs(TokenId::SymEqualGreater))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerCodeExpr>(consume());
        consumeAssert(TokenId::SymEqualGreater);
        nodePtr->nodeExprRef = parseExpression();
        return nodeRef;
    }

    // '#code(a, b) { ... }' / '#code(a) => expr': literal with binder names that
    // rename the callee's block parameters at the call site.
    if (isCodeLiteralBinderAhead())
    {
        const TokenRef tokCode = consume();
        const SpanRef  binder  = parseCodeBinderNames();

        if (is(TokenId::SymLeftCurly))
        {
            auto [nodeRef, nodePtr]     = ast_->makeNode<AstNodeId::CompilerCodeBlock>(tokCode);
            nodePtr->spanBinderNamesRef = binder;
            nodePtr->nodeBodyRef        = parseFunctionBody();
            return nodeRef;
        }

        consumeAssert(TokenId::SymEqualGreater);
        auto [nodeRef, nodePtr]     = ast_->makeNode<AstNodeId::CompilerCodeExpr>(tokCode);
        nodePtr->spanBinderNamesRef = binder;
        nodePtr->nodeExprRef        = parseExpression();
        return nodeRef;
    }

    raiseError(DiagnosticId::parser_err_unexpected_token, ref());
    consume();
    return AstNodeRef::invalid();
}

bool Parser::isCodeLiteralBinderAhead() const
{
    // '#code' '(' [ident {',' ident}] ')' followed by '{' or '=>'. Anything else
    // is the legacy expression literal (e.g. '#code (a + b)').
    const Token* t = curToken_ + 1;
    if (t >= lastToken_ || t->id != TokenId::SymLeftParen)
        return false;

    ++t;
    while (t < lastToken_ && t->id != TokenId::SymRightParen)
    {
        if (t->id != TokenId::Identifier)
            return false;
        ++t;
        if (t < lastToken_ && t->id == TokenId::SymComma)
        {
            ++t;
            continue;
        }
        break;
    }

    if (t >= lastToken_ || t->id != TokenId::SymRightParen)
        return false;

    ++t;
    return t < lastToken_ && (t->id == TokenId::SymLeftCurly || t->id == TokenId::SymEqualGreater);
}

SpanRef Parser::parseCodeBinderNames()
{
    const TokenRef openRef = consumeAssert(TokenId::SymLeftParen);

    SmallVector<TokenRef> names;
    while (!atEnd() && isNot(TokenId::SymRightParen))
    {
        const TokenRef nameRef = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_before);
        if (nameRef.isInvalid())
            break;
        names.push_back(nameRef);

        if (isNot(TokenId::SymRightParen) &&
            expectAndConsume(TokenId::SymComma, DiagnosticId::parser_err_expected_token_before).isInvalid())
            break;
    }

    expectAndConsumeClosing(TokenId::SymRightParen, openRef);
    return names.empty() ? SpanRef::invalid() : ast_->pushSpan(names.span());
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
        // `#if cond do expr` and `#if cond do { ... }` share the same entry point.
        // A block after `do` is accepted for recovery, but diagnosed because the
        // block form normally omits `do`.
        if (is(TokenId::SymLeftCurly))
        {
            const Diagnostic diag = reportUnexpectedDoBlock(ref().offset(-1));
            diag.report(*ctx_);
            return parseCompound<ID>(TokenId::SymLeftCurly);
        }

        return parseCompoundValue(ID);
    }

    if (is(TokenId::SymLeftCurly))
        return parseCompound<ID>(TokenId::SymLeftCurly);

    const Diagnostic diag = reportExpectedDoBlock(ref().offset(-1));
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

    // Parse optional 'else' or 'elif' block. Else-if is nested in the else slot so
    // compiler-if chains have the same AST shape as regular if chains.
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
    auto [nodeRef, nodePtr]       = ast_->makeNode<AstNodeId::CompilerGlobal>(consume());
    const std::string_view tokStr = tok().string(ast_->srcView());

    nodePtr->spanNameRef.setInvalid();
    nodePtr->nodeModeRef.setInvalid();

    if (tokStr == Token::toName(TokenId::KwdGenerated))
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
        nodePtr->mode             = AstCompilerGlobal::Mode::AttributeList;
        nodePtr->nodeModeRef      = parseCompound<AstNodeId::AttributeList>(TokenId::SymAttrStart);
        AstAttributeList* attrPtr = ast_->node<AstNodeId::AttributeList>(nodePtr->nodeModeRef);
        attrPtr->nodeBodyRef.setInvalid();
    }
    else if (is(TokenId::KwdPublic))
    {
        nodePtr->mode        = AstCompilerGlobal::Mode::AccessPublic;
        nodePtr->nodeModeRef = AstNodeRef::invalid();
        consume();
    }
    else if (is(TokenId::KwdPrivate))
    {
        nodePtr->mode        = AstCompilerGlobal::Mode::AccessPrivate;
        nodePtr->nodeModeRef = AstNodeRef::invalid();
        consume();
    }
    else if (is(TokenId::KwdInternal))
    {
        nodePtr->mode        = AstCompilerGlobal::Mode::AccessInternal;
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
    const TokenRef openRef  = ref();

    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    nodePtr->tokModuleNameRef = expectAndConsume(TokenId::StringLine, DiagnosticId::parser_err_expected_token_before);
    nodePtr->tokLocationRef   = TokenRef::invalid();
    nodePtr->tokLinkRef       = TokenRef::invalid();
    nodePtr->tokVersionRef    = TokenRef::invalid();

    while (consumeIf(TokenId::SymComma).isValid())
    {
        TokenRef*              targetRef = nullptr;
        const std::string_view tokStr    = tok().string(ast_->srcView());
        if (tokStr == Token::toName(TokenId::KwdLocation))
            targetRef = &nodePtr->tokLocationRef;
        else if (tokStr == Token::toName(TokenId::KwdLink))
            targetRef = &nodePtr->tokLinkRef;
        else if (tokStr == Token::toName(TokenId::KwdVersion))
            targetRef = &nodePtr->tokVersionRef;
        else
        {
            raiseError(DiagnosticId::parser_err_unexpected_token, ref());
            skipTo({TokenId::SymComma, TokenId::SymRightParen});
            continue;
        }

        consume();
        expectAndConsume(TokenId::SymColon, DiagnosticId::parser_err_expected_token_before);
        *targetRef = expectAndConsume(TokenId::StringLine, DiagnosticId::parser_err_expected_token_before);
    }

    expectAndConsumeClosing(TokenId::SymRightParen, openRef);

    return nodeRef;
}

AstNodeRef Parser::parseCompilerScope()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerScope>(consume());

    const TokenRef openRef = ref();
    if (consumeIf(TokenId::SymLeftParen).isValid())
    {
        nodePtr->tokNameRef = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_before);
        expectAndConsumeClosing(TokenId::SymRightParen, openRef);
    }

    nodePtr->nodeBodyRef = parseEmbeddedStmt();
    return nodeRef;
}

AstNodeRef Parser::parseCompilerInject()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerInject>(consume());
    const TokenRef openRef  = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);

    nodePtr->nodeExprRef               = parseExpression();
    nodePtr->spanReplaceInstructionRef = SpanRef::invalid();
    nodePtr->spanReplaceNodeRef        = SpanRef::invalid();
    SmallVector<TokenRef>   replacementInstructionRefs;
    SmallVector<AstNodeRef> replacementNodeRefs;
    SmallVector<TokenRef>   bindingNameRefs;
    SmallVector<AstNodeRef> bindingNodeRefs;

    while (consumeIf(TokenId::SymComma).isValid())
    {
        if (isAny(TokenId::KwdBreak, TokenId::KwdContinue))
        {
            const TokenId  replacementId          = id();
            const TokenRef instructionRef         = consume();
            const TokenRef previousInstructionRef = findInjectReplacement(ast_->srcView(), replacementInstructionRefs.span(), replacementId);
            if (previousInstructionRef.isValid())
            {
                Diagnostic diag = reportError(DiagnosticId::parser_err_inject_instruction_done, instructionRef);
                diag.addArgument(Diagnostic::ARG_SYM, Token::toName(replacementId));
                diag.last().addSpan(ast_->srcView().tokenCodeRange(*ctx_, previousInstructionRef), DiagnosticId::parser_note_other_def, DiagnosticSeverity::Note);
                diag.report(*ctx_);
                skipTo({TokenId::SymRightParen, TokenId::SymLeftParen});
                continue;
            }

            expectAndConsume(TokenId::SymEqual, DiagnosticId::parser_err_expected_token_before);
            replacementInstructionRefs.push_back(instructionRef);
            replacementNodeRefs.push_back(parseEmbeddedStmt());
            continue;
        }

        // '#inject(stmt, name = expr)': named value binding for a declared
        // '#code' parameter of the injected code.
        if (is(TokenId::Identifier) && nextIs(TokenId::SymEqual))
        {
            bindingNameRefs.push_back(consume());
            consumeAssert(TokenId::SymEqual);
            bindingNodeRefs.push_back(parseExpression());
            continue;
        }

        raiseError(DiagnosticId::parser_err_inject_invalid_instruction, ref());
        skipTo({TokenId::SymRightParen});
        break;
    }

    expectAndConsumeClosing(TokenId::SymRightParen, openRef);
    if (!replacementInstructionRefs.empty())
    {
        nodePtr->spanReplaceInstructionRef = ast_->pushSpan(replacementInstructionRefs.span());
        nodePtr->spanReplaceNodeRef        = ast_->pushSpan(replacementNodeRefs.span());
    }
    if (!bindingNameRefs.empty())
    {
        nodePtr->spanBindingNameRef = ast_->pushSpan(bindingNameRefs.span());
        nodePtr->spanBindingNodeRef = ast_->pushSpan(bindingNodeRefs.span());
    }

    return nodeRef;
}

SWC_END_NAMESPACE();
