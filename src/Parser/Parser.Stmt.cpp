#include "pch.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseTopLevelCall()
{
    auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::CallExpr>(ref());
    nodePtr->nodeExprRef     = parseQualifiedIdentifier();
    nodePtr->spanChildrenRef = parseCompoundContent(AstNodeId::NamedArgumentList, TokenId::SymLeftParen);
    return nodeRef;
}

AstNodeRef Parser::parseAccessModifier()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AccessModifier>(consume());

    switch (id())
    {
        case TokenId::KwdPublic:
        case TokenId::KwdPrivate:
        case TokenId::KwdInternal:
            raiseError(DiagnosticId::parser_err_duplicate_modifier, ref());
            skipTo({TokenId::SymSemiColon, TokenId::SymRightCurly}, SkipUntilFlagsE::EolBefore);
            return AstNodeRef::invalid();
        default:
            break;
    }

    nodePtr->nodeWhatRef = parseTopLevelDeclOrBlock();
    return nodeRef;
}

AstNodeRef Parser::parseUsing()
{
    if (nextIs(TokenId::KwdNamespace))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::UsingNamespaceStmt>(consume());
        nodePtr->nodeNameRef    = parseNamespace();
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::UsingDecl>(consume());

    SmallVector<AstNodeRef> nodeChildren;
    auto                    nodeIdentifier = parseQualifiedIdentifier();
    nodeChildren.push_back(nodeIdentifier);
    while (consumeIf(TokenId::SymComma).isValid())
    {
        nodeIdentifier = parseQualifiedIdentifier();
        nodeChildren.push_back(nodeIdentifier);
    }

    nodePtr->spanChildrenRef = ast_->pushSpan(nodeChildren.span());
    expectEndStatement();

    return nodeRef;
}

AstNodeRef Parser::parseConstraint()
{
    if (nextIs(TokenId::SymLeftCurly))
    {
        auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::ConstraintBlock>(consume());
        nodePtr->spanChildrenRef = parseCompoundContent(AstNodeId::EmbeddedBlock, TokenId::SymLeftCurly);
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ConstraintExpr>(consume());
    nodePtr->nodeExprRef    = parseExpression();
    return nodeRef;
}

AstNodeRef Parser::parseAlias()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AliasDecl>(consume());
    nodePtr->tokNameRef     = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam);
    expectAndConsume(TokenId::SymEqual, DiagnosticId::parser_err_expected_token_fam);

    // 1) Definitely looks like a type (array, func, struct literal type, pointer type, etc.)
    if (isAny(TokenId::CompilerDeclType,
              TokenId::SymLeftBracket,
              TokenId::SymLeftCurly,
              TokenId::KwdFunc,
              TokenId::KwdMtd,
              TokenId::KwdConst,
              TokenId::ModifierNullable,
              TokenId::SymAsterisk))
    {
        nodePtr->nodeExprRef = parseType();
    }

    // 2) Built-in scalar types, etc.
    else if (Token::isType(id()))
    {
        nodePtr->nodeExprRef = parseType();
    }

    // 3) Otherwise, allow only a symbol / qualified name as RHS
    else if (is(TokenId::Identifier) ||
             is(TokenId::CompilerAlias0) || is(TokenId::CompilerAlias1) ||
             is(TokenId::CompilerAlias2) || is(TokenId::CompilerAlias3) ||
             is(TokenId::CompilerAlias4) || is(TokenId::CompilerAlias5) ||
             is(TokenId::CompilerAlias6) || is(TokenId::CompilerAlias7) ||
             is(TokenId::CompilerAlias8) || is(TokenId::CompilerAlias9))
    {
        nodePtr->nodeExprRef = parseQualifiedIdentifier();
    }

    // 4) Everything else: error (e.g. "alias A = 1 + 2")
    else
    {
        raiseError(DiagnosticId::parser_err_expected_type_or_symbol, ref());
        skipTo({TokenId::SymSemiColon, TokenId::SymRightCurly}, SkipUntilFlagsE::EolBefore);
        return AstNodeRef::invalid();
    }

    return nodeRef;
}

AstNodeRef Parser::parseReturn()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ReturnStmt>(consume());
    if (is(TokenId::SymSemiColon) || tok().startsLine())
        nodePtr->nodeExprRef.setInvalid();
    else
        nodePtr->nodeExprRef = parseExpression();

    return nodeRef;
}

AstNodeRef Parser::parseUnreachable()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::UnreachableStmt>(consume());
    return nodeRef;
}

AstNodeRef Parser::parseContinue()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ContinueStmt>(consume());
    return nodeRef;
}

AstNodeRef Parser::parseBreak()
{
    if (nextIs(TokenId::KwdTo))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ScopedBreakStmt>(ref());
        consumeAssert(TokenId::KwdBreak);
        consumeAssert(TokenId::KwdTo);
        nodePtr->tokNameRef = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam);

        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::BreakStmt>(consume());
    return nodeRef;
}

AstNodeRef Parser::parseFallThrough()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::FallThroughStmt>(consume());
    return nodeRef;
}

AstNodeRef Parser::parseDefer()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::DeferStmt>(consume());
    nodePtr->modifierFlags  = parseModifiers();
    nodePtr->nodeBodyRef    = parseEmbeddedStmt();
    return nodeRef;
}

AstNodeRef Parser::parseIf()
{
    if (nextIsAny(TokenId::KwdVar, TokenId::KwdLet, TokenId::KwdConst))
    {
        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IfVarDecl>(consume());

        // Parse the variable declaration and the constraint
        nodePtr->nodeVarRef = parseVarDecl();
        if (consumeIf(TokenId::KwdWhere).isValid())
            nodePtr->nodeWhereRef = parseExpression();
        else
            nodePtr->nodeWhereRef.setInvalid();

        nodePtr->nodeIfBlockRef = parseDoCurlyBlock();
        if (is(TokenId::KwdElseIf))
            nodePtr->nodeElseBlockRef = parseIf();
        else if (consumeIf(TokenId::KwdElse).isValid())
            nodePtr->nodeElseBlockRef = parseDoCurlyBlock();
        else
            nodePtr->nodeElseBlockRef.setInvalid();

        return nodeRef;
    }

    const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IfStmt>(consume());

    // Parse the condition expression
    nodePtr->nodeConditionRef = parseExpression();
    if (nodePtr->nodeConditionRef.isInvalid())
        skipTo({TokenId::KwdDo, TokenId::SymLeftCurly});

    nodePtr->nodeIfBlockRef = parseDoCurlyBlock();
    if (is(TokenId::KwdElseIf))
        nodePtr->nodeElseBlockRef = parseIf();
    else if (consumeIf(TokenId::KwdElse).isValid())
        nodePtr->nodeElseBlockRef = parseDoCurlyBlock();
    else
        nodePtr->nodeElseBlockRef.setInvalid();

    return nodeRef;
}

AstNodeRef Parser::parseWith()
{
    if (nextIsAny(TokenId::KwdVar, TokenId::KwdLet))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::WithVarDecl>(consume());
        nodePtr->nodeVarRef     = parseVarDecl();
        nodePtr->nodeBodyRef    = parseEmbeddedStmt();
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::WithStmt>(consume());
    nodePtr->nodeExprRef    = parseAssignStmt();
    nodePtr->nodeBodyRef    = parseEmbeddedStmt();
    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicInit()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicInit>(consume());
    const auto openRef      = ref();

    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    nodePtr->nodeWhatRef = parseExpression();
    if (consumeIf(TokenId::SymComma).isValid())
        nodePtr->nodeCountRef = parseExpression();
    else
        nodePtr->nodeCountRef.setInvalid();
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);

    if (is(TokenId::SymLeftParen))
        nodePtr->spanArgsRef = parseCompoundContent(AstNodeId::UnnamedArgumentList, TokenId::SymLeftParen);
    else
        nodePtr->spanArgsRef.setInvalid();

    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicDrop()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicDrop>(consume());
    const auto openRef      = ref();

    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    nodePtr->nodeWhatRef = parseExpression();
    if (consumeIf(TokenId::SymComma).isValid())
        nodePtr->nodeCountRef = parseExpression();
    else
        nodePtr->nodeCountRef.setInvalid();
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);

    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicPostCopy()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicPostCopy>(consume());
    const auto openRef      = ref();

    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    nodePtr->nodeWhatRef = parseExpression();
    if (consumeIf(TokenId::SymComma).isValid())
        nodePtr->nodeCountRef = parseExpression();
    else
        nodePtr->nodeCountRef.setInvalid();
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);

    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicPostMove()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicPostMove>(consume());
    const auto openRef      = ref();

    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    nodePtr->nodeWhatRef = parseExpression();
    if (consumeIf(TokenId::SymComma).isValid())
        nodePtr->nodeCountRef = parseExpression();
    else
        nodePtr->nodeCountRef.setInvalid();
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);

    return nodeRef;
}

AstNodeRef Parser::parseWhile()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::WhileStmt>(consume());
    nodePtr->nodeExprRef    = parseExpression();
    nodePtr->nodeBodyRef    = parseDoCurlyBlock();
    return nodeRef;
}

AstNodeRef Parser::parseForCpp()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ForCStyleStmt>(consume());
    nodePtr->nodeVarDeclRef = parseVarDecl();
    expectAndConsume(TokenId::SymSemiColon, DiagnosticId::parser_err_expected_token_before);

    nodePtr->nodeExprRef = parseExpression();
    expectAndConsume(TokenId::SymSemiColon, DiagnosticId::parser_err_expected_token_before);

    nodePtr->nodePostStmtRef = parseEmbeddedStmt();
    nodePtr->nodeBodyRef     = parseDoCurlyBlock();
    return nodeRef;
}

AstNodeRef Parser::parseForInfinite()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::InfiniteLoopStmt>(consume());
    nodePtr->nodeBodyRef    = parseDoCurlyBlock();
    return nodeRef;
}

AstNodeRef Parser::parseForLoop()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ForStmt>(consume());
    nodePtr->modifierFlags  = parseModifiers();
    nodePtr->tokNameRef.setInvalid();

    if (isNot(TokenId::SymLeftParen))
    {
        if (nextIs(TokenId::KwdIn))
        {
            nodePtr->tokNameRef = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam);
            consumeAssert(TokenId::KwdIn);
        }
    }

    nodePtr->nodeExprRef = parseRangeExpression();

    if (consumeIf(TokenId::KwdWhere).isValid())
        nodePtr->nodeWhereRef = parseExpression();
    else
        nodePtr->nodeWhereRef.setInvalid();

    nodePtr->nodeBodyRef = parseDoCurlyBlock();
    return nodeRef;
}

AstNodeRef Parser::parseFor()
{
    if (nextIs(TokenId::KwdVar))
        return parseForCpp();
    if (nextIsAny(TokenId::SymLeftCurly, TokenId::KwdDo))
        return parseForInfinite();
    return parseForLoop();
}

AstNodeRef Parser::parseForeach()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ForeachStmt>(consume());

    // Specialization
    nodePtr->tokSpecializationRef = consumeIf(TokenId::SharpIdentifier);

    // Additional flags
    nodePtr->modifierFlags = parseModifiers();

    SmallVector<TokenRef> tokNames;

    // By address
    if (consumeIf(TokenId::SymAmpersand).isValid())
    {
        nodePtr->addFlag(AstForeachStmtFlagsE::ByAddress);
        const auto tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);
        tokNames.push_back(tokName);
    }
    else if (nextIsAny(TokenId::KwdIn, TokenId::SymComma))
    {
        const auto tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);
        tokNames.push_back(tokName);
    }

    while (consumeIf(TokenId::SymComma).isValid())
    {
        auto tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);
        tokNames.push_back(tokName);
    }

    nodePtr->spanNamesRef = ast_->pushSpan(tokNames.span());
    if (!tokNames.empty())
        expectAndConsume(TokenId::KwdIn, DiagnosticId::parser_err_expected_token_before);

    nodePtr->nodeExprRef = parseExpression();

    if (consumeIf(TokenId::KwdWhere).isValid())
        nodePtr->nodeWhereRef = parseExpression();
    else
        nodePtr->nodeWhereRef.setInvalid();

    nodePtr->nodeBodyRef = parseDoCurlyBlock();
    return nodeRef;
}

AstNodeRef Parser::parseTryCatch()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::TryCatchStmt>(consume());
    if (is(TokenId::SymLeftCurly))
        nodePtr->nodeBodyRef = parseCompound<AstNodeId::EmbeddedBlock>(TokenId::SymLeftCurly);
    else
        nodePtr->nodeBodyRef = parseExpression();
    return nodeRef;
}

AstNodeRef Parser::parseDiscard()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::DiscardExpr>(consume());
    nodePtr->nodeExprRef    = parseExpression();
    return nodeRef;
}

AstNodeRef Parser::parseSwitchCaseDefault()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::SwitchCaseStmt>(ref());
    if (consumeIf(TokenId::KwdCase).isValid())
    {
        SmallVector<AstNodeRef> nodeExpressions;
        auto                    nodeExpr = parseRangeExpression();
        nodeExpressions.push_back(nodeExpr);
        while (consumeIf(TokenId::SymComma).isValid())
        {
            nodeExpr = parseRangeExpression();
            nodeExpressions.push_back(nodeExpr);
        }

        nodePtr->spanExprRef = ast_->pushSpan(nodeExpressions.span());
    }
    else
    {
        consume();
        nodePtr->spanExprRef.setInvalid();
    }

    if (consumeIf(TokenId::KwdWhere).isValid())
        nodePtr->nodeWhereRef = parseExpression();
    else
        nodePtr->nodeWhereRef.setInvalid();

    expectAndConsume(TokenId::SymColon, DiagnosticId::parser_err_expected_token_before);
    return nodeRef;
}

AstNodeRef Parser::parseSwitch()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::SwitchStmt>(consume());

    if (isNot(TokenId::SymLeftCurly))
        nodePtr->nodeExprRef = parseExpression();
    else
        nodePtr->nodeExprRef.setInvalid();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftCurly, DiagnosticId::parser_err_expected_token_before);

    SmallVector<AstNodeRef> nodeChildren;
    SmallVector<AstNodeRef> nodeStmts;
    AstSwitchCaseStmt*      currentCase = nullptr;

    while (isNot(TokenId::SymRightCurly) && !atEnd())
    {
        switch (id())
        {
            case TokenId::KwdDefault:
            case TokenId::KwdCase:
            {
                if (currentCase)
                    currentCase->spanChildrenRef = ast_->pushSpan(nodeStmts.span());
                nodeStmts.clear();

                auto caseRef = parseSwitchCaseDefault();
                nodeChildren.push_back(caseRef);
                currentCase = ast_->node<AstNodeId::SwitchCaseStmt>(caseRef);
                break;
            }

            default:
            {
                auto stmtRef = parseEmbeddedStmt();
                nodeStmts.push_back(stmtRef);
                break;
            }
        }
    }

    if (currentCase)
        currentCase->spanChildrenRef = ast_->pushSpan(nodeStmts.span());

    nodePtr->spanChildrenRef = ast_->pushSpan(nodeChildren.span());
    expectAndConsumeClosing(TokenId::SymRightCurly, openRef);
    return nodeRef;
}

AstNodeRef Parser::parseFile()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::File>(ref());

    // #global must be first
    SmallVector<AstNodeRef> globals;
    while (is(TokenId::CompilerGlobal))
    {
        AstNodeRef one = parseCompilerGlobal();
        if (ast_->hasFlag(AstFlagsE::GlobalSkip))
        {
            nodePtr->spanGlobalsRef.setInvalid();
            nodePtr->spanChildrenRef.setInvalid();
            return nodeRef;
        }

        if (one.isValid())
            globals.push_back(one);
    }

    nodePtr->spanGlobalsRef = ast_->pushSpan(globals.span());

    // Then using
    SmallVector<AstNodeRef> usings;
    while (is(TokenId::KwdUsing))
    {
        AstNodeRef one = parseUsing();
        if (one.isValid())
            usings.push_back(one);
    }

    nodePtr->spanUsingsRef = ast_->pushSpan(usings.span());

    // All the rest
    nodePtr->spanChildrenRef = parseCompoundContent(AstNodeId::TopLevelBlock, TokenId::Invalid);
    return nodeRef;
}

SpanRef Parser::parseQualifiedName()
{
    SmallVector<TokenRef> names;
    TokenRef              tokRef = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam);
    if (tokRef.isInvalid())
    {
        skipTo({TokenId::SymLeftCurly});
        return SpanRef::invalid();
    }

    names.push_back(tokRef);
    while (consumeIf(TokenId::SymDot).isValid())
    {
        tokRef = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam);
        if (tokRef.isInvalid())
        {
            skipTo({TokenId::SymLeftCurly});
            break;
        }

        names.push_back(tokRef);
    }

    return ast_->pushSpan(names.span());
}

AstNodeRef Parser::parseNamespace()
{
    auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::NamespaceDecl>(consume());
    nodePtr->spanNameRef     = parseQualifiedName();
    nodePtr->spanChildrenRef = parseCompoundContent(AstNodeId::TopLevelBlock, TokenId::SymLeftCurly);
    return nodeRef;
}

AstNodeRef Parser::parseDoCurlyBlock()
{
    if (consumeIf(TokenId::KwdDo).isValid())
    {
        if (is(TokenId::SymLeftCurly))
        {
            raiseError(DiagnosticId::parser_err_unexpected_do_block, ref().offset(-1));
            return parseCompound<AstNodeId::EmbeddedBlock>(TokenId::SymLeftCurly);
        }

        return parseEmbeddedStmt();
    }

    if (is(TokenId::SymLeftCurly))
        return parseCompound<AstNodeId::EmbeddedBlock>(TokenId::SymLeftCurly);

    const auto diag = reportError(DiagnosticId::parser_err_expected_do_block, ref().offset(-1));
    diag.report(*ctx_);
    return AstNodeRef::invalid();
}

AstNodeRef Parser::parseAssignStmt()
{
    AstNodeRef nodeLeft;

    // Decomposition
    if (is(TokenId::SymLeftParen))
    {
        const auto openRef            = consume();
        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AssignListStmt>(ref());
        nodePtr->addFlag(AstAssignListStmtFlagsE::Decomposition);
        if (consumeIf(TokenId::SymQuestion).isValid())
            nodeLeft = AstNodeRef::invalid();
        else
            nodeLeft = parseExpression();

        SmallVector<AstNodeRef> nodeAffects;
        nodeAffects.push_back(nodeLeft);
        while (consumeIf(TokenId::SymComma).isValid())
        {
            if (consumeIf(TokenId::SymQuestion).isValid())
                nodeAffects.push_back(AstNodeRef::invalid());
            else
                nodeAffects.push_back(parseExpression());
        }

        expectAndConsumeClosing(TokenId::SymRightParen, openRef);

        nodePtr->spanChildrenRef = ast_->pushSpan(nodeAffects.span());
        nodeLeft                 = nodeRef;
    }
    else
    {
        // Simple affectation
        nodeLeft = parseExpression();
        if (nodeLeft.isInvalid())
            return AstNodeRef::invalid();

        // Multi affectations
        if (is(TokenId::SymComma))
        {
            const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AssignListStmt>(ref());
            SmallVector<AstNodeRef> nodeAffects;
            nodeAffects.push_back(nodeLeft);
            while (consumeIf(TokenId::SymComma).isValid())
            {
                const auto nodeExpr = parseExpression();
                nodeAffects.push_back(nodeExpr);
            }

            nodePtr->spanChildrenRef = ast_->pushSpan(nodeAffects.span());
            nodeLeft                 = nodeRef;
        }
    }

    // Operation
    if (isAny(TokenId::SymEqual,
              TokenId::SymPlusEqual,
              TokenId::SymMinusEqual,
              TokenId::SymAsteriskEqual,
              TokenId::SymSlashEqual,
              TokenId::SymAmpersandEqual,
              TokenId::SymPipeEqual,
              TokenId::SymCircumflexEqual,
              TokenId::SymPercentEqual,
              TokenId::SymLowerLowerEqual,
              TokenId::SymGreaterGreaterEqual))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AssignStmt>(consume());
        nodePtr->nodeLeftRef    = nodeLeft;
        nodePtr->modifierFlags  = parseModifiers();
        nodePtr->nodeRightRef   = parseExpression();
        return nodeRef;
    }

    return nodeLeft;
}

AstNodeRef Parser::parseTopLevelDeclOrBlock()
{
    switch (id())
    {
        case TokenId::SymLeftCurly:
            return parseCompound<AstNodeId::TopLevelBlock>(TokenId::SymLeftCurly);
        case TokenId::KwdImpl:
            return parseImpl();

        case TokenId::KwdEnum:
            return parseEnumDecl();
        case TokenId::KwdUnion:
            return parseUnionDecl();
        case TokenId::KwdStruct:
            return parseStructDecl();
        case TokenId::KwdNamespace:
            return parseNamespace();
        case TokenId::SymAttrStart:
            return parseAttributeList<AstNodeId::TopLevelBlock>();
        case TokenId::KwdConst:
        case TokenId::KwdVar:
            return parseVarDecl();
        case TokenId::KwdFunc:
        case TokenId::KwdMtd:
            return parseFunctionDecl();
        case TokenId::KwdAttr:
            return parseAttrDecl();

        case TokenId::KwdAlias:
            return parseAlias();

        case TokenId::KwdInterface:
            return parseInterfaceDecl();

        default:
            raiseError(DiagnosticId::parser_err_unexpected_token, ref());
            skipTo({TokenId::SymSemiColon, TokenId::SymRightCurly}, SkipUntilFlagsE::EolBefore);
            return AstNodeRef::invalid();
    }
}

AstNodeRef Parser::parseTopLevelStmt()
{
    switch (id())
    {
        case TokenId::CompilerAssert:
        case TokenId::CompilerError:
        case TokenId::CompilerWarning:
        case TokenId::CompilerPrint:
            return parseCompilerDiagnostic();
        case TokenId::CompilerIf:
            return parseCompilerIf<AstNodeId::TopLevelBlock>();

        case TokenId::SymRightCurly:
            raiseError(DiagnosticId::parser_err_unexpected_token, ref());
            return AstNodeRef::invalid();

        case TokenId::SymSemiColon:
            consume();
            return AstNodeRef::invalid();

        case TokenId::CompilerFuncTest:
        case TokenId::CompilerFuncMain:
        case TokenId::CompilerFuncPreMain:
        case TokenId::CompilerFuncInit:
        case TokenId::CompilerFuncDrop:
        case TokenId::CompilerAst:
        case TokenId::CompilerRun:
            return parseCompilerFunc();

        case TokenId::CompilerFuncMessage:
            return parseCompilerMessageFunc();

        case TokenId::CompilerDependencies:
            return parseCompilerDependencies();

        case TokenId::KwdPublic:
        case TokenId::KwdInternal:
        case TokenId::KwdPrivate:
            return parseAccessModifier();

        case TokenId::KwdUsing:
            return parseUsing();

        case TokenId::CompilerLoad:
        case TokenId::CompilerForeignLib:
            return parseCompilerCall(1);

        case TokenId::CompilerImport:
            return parseCompilerImport();

        case TokenId::CompilerGlobal:
            raiseError(DiagnosticId::parser_err_misplaced_global, ref());
            return parseCompilerGlobal();

        case TokenId::Identifier:
            return parseTopLevelCall();

        case TokenId::EndOfFile:
            return AstNodeRef::invalid();

        default:
            return parseTopLevelDeclOrBlock();
    }
}

AstNodeRef Parser::parseEmbeddedStmt()
{
    switch (id())
    {
        case TokenId::CompilerAssert:
        case TokenId::CompilerError:
        case TokenId::CompilerWarning:
        case TokenId::CompilerPrint:
            return parseCompilerDiagnostic();
        case TokenId::CompilerIf:
            return parseCompilerIf<AstNodeId::EmbeddedBlock>();

        case TokenId::SymLeftCurly:
            return parseCompound<AstNodeId::EmbeddedBlock>(TokenId::SymLeftCurly);
        case TokenId::SymRightCurly:
            raiseError(DiagnosticId::parser_err_unexpected_token, ref());
            return AstNodeRef::invalid();

        case TokenId::SymSemiColon:
            consume();
            return AstNodeRef::invalid();

        case TokenId::KwdEnum:
            return parseEnumDecl();
        case TokenId::KwdUnion:
            return parseUnionDecl();
        case TokenId::KwdStruct:
            return parseStructDecl();

        case TokenId::IntrinsicBcBreakpoint:
            return parseIntrinsicCall(0);
        case TokenId::IntrinsicAssert:
        case TokenId::IntrinsicCVaStart:
        case TokenId::IntrinsicCVaEnd:
        case TokenId::IntrinsicSetContext:
            return parseIntrinsicCall(1);
        case TokenId::IntrinsicAtomicAdd:
            return parseIntrinsicCall(2);

        case TokenId::IntrinsicFree:
            return parseIntrinsicCallExpr(1);
        case TokenId::IntrinsicCompilerError:
        case TokenId::IntrinsicCompilerWarning:
        case TokenId::IntrinsicPanic:
            return parseIntrinsicCallExpr(2);            
        case TokenId::IntrinsicMemCpy:
        case TokenId::IntrinsicMemMove:
        case TokenId::IntrinsicMemSet:
            return parseIntrinsicCallExpr(3);
        case TokenId::IntrinsicPrint:
            return parseIntrinsicCallExpr(UINT32_MAX);
            
        case TokenId::SymAttrStart:
            return parseAttributeList<AstNodeId::EmbeddedBlock>();

        case TokenId::KwdFunc:
        case TokenId::KwdMtd:
            return parseFunctionDecl();

        case TokenId::KwdConst:
        case TokenId::KwdVar:
        case TokenId::KwdLet:
        {
            AstNodeRef nodeRef;
            if (nextIs(TokenId::SymLeftParen))
                nodeRef = parseVarDeclDecomposition();
            else
                nodeRef = parseVarDecl();

            return nodeRef;
        }

        case TokenId::CompilerAst:
        case TokenId::CompilerRun:
            return parseCompilerFunc();

        case TokenId::KwdReturn:
            return parseReturn();

        case TokenId::KwdUnreachable:
            return parseUnreachable();
        case TokenId::KwdBreak:
            return parseBreak();
        case TokenId::KwdContinue:
            return parseContinue();
        case TokenId::KwdFallThrough:
            return parseFallThrough();

        case TokenId::CompilerScope:
            return parseCompilerScope();
        case TokenId::CompilerMacro:
            return parseCompilerMacro();
        case TokenId::CompilerInject:
            return parseCompilerInject();

        case TokenId::KwdWith:
            return parseWith();
        case TokenId::KwdDefer:
            return parseDefer();
        case TokenId::KwdIf:
            return parseIf();
        case TokenId::KwdWhile:
            return parseWhile();
        case TokenId::KwdForeach:
            return parseForeach();
        case TokenId::KwdSwitch:
            return parseSwitch();
        case TokenId::KwdFor:
            return parseFor();

        case TokenId::KwdUsing:
            return parseUsing();
        case TokenId::KwdAlias:
            return parseAlias();

        case TokenId::IntrinsicInit:
            return parseIntrinsicInit();
        case TokenId::IntrinsicDrop:
            return parseIntrinsicDrop();
        case TokenId::IntrinsicPostCopy:
            return parseIntrinsicPostCopy();
        case TokenId::IntrinsicPostMove:
            return parseIntrinsicPostMove();

        case TokenId::KwdAssume:
        case TokenId::KwdCatch:
        case TokenId::KwdTry:
        case TokenId::KwdTryCatch:
            return parseTryCatch();
        case TokenId::KwdThrow:
            return parseThrow();

        case TokenId::KwdDiscard:
            return parseDiscard();

        case TokenId::CompilerUp:
        case TokenId::Identifier:
        case TokenId::SymDot:
        case TokenId::SymLeftParen:
        case TokenId::KwdDRef:
        case TokenId::KwdMoveRef:
        case TokenId::IntrinsicGetContext:
        case TokenId::IntrinsicProcessInfos:
        case TokenId::IntrinsicDbgAlloc:
        case TokenId::IntrinsicSysAlloc:
        case TokenId::KwdMe:
        case TokenId::CompilerUniq0:
        case TokenId::CompilerUniq1:
        case TokenId::CompilerUniq2:
        case TokenId::CompilerUniq3:
        case TokenId::CompilerUniq4:
        case TokenId::CompilerUniq5:
        case TokenId::CompilerUniq6:
        case TokenId::CompilerUniq7:
        case TokenId::CompilerUniq8:
        case TokenId::CompilerUniq9:
        case TokenId::CompilerAlias0:
        case TokenId::CompilerAlias1:
        case TokenId::CompilerAlias2:
        case TokenId::CompilerAlias3:
        case TokenId::CompilerAlias4:
        case TokenId::CompilerAlias5:
        case TokenId::CompilerAlias6:
        case TokenId::CompilerAlias7:
        case TokenId::CompilerAlias8:
        case TokenId::CompilerAlias9:
            return parseAssignStmt();

        default:
            raiseError(DiagnosticId::parser_err_unexpected_token, ref());
            skipTo({TokenId::SymSemiColon, TokenId::SymRightCurly}, SkipUntilFlagsE::EolBefore);
            return AstNodeRef::invalid();
    }
}

SWC_END_NAMESPACE();
